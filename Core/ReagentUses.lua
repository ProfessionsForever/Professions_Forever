local _, FP = ...

-- Recipe Search's data: the recipes that use an item as a reagent, and every recipe by name. It comes from the game
-- data (Data/Recipes.lua), so it covers professions that are not open and recipes that are not learned.
local Uses = {}
FP.Uses = Uses

function Uses.IsReagent(itemID)
    return FP.ReagentUses[itemID] ~= nil
end

local byRecipe -- [recipe spell ID] = { { itemID, qty } }, the same table read the other way, built on first use

-- A recipe's reagents { itemID, qty }, from the game data, so any recipe works on any character. Treat as read-only.
function Uses:ReagentsOf(recipeID)
    if not byRecipe then
        byRecipe = {}
        for itemID, data in pairs(FP.ReagentUses) do
            for recipe, qty in data:gmatch("(%d+),(%d+),%d+") do
                recipe = tonumber(recipe)
                local list = byRecipe[recipe]
                if not list then list = {} byRecipe[recipe] = list end
                list[#list + 1] = { itemID = itemID, qty = tonumber(qty) }
            end
        end
        for _, list in pairs(byRecipe) do table.sort(list, function(a, b) return a.itemID < b.itemID end) end
    end
    return byRecipe[recipeID] or {}
end

local byOutput -- [item ID] = { recipe spell ID, ... }, FP.RecipeOutputs read the other way, built on first use

-- The recipes that make the item, from the game data, whether or not anyone knows them. Treat as read-only.
function Uses:MakersOf(itemID)
    if not byOutput then
        byOutput = {}
        for recipe, made in pairs(FP.RecipeOutputs) do
            local list = byOutput[made]
            if not list then list = {} byOutput[made] = list end
            list[#list + 1] = recipe
        end
        for _, list in pairs(byOutput) do table.sort(list) end
    end
    return byOutput[itemID] or {}
end

-- One recipe is learned when the open profession says so, else when the character knows its spell.
local function Learned(recipeID)
    local e = FP.Recipes.byID[recipeID]
    if e then return e.learned and true or false end
    return IsPlayerSpell(recipeID) and true or false
end

-- What a result row shows of a recipe that doesn't depend on the character: { id, name, icon, skillLine, prof }.
local function Base(spell, line)
    local made = FP.RecipeOutputs[spell]
    return {
        id = spell, name = C_Spell.GetSpellName(spell) or ("[" .. spell .. "]"),
        icon = made and C_Item.GetItemIconByID(made) or C_Spell.GetSpellTexture(spell),
        skillLine = line, prof = C_TradeSkillUI.GetTradeSkillDisplayName(line) or "",
    }
end

local function Order(a, b)
    if a.learned ~= b.learned then return a.learned end
    if a.mine ~= b.mine then return a.mine end
    if a.prof ~= b.prof then return a.prof < b.prof end
    return a.name < b.name
end

-- Result rows { id, name, icon, skillLine, prof, learned, mine } for base entries: learned first, then those of your
-- professions, then by profession and name.
local function Results(bases)
    local owned, out = {}, {}
    for _, p in ipairs(FP:GetProfessions()) do owned[p.skillLine] = true end
    for i, b in ipairs(bases) do
        out[i] = { id = b.id, name = b.name, icon = b.icon, skillLine = b.skillLine, prof = b.prof,
            learned = Learned(b.id), mine = owned[b.skillLine] == true }
    end
    table.sort(out, Order)
    return out
end

-- The recipes that use the item.
function Uses:Find(itemID)
    local bases, data = {}, FP.ReagentUses[itemID]
    if not data then return bases end
    for recipe, skillLine in data:gmatch("(%d+),%d+,(%d+)") do
        bases[#bases + 1] = Base(tonumber(recipe), tonumber(skillLine))
    end
    return Results(bases)
end

local all -- every recipe in the game as a base entry with its lowercased name, built on the first search

local function AllRecipes()
    if not all then
        all = {}
        for line, list in pairs(FP.RecipeLines) do
            for id in list:gmatch("%d+") do
                local b = Base(tonumber(id), line)
                b.lower = strlower(b.name)
                all[#all + 1] = b
            end
        end
    end
    return all
end

-- The recipes, in any profession, whose name contains the text.
function Uses:Search(text)
    local typed, bases = strlower(strtrim(text)), {}
    if typed == "" then return bases end
    for _, b in ipairs(AllRecipes()) do
        if b.lower:find(typed, 1, true) then bases[#bases + 1] = b end
    end
    return Results(bases)
end
