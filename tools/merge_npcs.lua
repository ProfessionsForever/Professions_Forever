-- Merges the trainers, bankers and vendors players recorded (SavedVariables/ProfessionsForever.lua files)
-- into Data/Npcs.lua. NPCs in the player files replace what Data/Npcs.lua has for them; the rest is kept.
-- Trainers' recipes are kept by recipe spell ID; a file last saved by a version that kept them by name has to be
-- opened in game once with this version first, which moves them over. Class and weapon trainers that older versions
-- recorded are left out: 1.12 NPCs with no profession that Data/ClassicNpcs.lua doesn't list as profession trainers.
--
-- Usage: luajit tools/merge_npcs.lua <ProfessionsForever.lua>...
--
-- The files are run in an empty environment and every value is validated before it is written, so a
-- file from another player cannot put anything but plain data into the addon.
local root = (arg[0]:match("^(.*)/tools/[^/]*$") or ".")
local TARGET = root .. "/Data/Npcs.lua"
local BUILT_IN = root .. "/Data/ClassicNpcs.lua"
local CLASSIC_IDS = 20000 -- 1.12's NPCs have ids below this; Forever's own start far above it
local KINDS = { "trainers", "bankers", "vendors" }

local function load(path, ...)
    local chunk, err = loadfile(path)
    if not chunk then error(err, 0) end
    local env = {}
    setfenv(chunk, env)
    local ok, runErr = pcall(chunk, ...)
    if not ok then error(path .. ": " .. tostring(runErr), 0) end
    return env
end

local function number(v, lo, hi)
    if type(v) == "number" and v >= lo and v <= hi then return v end
end

local function text(v)
    if type(v) ~= "string" then return end
    v = (v:gsub("%c", ""))
    if #v > 0 and #v <= 100 then return v end
end

-- Keeps only well-formed entries: a map, a position, plain strings and id lists.
local function clean(e)
    if type(e) ~= "table" then return end
    local uiMap, x, y = number(e.uiMap, 1, 1e6), number(e.x, 0, 1), number(e.y, 0, 1)
    if not (uiMap and x and y) then return end
    local c = { uiMap = math.floor(uiMap), x = x, y = y, npc = text(e.npc), sub = text(e.sub), skill = text(e.skill),
        zone = text(e.zone), alliance = e.alliance == true or nil, horde = e.horde == true or nil }
    if type(e.ver) == "string" and e.ver:match("^%d+[%d.]*$") then c.ver = e.ver end
    c.build = number(e.build, 1, 1e9)
    for _, k in ipairs({ "items", "ranks", "noRanks" }) do
        if type(e[k]) == "string" and e[k]:match("^,[%d,]*,$") then c[k] = e[k] end
    end
    return c
end

local function union(a, b)
    local seen, out = {}, {}
    for _, v in ipairs(a) do if not seen[v] then seen[v] = true out[#out + 1] = v end end
    for _, v in ipairs(b) do if not seen[v] then seen[v] = true out[#out + 1] = v end end
    return out
end

local function ids(s)
    local out = {}
    for v in (s or ""):gmatch("%d+") do out[#out + 1] = tonumber(v) end
    return out
end

local function sorted(list)
    table.sort(list)
    return list
end

local function joinIds(list)
    return "," .. table.concat(sorted(list), ",") .. ","
end

local function mergeEntry(dst, src)
    for _, k in ipairs({ "npc", "sub", "skill", "zone" }) do dst[k] = dst[k] or src[k] end
    dst.alliance, dst.horde = dst.alliance or src.alliance, dst.horde or src.horde
    for _, k in ipairs({ "items", "ranks", "noRanks" }) do
        if dst[k] or src[k] then dst[k] = joinIds(union(ids(dst[k]), ids(src[k]))) end
    end
end

local builtIn = {}
load(BUILT_IN, "ProfessionsForever", builtIn)
local professionTrainers = builtIn.ClassicNpcs.trainers

local skippedNames = 0

local function newSet()
    local set = { trainerRecipes = {} }
    for _, kind in ipairs(KINDS) do set[kind] = {} end
    return set
end

-- Adds one table of recordings to set, combining with what set already has for the same NPC.
local function add(set, source)
    for _, kind in ipairs(KINDS) do
        for id, e in pairs(type(source[kind]) == "table" and source[kind] or {}) do
            local c = type(id) == "number" and clean(e)
            if c and kind == "trainers" and id < CLASSIC_IDS and not c.skill and not professionTrainers[id] then c = nil end
            if c then
                local old = set[kind][id]
                if old then mergeEntry(old, c) else set[kind][id] = c end
            end
        end
    end
    for recipe, list in pairs(type(source.trainerRecipes) == "table" and source.trainerRecipes or {}) do
        if number(recipe, 1, 1e9) and type(list) == "string" and list:match("^[%d,]+$") then
            set.trainerRecipes[recipe] = union(set.trainerRecipes[recipe] or {}, ids(list))
        elseif type(recipe) == "string" then
            skippedNames = skippedNames + 1
        end
    end
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local FP = {}
load(TARGET, "ProfessionsForever", FP)
local data = newSet()
add(data, FP.NpcData or {})
local before = {}
for _, kind in ipairs(KINDS) do before[kind] = count(data[kind]) end

-- The player files are combined with each other, then each NPC they have replaces the shipped entry, so
-- re-recording an NPC updates it (a corrected zone or position).
local incoming = newSet()
for i = 1, #arg do
    local env = load(arg[i])
    local db = env.ProfessionsForeverDB
    if type(db) ~= "table" then error(arg[i] .. ": no ProfessionsForeverDB in this file", 0) end
    add(incoming, db)
end
-- Stock and factions are still combined with the shipped entry: sold-out limited-supply items drop off a
-- vendor's list, and each faction only adds its own flag.
for _, kind in ipairs(KINDS) do
    for id, e in pairs(incoming[kind]) do
        local old = data[kind][id]
        if old then
            e.alliance, e.horde = e.alliance or old.alliance, e.horde or old.horde
            for _, k in ipairs({ "items", "ranks", "noRanks" }) do
                if e[k] or old[k] then e[k] = joinIds(union(ids(e[k]), ids(old[k]))) end
            end
        end
        data[kind][id] = e
    end
end
for recipe, list in pairs(incoming.trainerRecipes) do
    data.trainerRecipes[recipe] = union(data.trainerRecipes[recipe] or {}, list)
end

-- Output ---------------------------------------------------------------
local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function field(k, v)
    if type(v) == "string" then return ("%s = %q"):format(k, v) end
    if type(v) == "boolean" then return k .. " = true" end
    if k == "x" or k == "y" then return ("%s = %.4f"):format(k, v) end
    return ("%s = %d"):format(k, v)
end

local ORDER = { "npc", "sub", "skill", "zone", "uiMap", "x", "y", "alliance", "horde", "ver", "build", "ranks", "noRanks", "items" }

local function entryText(e)
    local parts = {}
    for _, k in ipairs(ORDER) do
        if e[k] ~= nil then parts[#parts + 1] = field(k, e[k]) end
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local out = {
    "-- Generated by tools/merge_npcs.lua from players' recorded data. Do not edit.",
    "local _, FP = ...",
    "",
    "FP.NpcData = {",
}
for _, kind in ipairs(KINDS) do
    out[#out + 1] = "    " .. kind .. " = {"
    for _, id in ipairs(sortedKeys(data[kind])) do
        out[#out + 1] = ("        [%d] = %s,"):format(id, entryText(data[kind][id]))
    end
    out[#out + 1] = "    },"
end
out[#out + 1] = "    -- [recipe spell ID] = \"npcId,npcId\""
out[#out + 1] = "    trainerRecipes = {"
local kept = 0
for _, recipe in ipairs(sortedKeys(data.trainerRecipes)) do
    local trainers = {}
    for _, id in ipairs(sorted(data.trainerRecipes[recipe])) do
        if data.trainers[id] then trainers[#trainers + 1] = id end
    end
    if #trainers > 0 then
        kept = kept + 1
        out[#out + 1] = ("        [%d] = %q,"):format(recipe, table.concat(trainers, ","))
    end
end
out[#out + 1] = "    },"
out[#out + 1] = "}"

local f = assert(io.open(TARGET, "w"))
f:write(table.concat(out, "\n"), "\n")
f:close()

for _, kind in ipairs(KINDS) do
    local now = count(data[kind])
    print(("%s: %d (%+d)"):format(kind, now, now - before[kind]))
end
print(("trainerRecipes: %d"):format(kept))
if skippedNames > 0 then
    print(("%d recipes listed by name were skipped: open the game once with this version, then merge that file again"):format(skippedNames))
end
