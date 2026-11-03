local _, FP = ...
local R = { list = {}, byID = {}, categories = {} }
FP.Recipes = R

local BASIC = (Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 1
local schematics, evalCache = {}, {}
local floor, min, max, huge = math.floor, math.min, math.max, math.huge

-- Rebuild the recipe list for the currently open profession.
function R:Reload()
    wipe(self.list)
    wipe(self.byID)
    local ids = C_TradeSkillUI.GetAllRecipeIDs() or {}
    for _, id in ipairs(ids) do
        local info = C_TradeSkillUI.GetRecipeInfo(id)
        if info and info.name then
            local e = { id = id, name = info.name, icon = info.icon, learned = info.learned,
                difficulty = info.relativeDifficulty, categoryID = info.categoryID,
                verb = info.abilityVerb or info.alternateVerb, allVerb = info.abilityAllVerb,
                favorite = self:IsFavorite(id) }
            self.byID[id] = e
            self.list[#self.list + 1] = e
        end
    end
    self:LoadCategories()
    table.sort(self.list, function(a, b)
        if a.learned ~= b.learned then return a.learned and true or false end
        return a.name < b.name
    end)
    self:ResetEvalCache()
end

function R:ResetEvalCache() wipe(evalCache) end

-- Category filter value for the favorites group.
R.FAVORITES = "\1favorites"

-- Favorites are the game's own, shared with Blizzard's window.
function R:IsFavorite(recipeID)
    return C_TradeSkillUI.IsRecipeFavorite(recipeID) and true or false
end

function R:SetFavorite(recipeID, on)
    C_TradeSkillUI.SetRecipeFavorite(recipeID, on)
    local e = self.byID[recipeID]
    if e then e.favorite = on and true or false end
end

local typeCache, salvageQuantity = {}, {}

-- The recipe's Enum.TradeskillRecipeType, or nil until its schematic has loaded (not cached before then).
local function RecipeType(recipeID)
    local cached = typeCache[recipeID]
    if cached ~= nil then return cached end
    local T = C_TradeSkillUI
    if not (T.GetRecipeSchematic and Enum.TradeskillRecipeType) then return nil end
    local ok, schematic = pcall(T.GetRecipeSchematic, recipeID, false)
    if not (ok and schematic) then return nil end
    typeCache[recipeID] = schematic.recipeType
    salvageQuantity[recipeID] = max(1, schematic.quantityMax or 1)
    return schematic.recipeType
end

-- True for enchanting recipes, which are crafted onto a chosen item instead of producing one.
function R:IsEnchant(recipeID)
    local kinds = Enum.TradeskillRecipeType
    return kinds ~= nil and RecipeType(recipeID) == kinds.Enchant
end

-- True for salvage recipes (prospecting, milling...), which break down a chosen stack of items.
function R:IsSalvage(recipeID)
    local kinds = Enum.TradeskillRecipeType
    return kinds ~= nil and RecipeType(recipeID) == kinds.Salvage
end

-- Items consumed per craft of a salvage recipe.
function R:SalvageQuantity(recipeID)
    RecipeType(recipeID)
    return salvageQuantity[recipeID] or 1
end

-- The open profession's trade categories (the same tree Blizzard's window shows), found by walking up
-- from each recipe's category, so it doesn't depend on the client's category-listing call.
function R:LoadCategories()
    local T = C_TradeSkillUI
    wipe(self.categories)
    if not T.GetCategoryInfo then return end
    -- Some clients return one table of IDs, others return the IDs as separate values.
    local order = {}
    if T.GetCategories then
        local result = { pcall(T.GetCategories) }
        local ids = type(result[2]) == "table" and result[2] or { unpack(result, 2) }
        for i, id in ipairs(ids) do order[id] = i end
    end
    local function Add(id)
        while id and id ~= 0 and not self.categories[id] do
            local ok, info = pcall(T.GetCategoryInfo, id)
            if not (ok and type(info) == "table" and info.name) then return end
            local parent = info.parentCategoryID
            self.categories[id] = { id = id, name = info.name, order = order[id] or (1000 + id),
                parent = (parent and parent ~= 0) and parent or nil }
            id = parent
        end
    end
    for _, e in ipairs(self.list) do Add(e.categoryID) end
end

-- Splits the category table into root categories and a parent-to-children map, both in game order.
local function BuildTree(cats)
    local roots, children = {}, {}
    for _, c in pairs(cats) do
        if c.parent and cats[c.parent] then
            children[c.parent] = children[c.parent] or {}
            table.insert(children[c.parent], c)
        else
            roots[#roots + 1] = c
        end
    end
    local byOrder = function(a, b) return a.order < b.order end
    table.sort(roots, byOrder)
    for _, list in pairs(children) do table.sort(list, byOrder) end
    return roots, children
end

-- Category names for the filter, depth-first, as { name, depth }; names repeated under several parents are merged.
function R:CategoryNames()
    local roots, children = BuildTree(self.categories)
    local out, seen = {}, {}
    local function Walk(c, depth)
        if not seen[c.name] then
            seen[c.name] = true
            out[#out + 1] = { name = c.name, depth = depth }
        end
        for _, child in ipairs(children[c.id] or {}) do Walk(child, depth + 1) end
    end
    for _, root in ipairs(roots) do Walk(root, 0) end
    return out
end

-- True when the recipe sits in a category called `name`, or below one.
function R:InCategoryNamed(e, name)
    local c = self.categories[e.categoryID]
    while c do
        if c.name == name then return true end
        c = c.parent and self.categories[c.parent]
    end
    return false
end

---@class FPDisplayItem
---@field recipe table?
---@field category table?
---@field depth integer
---@field count any set on category headers
---@field open any set on category headers

-- Flattens recipes into category headers and recipe rows: { category, depth, count, open } or { recipe, depth }.
-- `collapsed` maps categoryID to true; `expandAll` ignores it (used while searching).
---@return FPDisplayItem[]
function R:BuildDisplay(recipes, collapsed, expandAll, showCategories, favoritesOnly)
    local cats = self.categories
    if showCategories == false then
        local out = {}
        for _, e in ipairs(recipes) do out[#out + 1] = { recipe = e, depth = 0 } end
        return out
    end
    -- Favorites come first as their own group; those recipes also stay in their normal categories.
    local out, favorites = {}, {}
    for _, e in ipairs(recipes) do
        if e.favorite and not favoritesOnly then favorites[#favorites + 1] = e end
    end
    if #favorites > 0 then
        local open = expandAll or not collapsed.favorites
        out[#out + 1] = { category = { id = "favorites", name = FP.L["Favorites"] }, depth = 0, count = #favorites, open = open }
        if open then
            for _, e in ipairs(favorites) do out[#out + 1] = { recipe = e, depth = 1 } end
        end
    end
    if not next(cats) then
        for _, e in ipairs(recipes) do out[#out + 1] = { recipe = e, depth = 0 } end
        return out
    end
    local direct, uncategorized = {}, {}
    for _, e in ipairs(recipes) do
        local c = cats[e.categoryID]
        if c then
            direct[c.id] = direct[c.id] or {}
            table.insert(direct[c.id], e)
        else
            uncategorized[#uncategorized + 1] = e
        end
    end
    local roots, children = BuildTree(cats)
    local counts = {}
    local function Count(c)
        local n = direct[c.id] and #direct[c.id] or 0
        for _, child in ipairs(children[c.id] or {}) do n = n + Count(child) end
        counts[c.id] = n
        return n
    end
    for _, c in ipairs(roots) do Count(c) end

    local function Emit(c, depth)
        if (counts[c.id] or 0) == 0 then return end
        local open = expandAll or not collapsed[c.id]
        out[#out + 1] = { category = c, depth = depth, count = counts[c.id], open = open }
        if not open then return end
        for _, e in ipairs(direct[c.id] or {}) do out[#out + 1] = { recipe = e, depth = depth + 1 } end
        for _, child in ipairs(children[c.id] or {}) do Emit(child, depth + 1) end
    end
    for _, c in ipairs(roots) do Emit(c, 0) end
    for _, e in ipairs(uncategorized) do out[#out + 1] = { recipe = e, depth = 0 } end
    return out
end

-- Basic reagents only: { itemID, qty }.
function R:GetReagents(recipeID)
    if schematics[recipeID] then return schematics[recipeID] end
    local schem = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    local out = {}
    for _, slot in ipairs(schem and schem.reagentSlotSchematics or {}) do
        local reagent = slot.reagentType == BASIC and slot.reagents and slot.reagents[1]
        if reagent and reagent.itemID then out[#out + 1] = { itemID = reagent.itemID, qty = max(1, slot.quantityRequired or 1) } end
    end
    if schem then schematics[recipeID] = out end -- don't cache when data wasn't ready
    return out
end

-- Material evaluation for `count` crafts.
-- status: full (bags suffice), bank (complete only with bank), partial, missing, none.
function R:Evaluate(recipeID, count)
    count = count or 1
    if count == 1 and evalCache[recipeID] then return evalCache[recipeID] end
    local reagents = self:GetReagents(recipeID)
    local ev = { reagents = {}, count = count, craftBags = 0, craftTotal = 0, haveAny = false, satisfied = 0, anyShort = false }
    local cb, ct = huge, huge
    for i, r in ipairs(reagents) do
        local bags, bank, total = FP.Inv:Owned(r.itemID)
        local need = r.qty * count
        local short = max(0, need - total)
        ev.reagents[i] = { itemID = r.itemID, qty = r.qty, need = need, bags = bags, bank = bank, total = total, short = short }
        -- Whole crafts only: partial stacks never count toward an extra craft.
        cb = min(cb, floor(bags / r.qty))
        ct = min(ct, floor(total / r.qty))
        if total > 0 then ev.haveAny = true end
        if short == 0 then ev.satisfied = ev.satisfied + 1 else ev.anyShort = true end
    end
    if #reagents == 0 then
        ev.status = "none"
    else
        ev.craftBags, ev.craftTotal = cb, ct
        if cb >= count then ev.status = "full"
        elseif ct >= count then ev.status = "bank"
        elseif ev.haveAny then ev.status = "partial"
        else ev.status = "missing" end
    end
    if count == 1 then evalCache[recipeID] = ev end
    return ev
end

-- Adds what other characters could contribute, from the shared transfer plan; the detail panel only, since the
-- recipe list never needs it. craftBags and craftTotal stay current-character values.
--   ev.craftWithAlts: whole crafts with current stock plus enabled alts (never below craftTotal)
--   ev.plan: allocation for the requested count; ev.planMax: allocation for craftWithAlts crafts
--   ev.altsCover: every shortage of the requested count can be met from alts
--   reagent.alts / totalWithAlts / shortAfterAlts / shortage / plan: that reagent's slice of ev.plan
function R:EvaluateAlts(ev)
    local P = FP.Planner
    if ev.altsVersion == P:Version() then return ev end
    ev.altsVersion = P:Version()
    ev.craftWithAlts, ev.plan, ev.planMax, ev.altsCover = ev.craftTotal, nil, nil, false
    if #ev.reagents == 0 then return ev end
    ev.plan = P:Plan(ev.reagents)
    for _, r in ipairs(ev.reagents) do
        local it = ev.plan.byItem[r.itemID]
        r.plan, r.alts, r.totalWithAlts = it, it.altAvailable, r.total + it.altAvailable
        r.shortAfterAlts, r.shortage = it.stillMissing, it.shortage
    end
    ev.altsCover = ev.anyShort and ev.plan.totals.covered and P:Mode() ~= "never"
    if P:Mode() == "never" then return ev end
    ev.craftWithAlts = max(ev.craftTotal, P:MaxCrafts(ev.reagents))
    if ev.craftWithAlts > ev.craftTotal then
        local reqs = {}
        for i, r in ipairs(ev.reagents) do reqs[i] = { itemID = r.itemID, need = r.qty * ev.craftWithAlts } end
        ev.planMax = P:Plan(reqs)
    end
    return ev
end

-- Lowercased recipe and reagent names in one string, so a search is one find per recipe. Rebuilt until every
-- reagent name has loaded.
local function SearchText(self, e)
    if e.searchDone then return e.searchText end
    local reagents = self:GetReagents(e.id)
    e.nameLower = e.nameLower or strlower(e.name)
    local parts, done = { e.nameLower }, #reagents > 0
    for _, r in ipairs(reagents) do
        local n = C_Item.GetItemNameByID(r.itemID)
        if n then parts[#parts + 1] = strlower(n) else done = false end
    end
    e.searchText, e.searchDone = table.concat(parts, "\n"), done
    return e.searchText
end

-- A search term matches the recipe name or any of its reagent names (names that haven't loaded yet are skipped).
local function MatchesSearch(self, e, search)
    return strfind(SearchText(self, e), search, 1, true) ~= nil
end

-- Sort keys: lower sorts first, compared in order; ties fall back on the name.
-- craftable: crafts from bags, then with the bank, then with enabled alts, then reagents already held in full.
local function SortValue(self, e, key)
    if key == "difficulty" then return e.learned and (e.difficulty or 9) or 10 end
    if key == "craftable" then
        local ev = self:Evaluate(e.id)
        return -ev.craftBags, -ev.craftTotal, -max(ev.craftTotal, FP.Planner:MaxCrafts(ev.reagents)), -ev.satisfied
    end
    if key == "profit" then
        local profit = FP.UI.RecipeProfit(e.id)
        return profit and -profit or huge
    end
    return e.learned and 0 or 1
end

-- o: search, categoryName, showUnlearned, unlearnedOnly, matsOnly, skillUps, hideTrivial, sortKey (name|difficulty|craftable|profit), sortDesc.
function R:GetFiltered(o)
    local out = {}
    local search = o.search and strlower(o.search) or ""
    for _, e in ipairs(self.list) do
        if (o.unlearnedOnly and not e.learned or not o.unlearnedOnly and (e.learned or o.showUnlearned))
            and (not o.categoryName or (o.categoryName == R.FAVORITES and e.favorite)
                or (o.categoryName ~= R.FAVORITES and self:InCategoryNamed(e, o.categoryName)))
            and (search == "" or MatchesSearch(self, e, search))
            and (not o.skillUps or (e.learned and e.difficulty ~= nil and e.difficulty <= 1))
            and (not o.hideTrivial or e.difficulty ~= 3)
            and (not o.favoritesOnly or e.favorite)
            and (not o.matsOnly or self:Evaluate(e.id).haveAny) then
            out[#out + 1] = e
        end
    end
    local key = o.sortKey or "name"
    if key == "profit" and not FP.Prices:Available() then key = "name" end
    if key ~= "name" or o.sortDesc then
        local keys = {}
        for _, e in ipairs(out) do keys[e] = { SortValue(self, e, key) } end
        table.sort(out, function(a, b)
            if o.sortDesc then a, b = b, a end
            local va, vb = keys[a], keys[b]
            for i = 1, #va do
                if va[i] ~= vb[i] then return va[i] < vb[i] end
            end
            return a.name < b.name
        end)
    end
    return out
end
