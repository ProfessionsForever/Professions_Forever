local _, FP = ...
local T = {}
FP.Tools = T

-- What a recipe requires. The game's own "met" flag is believed whenever it says met: it knows what stands in for a
-- tool (on Forever a better Enchanting rod meets a lower one's requirement: a Runed Silver Rod for "Runed Copper Rod").
-- When it isn't met, a tool-like requirement is looked for by name in the bags and bank, to tell "in the bank" from
-- missing; anything else (a forge, an anvil) is simply missing. Another character's profession is always checked by
-- name in its saved bags and bank, since the flag is about the current character.
local TOOL_WORDS = { "hammer", "pick", "knife", "spanner", "rod", "adjustor", "kit", "stone", "needle", "mallet" }

local function LooksLikeTool(name)
    local low = name:lower()
    for _, w in ipairs(TOOL_WORDS) do
        if low:find("%f[%a]" .. w .. "%f[%A]") then return true end
    end
    return false
end

local function Field(entry, ...)
    for i = 1, select("#", ...) do
        local v = entry[select(i, ...)]
        if v ~= nil then return v end
    end
end

-- Requirements of a recipe: { name, tool = bool, state = "bags" | "bank" | "missing" }.
local function ToolState(name)
    local id = C_Item.GetItemInfoInstant(name)
    local crafter = FP.Recipes:Crafter()
    if crafter then -- another character's profession: its saved bags and bank (worn tools aren't saved)
        local b, bk = 0, 0
        if id then b, bk = FP.Planner:Holding(crafter, id) end
        return b > 0 and "bags" or bk > 0 and "bank" or "missing"
    end
    local bags, bank = C_Item.GetItemCount(name) or 0, 0 -- bags and equipped
    if id then
        local b, bk = FP.Inv:Owned(id)
        bags, bank = math.max(bags, b), bk
    else
        bank = math.max(0, (C_Item.GetItemCount(name, true) or 0) - bags)
    end
    if bags > 0 then return "bags" end
    if bank > 0 then return "bank" end
    return "missing"
end

function T:Get(recipeID)
    local out = {}
    local ok, list = pcall(C_TradeSkillUI.GetRecipeRequirements, recipeID)
    if not (ok and type(list) == "table") then return out end
    for _, entry in ipairs(list) do
        local name = type(entry) == "string" and entry or Field(entry, "name", "requirement", "text")
        if type(name) == "string" and name ~= "" then
            local tool = LooksLikeTool(name)
            local met = type(entry) == "table" and Field(entry, "met") == true and not FP.Recipes:Crafter()
            local state
            if met then
                state = "bags"
            elseif tool then
                state = ToolState(name)
            else
                state = "missing"
            end
            out[#out + 1] = { name = name, tool = tool, state = state }
        end
    end
    return out
end

-- Names of the requirements of the recipe that aren't met from the bags (a tool in the bank doesn't count).
function T:Missing(recipeID)
    local missing = {}
    for _, r in ipairs(self:Get(recipeID)) do
        if r.state ~= "bags" then missing[#missing + 1] = r.name end
    end
    return missing
end
