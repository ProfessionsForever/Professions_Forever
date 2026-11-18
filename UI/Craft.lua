local _, FP = ...
local L = FP.L
local UI = FP.UI

-- Crafting actions for the selected recipe, and the item picker for enchanting.

-- The item chosen as the enchant target; only valid for the recipe it was chosen for.
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

-- Items the recipe can be applied to (worn or in bags), from the game's own eligibility checks.
local function TargetItems(recipeID)
    local out = {}
    local ok, guids = pcall(C_TradeSkillUI.GetEnchantItems, recipeID, {})
    for _, guid in ipairs(ok and type(guids) == "table" and guids or {}) do
        out[#out + 1] = Item:CreateFromItemGUID(guid)
    end
    return out
end

function UI.TargetMenu()
    local recipeID = FP.selected
    local current = recipeID and CurrentTarget(recipeID)
    local items = { { text = L["No Target"], checked = current == nil, onSelect = function()
        UI.craftTarget = nil
        UI:UpdateDetail()
    end } }
    local list = {}
    for _, item in ipairs(recipeID and TargetItems(recipeID) or {}) do
        list[#list + 1] = { item = item, name = item:GetItemName() or tostring(item:GetItemID()) }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    for _, entry in ipairs(list) do
        local item = entry.item
        items[#items + 1] = { text = item:GetItemLink() or entry.name, icon = item:GetItemIcon(), link = item:GetItemLink(),
            checked = current ~= nil and current:GetItemGUID() == item:GetItemGUID(),
            onSelect = function()
                UI.craftTarget, UI.craftTargetRecipe = item, recipeID
                UI:UpdateDetail()
            end }
    end
    if #items == 1 then items[2] = { text = L["No Eligible Items"], dim = true } end
    return items
end

-- The running batch ({ id, left }); the quantity box shows the crafts still to do, as Blizzard's does.
UI.craftBatch = nil

local function ShowBatchCount(id, n)
    local qty = UI.frame and FP.selected == id and UI.frame.detail.qty
    n = math.min(n, 999)
    if qty and qty:GetText() ~= tostring(n) then qty:SetText(n) end
end

local function StartBatch(id, count)
    UI.craftBatch = { id = id, left = count }
    ShowBatchCount(id, count)
end

-- A craft of the batch's recipe finished.
function UI:OnCraftCast(spellID)
    local batch = self.craftBatch
    if not batch or spellID ~= batch.id then return end
    batch.left = batch.left - 1
    if batch.left > 0 then return ShowBatchCount(batch.id, batch.left) end
    self.craftBatch = nil
    ShowBatchCount(batch.id, 1)
end

-- The cast sequence stopped, finished or not.
function UI:EndCraftBatch()
    local batch = self.craftBatch
    if not batch then return end
    self.craftBatch = nil
    ShowBatchCount(batch.id, 1)
end

-- The window closed or moved to another tab or profession: forget the batch and the typed quantity.
function UI:ResetCraftQty()
    self.craftBatch = nil
    local qty = self.frame and self.frame.detail.qty
    if qty and qty:GetText() ~= "1" then qty:SetText(1) end
end

function UI.DoCraft(count)
    local id = FP.selected
    if not id then return end
    if InCombatLockdown() then return FP:Print(L["Cannot do that in combat."]) end
    local ev = FP.Recipes:Evaluate(id, 1)
    count = math.min(count, ev.craftBags)
    if count < 1 then return end
    if FP.Recipes:IsEnchant(id) then
        local target = CurrentTarget(id)
        -- No target: cast for a targeting cursor, as Blizzard's window does, to enchant an item in the trade window.
        if not target then
            local ok, err = pcall(C_TradeSkillUI.CraftRecipe, id, 1)
            if not ok then FP:Print(err) else StartBatch(id, 1) end
            return
        end
        local location = target:GetItemLocation()
        if not location then return FP:Print(L["The enchant target is no longer available."]) end
        -- Only a stack of vellum can take several enchants; a worn or bagged item takes one.
        local crafts = target:IsStackable() and count or 1
        local ok, err = pcall(C_TradeSkillUI.CraftEnchant, id, crafts, {}, location, false)
        if not ok then FP:Print(err) else StartBatch(id, crafts) end
        return
    end
    local ok, err = pcall(C_TradeSkillUI.CraftRecipe, id, count)
    if not ok then FP:Print(err) else StartBatch(id, count) end
end
