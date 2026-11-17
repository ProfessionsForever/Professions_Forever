local _, FP = ...
local L = FP.L
local Tips = FP.Tooltips

-- "Needed by Crafting Queues" on item tooltips, and how many are still to buy: the shopping list's numbers for that
-- item, so the bags, bank and loot window say what the queues still want without opening the list. Only items the
-- queues need; the shopping list's own rows add these lines themselves (Panels/Shopping/ShoppingList.lua).
-- With the detail key (or always, Options, Tooltips, Crafting Queues), under the total: each character whose queue
-- uses it, with how many, and under each one the queued recipes that use it, crafts and how many each takes.

local LABEL, DETAIL = { 0.8, 0.8, 0.8 }, { 0.6, 0.6, 0.6 }

local byItem -- [itemID] = the shopping list's row for it, built on first hover after a change

local function Row(itemID)
    local preview = Tips.preview
    if preview then return itemID == preview.itemID and preview.queue.row or nil end
    if not byItem then
        byItem = {}
        for _, e in ipairs(FP.Shop:Aggregate()) do byItem[e.itemID] = e end
    end
    return byItem[itemID]
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

local function AddRecipes(tip, itemID)
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
        AddRecipes(tip, itemID)
    elseif recipes == "shift" then
        return true
    end
end

local function Add(tip, _, itemID)
    local db = FP.db
    if not db.queueTooltip then return end
    local owner = tip:GetOwner()
    if owner and owner.ownQueueLines then return end
    local e = Row(itemID)
    if not (e and e.queue > 0) then return end
    Tips:Space(tip)
    tip:AddDoubleLine(L["Needed by Crafting Queues"], e.queue, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
    local hidden = Tips:AddQueueRecipes(tip, itemID)
    if db.queueTooltipToBuy and e.toBuy > 0 then
        tip:AddDoubleLine(L["Still to Buy"], e.toBuy, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
    end
    return true, hidden
end

Tips:Register("queue", Add, function() byItem = nil end)
