local _, FP = ...
local L = FP.L
local UI = FP.UI
local STATUS_COLORS, ItemName = UI.STATUS_COLORS, UI.ItemName

-- A reagent's unit price in copper and where it came from: a vendor's price when known, else the auction price.
local function ReagentUnit(itemID)
    local vendor = FP.Prices:VendorUnit(itemID)
    if vendor then return vendor, "vendor" end
    local auction = FP.Prices:Unit(itemID)
    if auction then return auction, "auction" end
end

local function EstimateCraftCost(reagents)
    local total, priced, unpriced = 0, 0, 0
    for _, reagent in ipairs(reagents) do
        local unit = ReagentUnit(reagent.itemID)
        if unit then
            total = total + unit * reagent.need
            priced = priced + 1
        else
            unpriced = unpriced + 1
        end
    end
    return total, priced, unpriced
end

local function FillCostTip(tip, info)
    tip:AddLine(info.priced > 0 and L["Cost to Craft x%d: %s"]:format(info.count, FP.Prices:Format(info.total))
        or L["Cost unavailable: no known prices."], 1, 1, 1)
    for _, reagent in ipairs(info.reagents) do
        local unit, source = ReagentUnit(reagent.itemID)
        local right = unit and (FP.Prices:Format(unit * reagent.need) .. " |cff888888" .. L[source] .. "|r") or L["no price"]
        local r, g, b = 1, 1, 1
        if not unit then r, g, b = 0.9, 0.3, 0.3 end
        tip:AddDoubleLine(("%s x%d"):format(ItemName(reagent.itemID), reagent.need), right, 0.8, 0.8, 0.8, r, g, b)
    end
    tip:AddLine(" ")
    tip:AddLine(L["Uses Auctionator vendor price when available, with auction price as fallback."], 0.6, 0.6, 0.6, true)
end

local function ProfitMoney(copper)
    local text = FP.Prices:Format(math.abs(copper))
    return copper < 0 and ("(" .. text .. ")") or text
end

local function OutputItemID(recipeID)
    local output = UI.RecipeOutputInfo(recipeID)
    if not output then return end
    return output.itemID or (output.hyperlink and C_Item.GetItemInfoInstant(output.hyperlink))
end

-- Items one craft makes; a range is averaged.
local function OutputQuantity(recipeID)
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    local lo, hi = ok and schematic and schematic.quantityMin, ok and schematic and schematic.quantityMax
    if lo and hi and lo > 0 then return (lo + hi) / 2 end
    return 1
end

-- One craft's profit in copper after the standard auction house cut; nil when any reagent or the product can't be priced.
function UI.RecipeProfit(recipeID)
    local ev = FP.Recipes:Evaluate(recipeID)
    if #ev.reagents == 0 or FP.Recipes:IsEnchant(recipeID) then return end
    local cost, _, unpriced = EstimateCraftCost(ev.reagents)
    if unpriced > 0 then return end
    return FP.Prices:Profit(OutputItemID(recipeID), OutputQuantity(recipeID), cost).profit
end

local PROFIT_GREY = { 0.65, 0.65, 0.65 }

-- The profit line under the cost line: what the craft sells for on the auction house less its reagents.
local function UpdateProfit(d, e, ev, count, salvage, cost, priced, unpriced)
    d.profitInfo = nil
    if salvage or #ev.reagents == 0 then d.profit:SetText("") return end
    if priced == 0 then
        d.profit:SetText(L["Profit unavailable: reagent prices unknown"])
        d.profit:SetTextColor(unpack(PROFIT_GREY))
        return
    end
    local enchant = FP.Recipes:IsEnchant(e.id)
    local r = FP.Prices:Profit(not enchant and OutputItemID(e.id) or nil, enchant and 1 or OutputQuantity(e.id) * count, cost)
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
end

UI.EstimateCraftCost, UI.UpdateProfit, UI.FillCostTip, UI.FillProfitTip = EstimateCraftCost, UpdateProfit, FillCostTip, FillProfitTip
