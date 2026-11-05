local _, FP = ...
local T = {}
FP.Tools = T

-- Tool-like requirements are checked in the bags by item name; anything else (a forge, an anvil) uses the game's own "met" flag.
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
    local bags, bank = C_Item.GetItemCount(name) or 0, 0 -- bags and equipped
    local id = C_Item.GetItemInfoInstant(name)
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
    local fn = C_TradeSkillUI and C_TradeSkillUI.GetRecipeRequirements
    if not fn then return out end
    local ok, list = pcall(fn, recipeID)
    if not (ok and type(list) == "table") then return out end
    for _, entry in ipairs(list) do
        local name = type(entry) == "string" and entry or Field(entry, "name", "requirement", "text")
        if type(name) == "string" and name ~= "" then
            local tool = LooksLikeTool(name)
            local state
            if tool then
                state = ToolState(name)
            else
                state = (type(entry) == "table" and Field(entry, "met") == true) and "bags" or "missing"
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

-- Prints what the client reports for the selected recipe, to adjust the lookup if nothing shows up.
function T:Debug()
    local id = FP.selected
    if not id then return FP:Print("Select a recipe first.") end
    local fn = C_TradeSkillUI and C_TradeSkillUI.GetRecipeRequirements
    FP:Print(("recipe %s: GetRecipeRequirements exists=%s"):format(tostring(id), tostring(fn ~= nil)))
    if fn then
        local ok, list = pcall(fn, id)
        FP:Print(("  call ok=%s type=%s count=%s"):format(tostring(ok), type(list), type(list) == "table" and #list or "-"))
        for i, entry in ipairs(type(list) == "table" and list or {}) do
            if type(entry) == "table" then
                local parts = {}
                for k, v in pairs(entry) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
                FP:Print(("  [%d] %s"):format(i, table.concat(parts, ", ")))
            else
                FP:Print(("  [%d] %s"):format(i, tostring(entry)))
            end
        end
    end
    local info = C_TradeSkillUI.GetRecipeInfo(id)
    for k, v in pairs(info or {}) do
        local key = tostring(k):lower()
        if key:find("tool") or key:find("requir") or key:find("reagent") == nil and key:find("need") then
            FP:Print(("  info.%s = %s"):format(tostring(k), tostring(v)))
        end
    end
    for _, name in ipairs({ "GetTradeSkillTools", "GetRecipeTools", "GetRecipeRequirementText" }) do
        FP:Print(("  %s exists: global=%s, C_TradeSkillUI=%s"):format(name, tostring(_G[name] ~= nil), tostring(C_TradeSkillUI[name] ~= nil)))
    end
end
