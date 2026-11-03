local _, FP = ...
local W = FP.Waypoint

-- NPCs you open (trainers, bankers, vendors) are recorded in FP.db[kind] by npc id. The saved data is
-- account-wide, so each entry notes which factions have used it. FP.NpcData (Data/Npcs.lua) ships the
-- same tables, merged from players' recordings by tools/merge_npcs.lua.
local function Round(v) return math.floor(v * 10000 + 0.5) / 10000 end

-- Returns the entry, the npc id and whether it is new; nil when no NPC is open or it has no known position.
function W.Remember(kind)
    local npcId = W.NpcID()
    if not npcId then return end
    local set = FP.db[kind]
    local entry = set[npcId]
    local isNew = entry == nil
    if isNew then
        local uiMap, x, y, zone = W.NpcLocation(npcId)
        if not uiMap then return end
        entry = { uiMap = uiMap, x = Round(x), y = Round(y), zone = zone }
        set[npcId] = entry
    end
    entry.npc = UnitName("npc")
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
