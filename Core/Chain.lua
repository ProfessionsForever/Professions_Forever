local _, FP = ...
local L = FP.L

-- Recipe chaining: a reagent you are short of but know how to craft is crafted first.
local Chain = {}
FP.Chain = Chain

local MAX_DEPTH = 6

-- chardb.makes[itemID] is the queue's description of a recipe (Queue:InfoFor) that makes the item, kept for every
-- learned recipe of a profession you have opened, so a reagent can be traced to a recipe in a profession that isn't
-- open now.
local recorded = {}

function Chain:Record()
    local R, makes = FP.Recipes, FP.chardb.makes
    if not FP.Queue:CurrentSkillLine() then return end
    for _, e in ipairs(R.list) do
        if e.learned and not recorded[e.id] and #R:GetReagents(e.id) > 0 and not R:IsEnchant(e.id) then
            local info = FP.Queue:InfoFor(e.id)
            if info and info.output then
                recorded[e.id] = true
                local old = makes[info.output.itemID]
                if not old or e.id <= old.id then makes[info.output.itemID] = info end
            end
        end
    end
end

-- The recipe that makes the item, when you still know one: a dropped profession takes its recipes with it, and
-- learning it again doesn't bring them back.
function Chain:Maker(itemID)
    local info = FP.chardb.makes[itemID]
    return info and IsPlayerSpell(info.id) and info or nil
end

-- What planning counts as already held of an item: bags, bank and mailbox, and what other characters hold when alts
-- count toward planning.
function Chain:Held(itemID)
    local _, _, total, mail = FP.Inv:Owned(itemID)
    if FP.Planner:Applies() then total = total + FP.Alts:GetEnabledAltTotal(itemID) end
    return total + mail
end

-- What to craft first for `count` crafts of `info` (Queue:InfoFor). steps lists { recipe, crafts } with makers before
-- the crafts that use them; short[itemID] is what raw materials would still be missing. Bags, bank and mailbox count, and
-- what other characters hold when alts count toward planning, less what the queue already needs and plus what it will
-- make: bars on a bank alt are sent for, not smelted again.
function Chain:Plan(info, count)
    local steps, short, supply, active = {}, {}, {}, { [info.id] = true }
    local function Have(itemID)
        if supply[itemID] == nil then
            supply[itemID] = self:Held(itemID) - FP.Queue:QueuedAmount(itemID) + FP.Queue:QueuedProduction(itemID)
        end
        return supply[itemID]
    end
    local function Expand(recipe, crafts, depth)
        for _, r in ipairs(recipe.reagents) do
            local need = r.qty * crafts
            local take = math.max(0, math.min(Have(r.itemID), need))
            supply[r.itemID] = Have(r.itemID) - take
            local missing = need - take
            local maker = missing > 0 and depth < MAX_DEPTH and self:Maker(r.itemID)
            if maker and not active[maker.id] then
                local makes = math.ceil(missing / maker.output.qty)
                active[maker.id] = true
                Expand(maker, makes, depth + 1)
                active[maker.id] = nil
                steps[#steps + 1] = { recipe = maker, crafts = makes }
                supply[r.itemID] = supply[r.itemID] + makes * maker.output.qty - missing
            elseif missing > 0 then
                short[r.itemID] = (short[r.itemID] or 0) + missing
            end
        end
    end
    Expand(info, count, 1)

    -- A recipe needed by two branches is one step.
    local merged, byRecipe = {}, {}
    for _, step in ipairs(steps) do
        local same = byRecipe[step.recipe.id]
        if same then same.crafts = same.crafts + step.crafts else
            byRecipe[step.recipe.id] = step
            merged[#merged + 1] = step
        end
    end
    return { steps = merged, short = short }
end

-- The detail panel's line when the recipe is short only of things you can craft, else nil.
function Chain:Describe(recipeID, count)
    local info = FP.Queue:InfoFor(recipeID)
    if not info or #info.reagents == 0 then return end
    local plan = self:Plan(info, count)
    if #plan.steps == 0 or next(plan.short) then return end
    local parts = {}
    for i, step in ipairs(plan.steps) do
        if i > 2 then
            parts[#parts + 1] = L["+%d more"]:format(#plan.steps - 2)
            break
        end
        parts[#parts + 1] = ("%dx %s"):format(step.crafts, step.recipe.name)
    end
    return L["Craftable after crafting: %s"]:format(table.concat(parts, ", "))
end
