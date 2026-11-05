local _, FP = ...
local L = FP.L
local W = {}
FP.Waypoint = W

local sqrt = math.sqrt

-- The Questie database comes from whichever provider is installed, with the same db/zone shape either way:
-- the QuestieDB addon (LibQuestieDB) read directly, or older Questie releases that bundle the database.
local function IsFriendlyToPlayer(faction) -- "A", "H", "AH" or nil
    if not faction or faction == "AH" then return true end
    local player = UnitFactionGroup("player")
    return (faction == "A" and player == "Alliance") or (faction == "H" and player == "Horde")
end

-- QuestieDB ships the area -> map tables as Lua source strings; the override table wins.
local function DecodeAreaMaps(lib)
    local data = lib.Support.Get("ZoneDB")
    local private = type(data) == "table" and data.private
    if type(private) ~= "table" then return end
    local map = {}
    for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
        local chunk = type(private[key]) == "string" and loadstring(private[key])
        local ok, decoded
        if chunk then ok, decoded = pcall(chunk) end
        if not (ok and type(decoded) == "table") then return end
        for areaId, uiMap in pairs(decoded) do map[areaId] = uiMap end
    end
    return map
end

local function FromLibrary()
    local lib = _G.LibQuestieDB
    if not (type(lib) == "table" and lib.Npc and lib.Item and lib.Support) then return end
    if lib.RequireContract and not lib.RequireContract(1) then return end
    local ok, areaMap = pcall(DecodeAreaMaps, lib)
    if not (ok and areaMap) then return end
    local npc, item = lib.Npc, lib.Item
    -- The id maps are replaced when corrections change, so they are read fresh each time.
    local db = setmetatable({
        QueryNPCSingle = npc.Get, QueryItemSingle = item.Get, IsFriendlyToPlayer = IsFriendlyToPlayer,
    }, { __index = function(_, k)
        if k == "NPCPointers" then return npc.GetAllIds(true) end
        if k == "ItemPointers" then return item.GetAllIds(true) end
    end })
    return db, { GetUiMapIdByAreaId = function(_, areaId) return areaMap[areaId] end }
end

local function FromLoader()
    if not _G.QuestieLoader then return end
    local ok, db = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    local okZ, zone = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
    if ok and okZ and db and zone and db.NPCPointers and db.ItemPointers and db.QueryNPCSingle and db.QueryItemSingle then
        return db, zone
    end
end

-- Neither provider changes once found, so a successful lookup is cached.
local questieDB, questieZone
---@return any db, any zone
local function Questie()
    if not questieDB then questieDB, questieZone = FromLibrary() end
    if not questieDB then questieDB, questieZone = FromLoader() end
    return questieDB, questieZone
end
W.Questie = Questie

local OWNER = "ProfessionsForever"

-- Everything here is optional: a navigator is used only when installed and, for Polestar, enabled.
local function PolestarAPI()
    local api = _G.Polestar and Polestar.Nav and Polestar.Nav.API
    if api and type(api.Navigate) == "function" and type(api.Cancel) == "function" then return api end
end

-- Real TomTom only: Polestar can install a stand-in under the same global name.
local function TomTomInstalled()
    return C_AddOns.IsAddOnLoaded("TomTom") and _G.TomTom and TomTom.AddWaypoint and true or false
end

-- Polestar steers only when its own integration setting is on: "Follow TomTom's arrow" with TomTom
-- installed, "Let other addons set waypoints" without it.
local function PolestarEnabled()
    if not (PolestarAPI() and type(Polestar.Get) == "function") then return false end
    local ok, on = pcall(Polestar.Get, TomTomInstalled() and "nav.followTomTom" or "nav.answerTomTom")
    return ok and on and true or false
end

local function Navigator()
    if PolestarEnabled() then return "polestar" end
    if TomTomInstalled() then return "tomtom" end
end

function W:NavAvailable()
    return Navigator() ~= nil
end

-- For commands: explains what is missing when there is no navigator.
function W:CheckNav()
    if Navigator() then return true end
    FP:Print(L["Polestar or TomTom is needed for waypoints."])
end

function W:Available(recipeID)
    if not Navigator() then return false end
    if Questie() then return true end
    local e = recipeID and FP.Recipes.byID[recipeID]
    return e ~= nil and (W:TrainerFor(recipeID) ~= nil or #W.KnownRecipeVendors(e.name) > 0)
end

local function WorldPos(uiMap, x, y)
    local continent, pos = C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(x, y))
    if not pos then return end
    local wx, wy = pos:GetXY()
    return continent, wx, wy
end

-- Nil where the map has no position (instances).
local function PlayerMapPos()
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if pos then return map, pos:GetXY() end
end

local function PlayerWorldPos()
    local map, x, y = PlayerMapPos()
    if map then return WorldPos(map, x, y) end
end

-- Nearest candidate ({ uiMap, x, y, ... }) on the player's continent plus its distance in yards;
-- otherwise the first candidate found elsewhere, with no distance.
local function PickNearest(cands)
    local pc, px, py = PlayerWorldPos()
    local best, bestDist, other
    for _, cand in ipairs(cands) do
        local c, wx, wy = WorldPos(cand.uiMap, cand.x, cand.y)
        if c and c == pc and px then
            local d = sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
            if not bestDist or d < bestDist then best, bestDist = cand, d end
        else
            other = other or cand
        end
    end
    if best then return best, bestDist end
    return other
end
W.PickNearest = PickNearest

-- Only one waypoint of ours at a time. TomTom's own clearing is unreliable here, so we remove it on arrival too.
local active
local ARRIVE_YARDS = 20

function W:HasActive() return active ~= nil end

local function RefreshButton()
    local f = FP.UI and FP.UI.frame
    if f and f.clearWay then f.clearWay:SetShown(active ~= nil) end
end

function W:Clear()
    if not active then return end
    if active.ticker then active.ticker:Cancel() end
    if active.polestar then
        local api = PolestarAPI()
        if api then
            local ok, cancelled = pcall(api.Cancel, OWNER)
            -- Cancel refuses when Polestar swapped its target table; drop it directly if it is still ours.
            local N = Polestar.Nav
            local t = N and N.GetTarget and N.GetTarget()
            if not (ok and cancelled) and t and t.label == active.title and N.IsOverride and N.IsOverride() and N.ReleaseTarget then
                pcall(N.ReleaseTarget)
            end
        end
    elseif _G.TomTom and TomTom.RemoveWaypoint then
        pcall(TomTom.RemoveWaypoint, TomTom, active.uid)
    end
    active = nil
    RefreshButton()
end

-- Right-clicking Polestar's arrow clears our waypoint, like its own "mark done" on travel legs.
local arrowHooked
local function HookArrow()
    local arrow = _G.PolestarNavArrow
    if arrowHooked or not (arrow and arrow.HookScript) then return end
    arrowHooked = true
    arrow:HookScript("OnMouseUp", function(_, button)
        if button == "RightButton" and active and active.polestar then
            W:Clear()
            GameTooltip:Hide()
            -- Redraw at once so the clear hint disappears without moving the mouse.
            local onEnter = arrow:IsShown() and arrow:IsMouseOver() and arrow:GetScript("OnEnter")
            if onEnter then onEnter(arrow) end
        end
    end)
    arrow:HookScript("OnEnter", function()
        if active and active.polestar then
            GameTooltip:AddLine(L["Right-click: clear the ProfessionsForever waypoint"], 0.5, 0.8, 1)
            GameTooltip:Show()
        end
    end)
end

local function Place(uiMap, x, y, title)
    W:Clear()
    local nav = Navigator()
    local mine
    if nav == "polestar" then
        if not PolestarAPI().Navigate(OWNER, uiMap, x, y, title) then return end
        mine = { polestar = true, title = title }
        HookArrow()
    elseif nav == "tomtom" then
        local uid = TomTom:AddWaypoint(uiMap, x, y, { title = title, persistent = false, crazy = true,
            cleardistance = ARRIVE_YARDS, arrivaldistance = ARRIVE_YARDS })
        if not uid then return end
        mine = { uid = uid }
    else
        return
    end
    active = mine
    RefreshButton()
    local tc, tx, ty = WorldPos(uiMap, x, y)
    mine.ticker = C_Timer.NewTicker(1, function()
        if active ~= mine then return end
        local pc, px, py = PlayerWorldPos()
        if pc and pc == tc and sqrt((px - tx) ^ 2 + (py - ty) ^ 2) <= ARRIVE_YARDS then W:Clear() end
    end)
end
W.Place = Place

-- Places a pick from PickNearest and prints nearKey (distance appended as its last argument) or farKey.
function W.PlaceNearest(pick, dist, title, nearKey, farKey, ...)
    Place(pick.uiMap, pick.x, pick.y, title)
    local args = { ... }
    if dist then args[#args + 1] = dist end
    FP:Print(L[dist and nearKey or farKey]:format(unpack(args)))
end

---------------------------------------------------------------------------
-- Questie helpers shared by the vendor, trainer and banker files
---------------------------------------------------------------------------
function W.HasWord(text, word)
    return text:find("%f[%a]" .. word:gsub("%p", "%%%0") .. "%f[%A]") ~= nil
end

function W.Friendly(db, npcId)
    local faction = db.QueryNPCSingle(npcId, "friendlyToFaction")
    return faction == nil or db.IsFriendlyToPlayer(faction)
end

-- One spot per area the NPC spawns in, as map fractions.
function W.Spawns(db, zoneDB, npcId)
    local out = {}
    for areaId, points in pairs(db.QueryNPCSingle(npcId, "spawns") or {}) do
        local uiMap, pt = zoneDB:GetUiMapIdByAreaId(areaId), points[1]
        if uiMap and uiMap ~= 0 and pt then -- map 0 marks areas Questie never displays
            out[#out + 1] = { uiMap = uiMap, x = pt[1] / 100, y = pt[2] / 100, area = C_Map.GetAreaInfo(areaId) }
        end
    end
    return out
end

function W.NpcID()
    local guid = UnitGUID("npc")
    return guid and tonumber((select(6, strsplit("-", guid))))
end

-- Questie's spawn when available, else where you are standing (you're next to the NPC).
function W.NpcLocation(npcId)
    local db, zoneDB = Questie()
    local spot = db and W.Spawns(db, zoneDB, npcId)[1]
    if spot then return spot.uiMap, spot.x, spot.y, spot.area end
    local map, x, y = PlayerMapPos()
    if map then
        local info = C_Map.GetMapInfo(map)
        return map, x, y, info and info.name
    end
end

-- Questie scans run over several frames so the client doesn't hitch. onFound(name, id) is called for each name keep() accepts.
local CHUNK = 3000
local function Scan(db, pointerKey, queryKey, field, keep, onFound, onDone)
    local pointers, query, id = db[pointerKey], db[queryKey], nil
    local function Step()
        for _ = 1, CHUNK do
            id = next(pointers, id)
            if not id then return onDone() end
            local name = query(id, field)
            if name and keep(name) then onFound(name, id) end
        end
        C_Timer.After(0, Step)
    end
    Step()
end

-- Only the names the lookups can match are kept; indexing all of Questie's items and NPCs costs megabytes.
W.RECIPE_PREFIXES = { "Recipe", "Plans", "Pattern", "Schematic", "Formula", "Manual", "Design", "Technique", "Book" }
local recipePrefix = {}
for _, p in ipairs(W.RECIPE_PREFIXES) do recipePrefix[p] = true end

local SUB_WORDS = { "trainer", "banker", "apprentice", "junior", "journeyman", "expert", "artisan" }

local INDEX_SOURCES = { -- kind = { Questie pointer table, query function, field indexed, name filter }
    item = { "ItemPointers", "QueryItemSingle", "name", function(name)
        return recipePrefix[name:match("^(%a+): ")] == true
    end },
    sub = { "NPCPointers", "QueryNPCSingle", "subName", function(name)
        local low = name:lower()
        for _, word in ipairs(SUB_WORDS) do
            if low:find(word, 1, true) then return true end
        end
        return false
    end },
}

local indexes = {} -- [kind] = { map = name -> ids | nil, building = bool, waiting = {} }
W.indexes = indexes

function W.Index(kind, db, onDone)
    local st = indexes[kind]
    if not st then st = { waiting = {} } indexes[kind] = st end
    if st.map then if onDone then onDone() end return end
    if onDone then st.waiting[#st.waiting + 1] = onDone end
    if st.building then return end
    st.building = true
    local map = {}
    local pointerKey, queryKey, field, keep = unpack(INDEX_SOURCES[kind])
    Scan(db, pointerKey, queryKey, field, keep, function(name, id)
        local list = map[name]
        if not list then list = {} map[name] = list end
        list[#list + 1] = id
    end, function()
        st.map, st.building = map, false
        for _, fn in ipairs(st.waiting) do fn() end
        wipe(st.waiting)
    end)
end

-- Same, announcing the wait. Without Questie there is nothing to build and onDone runs at once.
function W.Search(kind, db, onDone)
    if not db then return onDone() end
    FP:Print(L["Searching Questie's database..."])
    W.Index(kind, db, onDone)
end

-- Ids of the NPCs with exactly this name; the NPC names are not indexed, only the asked-for ones are remembered.
local npcsByName = {}
function W.SearchNpc(db, name, onDone)
    if npcsByName[name] then return onDone(npcsByName[name]) end
    FP:Print(L["Searching Questie's database..."])
    local ids = {}
    Scan(db, "NPCPointers", "QueryNPCSingle", "name", function(n) return n == name end,
        function(_, id) ids[#ids + 1] = id end,
        function() npcsByName[name] = ids onDone(ids) end)
end

-- Same, announcing the wait. Without Questie there is nothing to build and onDone runs at once.
function W.Search(kind, db, onDone)
    if not db then return onDone() end
    FP:Print(L["Searching Questie's database..."])
    W.Index(kind, db, onDone)
end
