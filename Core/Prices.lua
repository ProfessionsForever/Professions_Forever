local _, FP = ...
local P = {}
FP.Prices = P

local CALLER = "ProfessionsForever"

local function API() return _G.Auctionator and Auctionator.API and Auctionator.API.v1 end

function P:Available() return API() ~= nil end

-- Auctionator's last-scan lowest buyout for one item, in copper; nil when unavailable or never scanned.
function P:Unit(itemID)
    local api = API()
    if not (api and api.GetAuctionPriceByItemID) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, CALLER, itemID)
    if ok and type(price) == "number" and price > 0 then return price end
end

function P:VendorUnit(itemID)
    local api = API()
    if not (api and api.GetVendorPriceByItemID) then return nil end
    local ok, price = pcall(api.GetVendorPriceByItemID, CALLER, itemID)
    if ok and type(price) == "number" and price > 0 then return price end
end

function P:Format(copper)
    local fn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    return fn(math.floor(copper + 0.5))
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
