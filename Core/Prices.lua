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

-- "Auction Price: 25c each" on the addon's own item tooltips. Options, Tooltips, Prices and Hints: by default not while
-- Auctionator already shows its auction price there, or always, or never. `unit` stands in for the real price (the
-- options' previewer).
function P:AddUnitLine(tip, itemID, unit)
    local mode = FP.db.tipAuctionPrice
    if mode == "never" then return end
    local A = _G.Auctionator
    if mode == "auto" and A and A.Config and A.Config.Get(A.Config.Options.AUCTION_TOOLTIPS) then return end
    unit = unit or self:Unit(itemID)
    if unit then tip:AddLine(FP.L["Auction Price: %s each"]:format(self:Format(unit)), 1, 0.82, 0) end
end

function P:VendorUnit(itemID)
    local api = API()
    if not (api and api.GetVendorPriceByItemID) then return nil end
    local ok, price = pcall(api.GetVendorPriceByItemID, CALLER, itemID)
    if ok and type(price) == "number" and price > 0 then return price end
end

-- Crafted reagents inside crafted reagents are followed at most this deep (Bolt of Silk Cloth in a robe is depth 1).
local MAX_DEPTH = 4

-- Reagent prices last until the next frame: the profit sort prices every recipe at once, and new auction or vendor
-- prices and newly learned recipes are read fresh after.
local cache, clearing = {}, false
local function ClearCache()
    wipe(cache)
    clearing = false
end
local function Remember(itemID, cost)
    cache[itemID] = cost
    if not clearing then
        clearing = true
        C_Timer.After(0, ClearCache)
    end
end

-- Whether a recipe counts toward a reagent's price: this character knows it, or, with priceCraftedAlts, another of
-- your characters does who could get the materials by mail (Alts:IsEligible: switched on, same faction).
local function Usable(recipeID)
    if IsPlayerSpell(recipeID) then return true end
    if not FP.db.priceCraftedAlts then return false end
    for _, key in ipairs(FP.Known:Who(recipeID)) do
        if FP.Alts:IsEligible(key, FP.db.characters[key]) then return true end
    end
    return false
end

local Resolve

-- One craft's cost per item made: { unit, source = "crafted", recipe, made, parts = { { itemID, qty, cost } } }, each
-- part's cost being what Resolve gave it; nil when one of its reagents has no price. The second result is true when a
-- reagent somewhere below was priced without crafting to break a loop (see Resolve).
local function CraftCostOf(recipeID, depth, visiting)
    local reagents = FP.Uses:ReagentsOf(recipeID)
    if #reagents == 0 then return end
    local total, parts, cut = 0, {}, false
    for i, r in ipairs(reagents) do
        local cost, c = Resolve(r.itemID, depth + 1, visiting)
        cut = cut or c
        if not cost then return nil, cut end
        total = total + cost.unit * r.qty
        parts[i] = { itemID = r.itemID, qty = r.qty, cost = cost }
    end
    local made = P:AverageMade(recipeID)
    return { unit = total / made, source = "crafted", recipe = recipeID, made = made, parts = parts }, cut
end

-- The cheapest way to get one of the item: { unit, source = "vendor" | "auction" } or CraftCostOf's result; nil when
-- nothing prices it. Ties go to the vendor, then the auction house. Some recipes make each other's reagents
-- (transmutes go in circles), so an item already being priced further up, or past MAX_DEPTH, is priced without
-- crafting; such a result is "cut" and not remembered, since higher up it may be priced differently.
function Resolve(itemID, depth, visiting)
    local hit = cache[itemID]
    if hit ~= nil then return hit or nil, false end
    local best
    local vendor, auction = P:VendorUnit(itemID), P:Unit(itemID)
    if vendor then best = { unit = vendor, source = "vendor" } end
    if auction and not (best and best.unit <= auction) then best = { unit = auction, source = "auction" } end
    local cut = false
    local makers = FP.db.priceCrafted and FP.Uses:MakersOf(itemID) or {}
    if #makers > 0 then
        if visiting[itemID] or depth > MAX_DEPTH then
            cut = true
        else
            visiting[itemID] = true
            for _, recipe in ipairs(makers) do
                if Usable(recipe) then
                    local craft, c = CraftCostOf(recipe, depth, visiting)
                    cut = cut or c
                    if craft and not (best and best.unit <= craft.unit) then best = craft end
                end
            end
            visiting[itemID] = nil
        end
    end
    if not cut then Remember(itemID, best or false) end
    return best, cut
end

-- A reagent's cheapest price per item, with where it comes from (see Resolve); nil when it has no price. Treat the
-- result as read-only: it is shared until the next frame.
function P:ReagentCost(itemID)
    return (Resolve(itemID, 1, {}))
end

-- A reagent's unit price in copper and where it came from: "vendor", "auction" or "crafted", whichever is cheapest.
function P:ReagentUnit(itemID)
    local cost = self:ReagentCost(itemID)
    if cost then return cost.unit, cost.source end
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
