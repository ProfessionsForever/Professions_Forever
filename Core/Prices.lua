local _, FP = ...
local P = {}
FP.Prices = P

local CALLER = "ProfessionsForever"

local function API() return FP.db.useAuctionator and _G.Auctionator and Auctionator.API and Auctionator.API.v1 end

function P:Available() return API() ~= nil end

-- Asks Auctionator to say when its prices change (a full scan finished, or a search's prices were processed), so the
-- windows showing prices redraw with them. Registered once, when Auctionator is in use: at login, or when the Use
-- Auctionator switch is turned on. While it is off again, the updates are ignored.
local watching = false
function P:WatchScans()
    local api = API()
    if watching or not (api and api.RegisterForDBUpdate) then return end
    watching = pcall(api.RegisterForDBUpdate, CALLER, function()
        if API() then FP:Changed("prices") end
    end)
end
FP:RegisterEvent("PLAYER_LOGIN", function() P:WatchScans() end)

-- Auctionator's last-scan lowest buyout for one item, in copper; nil when unavailable or never scanned. With `link`
-- the price is that exact item's: gear with a random enchantment ("of the Bear") shares its ID with every other
-- enchantment of it, and their prices differ widely.
function P:Unit(itemID, link)
    local api = API()
    if not api then return nil end
    local ok, price
    if link then ok, price = pcall(api.GetAuctionPriceByItemLink, CALLER, link)
    else ok, price = pcall(api.GetAuctionPriceByItemID, CALLER, itemID) end
    if ok and type(price) == "number" and price > 0 then return price end
end

function P:VendorUnit(itemID)
    local api = API()
    if not (api and api.GetVendorPriceByItemID) then return nil end
    local ok, price = pcall(api.GetVendorPriceByItemID, CALLER, itemID)
    if ok and type(price) == "number" and price > 0 then return price end
end

-- A reagent's unit price in copper and where it came from: a vendor's price when known, else the auction price.
function P:ReagentUnit(itemID)
    local vendor = self:VendorUnit(itemID)
    if vendor then return vendor, "vendor" end
    local auction = self:Unit(itemID)
    if auction then return auction, "auction" end
end

-- What reagents ({ itemID, need }) cost: the total in copper of those with a price, how many have one, how many don't.
function P:CraftCost(reagents)
    local total, priced, unpriced = 0, 0, 0
    for _, reagent in ipairs(reagents) do
        local unit = self:ReagentUnit(reagent.itemID)
        if unit then
            total = total + unit * reagent.need
            priced = priced + 1
        else
            unpriced = unpriced + 1
        end
    end
    return total, priced, unpriced
end

-- Items one craft makes; a range is averaged.
function P:AverageMade(recipeID)
    local lo, hi = FP.Recipes:OutputQuantity(recipeID)
    return (lo + hi) / 2
end

-- One craft's profit in copper after the standard auction house cut; nil when any reagent or the product can't be priced.
function P:RecipeProfit(recipeID)
    local R = FP.Recipes
    local ev = R:Evaluate(recipeID)
    if #ev.reagents == 0 or R:IsEnchant(recipeID) then return end
    local cost, _, unpriced = self:CraftCost(ev.reagents)
    if unpriced > 0 then return end
    return self:Profit(R:OutputItemID(recipeID), self:AverageMade(recipeID), cost).profit
end

function P:Format(copper)
    return C_CurrencyInfo.GetCoinTextureString(math.floor(copper + 0.5))
end

-- Auction house cut: the standard rate, and the neutral auction house's.
P.CUT, P.NEUTRAL_CUT = 0.05, 0.15

local BIND_PICKUP, BIND_QUEST = 1, 4

-- What crafting `made` items (itemID is nil when the craft makes none, such as an enchant) is worth against `cost`
-- copper of reagents. status: "ok", "loading", "noItem", "soulbound" or "noPrice". The break-even price is per item.
function P:Profit(itemID, made, cost)
    made = math.max(made, 1)
    local r = { status = "ok", made = made, cost = cost,
        breakEven = cost / made / (1 - P.CUT), breakEvenNeutral = cost / made / (1 - P.NEUTRAL_CUT) }
    if not itemID then r.status = "noItem" return r end
    local name, _, _, _, _, _, _, _, _, _, sellPrice, _, _, bindType = C_Item.GetItemInfo(itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(itemID) -- GET_ITEM_INFO_RECEIVED triggers a refresh
        r.status = "loading"
        return r
    end
    r.vendor = (sellPrice or 0) * made
    r.vendorProfit = r.vendor - cost
    if bindType == BIND_PICKUP or bindType == BIND_QUEST then r.status = "soulbound" return r end
    r.unit = P:Unit(itemID)
    if not r.unit then r.status = "noPrice" return r end
    local gross = r.unit * made
    r.profit = gross * (1 - P.CUT) - cost
    r.profitNeutral = gross * (1 - P.NEUTRAL_CUT) - cost
    return r
end
