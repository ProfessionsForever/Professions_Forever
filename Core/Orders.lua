local _, FP = ...

-- Forever's Waylaid Crates and Craftsman's Writs (Data/Orders.lua), for the Crates and Writs window: which of them are
-- worth doing, and the cheapest way to do each.
--
-- A crate is filled with any one of its bundles, becomes a Sealed crate, and is handed in at your faction's camp for
-- Merchant's Favor: nothing else. A writ asks for one crafted item, handed to a customer out in the world for
-- reputation with the camp's faction; each writ can be done once a day.
local Orders = {}
FP.Orders = Orders

Orders.FAVOR = 3402 -- the Merchant's Favor currency
local FACTIONS = { Alliance = 2586, Horde = 2587 } -- Azeroth Commerce Authority, Durotar Supply and Logistics
Orders.TIERS = { "Apprentice", "Journeyman", "Expert", "Artisan", "Elite" }

-- Favor a Sealed crate pays, by its item ID, as far as it is known (2026-11-19): white Apprentice, Journeyman and
-- Expert crates pay 5, 10 and 15, green ones double. Artisan, Elite and blue crates aren't known: what a hand-in pays
-- is recorded (FP.db.cratePay), and a recorded value wins.
local KNOWN_PAY = { [248765] = 5, [248766] = 10, [248767] = 15, [248770] = 10, [248771] = 20, [248772] = 30 }

-- A Forged Delivery Receipt (bought for Favor from the camp's Uncertified Scribe, from Friendly) turns an empty crate
-- into a Notarized Shipping Container, handed in for reputation.
Orders.RECEIPT_FAVOR, Orders.RECEIPT_REP = 15, 50
local FRIENDLY, EXALTED = 5, 8

---------------------------------------------------------------------------
-- Performance Bonus, standing, Favor
---------------------------------------------------------------------------
-- Performance Bonus, a node of the Legacy professions talent tree beside Working Overtime (Core/Recipes.lua): each of
-- its three points is a 5% chance of double Favor from a crate.
local BONUS_NODE, BONUS_PER_POINT = 110292, 0.05
local bonus -- nil until the talent config can be read

function Orders:BonusChance()
    if bonus then return bonus end
    local configID = C_Traits.GetConfigIDByTreeID(Constants.LegacyConsts.LEGACY_TREE_PROFESSIONS_ID)
    if not configID then return 0 end -- not loaded yet; ask again next time
    local info = C_Traits.GetNodeInfo(configID, BONUS_NODE)
    bonus = (info and tonumber(info.activeRank or info.currentRank) or 0) * BONUS_PER_POINT
    return bonus
end

local function TalentsChanged()
    bonus = nil
    FP:Changed("standing")
end
FP:RegisterEvent("TRAIT_CONFIG_UPDATED", TalentsChanged)
FP:RegisterEvent("TRAIT_NODE_CHANGED", TalentsChanged)

-- A Sealed crate's Favor without the bonus, or nil when nobody has seen one handed in.
function Orders:BasePay(sealedID) return FP.db.cratePay[sealedID] or KNOWN_PAY[sealedID] end

-- What a hand-in pays on average with Performance Bonus.
function Orders:ExpectedPay(sealedID)
    local base = self:BasePay(sealedID)
    return base and base * (1 + self:BonusChance())
end

-- { name, reaction (4 Neutral to 8 Exalted), have, need (reputation into and across the current standing), favor }.
-- The game knows nothing of the faction until this character has met it: Neutral then.
function Orders:Standing()
    local data = C_Reputation.GetFactionDataByID(FACTIONS[UnitFactionGroup("player")])
    local out = { reaction = 4, have = 0, need = 0, favor = C_CurrencyInfo.GetCurrencyInfo(self.FAVOR).quantity }
    if data then
        out.name, out.reaction = data.name, data.reaction
        out.have = data.currentStanding - data.currentReactionThreshold
        out.need = data.nextReactionThreshold - data.currentReactionThreshold
    end
    return out
end

-- Your faction's camp: who takes Sealed crates and the Uncertified Scribe, each { NPC ID, name, map, x, y }.
function Orders:Camp() return FP.OrderCamps[UnitFactionGroup("player")] end

---------------------------------------------------------------------------
-- What an item costs you
---------------------------------------------------------------------------
-- Getting `need` of an item: { itemID, need, have (in hand: bags, bank, mailbox, less what the queues use), alts (what
-- other characters would send, when alts count toward planning), missing, via ("stock", "craft" or "buy"), maker and
-- crafts (the known recipe and how many crafts cover what is missing, when that is cheapest), source (where the
-- item's own price comes from: "vendor", "auction" or "crafted"), short (the raw
-- materials those crafts still lack), cost (what the whole amount is worth at its price, in hand or not: what you hold
-- could be sold instead; nil without a price) }.
function Orders:Get(itemID, need)
    local _, _, total, mail = FP.Inv:Owned(itemID)
    local have = math.max(0, math.min(need, total + mail - FP.Queue:QueuedAmount(itemID)))
    local alts = FP.Planner:Applies() and math.min(need - have, FP.Alts:GetEnabledAltTotal(itemID)) or 0
    local missing = need - have - alts
    local unit, source = FP.Prices:ReagentUnit(itemID)
    local g = { itemID = itemID, need = need, have = have, alts = alts, missing = missing, via = "stock",
        cost = unit and unit * need, source = source }
    if missing == 0 then return g end
    -- How what is missing is best come by: crafted when that costs no more than buying it.
    g.via = "buy"
    local buy = unit and unit * missing
    local maker = FP.Chain:Maker(itemID)
    if maker then
        local crafts = math.ceil(missing / maker.output.qty)
        local short = FP.Chain:Plan(maker, crafts).short
        local cost = 0
        for id, n in pairs(short) do
            local u = FP.Prices:ReagentUnit(id)
            cost = u and cost and cost + u * n
        end
        if cost and not (buy and buy <= cost) then
            g.via, g.maker, g.crafts, g.short = "craft", maker, crafts, short
        end
    end
    return g
end

-- Cheapest first; one with no price goes last. Between equals, the one you have more of in hand.
local function Cheaper(a, b)
    if (a.cost == nil) ~= (b.cost == nil) then return a.cost ~= nil end
    if a.cost ~= b.cost then return a.cost < b.cost end
    return a.missing < b.missing
end

-- The bundles that fill `copies` of a crate as Orders:Get results, the cheapest for you first.
function Orders:Bundles(crateID, copies)
    local out = {}
    for itemID, qty in FP.Crates[crateID][3]:gmatch("(%d+):(%d+)") do
        out[#out + 1] = self:Get(tonumber(itemID), tonumber(qty) * copies)
    end
    table.sort(out, Cheaper)
    return out
end

---------------------------------------------------------------------------
-- Crates
---------------------------------------------------------------------------
-- A crate type as the window lists it: { kind = "crate", id, tier, sealed, copies (how many of it are filled, one
-- unless said), bundles (each for all the copies), best (the bundle to fill it with: the cheapest, or the one of item
-- `fill` when the player chose it), pay and expected (Favor for one, nil when unknown), cost (of the best bundle),
-- perFavor (copper per expected Favor; nil without a price or a known pay), fillPerFavor (the same for the cheapest
-- bundle alone, whatever is chosen and where a list adds the crate's own price to cost and perFavor) }.
function Orders:Crate(crateID, copies, fill)
    copies = copies or 1
    local d = FP.Crates[crateID]
    local e = { kind = "crate", id = crateID, tier = d[1], sealed = d[2], copies = copies, bundles = self:Bundles(crateID, copies) }
    e.best = e.bundles[1]
    for _, g in ipairs(e.bundles) do
        if g.itemID == fill then e.best = g end
    end
    e.pay, e.expected = self:BasePay(e.sealed), self:ExpectedPay(e.sealed)
    e.cost = e.best.cost
    e.perFavor = e.cost and e.expected and e.cost / (e.expected * copies)
    local cheapest = e.bundles[1].cost
    e.fillPerFavor = cheapest and e.expected and cheapest / (e.expected * copies)
    return e
end

---------------------------------------------------------------------------
-- Writs
---------------------------------------------------------------------------
-- How many of its item a writ asks for is in no data source, only in the quest itself: Crafted Solid Shot asks for
-- 200. The game loads a quest's objectives on request, accepted or not, so each writ's quest is asked for the first
-- time it is looked at and the answer kept account-wide (FP.db.writQty). A quest lists two item objectives, the writ
-- itself (always one) and the item, and doesn't say which is which, so the larger amount is the item's.
local SEND, EVERY = 5, 0.5 -- quests asked for per tick, and seconds between ticks: Worth Buying looks at every writ
local asked, waiting, sender = {}, {}, nil
local writOfQuest -- [quest ID] = writ item ID, built on first use

local function WritOf(questID)
    if not writOfQuest then
        writOfQuest = {}
        for id, d in pairs(FP.Writs) do writOfQuest[d[1]] = id end
    end
    return writOfQuest[questID]
end

local function SendRequests()
    for _ = 1, math.min(SEND, #waiting) do C_QuestLog.RequestLoadQuestByID(table.remove(waiting)) end
    if #waiting == 0 then
        sender:Cancel()
        sender = nil
    end
end

-- The quantity, and whether it is known; one until the quest's answer arrives.
local function WritQuantity(questID)
    local known = FP.db.writQty[questID]
    if known then return known, true end
    if not asked[questID] then
        asked[questID] = true
        waiting[#waiting + 1] = questID
        sender = sender or C_Timer.NewTicker(EVERY, SendRequests)
    end
    return 1, false
end

-- Answers arrive in a burst when every writ was asked for: the windows redraw once they have settled.
local redrawing = false
local function LearnQuantity(questID)
    if not WritOf(questID) then return end
    local most = 0
    for _, o in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
        if o.type == "item" then most = math.max(most, o.numRequired) end
    end
    if most == 0 or FP.db.writQty[questID] == most then return end
    FP.db.writQty[questID] = most
    if not redrawing then
        redrawing = true
        C_Timer.After(1, function()
            redrawing = false
            FP:Changed("orders")
        end)
    end
end
FP:RegisterEvent("QUEST_DATA_LOAD_RESULT", function(_, questID, success)
    if success then LearnQuantity(questID) else asked[questID] = nil end -- asked again the next time it is looked at
end)

-- Whether this character has handed the writ in today.
function Orders:Delivered(questID)
    return C_QuestLog.IsQuestFlaggedCompleted(questID) or (FP.chardb.writsDone[questID] or 0) > GetServerTime()
end

-- The writ's customer: { name, uiMap, x, y }, as you recorded it handing one in, else from the data; nil when unknown.
function Orders:Customer(writID)
    local d = FP.Writs[writID]
    local seen = FP.db.writCustomers[d[1]]
    if seen then return seen end
    if d[5] then return { name = d[5], uiMap = d[6], x = d[7], y = d[8] } end
end

-- Keys of the other characters who know a recipe making the item, and could mail it (Alts:IsEligible).
local function Crafters(itemID)
    local me, out, seen = FP.Alts:GetCharacterKey(), {}, {}
    for _, recipe in ipairs(FP.Uses:MakersOf(itemID)) do
        for _, key in ipairs(FP.Known:Who(recipe)) do
            if key ~= me and not seen[key] and FP.Alts:IsEligible(key, FP.db.characters[key]) then
                seen[key] = true
                out[#out + 1] = key
            end
        end
    end
    return out
end

-- A writ as the window lists it: { kind = "writ", id, quest, item, qty, qtyKnown (false until the game has said how
-- many it asks for: its cost is then for one), tier, rep, customer, done (handed in today), get (Orders:Get for its
-- item), cost, perRep (copper per reputation; nil without a price), crafters }.
function Orders:Writ(writID)
    local d = FP.Writs[writID]
    local e = { kind = "writ", id = writID, quest = d[1], item = d[2], tier = d[3], rep = d[4],
        customer = self:Customer(writID), done = self:Delivered(d[1]), crafters = Crafters(d[2]) }
    e.qty, e.qtyKnown = WritQuantity(d[1])
    e.get = self:Get(e.item, e.qty)
    e.cost = e.get.cost
    e.perRep = e.cost and e.cost / e.rep
    return e
end

---------------------------------------------------------------------------
-- What you hold
---------------------------------------------------------------------------
-- How many of an item this character holds (bags and bank), and the other characters holding some
-- (Alts:GetAltBreakdown's entries: switched on, same faction).
local function Held(itemID)
    return C_Item.GetItemCount(itemID, true), FP.Alts:GetAltBreakdown(itemID).enabled
end

-- What selling one at the auction house would bring after the cut; nil without an auction price.
local function Sale(itemID)
    local price = FP.Prices:Unit(itemID)
    return price and price * (1 - FP.Prices.CUT)
end

local function ByFavor(a, b)
    if (a.perFavor == nil) ~= (b.perFavor == nil) then return a.perFavor ~= nil end
    if a.perFavor ~= b.perFavor then return a.perFavor < b.perFavor end
    return a.id < b.id
end

local function ByRep(a, b)
    if a.done ~= b.done then return b.done end
    if (a.perRep == nil) ~= (b.perRep == nil) then return a.perRep ~= nil end
    if a.perRep ~= b.perRep then return a.perRep < b.perRep end
    return a.id < b.id
end

-- Marks the crates a Forged Delivery Receipt is the better use of: between Friendly and Exalted, with the Favor for
-- one (or one in the bags), on a crate that costs more per Favor to fill than your cheapest crate or has no priced
-- fill, and only while the reputation it buys is cheaper than your cheapest writ's. The Favor a receipt costs is
-- valued at what your cheapest crate costs you per Favor, and the crate at the sale it gives up. A marked crate gets
-- e.receipt = { perRep (copper per reputation this way), perFavor (that value of one Favor), sale (what selling the
-- crate would bring, nil without a price), writ (your cheapest writ's copper per reputation, nil with none to
-- compare), owned (receipts in the bags), favor (Merchant's Favor held) }.
local function MarkReceipts(crates, writs, standing)
    if standing.reaction < FRIENDLY or standing.reaction >= EXALTED then return end
    local owned = C_Item.GetItemCount(FP.OrderItems.receipt)
    local receipts = owned + math.floor(standing.favor / Orders.RECEIPT_FAVOR)
    local cheapest = crates[1] and crates[1].perFavor -- sorted ByFavor
    if receipts == 0 or not cheapest then return end
    local writ
    for _, w in ipairs(writs) do -- sorted ByRep
        if not w.done and w.perRep then
            writ = w.perRep
            break
        end
    end
    for i = #crates, 2, -1 do
        local c = crates[i]
        if receipts == 0 or (c.perFavor and c.perFavor <= cheapest) then break end
        local perRep = ((c.sale or 0) + Orders.RECEIPT_FAVOR * cheapest) / Orders.RECEIPT_REP
        if c.count > 0 and not (writ and writ < perRep) then
            c.receipt = { perRep = perRep, perFavor = cheapest, sale = c.sale, writ = writ, owned = owned, favor = standing.favor }
            receipts = receipts - math.min(receipts, c.count)
        end
    end
end

-- Everything this character and the others hold: { crates, writs (entries with count, the number this character
-- holds, and holders, the other characters with some; crates cheapest per Favor first, writs cheapest per reputation
-- first with today's delivered ones last), sealed ({ id, count, pay, expected } Sealed crates ready to hand in),
-- containers (Notarized Shipping Containers held), unopened ({ id, count, tier }: crates and writs not yet opened),
-- standing (Orders:Standing), repHeld (reputation the writs not yet delivered today would give) }.
-- A crate or writ in hand could be sold instead, so each one's cost, and perFavor or perRep, count the sale given up:
-- its auction price less the cut, as e.sale (nil without a price: only the fill is counted then).
-- picked: [crate item ID] = how many of the copies this character holds to fill; all of them when not said.
-- fills: [crate item ID] = the item chosen to fill it with; the cheapest when not said.
function Orders:Held(picked, fills)
    local out = { crates = {}, writs = {}, sealed = {}, unopened = {}, standing = self:Standing(), repHeld = 0 }
    for id in pairs(FP.Crates) do
        local count, holders = Held(id)
        if count > 0 or #holders > 0 then
            local e = self:Crate(id, math.max(1, math.min(count, picked and picked[id] or count)), fills and fills[id])
            e.count, e.holders = count, holders
            e.sale = Sale(id)
            if e.sale and e.cost then
                e.cost = e.cost + e.sale * e.copies
                e.perFavor = e.expected and e.cost / (e.expected * e.copies)
            end
            out.crates[#out.crates + 1] = e
        end
    end
    for id in pairs(FP.Writs) do
        local count, holders = Held(id)
        if count > 0 or #holders > 0 then
            local e = self:Writ(id)
            e.count, e.holders = count, holders
            e.sale = Sale(id)
            if e.sale and e.cost then
                e.cost = e.cost + e.sale
                e.perRep = e.cost / e.rep
            end
            out.writs[#out.writs + 1] = e
            if count > 0 and not e.done then out.repHeld = out.repHeld + e.rep end
        end
    end
    table.sort(out.crates, ByFavor)
    table.sort(out.writs, ByRep)
    MarkReceipts(out.crates, out.writs, out.standing)
    for id in pairs(FP.SealedCrates) do
        local count = C_Item.GetItemCount(id, true)
        if count > 0 then
            out.sealed[#out.sealed + 1] = { id = id, count = count, pay = self:BasePay(id), expected = self:ExpectedPay(id) }
        end
    end
    table.sort(out.sealed, function(a, b) return a.id < b.id end)
    out.containers = C_Item.GetItemCount(FP.OrderItems.container, true)
    local unopened = C_Item.GetItemCount(FP.OrderItems.unopened, true)
    if unopened > 0 then out.unopened[1] = { id = FP.OrderItems.unopened, count = unopened } end
    for id, tier in pairs(FP.SealedWrits) do
        local count = C_Item.GetItemCount(id, true)
        if count > 0 then out.unopened[#out.unopened + 1] = { id = id, count = count, tier = tier } end
    end
    table.sort(out.unopened, function(a, b) return a.id < b.id end)
    return out
end

-- Counts only, for the footer cell and the quick button: crates and writs held (this character's and what the other
-- characters would send), and Sealed crates and Notarized Shipping Containers this character can hand in.
function Orders:Counts()
    local Alts = FP.Alts
    local crates, writs, ready = 0, 0, C_Item.GetItemCount(FP.OrderItems.container, true)
    for id in pairs(FP.Crates) do crates = crates + C_Item.GetItemCount(id, true) + Alts:GetEnabledAltTotal(id) end
    for id in pairs(FP.Writs) do writs = writs + C_Item.GetItemCount(id, true) + Alts:GetEnabledAltTotal(id) end
    for id in pairs(FP.SealedCrates) do ready = ready + C_Item.GetItemCount(id, true) end
    return crates, writs, ready
end

---------------------------------------------------------------------------
-- What is worth buying at the auction house
---------------------------------------------------------------------------
-- Every crate type with what buying and filling one costs: Orders:Crate's entry plus price (the crate's auction price;
-- nil when it has none), total and perFavor (crate and fill together per expected Favor), cheapest first.
function Orders:CrateMarket()
    local out = {}
    for id in pairs(FP.Crates) do
        local e = self:Crate(id)
        e.price = FP.Prices:Unit(id)
        e.total = e.price and e.cost and e.price + e.cost
        e.perFavor = e.total and e.expected and e.total / e.expected
        out[#out + 1] = e
    end
    table.sort(out, ByFavor)
    return out
end

-- What is worth buying for reputation: { sealed = one entry per sealed writ tier, { id, tier, rep, price (the sealed
-- writ's auction price), orders (how many writs the tier has), priced (how many of them have a price for their item
-- and a known quantity),
-- average (their items' mean cost to you), perRep }, writs = Orders:Writ entries of the writs with an auction price,
-- with price, total and perRep counting it, cheapest first }. A sealed writ opens into a random writ of its tier, so
-- its cost is only an average.
function Orders:WritMarket()
    local out, byTier = { sealed = {}, writs = {} }, {}
    for id in pairs(FP.Writs) do
        local e = self:Writ(id)
        local t = byTier[e.tier]
        if not t then t = { orders = 0, priced = 0, sum = 0, rep = e.rep } byTier[e.tier] = t end
        t.orders = t.orders + 1
        if e.cost and e.qtyKnown then t.priced, t.sum = t.priced + 1, t.sum + e.cost end
        e.price = FP.Prices:Unit(id)
        if e.price then
            e.total = e.cost and e.price + e.cost
            e.perRep = e.total and e.total / e.rep
            out.writs[#out.writs + 1] = e
        end
    end
    table.sort(out.writs, ByRep)
    for id, tier in pairs(FP.SealedWrits) do
        local t = byTier[tier]
        if t then
            local e = { kind = "sealedWrit", id = id, tier = tier, rep = t.rep, orders = t.orders, priced = t.priced,
                price = FP.Prices:Unit(id), average = t.priced > 0 and t.sum / t.priced or nil }
            e.perRep = e.price and e.average and (e.price + e.average) / e.rep
            out.sealed[#out.sealed + 1] = e
        end
    end
    table.sort(out.sealed, function(a, b) return a.tier < b.tier end)
    return out
end

-- Buying the cheapest crate at auction for a Forged Delivery Receipt, when that is the cheapest reputation on offer:
-- { crate (its CrateMarket entry), perRep }, the receipt's Favor valued at what the cheapest crate to buy and fill
-- costs per Favor. Nil outside Friendly to Revered, without prices, or when a writ in `writs` (WritMarket) is cheaper.
function Orders:ReceiptMarket(crates, writs, standing)
    if standing.reaction < FRIENDLY or standing.reaction >= EXALTED then return end
    local favor = crates[1] and crates[1].perFavor -- sorted cheapest per Favor first
    local cheapest
    for _, c in ipairs(crates) do
        if c.price and not (cheapest and cheapest.price <= c.price) then cheapest = c end
    end
    if not (favor and cheapest) then return end
    local perRep = (cheapest.price + self.RECEIPT_FAVOR * favor) / self.RECEIPT_REP
    for _, list in ipairs({ writs.sealed, writs.writs }) do
        for _, w in ipairs(list) do
            if w.perRep and w.perRep < perRep then return end
        end
    end
    return { kind = "receipt", id = cheapest.id, crate = cheapest, perRep = perRep }
end

---------------------------------------------------------------------------
-- Acting on an entry
---------------------------------------------------------------------------
-- What of `g` (an Orders:Get result) is still to be asked for, as the window's button says it: "queue" (crafts to
-- queue), "shop" (to put on the shopping list, which also plans what alts send), "queued" or "listed" (already asked
-- for), or nil when everything is in hand.
function Orders:FetchState(g)
    if g.missing == 0 and g.alts == 0 then return end
    if g.via == "craft" then
        return FP.Queue:QueuedProduction(g.itemID) >= g.missing and "queued" or "queue"
    end
    return FP.Shop:Quantity(g.itemID) >= g.missing + g.alts and "listed" or "shop"
end

-- Queues the crafts that cover what is missing of `g`, with the crafts of their own reagents first, or puts what is
-- not in hand on the shopping list; what alts hold goes on the list either way, so the Transfer Planner asks for it.
function Orders:Fetch(g)
    local state = self:FetchState(g)
    if state == "queue" then
        FP.Queue:AddInfoWithPrerequisites(g.maker, g.crafts)
        if g.alts > 0 then FP.Shop:Add(g.itemID, g.alts) end
    elseif state == "shop" then
        FP.Shop:Add(g.itemID, g.missing + g.alts - FP.Shop:Quantity(g.itemID))
    end
end

---------------------------------------------------------------------------
-- Recording: what a hand-in pays, who takes a writ, what was delivered today
---------------------------------------------------------------------------
-- A Sealed crate leaving the bags and Favor arriving within MATCH seconds of each other, in either order, is that
-- crate's hand-in. Performance Bonus doubles one now and then, so the lowest amount seen for a crate is its pay.
local MATCH = 3
local counts = {} -- [Sealed crate item ID] = how many were in the bags at the last look
local left, gained -- { id | amount, at }: a crate that left, Favor that arrived, waiting for the other half

local function Pair()
    if not (left and gained) or math.abs(left.at - gained.at) > MATCH then return end
    local old = FP.db.cratePay[left.id]
    if not old or gained.amount < old then
        FP.db.cratePay[left.id] = gained.amount
        FP:Changed("orders")
    end
    left, gained = nil, nil
end

local function WatchSealed()
    for id in pairs(FP.SealedCrates) do
        local now = C_Item.GetItemCount(id)
        if counts[id] and now == counts[id] - 1 then
            left = { id = id, at = GetTime() }
            Pair()
        end
        counts[id] = now
    end
end
FP:RegisterEvent("PLAYER_LOGIN", WatchSealed)
FP:RegisterEvent("BAG_UPDATE_DELAYED", WatchSealed) -- the windows redraw with the bags ("inventory")

FP:RegisterEvent("CURRENCY_DISPLAY_UPDATE", function(_, currency, _, change)
    if currency ~= Orders.FAVOR then return end
    if change and change > 0 then
        gained = { amount = change, at = GetTime() }
        Pair()
    end
    FP:Changed("orders")
end)

FP:RegisterEvent("QUEST_TURNED_IN", function(_, questID)
    local writID = WritOf(questID)
    if not writID then return end
    FP.chardb.writsDone[questID] = GetServerTime() + C_DateAndTime.GetSecondsUntilDailyReset()
    -- You are standing at the customer: the data has none for some writs, and a customer may have moved.
    local uiMap = C_Map.GetBestMapForUnit("player")
    local pos = uiMap and C_Map.GetPlayerMapPosition(uiMap, "player")
    if pos then
        local x, y = pos:GetXY()
        local old = FP.db.writCustomers[questID]
        FP.db.writCustomers[questID] = { name = UnitName("npc") or (old and old.name) or FP.Writs[writID][5],
            uiMap = uiMap, x = math.floor(x * 1000 + 0.5) / 1000, y = math.floor(y * 1000 + 0.5) / 1000 }
    end
    FP:Changed("orders")
end)

-- Reputation moves the standing along the window's top.
FP:RegisterEvent("UPDATE_FACTION", function() FP:Changed("standing") end)
