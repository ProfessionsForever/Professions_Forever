local _, FP = ...
local DE = FP.Disenchant

-- Records what each of your disenchants gives, account-wide, so the chances in Data/Disenchant.lua can be checked
-- against what Forever really drops.
--
-- FP.db.deObserved[key] = { n = disenchants, items = { [itemID] = { drops = times it dropped, qty = total amount,
--   min, max = smallest and largest amount in one drop (recorded since 2026-11-13, so missing on older records) } },
--   first = WoW build of the first one, last = WoW build of the latest one }
-- key is "class:quality:item level" (weapons are class 2, armor 4), or "i" .. itemID for an item with its own loot
-- table. Keying by item level rather than by our loot table keeps the record useful when a level bracket is wrong.
--
-- How a disenchant is matched to its loot: each loot slot says where it came from, and disenchant loot comes from the
-- disenchanted item itself, by its GUID ("Item-..."). So the GUID and link of every weapon and armor piece in your
-- bags is remembered, and loot from one of them is that item's disenchant, however it was cast (the spellbook,
-- Disenchanting Mode, a macro, a bag addon). The item is gone from the bags by the time the loot window opens, so
-- what is remembered is kept for the session. Loot from anything else with an item GUID (a clam, a lockbox) isn't
-- on the list and is never counted. (On Forever, UNIT_SPELLCAST_SENT doesn't name the target of a disenchant, seen
-- in game 2026-11-13, so the cast can't be used for this.)

local gear = {} -- [item GUID] = link, for weapons and armor of uncommon quality or better seen in your bags
local recorded = {} -- [item GUID] = true once its disenchant is recorded (LOOT_READY can fire twice per window)

-- Only a character that knows Disenchant remembers its gear or checks its loot; the others can't disenchant.
local function CanDisenchant() return IsPlayerSpell(DE.SPELL) end
DE.CanDisenchant = CanDisenchant

-- A weapon or armor piece seen in the carried bags, from the bag walk Inv:ScanBagGear already does on each bag change
-- (only on a character that can disenchant). Nothing is removed, see above.
function DE:RememberGear(guid, link) gear[guid] = link end

-- The link of a remembered item, for /pf debug delog.
function DE:RememberedGear(guid) return gear[guid] end

function DE:RecordKey(itemID, classID, quality, level)
    if FP.DisenchantOverride[itemID] then return "i" .. itemID end
    return classID .. ":" .. quality .. ":" .. level
end

---------------------------------------------------------------------------
-- Your rates, per loot table
---------------------------------------------------------------------------
-- How many disenchants of one loot table before your observed rates are worth relying on: at 100 a result's observed
-- share is within about 10 percentage points of the real one (95% of the time, worst case near 50%), enough to catch
-- a table that is clearly wrong for Forever. Below it they are shown with a warning.
DE.ENOUGH_DISENCHANTS = 100

local byTable -- [loot table] = { n, items = { [itemID] = { drops, qty } } }, built from deObserved when first asked

-- The table a record key counts toward: an item with its own table by that table, the rest by their level's bracket.
local function TableOfKey(key)
    local item = key:match("^i(%d+)$")
    if item then return FP.DisenchantOverride[tonumber(item)] end
    local class, quality, level = key:match("^(%d+):(%d+):(%d+)$")
    if class then return DE:BracketTable(tonumber(class), tonumber(quality), tonumber(level)) end
end

-- Every character's disenchants of items that use `tableID`, added up: { n, items = { [itemID] = { drops, qty } },
-- enough }, or nil when there are none. Records are kept by item level (or item) and added up here, so a wrong level
-- bracket or item table can still be spotted in the stored records.
function DE:Observed(tableID)
    if not byTable then
        byTable = {}
        for key, e in pairs(FP.db.deObserved) do
            local id = TableOfKey(key)
            if id then
                local t = byTable[id] or { n = 0, items = {} }
                t.n = t.n + e.n
                for itemID, i in pairs(e.items) do
                    local sum = t.items[itemID] or { drops = 0, qty = 0 }
                    sum.drops, sum.qty = sum.drops + i.drops, sum.qty + i.qty
                    if i.min then sum.min, sum.max = math.min(sum.min or i.min, i.min), math.max(sum.max or i.max, i.max) end
                    t.items[itemID] = sum
                end
                byTable[id] = t
            end
        end
        for _, t in pairs(byTable) do t.enough = t.n >= DE.ENOUGH_DISENCHANTS end
    end
    return byTable[tableID]
end

-- Your observed share of one result of `tableID`, as text ("75%"), and whether there are enough disenchants to rely
-- on it; nil when none are recorded.
function DE:ObservedChance(tableID, itemID)
    local t = self:Observed(tableID)
    if not t then return end
    local i = t.items[itemID]
    return ("%d%%"):format(math.floor((i and i.drops or 0) / t.n * 100 + 0.5)), t.enough
end

-- Your average amount per drop of one result of `tableID`, as text ("1.7"), and whether there are enough
-- disenchants to rely on it; nil when it has never dropped. (Smallest and largest amounts are recorded too, for a
-- seen range later; older records don't have them.)
function DE:ObservedAmount(tableID, itemID)
    local t = self:Observed(tableID)
    local i = t and t.items[itemID]
    if not (i and i.drops > 0) then return end
    -- One decimal, but a whole number without it: "1", "1.7", "2".
    return (("%.1f"):format(i.qty / i.drops):gsub("%.0$", "")), t.enough
end

-- What your disenchants of `tableID` were really worth, on average per disenchant, at today's auction prices before
-- the cut: every result you got (the table's or not) times its price, over the number of disenchants. Shown beside
-- the expected value, never used for the verdict. Returns value, enough, unpriced (results with no price, counted as
-- nothing); nil without recorded disenchants or without Auctionator.
function DE:ObservedValue(tableID)
    local t = self:Observed(tableID)
    if not (t and FP.Prices:Available()) then return end
    local total, unpriced = 0, 0
    for itemID, i in pairs(t.items) do
        local unit = FP.Prices:Unit(itemID)
        if unit then total = total + i.qty * unit else unpriced = unpriced + 1 end
    end
    return total / t.n, t.enough, unpriced
end

-- The lines under the observed rates: how many disenchants they come from (with the warning while too few), and the
-- results seen that `results` (the table's own) doesn't list. Returns note, alsoSeen (nil when nothing extra).
function DE:ObservedNote(tableID, results)
    local L = FP.L
    local t = self:Observed(tableID)
    if not t then return L["Not seen yet."] end
    local note = t.enough and L["Seen in %d disenchants."]:format(t.n)
        or L["Seen in %d disenchants (unreliable until %d)."]:format(t.n, self.ENOUGH_DISENCHANTS)
    local listed, extra = {}, {}
    for _, r in ipairs(results) do listed[r.itemID] = true end
    for itemID, i in pairs(t.items) do
        if not listed[itemID] then
            extra[#extra + 1] = L["%s (%d)"]:format(FP.ItemName(itemID), i.drops)
        end
    end
    table.sort(extra)
    return note, #extra > 0 and L["Also seen: %s"]:format(table.concat(extra, ", ")) or nil
end

-- One disenchant of the item recorded under key gave loot ({ [itemID] = amount }).
function DE:Record(key, loot)
    byTable = nil -- added up again when next asked
    local build = (select(2, GetBuildInfo()))
    local e = FP.db.deObserved[key]
    if not e then
        e = { n = 0, items = {}, first = build }
        FP.db.deObserved[key] = e
    end
    e.n, e.last = e.n + 1, build
    for itemID, qty in pairs(loot) do
        local i = e.items[itemID] or { drops = 0, qty = 0 }
        i.drops, i.qty = i.drops + 1, i.qty + qty
        i.min, i.max = math.min(i.min or qty, qty), math.max(i.max or qty, qty)
        e.items[itemID] = i
    end
end

-- The loot window: the slots that came from one remembered item are its disenchant.
local function OnLoot()
    if not (FP.db.deRecord and CanDisenchant()) then return end
    local bySource = {} -- [item GUID] = { [itemID] = amount }
    for slot = 1, GetNumLootItems() do
        local source, link = GetLootSourceInfo(slot), GetLootSlotLink(slot)
        if source and gear[source] and not recorded[source] and link then
            local _, _, quantity = GetLootSlotInfo(slot)
            local loot = bySource[source] or {}
            local itemID = C_Item.GetItemInfoInstant(link)
            loot[itemID] = (loot[itemID] or 0) + quantity
            bySource[source] = loot
        end
    end
    for guid, loot in pairs(bySource) do
        local _, link, quality, level, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(gear[guid])
        if link then
            recorded[guid] = true
            DE:Record(DE:RecordKey(C_Item.GetItemInfoInstant(link), classID, quality, level), loot)
        end
    end
end

FP:RegisterEvent("LOOT_READY", OnLoot)
