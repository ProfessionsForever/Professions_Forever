local _, FP = ...
local Inv = {}
FP.Inv = Inv
Inv.bankOpen = false

-- The current character's bags and bank: counting items, scanning the bank while it is open (kept per character for
-- when it is closed), the gear that could be disenchanted, and withdrawing from the bank.

local GetItemCount = C_Item.GetItemCount
local max = math.max

-- Carried bags are the backpack, the bag slots and the reagent bag; the bank's tabs come after them.
local function LastCarriedBag() return NUM_TOTAL_EQUIPPED_BAG_SLOTS end

function Inv:IsCarriedBag(bag)
    return type(bag) == "number" and bag >= 0 and bag <= LastCarriedBag()
end

function Inv:CarriedBags()
    local out = {}
    for i = 0, LastCarriedBag() do out[#out + 1] = i end
    return out
end

-- Item counts in one carried bag, written into `into` when given; nil when the bag doesn't exist.
function Inv:ScanBag(bag, into)
    local slots = C_Container.GetContainerNumSlots(bag) or 0
    if slots == 0 then return nil end
    local counts = into and wipe(into) or {}
    for slot = 1, slots do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID then
            counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
        end
    end
    return counts
end

-- Forever's bank is a row of tabs, each a container of its own; the ones not bought yet have no slots.
local function BankContainers()
    local ids, i = {}, 1
    while Enum.BagIndex["CharacterBankTab_" .. i] do
        local tab = Enum.BagIndex["CharacterBankTab_" .. i]
        if C_Container.GetContainerNumSlots(tab) > 0 then ids[#ids + 1] = tab end
        i = i + 1
    end
    return ids
end
function Inv:BankContainers() return BankContainers() end

-- A free slot in a general-purpose carried bag that isn't in `used`.
local function FreeSlot(used)
    for _, bag in ipairs(Inv:CarriedBags()) do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if free and free > 0 and family == 0 then
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                if not used[bag .. ":" .. slot] and not C_Container.GetContainerItemInfo(bag, slot) then
                    used[bag .. ":" .. slot] = true
                    return bag, slot
                end
            end
        end
    end
end

-- A free slot in a general-purpose carried bag (bag, slot), or nil when the bags are full. A caller filling several
-- slots in one go passes the same `used` table each time, since a slot only fills a moment after an item is put there.
function Inv:FreeSlot(used) return FreeSlot(used or {}) end

-- The carried stack of itemID picked up on the cursor: the game locks a stack's slot while it is held. Its
-- GetContainerItemInfo (stackCount, isBound, ...), or nil when it isn't from the bags.
function Inv:CursorStack(itemID)
    for _, bag in ipairs(self:CarriedBags()) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID and info.isLocked then return info end
        end
    end
end

-- Moves items from the open bank into the bags; `needs` is { { itemID, qty } }. Whole stacks go as they are, smallest
-- first, and the last one is split. Returns how many of the items were at least partly moved. Call it from a click.
function Inv:Withdraw(needs)
    if not self.bankOpen then return 0 end
    local moved, used = 0, {}
    for _, need in ipairs(needs) do
        local stacks = {}
        for _, bag in ipairs(BankContainers()) do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID == need.itemID and not info.isLocked then
                    stacks[#stacks + 1] = { bag = bag, slot = slot, count = info.stackCount or 1 }
                end
            end
        end
        table.sort(stacks, function(a, b) return a.count < b.count end)
        local left = need.qty
        for _, s in ipairs(stacks) do
            if left <= 0 then break end
            if s.count <= left then
                C_Container.UseContainerItem(s.bag, s.slot)
                left = left - s.count
            else
                local bag, slot = FreeSlot(used)
                if bag then
                    C_Container.SplitContainerItem(s.bag, s.slot, left)
                    C_Container.PickupContainerItem(bag, slot)
                    left = 0
                end
            end
        end
        if left < need.qty then moved = moved + 1 end
    end
    return moved
end

-- A weapon or armor piece of uncommon quality or better: what Disenchanting Mode may list. Which of them really can be
-- disenchanted is decided where they are listed (Core/Disenchant.lua). `info` is GetContainerItemInfo's.
local function IsGear(info)
    if not (info.quality and info.quality >= 2) then return false end
    local classID = select(6, C_Item.GetItemInfoInstant(info.itemID))
    return classID == 2 or classID == 4
end

local function GUIDAt(bag, slot) return C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot)) end

-- Only valid while the bank is open: the container APIs return nothing otherwise, so an empty
-- scan never overwrites the cache.
-- Also saves the bank's uncommon-or-better weapons and armor slot by slot (bankGear), so Disenchanting Mode can list
-- them while the bank is closed, and the unbound ones account-wide for the other characters (Alts:SetGear).
function Inv:ScanBank()
    local counts, gear, unbound, scanned = {}, {}, {}, 0
    local SetsAt = FP.Disenchant:SetLookup() -- saved with the gear: the game can't tell once the bank is closed
    for _, bag in ipairs(BankContainers()) do
        scanned = scanned + 1
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
                if IsGear(info) then
                    local guid = GUIDAt(bag, slot)
                    gear[#gear + 1] = { bag = bag, slot = slot, link = info.hyperlink, bound = info.isBound or nil, guid = guid,
                        sets = SetsAt(bag, slot) }
                    if not info.isBound then unbound[#unbound + 1] = { guid = guid, link = info.hyperlink } end
                end
            end
        end
    end
    if scanned > 0 then
        FP.chardb.bank = counts
        FP.chardb.bankGear = gear
        FP.chardb.bankTime = time()
        FP.Alts:SetBank(counts)
        FP.Alts:SetGear("bank", unbound)
    end
end

-- Saves the unbound uncommon-or-better weapons and armor in the carried bags account-wide, by GUID, so the other
-- characters' Disenchanting Mode can list them (Alts:SetGear). On a character that can disenchant, every such piece,
-- bound or not, is also handed to the disenchant recorder (Core/DisenchantRecord.lua), so the bags are walked once for
-- both. Until the backpack can be read the client hasn't loaded the bags, and an empty scan would wipe the saved list.
function Inv:ScanBagGear()
    if (C_Container.GetContainerNumSlots(0) or 0) == 0 then return end
    local gear, DE = {}, FP.Disenchant
    local remember = DE.CanDisenchant()
    for _, bag in ipairs(self:CarriedBags()) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and IsGear(info) and (remember or not info.isBound) then
                local guid = GUIDAt(bag, slot)
                if not info.isBound then gear[#gear + 1] = { guid = guid, link = info.hyperlink } end
                if remember and guid then DE:RememberGear(guid, info.hyperlink) end
            end
        end
    end
    FP.Alts:SetGear("bags", gear)
end

-- Returns bags, bank, total and mail for an itemID. The bank is Syndicator's count when it is in use, else as of this
-- addon's last bank scan (whatever the client knows before the first one); mail is what waits in the mailbox as of
-- the last visit (Alts/AltInventory.lua). The total is
-- bags plus bank, what can be crafted with after a trip to the bank; mail is apart from it, owned but not in hand.
function Inv:Owned(id)
    local cache = FP.Alts:OwnBank() or (FP.chardb and FP.chardb.bank)
    local inBags = GetItemCount(id, false) or 0
    local inBank
    if cache then
        inBank = cache[id] or 0
    else
        inBank = max(0, (GetItemCount(id, true, false, true) or 0) - inBags)
    end
    return inBags, inBank, inBags + inBank, FP.Alts:MailCount(id)
end
