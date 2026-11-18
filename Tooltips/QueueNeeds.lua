local _, FP = ...
local L = FP.L
local Tips = FP.Tooltips

-- "On Shopping List", "Needed by Crafting Queues" and how many are still to buy on item tooltips: the shopping list's
-- numbers for that item, so the bags, bank and loot window say what is still wanted without opening the list. Any item
-- on the list, added by hand or by the queues; the shopping list's own rows add these lines themselves
-- (Panels/Shopping/ShoppingList.lua).
-- With the detail key (or always, Options, Tooltips, Crafting Queues and Shopping List), under the total: each character whose queue
-- uses it, with how many, and under each one the queued recipes that use it, crafts and how many each takes.
-- "Made by Queues" under it when another queue's crafts cover some of the need (Shop.cover), and "Crafts Into" on an item
-- no queue needs itself but that a known recipe turns into something they do.

local LABEL, DETAIL = { 0.8, 0.8, 0.8 }, { 0.6, 0.6, 0.6 }

local byItem, cover -- [itemID] = the shopping list's row for it, and who covers it (Shop.cover), built on first hover after a change

-- The item's shopping list row and its cover by other queues, either one nil.
local function Row(itemID)
    local preview = Tips.preview
    if preview then
        if itemID ~= preview.itemID then return end
        return preview.queue.row, preview.queue.cover
    end
    if not byItem then
        byItem = {}
        for _, e in ipairs(FP.Shop:Aggregate()) do byItem[e.itemID] = e end
        cover = FP.Shop.cover
    end
    return byItem[itemID], cover[itemID]
end

-- The queued recipes of `key`'s queue that use the item, most used first, and how many they take in all.
local function Uses(key, itemID)
    local list, total = {}, 0
    for _, q in ipairs(FP.Queue:Data(key)) do
        for _, r in ipairs(q.reagents) do
            if r.itemID == itemID then
                list[#list + 1] = { name = q.name, crafts = q.qty, need = r.qty * q.qty }
                total = total + r.qty * q.qty
            end
        end
    end
    table.sort(list, function(a, b) return a.need > b.need end)
    return list, total
end

-- The characters whose queues count toward the total, as the shopping list counts them (Shop:QueueNeeds): this one,
-- then with a faction-wide list your others of this faction, by name.
local function Characters()
    local me = FP.Alts:GetCharacterKey()
    local keys = { me }
    if FP.db.shoppingScope ~= "account" then return keys end
    local others = {}
    for key, rec in pairs(FP.db.characters) do
        if key ~= me and rec.queue and #rec.queue > 0 and not FP.Alts:IsOtherFaction(rec) then others[#others + 1] = key end
    end
    local chars = FP.db.characters
    table.sort(others, function(a, b) return (chars[a].name or a) < (chars[b].name or b) end)
    for _, key in ipairs(others) do keys[#keys + 1] = key end
    return keys
end

-- Each character using the item: { key, name, realm, class, total, list }, in the order above.
local function Groups(itemID)
    if Tips.preview then return Tips.preview.queue.groups end
    local groups = {}
    for _, key in ipairs(Characters()) do
        local list, total = Uses(key, itemID)
        if total > 0 then
            local rec = FP.db.characters[key]
            groups[#groups + 1] = { key = key, name = rec.name, realm = rec.realm, class = rec.class, total = total, list = list }
        end
    end
    return groups
end

local function RecipeText(u)
    return FP.db.queueTooltipCrafts and (u.name .. " x" .. u.crafts) or u.name
end

-- Each character whose queue uses the item, and their recipes, whatever Show the Recipes says. The recipe panel's
-- Queue Needed button shows them too.
function Tips:AddQueueRecipeLines(tip, itemID)
    local db, me = FP.db, FP.Alts:GetCharacterKey()
    for _, g in ipairs(Groups(itemID)) do
        local label = FP.Alts:Label(g)
        if db.queueTooltipGroup then
            local r, gr, b = FP.Alts:ClassColor(g.class)
            tip:AddDoubleLine(Tips:Indent(1) .. label, g.total, r, gr, b, 1, 1, 1)
            for _, u in ipairs(g.list) do
                tip:AddDoubleLine(Tips:Indent(2) .. RecipeText(u), u.need, DETAIL[1], DETAIL[2], DETAIL[3], unpack(DETAIL))
            end
        else
            -- One list: your recipes as they are, your alts' with their name after.
            for _, u in ipairs(g.list) do
                local text = RecipeText(u) .. (g.key ~= me and (" (" .. label .. ")") or "")
                tip:AddDoubleLine(Tips:Indent(1) .. text, u.need, DETAIL[1], DETAIL[2], DETAIL[3], unpack(DETAIL))
            end
        end
    end
end

-- The character and recipe lines, when Show the Recipes says so; returns true when they are held back for the detail
-- key. The shopping list's rows use it too, under their own Needed by Crafting Queues line.
function Tips:AddQueueRecipes(tip, itemID)
    local recipes = FP.db.queueTooltipRecipes
    if recipes == "always" or (recipes == "shift" and self:DetailDown()) then
        self:AddQueueRecipeLines(tip, itemID)
    elseif recipes == "shift" then
        return true
    end
end

-- Whether the detail lines show now; "held" when they wait for the detail key.
local function DetailShown()
    local recipes = FP.db.queueTooltipRecipes
    if recipes == "always" or (recipes == "shift" and Tips:DetailDown()) then return true end
    if recipes == "shift" then return "held" end
end

-- "Made by Queues": what other queues make of an item the queues need, beyond their own use (Shop.cover), and under it
-- on the detail key each character making it with their recipes. The shopping list's rows use it too. Returns true
-- when the detail is held back for the detail key.
function Tips:AddMadeBy(tip, c)
    if not (c and FP.db.queueTooltipMade) then return end
    tip:AddDoubleLine(L["Made by Queues"], c.made, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
    local shown = DetailShown()
    if shown ~= true then return shown == "held" end
    local keys, chars = {}, FP.db.characters
    for key in pairs(c.by) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return (chars[a].name or a) < (chars[b].name or b) end)
    for _, key in ipairs(keys) do
        local by, rec = c.by[key], chars[key]
        local names = {}
        for i, u in ipairs(by.recipes) do names[i] = RecipeText(u) end
        local r, g, b = FP.Alts:ClassColor(rec.class)
        tip:AddDoubleLine(self:Indent(1) .. FP.Alts:Label(rec) .. ": " .. table.concat(names, ", "), by.qty, r, g, b, 1, 1, 1)
    end
end

-- Characters of this faction who know a recipe, by name.
local function Knowers(recipeID)
    local names, chars = {}, FP.db.characters
    for _, key in ipairs(FP.Known:Who(recipeID)) do
        local rec = chars[key]
        if rec and not FP.Alts:IsOtherFaction(rec) then names[#names + 1] = FP.Alts:Label(rec) end
    end
    table.sort(names)
    return names
end

-- What a known recipe makes of this item that the queues still need, one level deep: { name, need, amount, recipes =
-- { { name, who } } } per item made, by name. The shopping list's netted queue part is the need.
local function CraftsInto(itemID)
    local preview = Tips.preview
    if preview then return preview.queue.craftsInto or {} end
    local uses, byOut, out = FP.ReagentUses[itemID], {}, {}
    if not uses then return out end
    for recipe, count in uses:gmatch("(%d+),(%d+),%d+") do
        recipe = tonumber(recipe)
        local made = FP.RecipeOutputs[recipe]
        local row = made and byItem[made]
        local who = row and row.queue > 0 and Knowers(recipe)
        if who and #who > 0 then
            local yield = FP.Recipes:OutputQuantity(recipe)
            local e = byOut[made]
            if not e then
                e = { name = FP.ItemName(made), need = row.queue, amount = 0, recipes = {} }
                byOut[made] = e
                out[#out + 1] = e
            end
            e.amount = math.max(e.amount, math.ceil(row.queue / yield) * tonumber(count))
            e.recipes[#e.recipes + 1] = { name = C_Spell.GetSpellName(recipe) or tostring(recipe), who = table.concat(who, ", ") }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- "Crafts Into" on an item no queue needs itself: what it is crafted into that the queues still need, how many of it
-- that takes, and on the detail key who knows each recipe. Returns true when the detail is held back.
local function AddCraftsInto(tip, itemID)
    local list = CraftsInto(itemID)
    if #list == 0 then return end
    Tips:Space(tip)
    tip:AddLine(L["Crafts Into"], LABEL[1], LABEL[2], LABEL[3])
    local shown = DetailShown()
    for _, e in ipairs(list) do
        tip:AddDoubleLine(Tips:Indent(1) .. L["%s: %d needed"]:format(e.name, e.need), e.amount, 1, 1, 1, 1, 1, 1)
        if shown == true then
            for _, r in ipairs(e.recipes) do
                tip:AddLine(Tips:Indent(2) .. r.name .. ": " .. r.who, DETAIL[1], DETAIL[2], DETAIL[3])
            end
        end
    end
    return true, shown == "held"
end

-- The block shows for any item on the list or needed by a queue, even with nothing left to buy: an item another
-- queue fully covers is off the list, and still says who makes it.
local function Add(tip, _, itemID)
    local db = FP.db
    local owner = tip:GetOwner()
    if owner and owner.ownQueueLines then return end
    local e, c = Row(itemID)
    local needed = c and c.need or (e and e.queue or 0)
    local added, hidden
    -- The options' previewer shows it on its sample too, though the sample is needed.
    if (needed == 0 or Tips.preview) and db.queueTooltipCraftsInto then added, hidden = AddCraftsInto(tip, itemID) end
    local onList, queue = db.shopTooltip and e, db.queueTooltip and needed > 0
    if not (onList or queue) then return added, hidden end
    Tips:Space(tip)
    if onList then tip:AddDoubleLine(L["On Shopping List"], e.needed, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1) end
    if queue then
        tip:AddDoubleLine(L["Needed by Crafting Queues"], needed, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
        if Tips:AddQueueRecipes(tip, itemID) then hidden = true end
        if Tips:AddMadeBy(tip, c) then hidden = true end
    end
    if db.queueTooltipToBuy and e and e.toBuy > 0 then
        tip:AddDoubleLine(L["Still to Buy"], e.toBuy, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
    end
    return true, hidden
end

Tips:Register("queue", Add, function() byItem, cover = nil, nil end)
