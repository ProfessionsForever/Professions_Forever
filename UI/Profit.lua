local _, FP = ...
local L = FP.L
local UI = FP.UI
local STATUS_COLORS, ItemName = UI.STATUS_COLORS, FP.ItemName

-- The cost and profit lines of the recipe panel and their tooltips; the sums are in Core/Prices.lua.

local INDENT = "    "

-- A reagent count: whole, or to one decimal when a recipe that makes several leaves a share of a craft.
local function Count(n)
    return ("%g"):format(math.floor(n * 10 + 0.5) / 10)
end

-- What `need` of a crafted reagent (Prices:ReagentCost) are made from, one indented line per reagent of its recipe
-- with that reagent's share of the cost, and the same again under any of them that is crafted too.
local function AddCraftedParts(tip, cost, need, depth)
    local crafts = need / cost.made
    for _, part in ipairs(cost.parts) do
        local qty = part.qty * crafts
        tip:AddDoubleLine(("%s%s x%s"):format(INDENT:rep(depth), ItemName(part.itemID), Count(qty)),
            FP.Prices:Format(part.cost.unit * qty) .. " |cff888888" .. L[part.cost.source] .. "|r",
            0.6, 0.6, 0.6, 0.8, 0.8, 0.8)
        if part.cost.parts then AddCraftedParts(tip, part.cost, qty, depth + 1) end
    end
end

local function FillCostTip(tip, info)
    tip:AddLine(info.priced > 0 and L["Cost to Craft x%d: %s"]:format(info.count, FP.Prices:Format(info.total))
        or L["Cost unavailable: no known prices."], 1, 1, 1)
    for _, reagent in ipairs(info.reagents) do
        local cost = FP.Prices:ReagentCost(reagent.itemID)
        local right = cost and (FP.Prices:Format(cost.unit * reagent.need) .. " |cff888888" .. L[cost.source] .. "|r") or L["no price"]
        local r, g, b = 1, 1, 1
        if not cost then r, g, b = 0.9, 0.3, 0.3 end
        tip:AddDoubleLine(("%s x%d"):format(ItemName(reagent.itemID), reagent.need), right, 0.8, 0.8, 0.8, r, g, b)
        if cost and cost.parts then AddCraftedParts(tip, cost, reagent.need, 1) end
    end
    tip:AddLine(" ")
    tip:AddLine(L["The cheapest of the vendor price, the auction price and the cost of crafting it."], 0.6, 0.6, 0.6, true)
    local scan = FP.Prices:ScanText()
    if scan then tip:AddLine(scan) end
end

local function ProfitMoney(copper)
    local text = FP.Prices:Format(math.abs(copper))
    return copper < 0 and ("(" .. text .. ")") or text
end

local PROFIT_GREY = { 0.65, 0.65, 0.65 }

-- The profit line under the cost line: what the craft sells for on the auction house less its reagents.
local function UpdateProfit(d, e, ev, count, cost, priced, unpriced)
    d.profitInfo = nil
    if #ev.reagents == 0 then d.profit:SetText("") return end
    if priced == 0 then
        d.profit:SetText(L["Profit unavailable: reagent prices unknown"])
        d.profit:SetTextColor(unpack(PROFIT_GREY))
        return
    end
    local enchant = FP.Recipes:IsEnchant(e.id)
    local r = FP.Prices:Profit(not enchant and FP.Recipes:OutputItemID(e.id) or nil, enchant and 1 or FP.Prices:AverageMade(e.id) * count, cost)
    d.profitInfo = { r = r, unpriced = unpriced }
    local text, c = "", PROFIT_GREY
    if r.status == "ok" then
        text = L["Profit on x%d: %s"]:format(count, ProfitMoney(r.profit))
        c = r.profit >= 0 and STATUS_COLORS.full or STATUS_COLORS.missing
    elseif r.status == "noItem" then
        text = L["Sell for at least %s to break even"]:format(FP.Prices:Format(r.breakEven))
    elseif r.status == "soulbound" then
        text = L["Profit: not sellable (soulbound)"]
    elseif r.status == "noPrice" then
        text = L["Profit unavailable: no auction price"]
    else
        text = L["Profit: loading item data..."]
    end
    d.profit:SetText(text)
    d.profit:SetTextColor(c[1], c[2], c[3])
end

local function FillProfitTip(tip, info)
    local r, Prices = info.r, FP.Prices
    local function Money(label, copper) tip:AddDoubleLine(label, Prices:Format(copper), 0.8, 0.8, 0.8, 1, 1, 1) end
    local function Result(label, copper)
        local c = copper >= 0 and STATUS_COLORS.full or STATUS_COLORS.missing
        tip:AddDoubleLine(label, ProfitMoney(copper), 0.8, 0.8, 0.8, c[1], c[2], c[3])
    end
    tip:AddLine(L["Profit Estimate"], 1, 1, 1)
    Money(L["Reagent Cost"], r.cost)
    if info.unpriced > 0 then
        tip:AddLine(L["Some reagent prices are missing, so the real profit is lower."], 1, 0.5, 0.3, true)
    end
    if r.status == "loading" then
        tip:AddLine(L["Loading item data..."], 0.6, 0.6, 0.6)
        return
    end
    if r.status == "ok" then
        Money(L["Auction Price (each)"], r.unit)
        tip:AddDoubleLine(L["Items Made"], ("%g"):format(r.made), 0.8, 0.8, 0.8, 1, 1, 1)
        tip:AddLine(" ")
        tip:AddLine(L["After the standard 5% auction house cut:"], 1, 0.82, 0)
        Result(L["Profit"], r.profit)
        tip:AddLine(L["After the 15% neutral auction house cut:"], 1, 0.82, 0)
        Result(L["Profit"], r.profitNeutral)
    else
        local why = r.status == "soulbound" and "Soulbound items can't be sold on the auction house."
            or r.status == "noItem" and "This craft makes no item that can be sold yet."
            or "No Auctionator price for this item."
        tip:AddLine(L[why], 0.8, 0.8, 0.8, true)
    end
    if r.status ~= "soulbound" then
        tip:AddLine(" ")
        Money(L["Break-Even Price (5% Cut)"], r.breakEven)
        Money(L["Break-Even Price (15% Cut)"], r.breakEvenNeutral)
    end
    if r.vendor and r.vendor > 0 then
        tip:AddLine(" ")
        Money(L["Sell to a vendor"], r.vendor)
        Result(L["Profit"], r.vendorProfit)
    end
    local scan = Prices:ScanText()
    if scan then tip:AddLine(scan) end
end

UI.UpdateProfit, UI.FillCostTip, UI.FillProfitTip = UpdateProfit, FillCostTip, FillProfitTip
