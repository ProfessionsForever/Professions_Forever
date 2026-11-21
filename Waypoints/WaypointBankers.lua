local _, FP = ...
local L = FP.L
local W = FP.Waypoint
local Questie, Spawns, Friendly, HasWord = W.Questie, W.Spawns, W.Friendly, W.HasWord
local indexes = W.indexes

-- Recorded and shipped bankers, plus Questie's "Banker" NPCs for the ones those lack.
function W:NearestBanker()
    if not self:CheckNav() then return end
    local db, zoneDB = Questie()
    W.Search("sub", db, function()
        local cands, have = {}, {}
        for id, t in W.Known("bankers") do
            if W.Usable(t, "bankers", id) then
                cands[#cands + 1] = { name = t.npc, uiMap = t.uiMap, x = t.x, y = t.y, area = t.zone }
                have[id] = true
            end
        end
        if db then
            for sub, ids in pairs(indexes.sub.map) do
                if HasWord(sub:lower(), "banker") then
                    for _, id in ipairs(ids) do
                        if not have[id] and Friendly(db, id) then
                            local name = db.QueryNPCSingle(id, "name")
                            for _, spot in ipairs(Spawns(db, zoneDB, id)) do
                                spot.name = name
                                cands[#cands + 1] = spot
                            end
                        end
                    end
                end
            end
        end

        local pick, dist = W.PickNearest(cands)
        if not pick then return FP:Print(L["No known banker location. Open a bank and it will be remembered."]) end
        W.PlaceNearest(pick, dist, W.Where(pick.name or L["Banker"], pick.area),
            "Nearest banker: %s (about %d yards)", "Nearest banker: %s (on another continent)", W.Where(pick.name or "?", pick.area))
    end)
end

-- Called on BANKFRAME_OPENED (from Core) to remember where this banker stands.
function W:RememberBanker()
    local entry, _, isNew = W.Remember("bankers")
    if isNew then FP:Print(L["Remembered banker: %s"]:format(entry.npc or "?")) end
end
