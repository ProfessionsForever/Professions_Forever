local _, FP = ...
local Alts = {}
FP.Alts = Alts

-- Record of each known character:
-- FP.db.characters[key] = { name, realm, class, faction, enabled, bags = { [itemID] = n }, bank = { [itemID] = n },
--                           fromSyndicator, cooldowns = { [recipeID] = { name, icon, prof, readyAt, ignored } } }
-- Cooldowns are kept by Core/Cooldowns.lua.
-- With Syndicator active it does the tracking: other characters' item counts are read from its saved data at login
-- (kept in memory only) and nothing is scanned or copied here, so bags and bank stay empty in the record.
-- Without it, the current character's bags and bank are scanned and saved in its record.
-- The current character's own record is kept for the other characters to see; it is never counted as an alt here.

local Inv = FP.Inv

local currentKey, order, eligible
local bagCounts, dirty, flushed = {}, {}, false
local index = {} -- [key] = { bags, bank } read from Syndicator this session
-- [key][itemID] = amount chosen for one character in the Transfer Planner (0 = not taken). Kept with the current
-- character's queue, so it lasts exactly as long as that queue.
local function Takes() return FP.chardb.queueTakes end

local function Reset() order, eligible = nil, nil end

function Alts:UsesSyndicator()
    local api = _G.Syndicator and Syndicator.API
    return api and api.GetAllCharacters and api.GetCharacter and true or false
end

-- Item counts held by another character: bags, bank. Syndicator's view wins over a snapshot saved here.
function Alts:Counts(key)
    local ix = index[key]
    if ix then return ix.bags, ix.bank end
    local rec = FP.db.characters[key]
    return rec.bags, rec.bank
end

-- Name-NormalizedRealm, the same form Syndicator keys its characters by.
function Alts:GetCharacterKey()
    if not currentKey then
        local name, realm = UnitName("player"), GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
        if not name or not realm or realm == "" then return nil end
        currentKey = name .. "-" .. realm:gsub("[%s%-]", "")
    end
    return currentKey
end

-- The current character's record, created on first sight. Returns record, key.
function Alts:Current()
    local key = self:GetCharacterKey()
    if not key then return nil end
    local rec = FP.db.characters[key]
    if not rec then
        rec = { enabled = true, bags = {}, bank = {} }
        FP.db.characters[key] = rec
        Reset()
    end
    if not rec.name then
        rec.name, rec.realm = UnitName("player"), GetRealmName()
        rec.class = select(2, UnitClass("player"))
        rec.faction = UnitFactionGroup("player")
    end
    return rec, key
end

function Alts:Init()
    local rec = self:Current()
    if not rec then return end
    rec.fromSyndicator = nil
    -- A bank scanned before the account-wide record existed.
    if not self:UsesSyndicator() and next(rec.bank) == nil and FP.chardb.bank then rec.bank = FP.chardb.bank end
    self:ImportSyndicator()
end

-- Item counts per ID from slot tables shaped { { itemID, itemCount }, ... }; empty slots are empty tables.
local function AddSlots(totals, slots)
    if type(slots) ~= "table" then return end
    for _, item in pairs(slots) do
        if type(item) == "table" and type(item.itemID) == "number" then
            totals[item.itemID] = (totals[item.itemID] or 0) + (item.itemCount or 1)
        end
    end
end

-- Reads the other characters' bags and character bank from Syndicator's saved data into the in-memory index, and adds
-- a metadata-only record for any it tracks that this addon hasn't seen, so they can be enabled or removed.
-- Layout read from its saved data: details, bags[bag][slot], and the bank as bankTabs[tab].slots[slot] or bank[bag][slot].
function Alts:ImportSyndicator()
    wipe(index)
    local chars, me = FP.db.characters, self:GetCharacterKey()
    local api = _G.Syndicator and Syndicator.API
    local ok, keys = false, nil
    if self:UsesSyndicator() and me then ok, keys = pcall(api.GetAllCharacters) end
    local seen = {}
    if ok and type(keys) == "table" then
        local live = api.GetCurrentCharacter and api.GetCurrentCharacter()
        for _, key in ipairs(keys) do
            local okData, data = pcall(api.GetCharacter, key)
            local d = okData and type(data) == "table" and type(data.details) == "table" and data.details
            -- Characters hidden in Syndicator stay hidden here.
            local hidden = d and d.show and d.show.inventory == false
            if d and key ~= me and key ~= live and not hidden and not FP.db.skipImport[key] then
                local bags, bank = {}, {}
                for _, slots in pairs(type(data.bags) == "table" and data.bags or {}) do AddSlots(bags, slots) end
                if type(data.bankTabs) == "table" and #data.bankTabs > 0 then
                    for _, tab in ipairs(data.bankTabs) do AddSlots(bank, type(tab) == "table" and tab.slots) end
                else
                    for _, slots in pairs(type(data.bank) == "table" and data.bank or {}) do AddSlots(bank, slots) end
                end
                index[key] = { bags = bags, bank = bank }
                seen[key] = true
                if not chars[key] then
                    chars[key] = { name = d.character, realm = d.realm, class = d.className, faction = d.faction,
                        enabled = true, bags = {}, bank = {}, fromSyndicator = true }
                end
            end
        end
    end
    -- Gone or hidden in Syndicator since last session, or Syndicator itself is gone.
    for key, rec in pairs(chars) do
        if rec.fromSyndicator and not seen[key] then chars[key] = nil end
    end
    Reset()
    FP.Planner:Invalidate()
end

---------------------------------------------------------------------------
-- Snapshots of the current character (only without Syndicator)
---------------------------------------------------------------------------
-- BAG_UPDATE names the bag that changed, so only that bag is rescanned on the next flush.
function Alts:OnBagUpdate(bag)
    if Inv:IsCarriedBag(bag) and not self:UsesSyndicator() then dirty[bag] = true end
end

-- Replaces the saved bag snapshot (never adds to it). Called once the bag events have settled.
function Alts:Flush()
    if self:UsesSyndicator() then return end
    local rec = self:Current()
    if not rec then return end
    if not flushed then
        for _, bag in ipairs(Inv:CarriedBags()) do dirty[bag] = true end
    end
    if next(dirty) == nil then return end
    for bag in pairs(dirty) do bagCounts[bag] = Inv:ScanBag(bag, bagCounts[bag]) end
    wipe(dirty)
    -- Until the backpack can be read, the client hasn't loaded the bags and an empty result would wipe the snapshot.
    if not bagCounts[0] then return end
    flushed = true
    local totals = wipe(rec.bags)
    for _, counts in pairs(bagCounts) do
        for id, n in pairs(counts) do totals[id] = (totals[id] or 0) + n end
    end
end

function Alts:SetBank(counts)
    local rec = self:Current()
    if rec and not self:UsesSyndicator() then rec.bank = counts end
    FP.Planner:Invalidate()
end

---------------------------------------------------------------------------
-- Known characters
---------------------------------------------------------------------------
-- Every character key, sorted by name then key so listings and tie-breaks are stable.
local function Order()
    if not order then
        local chars = FP.db.characters
        order = {}
        for key in pairs(chars) do order[#order + 1] = key end
        table.sort(order, function(a, b)
            local na, nb = strlower(chars[a].name or a), strlower(chars[b].name or b)
            if na ~= nb then return na < nb end
            return a < b
        end)
    end
    return order
end

-- Mail can't cross factions on this client. Records with no faction recorded are given the benefit of the doubt.
local function IsOtherFaction(rec)
    local mine = UnitFactionGroup("player")
    return mine ~= nil and rec.faction ~= nil and rec.faction ~= mine
end

function Alts:IsOtherFaction(rec) return IsOtherFaction(rec) end

-- The one place that decides whether a character may supply materials; transfer restrictions go here.
function Alts:IsEligible(key, rec)
    return key ~= self:GetCharacterKey() and rec.enabled ~= false and not IsOtherFaction(rec)
end

-- Other characters, current one excluded: { key, rec }.
function Alts:Others()
    local out, me = {}, self:GetCharacterKey()
    for _, key in ipairs(Order()) do
        if key ~= me then out[#out + 1] = { key = key, rec = FP.db.characters[key] } end
    end
    return out
end

-- Keys of the characters allowed to supply materials.
function Alts:Eligible()
    if not eligible then
        eligible = {}
        for _, key in ipairs(Order()) do
            if self:IsEligible(key, FP.db.characters[key]) then eligible[#eligible + 1] = key end
        end
    end
    return eligible
end

function Alts:HasSources() return #self:Eligible() > 0 end

function Alts:Get(key) return FP.db.characters[key] end

-- Settings changes: every consumer of the plan recalculates.
local function Changed()
    Reset()
    FP:RefreshPlanning()
end

function Alts:SetEnabled(key, on)
    local rec = FP.db.characters[key]
    if not rec or key == self:GetCharacterKey() then return end
    rec.enabled = on and true or false
    Changed()
end

function Alts:SetAllEnabled(on)
    for _, c in ipairs(self:Others()) do c.rec.enabled = on and true or false end
    Changed()
end

-- Fixes how much of one material to take from one character (0 = none, nil = let the planner decide).
-- A character set to 0 stays listed, as ignored, in tooltips.
function Alts:SetTake(key, itemID, amount)
    local takes = Takes()
    takes[key] = takes[key] or {}
    takes[key][itemID] = amount and math.max(0, math.floor(amount)) or nil
    Changed()
end

-- nil when the planner decides, otherwise the amount chosen.
function Alts:Taken(key, itemID)
    local t = Takes()[key]
    return t and t[itemID]
end

function Alts:IsSkipped(key, itemID)
    return self:Taken(key, itemID) == 0
end

-- Forgets the amounts chosen for materials the queue no longer needs (all of them once it is empty); byItem is the
-- set of needed item IDs.
function Alts:KeepTakes(byItem)
    local takes, dropped = Takes(), false
    for key, t in pairs(takes) do
        for id in pairs(t) do
            if not byItem[id] then t[id], dropped = nil, true end
        end
        if next(t) == nil then takes[key] = nil end
    end
    if dropped then FP.Planner:Invalidate() end
end

function Alts:Remove(key)
    if key == self:GetCharacterKey() then return end
    -- Otherwise the next login would import it again from Syndicator.
    FP.db.skipImport[key] = true
    FP.db.characters[key] = nil
    Takes()[key] = nil
    Changed()
end

---------------------------------------------------------------------------
-- Raw inventory queries (no allocation or planning; see TransferPlanner.lua)
---------------------------------------------------------------------------
local function Count(key, itemID)
    local bags, bank = Alts:Counts(key)
    return (bags[itemID] or 0) + (bank[itemID] or 0)
end

-- What every other character holds, whether or not it may be used.
function Alts:GetAltOwned(itemID)
    local total = 0
    for _, c in ipairs(self:Others()) do total = total + Count(c.key, itemID) end
    return total
end

function Alts:GetEnabledAltTotal(itemID)
    local total = 0
    for _, key in ipairs(self:Eligible()) do
        if not self:IsSkipped(key, itemID) then total = total + Count(key, itemID) end
    end
    return total
end

local function ByCount(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.key < b.key
end

-- { enabled = { entry }, ignored = { entry }, enabledTotal, ignoredTotal }; entries hold bags, bank and count,
-- largest holding first. Disabled characters, and ones unticked for this material, are listed as ignored, never counted.
function Alts:GetAltBreakdown(itemID)
    local out = { enabled = {}, ignored = {}, enabledTotal = 0, ignoredTotal = 0 }
    for _, c in ipairs(self:Others()) do
        local rec = c.rec
        local bagCount, bankCount = self:Counts(c.key)
        local bags, bank = bagCount[itemID] or 0, bankCount[itemID] or 0
        -- The other faction can never send anything, so it isn't listed at all.
        if bags + bank > 0 and not IsOtherFaction(rec) then
            local on = self:IsEligible(c.key, rec) and not self:IsSkipped(c.key, itemID)
            local list = on and out.enabled or out.ignored
            list[#list + 1] = { key = c.key, name = rec.name or c.key, realm = rec.realm, class = rec.class,
                bags = bags, bank = bank, count = bags + bank }
            if on then out.enabledTotal = out.enabledTotal + bags + bank else out.ignoredTotal = out.ignoredTotal + bags + bank end
        end
    end
    table.sort(out.enabled, ByCount)
    table.sort(out.ignored, ByCount)
    return out
end

-- Current character, enabled alts and ignored characters side by side, never merged into one number.
function Alts:GetAccountAvailability(itemID)
    local bags, bank, total = Inv:Owned(itemID)
    local b = self:GetAltBreakdown(itemID)
    return { bags = bags, bank = bank, currentTotal = total, alts = b.enabledTotal, altsByCharacter = b.enabled,
        ignored = b.ignored, ignoredTotal = b.ignoredTotal, totalWithAlts = total + b.enabledTotal }
end

---------------------------------------------------------------------------
-- Display helpers
---------------------------------------------------------------------------
function Alts:ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- The realm is only worth showing for characters on another one.
function Alts:Label(entry)
    local name = entry.name or entry.key
    if entry.realm and entry.realm ~= GetRealmName() then return name .. "-" .. entry.realm end
    return name
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
FP:RegisterEvent("BAG_UPDATE", function(self, bag) self.Alts:OnBagUpdate(bag) end)
FP:RegisterEvent("PLAYER_LOGOUT", function(self) self.Alts:Flush() end)
