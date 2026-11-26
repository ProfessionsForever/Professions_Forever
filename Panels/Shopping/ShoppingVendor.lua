local _, FP = ...
local L = FP.L
local Shop = FP.Shop

-- "Buy List" button on the merchant window: buys what the open vendor sells of the items still to buy.
local BUTTON_W, BUTTON_H = 100, 22

local button, pending

-- What this vendor sells of the shopping list, limited by stock and by gold: { { index, name, qty, stack, chunk }, ... }
-- and their total price. Items bought with other currencies are left out.
function Shop:VendorOrders()
    local orders, total = {}, 0
    local want = {}
    for _, e in ipairs(self:Aggregate()) do
        if e.toBuy > 0 then want[e.itemID] = e.toBuy end
    end
    if not next(want) then return orders, total end
    local money = GetMoney()
    for i = 1, GetMerchantNumItems() do
        local id = GetMerchantItemID(i)
        local need = id and want[id]
        local info = need and C_MerchantFrame.GetItemInfo(i)
        if info and info.isPurchasable and not info.hasExtendedCost and not info.currencyID then
            want[id] = nil -- a second listing of the same item is ignored
            local stack = math.max(1, info.stackCount or 1)
            local stacks = math.ceil(need / stack)
            if info.numAvailable >= 0 then stacks = math.min(stacks, info.numAvailable) end
            if info.price > 0 then stacks = math.min(stacks, math.floor(money / info.price)) end
            if stacks > 0 then
                local cost = stacks * info.price
                money, total = money - cost, total + cost
                local maxStack = GetMerchantItemMaxStack(i)
                orders[#orders + 1] = { index = i, name = info.name, qty = stacks * stack, stack = stack,
                    chunk = math.max(stack, maxStack - maxStack % stack) }
            end
        end
    end
    return orders, total
end

local function Buy()
    for _, o in ipairs(Shop:VendorOrders()) do
        local left = o.qty
        while left > 0 do
            local n = math.min(left, o.chunk)
            BuyMerchantItem(o.index, n)
            left = left - n
        end
    end
end

-- Asks first, listing what it buys and the total, unless Options, Shopping List turns that off. Yes buys what the
-- vendor sells of the list at that moment.
local function OnClick()
    if not FP.db.confirmVendorBuy then return Buy() end
    local orders, total = Shop:VendorOrders()
    local lines = { L["Buy these items from this vendor?"], "" }
    for _, o in ipairs(orders) do lines[#lines + 1] = L["%d x %s"]:format(o.qty, o.name) end
    lines[#lines + 1] = ""
    lines[#lines + 1] = L["Total: %s"]:format(FP.Prices:Format(total))
    FP.UI:Confirm(L["Buy from the Shopping List"], table.concat(lines, "\n"), Buy)
end

local function FillTooltip(tip)
    local orders, total = Shop:VendorOrders()
    tip:AddLine(L["Buy from the Shopping List"], 1, 1, 1)
    for _, o in ipairs(orders) do tip:AddDoubleLine(o.name, o.qty, 1, 1, 1, 1, 1, 1) end
    if total > 0 then tip:AddLine(FP.Prices:Format(total), 1, 0.82, 0) end
end

local function Create()
    button = CreateFrame("Button", "ProfessionsForeverBuyButton", MerchantFrame, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_W, BUTTON_H)
    button:SetPoint("RIGHT", MerchantFrame.FilterDropdown, "LEFT", -4, 0)
    button:SetText(L["Buy List"])
    button:SetScript("OnClick", OnClick)
    FP.UI:Tooltip(button, FillTooltip)
    -- The buyback tab hides the list's items.
    hooksecurefunc("MerchantFrame_Update", function()
        if button.hasOrders then button:SetShown(MerchantFrame.selectedTab == 1) end
    end)
end

function Shop:UpdateVendorButton()
    if not (MerchantFrame and MerchantFrame:IsShown()) then return end
    if not button then
        if not MerchantFrame.FilterDropdown then return end
        Create()
    end
    button.hasOrders = #self:VendorOrders() > 0
    button:SetShown(button.hasOrders and MerchantFrame.selectedTab == 1)
end

-- Coalesces bursts of events into one refresh on the next frame, after the planner has seen the bag change.
function Shop:QueueVendorUpdate(force)
    if pending or not (force or (MerchantFrame and MerchantFrame:IsShown())) then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        Shop:UpdateVendorButton()
    end)
end

-- Bag changes reach the button through Shop:Update (FP:Changed("inventory")).
FP:RegisterEvent("MERCHANT_SHOW", function() Shop:QueueVendorUpdate(true) end)
FP:RegisterEvent("MERCHANT_UPDATE", function() Shop:QueueVendorUpdate() end)
