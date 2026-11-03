local _, FP = ...
local L = FP.L
local UI = FP.UI

-- Crafting actions for the selected recipe, and the item picker for enchanting and salvaging.

-- The item chosen as the enchant or salvage target; only valid for the recipe it was chosen for.
UI.craftTarget, UI.craftTargetRecipe = nil, nil

function UI.CurrentTarget(recipeID)
    local target = UI.craftTarget
    if target and UI.craftTargetRecipe == recipeID then
        local guid = target:GetItemGUID()
        if guid and C_Item.IsItemGUIDInInventory(guid) then return target end
    end
    UI.craftTarget = nil
    return nil
end
local CurrentTarget = UI.CurrentTarget

-- Items the recipe can be applied to or break down (worn or in bags), from the game's own eligibility checks.
local function TargetItems(recipeID, salvage)
    local T = C_TradeSkillUI
    local out = {}
    if salvage then
        local okIDs, itemIDs = pcall(T.GetSalvagableItemIDs, recipeID)
        local ok, found = pcall(T.GetCraftingTargetItems, okIDs and type(itemIDs) == "table" and itemIDs or {})
        for _, target in ipairs(ok and type(found) == "table" and found or {}) do
            out[#out + 1] = Item:CreateFromItemGUID(target.itemGUID)
        end
    else
        local ok, guids = pcall(T.GetEnchantItems, recipeID, {})
        for _, guid in ipairs(ok and type(guids) == "table" and guids or {}) do
            out[#out + 1] = Item:CreateFromItemGUID(guid)
        end
    end
    return out
end

function UI.TargetMenu()
    local recipeID = FP.selected
    local R = FP.Recipes
    local salvage = recipeID and R:IsSalvage(recipeID)
    local need = salvage and R:SalvageQuantity(recipeID) or 1
    local current = recipeID and CurrentTarget(recipeID)
    local items = { { text = L["No Target"], checked = current == nil, onSelect = function()
        UI.craftTarget = nil
        UI:UpdateDetail()
    end } }
    local list = {}
    for _, item in ipairs(recipeID and TargetItems(recipeID, salvage) or {}) do
        list[#list + 1] = { item = item, name = item:GetItemName() or tostring(item:GetItemID()) }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    for _, entry in ipairs(list) do
        local item = entry.item
        local stack = item:GetStackCount() or 1
        -- A salvage stack smaller than one craft's worth can't be used.
        local enough = stack >= need
        local text = item:GetItemLink() or entry.name
        if salvage then text = text .. " x" .. stack end
        items[#items + 1] = { text = text, icon = item:GetItemIcon(), link = item:GetItemLink(), dim = not enough,
            checked = current ~= nil and current:GetItemGUID() == item:GetItemGUID(),
            onSelect = enough and function()
                UI.craftTarget, UI.craftTargetRecipe = item, recipeID
                UI:UpdateDetail()
            end or nil }
    end
    if #items == 1 then items[2] = { text = L["No Eligible Items"], dim = true } end
    return items
end

function UI.DoCraft(count)
    local id = FP.selected
    if not id then return end
    if InCombatLockdown() then return FP:Print(L["Cannot do that in combat."]) end
    if FP.Recipes:IsSalvage(id) then
        local target = CurrentTarget(id)
        if not target then return FP:Print(L["Choose an item to salvage first."]) end
        local location = target:GetItemLocation()
        if not location then return FP:Print(L["The item to salvage is no longer available."]) end
        count = math.min(count, math.floor((target:GetStackCount() or 0) / FP.Recipes:SalvageQuantity(id)))
        if count < 1 then return end
        local ok, err = pcall(C_TradeSkillUI.CraftSalvage, id, count, location, {}, false)
        if not ok then FP:Print(err) end
        return
    end
    local ev = FP.Recipes:Evaluate(id, 1)
    count = math.min(count, ev.craftBags)
    if count < 1 then return end
    if FP.Recipes:IsEnchant(id) then
        local target = CurrentTarget(id)
        if not target then return FP:Print(L["Choose an item to enchant first."]) end
        local location = target:GetItemLocation()
        if not location then return FP:Print(L["The enchant target is no longer available."]) end
        -- Only a stack of vellum can take several enchants; a worn or bagged item takes one.
        local crafts = target:IsStackable() and count or 1
        local ok, err = pcall(C_TradeSkillUI.CraftEnchant, id, crafts, {}, location, false)
        if not ok then FP:Print(err) end
        return
    end
    local ok, err = pcall(C_TradeSkillUI.CraftRecipe, id, count)
    if not ok then FP:Print(err) end
end
