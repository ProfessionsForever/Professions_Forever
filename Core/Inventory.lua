local _, FP = ...
local Inv = {}
FP.Inv = Inv
Inv.bankOpen = false

local GetItemCount = C_Item.GetItemCount
local max = math.max

-- Carried bags are the backpack, the bag slots and the reagent bag; bank bags come after them.
local function LastCarriedBag()
    local B = Enum.BagIndex or {}
    return max(NUM_BAG_SLOTS or 4, B.ReagentBag or 0)
end

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

-- Bank container IDs differ between client generations (classic bank + bank bags, reagent bank,
-- character bank tabs). Build the list from whatever exists and de-duplicate.
local function BankContainers()
    local ids, seen = {}, {}
    local function add(i)
        if i and not seen[i] and (C_Container.GetContainerNumSlots(i) or 0) > 0 then
            seen[i] = true
            ids[#ids + 1] = i
        end
    end
    local B = Enum.BagIndex or {}
    ---@diagnostic disable-next-line: undefined-field
    add(BANK_CONTAINER or B.Bank)
    ---@diagnostic disable-next-line: undefined-field
    add(REAGENTBANK_CONTAINER or B.Reagentbank)
    for i = 1, 12 do add(B["CharacterBankTab_" .. i]) end
    -- Carried bags (including the reagent bag slot) come before the bank bags and must not be scanned.
    local first = LastCarriedBag() + 1
    for i = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do add(i) end
    return ids
end

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

-- Only valid while the bank is open: the container APIs return nothing otherwise, so an empty
-- scan never overwrites the cache.
function Inv:ScanBank()
    local counts, scanned = {}, 0
    for _, bag in ipairs(BankContainers()) do
        scanned = scanned + 1
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    if scanned > 0 then
        FP.chardb.bank = counts
        FP.chardb.bankTime = time()
        FP.Alts:SetBank(counts)
    end
end

-- Bank count from Syndicator (live); nil when unavailable so callers fall back.
local function SyndicatorBank(id)
    local api = _G.Syndicator and Syndicator.API
    if not (api and api.GetInventoryInfoByItemID) then return nil end
    if api.IsReady and not api.IsReady() then return nil end
    local ok, info = pcall(api.GetInventoryInfoByItemID, id, true, true)
    local cur = ok and type(info) == "table" and info.current
    if type(cur) ~= "table" or type(cur.bank) ~= "number" then return nil end
    return cur.bank
end

-- Returns bags, bank, total for an itemID.
-- Bank source, in order: Syndicator (live), the last bank scan, then whatever the client knows.
function Inv:Owned(id)
    local cache = FP.chardb and FP.chardb.bank
    local inBags = GetItemCount(id, false) or 0
    local inBank = SyndicatorBank(id)
    if not inBank then
        if cache then
            inBank = cache[id] or 0
        else
            inBank = max(0, (GetItemCount(id, true, false, true) or 0) - inBags)
        end
    end
    return inBags, inBank, inBags + inBank
end
