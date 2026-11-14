local _, FP = ...

-- Which recipes each character knows, saved in its record so the other characters can see it:
-- FP.db.characters[key].known = { [skill line ID] = "recipe spell ID,..." }
-- It is read with IsPlayerSpell over every recipe in the game data (FP.RecipeLines), which needs no profession
-- window, so each character is recorded from its first login.
local Known = {}
FP.Known = Known

local NONE = {}
local index -- [recipe spell ID] = { character key, ... }, built on first use and dropped when a record changes

function Known:Snapshot()
    local rec = FP.Alts:Current()
    if not rec then return end
    local known = {}
    for line, list in pairs(FP.RecipeLines) do
        local ids = {}
        for id in list:gmatch("%d+") do
            if IsPlayerSpell(tonumber(id)) then ids[#ids + 1] = id end
        end
        if #ids > 0 then known[line] = table.concat(ids, ",") end
    end
    rec.known = known
    index = nil
end

FP.Alts:OnRemove(function() index = nil end)

-- Keys of the characters known to know the recipe. Treat the result as read-only.
function Known:Who(recipeID)
    if not index then
        index = {}
        for key, rec in pairs(FP.db.characters) do
            for _, list in pairs(rec.known or NONE) do
                for id in list:gmatch("%d+") do
                    id = tonumber(id)
                    local keys = index[id]
                    if not keys then keys = {} index[id] = keys end
                    keys[#keys + 1] = key
                end
            end
        end
    end
    return index[recipeID] or NONE
end
