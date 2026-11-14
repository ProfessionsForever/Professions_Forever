local _, FP = ...
local Alts = {}
FP.Alts = Alts

-- Record of each known character:
-- FP.db.characters[key] = { name, realm, class, faction, enabled, bags = { [itemID] = n }, bank = { [itemID] = n },
--                           mail = { [itemID] = n } (what waits in its mailbox, see "Mail" below),
--                           fromSyndicator, cooldowns = { [recipeID] = { name, icon, prof, readyAt, ignored } } }
--                           professions = { [skillLine] = ... }, queue = { crafting queue entries },
--                           deGear = { bags = { gear }, bank = { gear } } (see "Gear" below) }
-- Cooldowns are kept by Core/Cooldowns.lua, professions by Alts/AltProfessions.lua, the queue by Core/Queue.lua.
-- With Syndicator active it does the tracking: other characters' item counts are read from its saved data at login
-- (kept in memory only) and nothing is scanned or copied here, so bags and bank stay empty in the record.
-- Without it, the current character's bags and bank are scanned and saved in its record.
-- The current character's own record is kept for the other characters to see; it is never counted as an alt here.

local Inv = FP.Inv

local currentKey, order, eligible
local bagCounts, dirty, flushed = {}, {}, false
local index = {} -- [key] = { bags, bank, mail } read from Syndicator this session
-- [key][itemID] = amount chosen in the Transfer Planner for one supplying character (0 = not taken). Kept in the
-- crafter's record beside its queue (the current character's without `crafter`), so it lasts as long as that queue and
-- any character planning for the crafter uses the same choices.
local function Takes(crafter)
    local rec = crafter and FP.db.characters[crafter] or Alts:Current()
    rec.takes = rec.takes or {}
    return rec.takes
end

local function Reset() order, eligible = nil, nil end

-- Syndicator's data is read at login, so the option is read once too: changing it takes a UI reload.
local usesSyndicator
function Alts:UsesSyndicator()
    if usesSyndicator == nil then
        local api = FP.db.useSyndicator and _G.Syndicator and Syndicator.API
        usesSyndicator = api and api.GetAllCharacters and api.GetCharacter and true or false
    end
    return usesSyndicator
end

-- Item counts held by another character: bags, bank, mail. Treat them as read-only. With Syndicator active only its
-- view counts: a character it doesn't list (hidden there) holds nothing here, whatever an old snapshot of ours says.
local NOTHING = {}
function Alts:Counts(key)
    local ix = index[key]
    if ix then return ix.bags, ix.bank, ix.mail end
    if self:UsesSyndicator() then return NOTHING, NOTHING, NOTHING end
    local rec = FP.db.characters[key]
    return rec.bags, rec.bank, rec.mail or NOTHING
end

-- Where names are regional (WoW Forever), a character has a first name and a surname, and plays on a ruleset
-- (PvE, PvP...) instead of a realm. Names and keys follow Syndicator's, so both addons mean the same character.
local Regional = RegionalUniqueNamesEnabled

local function Ruleset()
    local Active, Rule = C_GameRules.IsGameRuleActive, Enum.GameRule
    local pvp, rp = Active(Rule.PvPRuleset), Active(Rule.RPRuleset)
    if pvp and rp then return "RPPvP" end
    if pvp then return "PvP" end
    if rp then return "RP" end
    if Active(Rule.HardcoreRuleset) then return "HC" end
    return "PvE"
end

-- The current character's name and realm as records show them; nil before the client knows them.
local function NameAndRealm()
    local name, surname = UnitName("player")
    if not name then return end
    if Regional() then
        if not surname then return end
        return name .. Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR .. surname, Ruleset()
    end
    return name, GetRealmName()
end

-- The key used before regional names were handled: first name and server realm.
local function LegacyKey()
    local name, realm = UnitName("player"), GetNormalizedRealmName()
    if not name or not realm or realm == "" then return nil end
    return name .. "-" .. realm:gsub("[%s%-]", "")
end

-- The same form Syndicator keys its characters by: Name-NormalizedRealm, or First Surname-Ruleset where names are regional.
function Alts:GetCharacterKey()
    if not currentKey then
        if Regional() then
            local name, realm = NameAndRealm()
            currentKey = name and (name .. "-" .. realm)
        else
            currentKey = LegacyKey()
        end
    end
    return currentKey
end

-- The current character's realm, in the form records hold it.
function Alts:Realm() return select(2, NameAndRealm()) end

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
        rec.name, rec.realm = NameAndRealm()
        rec.class = select(2, UnitClass("player"))
        rec.faction = UnitFactionGroup("player")
    end
    return rec, key
end

-- Before regional names were handled, this character was saved under its first name and server realm, so it had a
-- second record under Syndicator's key. Moves the old record onto the current key, keeping what only one of them has.
local function MigrateKey(new)
    local old = LegacyKey()
    if not old or old == new then return end
    local chars, rec = FP.db.characters, FP.db.characters[old]
    if rec then
        local into = chars[new]
        if into then
            for k, v in pairs(into) do
                if rec[k] == nil then rec[k] = v end
            end
            if into.cooldowns and rec.cooldowns ~= into.cooldowns then
                for id, c in pairs(into.cooldowns) do
                    if not rec.cooldowns[id] then rec.cooldowns[id] = c end
                end
            end
        end
        rec.name, rec.realm = nil, nil -- Current fills them in the new form
        chars[new], chars[old] = rec, nil
    end
    local transfers = FP.db.transfers
    if transfers[old] then transfers[new], transfers[old] = transfers[old], nil end
    for _, entry in pairs(transfers) do
        local manual = entry.manual
        if manual and manual[old] then
            manual[new] = manual[new] or manual[old]
            manual[old] = nil
        end
    end
    FP.db.skipImport[new] = nil -- a removed duplicate of this character is now its own record
    Reset()
end

local OwnChanged -- defined with the Syndicator reading below

function Alts:Init()
    local key = self:GetCharacterKey()
    if not key then return end
    MigrateKey(key)
    FP.db.skipImport[key] = nil -- logging in on a removed character brings it back
    local rec = self:Current()
    rec.fromSyndicator = nil
    -- A bank scanned before the account-wide record existed.
    if not self:UsesSyndicator() and next(rec.bank) == nil and FP.chardb.bank then rec.bank = FP.chardb.bank end
    -- Transfer Planner choices were saved per character before 0.10.0.
    if FP.chardb.queueTakes then
        rec.takes, FP.chardb.queueTakes = FP.chardb.queueTakes, nil
    end
    self:ImportSyndicator()
    if self:UsesSyndicator() then
        local events = Syndicator.CallbackRegistry
        events:RegisterCallback("BagCacheUpdate", OwnChanged, self) -- covers the bank
        events:RegisterCallback("MailCacheUpdate", OwnChanged, self)
    end
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

-- Unbound uncommon-or-better weapons and armour from slot tables shaped { { itemID, itemLink, quality, isBound } },
-- as { link } (Syndicator keeps no item GUIDs).
local function AddGear(gear, slots)
    if type(slots) ~= "table" then return end
    for _, item in pairs(slots) do
        if type(item) == "table" and type(item.itemLink) == "string" and not item.isBound
            and (item.quality or 0) >= 2 then
            local classID = select(6, C_Item.GetItemInfoInstant(item.itemLink))
            if classID == 2 or classID == 4 then gear[#gear + 1] = { link = item.itemLink } end
        end
    end
end

-- Item counts { bags, bank, mail } and unbound gear { gearBags, gearBank } from one character's Syndicator data.
local function ReadSyndicator(data)
    local bags, bank, mail, gearBags, gearBank = {}, {}, {}, {}, {}
    AddSlots(mail, data.mail) -- a flat list of the attachments in its mailbox
    for _, slots in pairs(type(data.bags) == "table" and data.bags or {}) do
        AddSlots(bags, slots)
        AddGear(gearBags, slots)
    end
    local bankSlots = {}
    if type(data.bankTabs) == "table" and #data.bankTabs > 0 then
        for _, tab in ipairs(data.bankTabs) do bankSlots[#bankSlots + 1] = type(tab) == "table" and tab.slots end
    else
        for _, slots in pairs(type(data.bank) == "table" and data.bank or {}) do bankSlots[#bankSlots + 1] = slots end
    end
    for _, slots in ipairs(bankSlots) do
        AddSlots(bank, slots)
        AddGear(gearBank, slots)
    end
    return { bags = bags, bank = bank, mail = mail, gearBags = gearBags, gearBank = gearBank }
end

-- The current character under Syndicator: its bank and mailbox are counted from Syndicator's record of it, so they
-- are known from the first login, before this addon has seen either. The counts are kept until Syndicator says its
-- record changed. (Its bags are always read live from the game.)
local own
local function Own()
    if own then return own end
    local api = Syndicator.API
    local key = api.GetCurrentCharacter()
    if not key then return end -- Syndicator hasn't started tracking yet
    local ok, data = pcall(api.GetCharacter, key)
    if ok and type(data) == "table" then own = ReadSyndicator(data) end
    return own
end

function OwnChanged()
    own = nil
    FP.Planner:Invalidate()
    FP:Changed("inventory")
end

-- The current character's bank counts from Syndicator; nil without it, or before it is ready (Inv:Owned then uses
-- this addon's own bank scan).
function Alts:OwnBank()
    local o = self:UsesSyndicator() and Own()
    return o and o.bank
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
                index[key] = ReadSyndicator(data)
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
-- Gear: each character's unbound gear, for the other characters' Disenchanting Mode
---------------------------------------------------------------------------
-- Every character saves the unbound uncommon-or-better weapons and armour in its bags and bank as { guid, link },
-- whether or not Syndicator is in use, since only this addon's own scan (Core/Inventory.lua) knows the items' GUIDs.
-- Each part is replaced by its next scan: the bags whenever they change, the bank at each visit.
function Alts:SetGear(where, gear)
    local rec = self:Current()
    if not rec then return end
    rec.deGear = rec.deGear or {}
    rec.deGear[where] = gear
end

-- The unbound gear another character holds: bags, bank, each a list of { guid, link }. A part it hasn't saved yet (not
-- logged in, or not at its bank, since this was added) comes from Syndicator, without GUIDs. As with item counts, a
-- character hidden in Syndicator holds nothing here.
function Alts:Gear(key)
    local ix = index[key]
    if self:UsesSyndicator() and not ix then return NOTHING, NOTHING end
    local g = FP.db.characters[key].deGear
    return g and g.bags or ix and ix.gearBags or NOTHING, g and g.bank or ix and ix.gearBank or NOTHING
end

---------------------------------------------------------------------------
-- Mail: the third place a character's items can be, beside its bags and bank
---------------------------------------------------------------------------
-- What waits in a mailbox belongs to that character but can't be crafted with until collected. It is known two ways:
-- the character's own inbox, read while its mailbox is open (Alts/Outgoing.lua), and what your other characters have
-- mailed it since, added as they send. The first replaces the second at its next mailbox visit. With Syndicator
-- active its record of every character's mailbox is used instead, the current character's included (see Own).

-- How many of an item wait in the current character's mailbox, as of its last visit.
function Alts:MailCount(itemID)
    local o = self:UsesSyndicator() and Own()
    local rec = not o and self:Current()
    local mail = o and o.mail or rec and rec.mail
    return mail and mail[itemID] or 0
end

-- The current character's mailbox was read: counts is { [itemID] = n }.
function Alts:SetMail(counts)
    local rec = self:Current()
    if rec then rec.mail = counts end
    FP.Planner:Invalidate()
end

-- The current character mailed items ({ [itemID] = n }) to another of yours.
function Alts:AddMail(key, items)
    local ix, rec = index[key], FP.db.characters[key]
    if not ix then rec.mail = rec.mail or {} end
    local mail = ix and ix.mail or rec.mail
    for itemID, n in pairs(items) do mail[itemID] = (mail[itemID] or 0) + n end
    FP.Planner:Invalidate()
end

-- The key of your other character a mail addressed to `name` goes to, or nil when it is nobody's, or could be more
-- than one's. Where names are regional the saved name has a surname, which the address may leave out.
function Alts:KeyByName(name)
    name = strlower((name or ""):match("^[^-]+") or "")
    local me, exact, first, firsts = self:GetCharacterKey(), nil, nil, 0
    for key, rec in pairs(FP.db.characters) do
        local full = key ~= me and rec.name and strlower(rec.name)
        if full == name then exact = key
        elseif full and full:match("^%S+") == name then first, firsts = key, firsts + 1 end
    end
    return exact or (firsts == 1 and first) or nil
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

-- Fixes how much of one material to take from one character (0 = none, nil = let the planner decide) for `crafter`'s
-- queue (the current character's without it). A character set to 0 stays listed, as ignored, in tooltips.
function Alts:SetTake(key, itemID, amount, crafter)
    local takes = Takes(crafter)
    takes[key] = takes[key] or {}
    takes[key][itemID] = amount and math.max(0, math.floor(amount)) or nil
    Changed()
end

-- nil when the planner decides, otherwise the amount chosen, for `crafter`'s queue (the current character's without it).
function Alts:Taken(key, itemID, crafter)
    local t = Takes(crafter)[key]
    return t and t[itemID]
end

function Alts:IsSkipped(key, itemID)
    return self:Taken(key, itemID) == 0
end

-- Forgets the amounts chosen for materials `crafter`'s queue no longer needs (all of them once it is empty); byItem
-- is the set of needed item IDs.
function Alts:KeepTakes(byItem, crafter)
    local takes, dropped = Takes(crafter), false
    for key, t in pairs(takes) do
        for id in pairs(t) do
            if not byItem[id] then t[id], dropped = nil, true end
        end
        if next(t) == nil then takes[key] = nil end
    end
    if dropped then FP.Planner:Invalidate() end
end

-- Anything that holds on to a character's key (the queue's view, the profession or Overview shown in the main window,
-- an index built from the records) registers here, and lets go of it when that character is removed. fn(key) runs
-- while the record still exists.
local onRemove = {}
function Alts:OnRemove(fn) onRemove[#onRemove + 1] = fn end

function Alts:Remove(key)
    if key == self:GetCharacterKey() then return end
    for _, fn in ipairs(onRemove) do fn(key) end
    -- Otherwise the next login would import it again from Syndicator.
    FP.db.skipImport[key] = true
    FP.db.characters[key] = nil
    for _, rec in pairs(FP.db.characters) do
        if rec.takes then rec.takes[key] = nil end
    end
    Changed()
end

---------------------------------------------------------------------------
-- Raw inventory queries (no allocation or planning; see TransferPlanner.lua)
---------------------------------------------------------------------------
local function Count(key, itemID)
    local bags, bank, mail = Alts:Counts(key)
    return (bags[itemID] or 0) + (bank[itemID] or 0) + (mail[itemID] or 0)
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

-- { enabled = { entry }, ignored = { entry }, enabledTotal, ignoredTotal }; entries hold bags, bank, mail and count,
-- largest holding first. Disabled characters, and ones unticked for this material, are listed as ignored, never counted.
function Alts:GetAltBreakdown(itemID)
    local out = { enabled = {}, ignored = {}, enabledTotal = 0, ignoredTotal = 0 }
    for _, c in ipairs(self:Others()) do
        local rec = c.rec
        local bagCount, bankCount, mailCount = self:Counts(c.key)
        local bags, bank, mail = bagCount[itemID] or 0, bankCount[itemID] or 0, mailCount[itemID] or 0
        local count = bags + bank + mail
        -- The other faction can never send anything, so it isn't listed at all.
        if count > 0 and not IsOtherFaction(rec) then
            local on = self:IsEligible(c.key, rec) and not self:IsSkipped(c.key, itemID)
            local list = on and out.enabled or out.ignored
            list[#list + 1] = { key = c.key, name = rec.name or c.key, realm = rec.realm, class = rec.class,
                bags = bags, bank = bank, mail = mail, count = count }
            if on then out.enabledTotal = out.enabledTotal + count else out.ignoredTotal = out.ignoredTotal + count end
        end
    end
    table.sort(out.enabled, ByCount)
    table.sort(out.ignored, ByCount)
    return out
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
    if entry.realm and entry.realm ~= self:Realm() then return name .. "-" .. entry.realm end
    return name
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
FP:RegisterEvent("BAG_UPDATE", function(self, bag) self.Alts:OnBagUpdate(bag) end)
FP:RegisterEvent("PLAYER_LOGOUT", function(self) self.Alts:Flush() end)
