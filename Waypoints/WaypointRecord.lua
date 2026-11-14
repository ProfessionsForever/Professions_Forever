local addonName, FP = ...
local W = FP.Waypoint

-- Each recording notes the addon version and game build that made it; tools/merge_npcs.lua lets newer recordings win.
local VERSION = C_AddOns.GetAddOnMetadata(addonName, "Version")
local BUILD = tonumber((select(2, GetBuildInfo())))

-- NPCs you open (trainers, bankers, vendors) are recorded in FP.db[kind] by npc id. The saved data is
-- account-wide, so each entry notes which factions have used it. FP.NpcData (Data/Npcs.lua) ships the
-- same tables, merged from players' recordings by tools/merge_npcs.lua.
local function Round(v) return math.floor(v * 10000 + 0.5) / 10000 end

-- Data/ClassicNpcs.lua (from classic-db) fills in the NPCs no player has recorded; recordings win.
do
    local classic, data = FP.ClassicNpcs, FP.NpcData
    for _, kind in ipairs({ "trainers", "bankers", "vendors" }) do
        for id, entry in pairs(classic[kind]) do
            -- The classic database's list of a trainer's ranks stays beside whatever players recorded of them.
            local ranks = entry.ranks
            entry.ranks = nil
            if not data[kind][id] then data[kind][id] = entry end
            data[kind][id].classicRanks = ranks
        end
    end
    for name, ids in pairs(classic.trainerRecipes) do
        local recorded = data.trainerRecipes[name]
        data.trainerRecipes[name] = recorded and (recorded .. "," .. ids) or ids
    end
    data.artisan = classic.artisan
    FP.ClassicNpcs = nil
end

-- Returns the entry, the npc id and whether it is new; nil when no NPC is open or it has no known position.
-- Every visit refreshes the entry, position included, so an NPC that moved is corrected.
function W.Remember(kind)
    local npcId = W.NpcID()
    if not npcId then return end
    local set = FP.db[kind]
    local entry = set[npcId]
    local isNew = entry == nil
    local uiMap, x, y = W.NpcLocation(npcId)
    if isNew then
        if not uiMap then return end
        entry = {}
        set[npcId] = entry
    end
    if uiMap then entry.uiMap, entry.x, entry.y = uiMap, Round(x), Round(y) end
    entry.npc = UnitName("npc")
    -- The zone the game names where you stand ("City of Dalaran"), which Questie may file under a parent zone.
    entry.zone = GetRealZoneText()
    entry.ver, entry.build = VERSION, BUILD
    local faction = UnitFactionGroup("player")
    if faction then entry[faction:lower()] = true end
    return entry, npcId, isNew
end

function W.Usable(entry)
    local faction = UnitFactionGroup("player")
    return not faction or entry[faction:lower()] == true
end

-- A recorded or shipped entry; yours win.
function W.KnownEntry(kind, npcId)
    return FP.db[kind][npcId] or FP.NpcData[kind][npcId]
end

-- Iterates every entry of a kind: yours, then the shipped ones you haven't recorded yourself.
function W.Known(kind)
    local mine, shipped = FP.db[kind], FP.NpcData[kind]
    local tbl, id, entry = mine
    return function()
        while tbl do
            id, entry = next(tbl, id)
            if id == nil then
                if tbl == shipped then return end
                tbl = shipped
            elseif tbl == mine or not mine[id] then
                return id, entry
            end
        end
    end
end
