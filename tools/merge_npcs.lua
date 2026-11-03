-- Merges the trainers, bankers and vendors players recorded (SavedVariables/ProfessionsForever.lua files)
-- into Data/Npcs.lua, keeping what is already there.
--
-- Usage: luajit tools/merge_npcs.lua <ProfessionsForever.lua>...
--
-- The files are run in an empty environment and every value is validated before it is written, so a
-- file from another player cannot put anything but plain data into the addon.
local root = (arg[0]:match("^(.*)/tools/[^/]*$") or ".")
local TARGET = root .. "/Data/Npcs.lua"
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

local function names(list)
    local out = {}
    if type(list) == "table" then
        for _, name in ipairs(list) do
            name = text(name)
            if name then out[#out + 1] = name end
        end
    end
    return out
end

-- Keeps only well-formed entries: a map, a position, plain strings and id lists.
local function clean(e)
    if type(e) ~= "table" then return end
    local uiMap, x, y = number(e.uiMap, 1, 1e6), number(e.x, 0, 1), number(e.y, 0, 1)
    if not (uiMap and x and y) then return end
    local c = { uiMap = math.floor(uiMap), x = x, y = y, npc = text(e.npc), sub = text(e.sub), skill = text(e.skill),
        zone = text(e.zone), alliance = e.alliance == true or nil, horde = e.horde == true or nil }
    if type(e.items) == "string" and e.items:match("^,[%d,]*,$") then c.items = e.items end
    c.recipes = names(e.recipes)
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
    if dst.items or src.items then dst.items = joinIds(union(ids(dst.items), ids(src.items))) end
    dst.recipes = sorted(union(dst.recipes, src.recipes))
end

local data = { trainerRecipes = {} }
for _, kind in ipairs(KINDS) do data[kind] = {} end

-- Adds one table of recordings: the existing Data/Npcs.lua first, then each player's file.
local function add(source)
    for _, kind in ipairs(KINDS) do
        for id, e in pairs(type(source[kind]) == "table" and source[kind] or {}) do
            local c = type(id) == "number" and clean(e)
            if c then
                local old = data[kind][id]
                if old then mergeEntry(old, c) else data[kind][id] = c end
            end
        end
    end
    for name, list in pairs(type(source.trainerRecipes) == "table" and source.trainerRecipes or {}) do
        name = text(name)
        if name and type(list) == "string" and list:match("^[%d,]+$") then
            data.trainerRecipes[name] = union(data.trainerRecipes[name] or {}, ids(list))
        end
    end
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local FP = {}
load(TARGET, "ProfessionsForever", FP)
add(FP.NpcData or {})
local before = {}
for _, kind in ipairs(KINDS) do before[kind] = count(data[kind]) end

for i = 1, #arg do
    local env = load(arg[i])
    local db = env.ProfessionsForeverDB
    if type(db) ~= "table" then error(arg[i] .. ": no ProfessionsForeverDB in this file", 0) end
    add(db)
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

local ORDER = { "npc", "sub", "skill", "zone", "uiMap", "x", "y", "alliance", "horde", "items" }

local function entryText(e)
    local parts = {}
    for _, k in ipairs(ORDER) do
        if e[k] ~= nil then parts[#parts + 1] = field(k, e[k]) end
    end
    if e.recipes and #e.recipes > 0 then
        local list = {}
        for _, name in ipairs(e.recipes) do list[#list + 1] = ("%q"):format(name) end
        parts[#parts + 1] = "recipes = { " .. table.concat(list, ", ") .. " }"
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
out[#out + 1] = "    -- [recipe name] = \"npcId,npcId\""
out[#out + 1] = "    trainerRecipes = {"
for _, name in ipairs(sortedKeys(data.trainerRecipes)) do
    local trainers = {}
    for _, id in ipairs(sorted(data.trainerRecipes[name])) do
        if data.trainers[id] then trainers[#trainers + 1] = id end
    end
    if #trainers > 0 then out[#out + 1] = ("        [%q] = %q,"):format(name, table.concat(trainers, ",")) end
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
print(("trainerRecipes: %d"):format(count(data.trainerRecipes)))
