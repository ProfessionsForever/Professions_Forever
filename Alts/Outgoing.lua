local _, FP = ...
local L = FP.L
local Outgoing = {}
FP.Outgoing = Outgoing

-- What each character should mail the others. It is worked out from each recipient's queue (Core/Queue.lua, kept
-- account-wide) every time it is asked, so it always matches the queues. Only what can't be worked out is saved:
-- FP.db.transfers[recipientKey] = { manual = { [senderKey] = { [itemID] = quantity } },
--                                   gear = { [senderKey] = { [guid] = link } }, gold = { [senderKey] = copper } }
-- `manual` holds what the recipient asked a character for by hand in the Transfer Planner, apart from any queue: it is
-- counted off as it is mailed (RecordSent), and so is `gold`, money to send. `gear` holds single pieces of gear asked for from Disenchanting Mode, by
-- GUID, since random-enchant pieces share one item ID. A piece is asked for only while the sender still holds it
-- (its saved gear, Alts/AltInventory.lua "Gear"): once mailed, sold, disenchanted or equipped it drops (PruneGear).
-- What has been mailed for a queue is not kept here: it is in the recipient's mailbox, which its record counts as its
-- own (Alts/AltInventory.lua, "Mail"), so its plan no longer asks for it.

local EMPTY = {}

-- Before 0.10.0 each crafter saved a snapshot of what others should send it (`senders`, by Publish or by queueing
-- for it). Those came from queues that may have changed since, so they are dropped and worked out again.
function Outgoing:MoveOldTransfers()
    for key, entry in pairs(FP.db.transfers) do
        entry.senders, entry.name, entry.realm, entry.class, entry.sent = nil, nil, nil, nil, nil
        if next(entry) == nil then FP.db.transfers[key] = nil end
    end
end

-- A removed character is owed nothing and asked for nothing.
FP.Alts:OnRemove(function(key)
    FP.db.transfers[key] = nil
    for recipient, entry in pairs(FP.db.transfers) do
        if entry.manual then entry.manual[key] = nil end
        if entry.gear then entry.gear[key] = nil end
        if entry.gold then entry.gold[key] = nil end
        Outgoing.Tidy(recipient)
    end
end)

---------------------------------------------------------------------------
-- Requests made by hand: items asked for in the Transfer Planner, gear asked for from Disenchanting Mode
---------------------------------------------------------------------------
-- Drops the empty tables a removed request leaves behind.
function Outgoing.Tidy(recipient)
    local entry = FP.db.transfers[recipient]
    if not entry then return end
    for _, field in ipairs({ "manual", "gear", "gold" }) do
        local t = entry[field]
        if t then
            for sender, list in pairs(t) do
                if type(list) == "table" and next(list) == nil then t[sender] = nil end
            end
            if next(t) == nil then entry[field] = nil end
        end
    end
    if next(entry) == nil then FP.db.transfers[recipient] = nil end
end

-- The table `field` ("manual" or "gear") of what `recipient` asked `sender` for, made when `create` is set.
local function Asks(recipient, field, sender, create)
    local entry = FP.db.transfers[recipient]
    if not entry then
        if not create then return nil end
        entry = {}
        FP.db.transfers[recipient] = entry
    end
    local t = entry[field]
    if not t then
        if not create then return nil end
        t = {}
        entry[field] = t
    end
    if not t[sender] and create then t[sender] = {} end
    return t[sender]
end

-- How many of an item `recipient` asked `sender` for by hand.
function Outgoing:Asked(recipient, sender, itemID)
    local t = Asks(recipient, "manual", sender)
    return t and t[itemID] or 0
end

-- Sets how many of an item `recipient` asks `sender` for; 0 removes the request.
function Outgoing:SetAsked(recipient, sender, itemID, qty)
    qty = math.max(0, math.floor(qty or 0))
    local t = Asks(recipient, "manual", sender, qty > 0)
    if t then t[itemID] = qty > 0 and qty or nil end
    self.Tidy(recipient)
    FP:Changed("sends")
end

-- How much money (copper) `recipient` gets from `sender` by hand.
function Outgoing:Gold(recipient, sender)
    local entry = FP.db.transfers[recipient]
    return entry and entry.gold and entry.gold[sender] or 0
end

-- Sets how much money `sender` sends `recipient`; 0 removes it.
function Outgoing:SetGold(recipient, sender, copper)
    copper = math.max(0, math.floor(copper or 0))
    local entry = FP.db.transfers[recipient]
    if copper > 0 then
        entry = entry or {}
        FP.db.transfers[recipient] = entry
        entry.gold = entry.gold or {}
        entry.gold[sender] = copper
    elseif entry and entry.gold then
        entry.gold[sender] = nil
    end
    self.Tidy(recipient)
    FP:Changed("sends")
end

-- Whether `sender` still holds the piece of gear with this GUID, as of its last scan.
local function Holds(sender, guid)
    local g = FP.db.characters[sender] and FP.db.characters[sender].deGear
    for _, part in ipairs({ g and g.bags or EMPTY, g and g.bank or EMPTY }) do
        for _, piece in ipairs(part) do
            if piece.guid == guid then return true end
        end
    end
    return false
end

function Outgoing:GearAsked(recipient, sender, guid)
    local t = Asks(recipient, "gear", sender)
    return t and t[guid] ~= nil or false
end

-- Asks `sender` to send `recipient` the piece with this GUID (`link` set), or stops asking (`link` nil).
function Outgoing:SetGearAsked(recipient, sender, guid, link)
    local t = Asks(recipient, "gear", sender, link ~= nil)
    if t then t[guid] = link end
    self.Tidy(recipient)
    FP:Changed("sends")
end

-- The current character's gear was scanned: pieces it no longer holds are no longer asked for. Not while its bank is
-- open: a piece moved between bags and bank would be missing from both for a moment.
function Outgoing:PruneGear()
    if FP.Inv.bankOpen then return end
    local me = FP.Alts:GetCharacterKey()
    local changed = false
    for recipient, entry in pairs(FP.db.transfers) do
        local t = entry.gear and entry.gear[me]
        if t then
            for guid in pairs(t) do
                if not Holds(me, guid) then t[guid], changed = nil, true end
            end
            self.Tidy(recipient)
        end
    end
    if changed then FP:Changed("sends") end
end

-- The pieces `recipient` asked `sender` for that it still holds: { { guid, link, itemID } }, by name.
local function GearList(recipient, sender)
    local out = {}
    for guid, link in pairs(Asks(recipient, "gear", sender) or EMPTY) do
        if Holds(sender, guid) then
            out[#out + 1] = { guid = guid, link = link, itemID = C_Item.GetItemInfoInstant(link) }
        end
    end
    table.sort(out, function(a, b) return a.link < b.link end)
    return out
end

local function ByName(a, b)
    local na, nb = a.name:lower(), b.name:lower()
    if na ~= nb then return na < nb end
    return a.key < b.key
end

-- What `recipient` gets from the other characters by hand: { { key, name, realm, class, items = { { itemID, qty } },
-- gear = { { guid, link, itemID } }, gold (copper) } }, by name.
function Outgoing:Requests(recipient)
    local out, entry, senders = {}, FP.db.transfers[recipient], {}
    for _, field in ipairs({ "manual", "gear", "gold" }) do
        for sender in pairs(entry and entry[field] or EMPTY) do senders[sender] = true end
    end
    for sender in pairs(senders) do
        local rec = FP.db.characters[sender]
        local r = { key = sender, name = rec.name or sender, realm = rec.realm, class = rec.class, items = {},
            gear = GearList(recipient, sender), gold = self:Gold(recipient, sender) }
        for itemID, qty in pairs(entry.manual and entry.manual[sender] or EMPTY) do
            r.items[#r.items + 1] = { itemID = itemID, qty = qty }
        end
        table.sort(r.items, function(a, b) return a.itemID < b.itemID end)
        if #r.items > 0 or #r.gear > 0 or r.gold > 0 then out[#out + 1] = r end
    end
    table.sort(out, ByName)
    return out
end

-- What `sender` sends the other characters by hand (not for a queue): { { key (the recipient), name, realm, class,
-- items = { { itemID, qty } }, gear = { { guid, link, itemID } }, gold (copper) } }, by name. The shape of a Pending
-- entry, so the Mail button can attach it.
function Outgoing:ManualSends(sender)
    local out = {}
    for recipient in pairs(FP.db.transfers) do
        local rec = FP.db.characters[recipient]
        if rec and recipient ~= sender then
            local r = { key = recipient, name = rec.name or recipient, realm = rec.realm, class = rec.class, items = {},
                gear = GearList(recipient, sender), gold = self:Gold(recipient, sender) }
            for itemID, qty in pairs(Asks(recipient, "manual", sender) or EMPTY) do
                r.items[#r.items + 1] = { itemID = itemID, qty = qty }
            end
            table.sort(r.items, function(a, b) return a.itemID < b.itemID end)
            if #r.items > 0 or #r.gear > 0 or r.gold > 0 then out[#out + 1] = r end
        end
    end
    table.sort(out, ByName)
    return out
end

-- The characters `key` can mail or be mailed by: every other character of its faction (mail can't cross factions).
function Outgoing:SameFaction(key)
    local out, faction = {}, FP.db.characters[key].faction
    for other, rec in pairs(FP.db.characters) do
        if other ~= key and (faction == nil or rec.faction == nil or rec.faction == faction) then
            out[#out + 1] = { key = other, name = rec.name or other }
        end
    end
    table.sort(out, ByName)
    return out
end

-- The part of what this character should send `recipient` that its queue asks for: { [itemID] = n }.
local function QueuePart(recipient)
    local want, rec = {}, FP.db.characters[recipient]
    if rec.queue and #rec.queue > 0 then
        local c = FP.Queue:TransferNeeds(recipient).byCharacter[FP.Alts:GetCharacterKey()]
        for _, item in ipairs(c and c.items or EMPTY) do want[item.itemID] = item.transfer end
    end
    return want
end

-- What this character should still send: { { key, name, realm, class, items = { { itemID, qty, asked } },
-- gear = { { guid, link, itemID } }, gold (copper) } }, by name. `asked` is the part of qty asked for by hand, the rest is for the
-- recipient's queue.
function Outgoing:Pending()
    local out, me = {}, FP.Alts:GetCharacterKey()
    for key, rec in pairs(FP.db.characters) do
        if key ~= me then
            local want, asked = QueuePart(key), Asks(key, "manual", me) or EMPTY
            for itemID, qty in pairs(asked) do want[itemID] = (want[itemID] or 0) + qty end
            local gear, gold = GearList(key, me), self:Gold(key, me)
            if next(want) or #gear > 0 or gold > 0 then
                local p = { key = key, name = rec.name or key, realm = rec.realm, class = rec.class, items = {}, gear = gear,
                    gold = gold }
                for itemID, qty in pairs(want) do
                    p.items[#p.items + 1] = { itemID = itemID, qty = qty, asked = asked[itemID] or 0 }
                end
                table.sort(p.items, function(a, b) return a.itemID < b.itemID end)
                out[#out + 1] = p
            end
        end
    end
    table.sort(out, ByName)
    return out
end

-- How many characters this one should still mail, and how many item types (each piece of gear, and money, counting as
-- one) in all.
function Outgoing:PendingTotals()
    local recipients, itemTypes = 0, 0
    for _, p in ipairs(self:Pending()) do
        recipients, itemTypes = recipients + 1, itemTypes + #p.items + #p.gear + (p.gold > 0 and 1 or 0)
    end
    return recipients, itemTypes
end

-- Everything to send `p` (an entry of Pending or Requests) as one list: its items, then its gear as { itemID, qty = 1,
-- link }.
function Outgoing.AllItems(p)
    local out = {}
    for _, item in ipairs(p.items) do out[#out + 1] = item end
    for _, g in ipairs(p.gear) do out[#out + 1] = { itemID = g.itemID, qty = 1, link = g.link } end
    return out
end

-- "2x Linen Cloth, 4x Coarse Thread and 3 more": the first few of `items`, each { itemID, [field] = quantity, link }.
local function ItemList(items, field)
    local parts = {}
    for i, item in ipairs(items) do
        if i > 4 then
            parts[#parts + 1] = L["and %d more"]:format(#items - 4)
            break
        end
        parts[#parts + 1] = item[field] .. "x " .. (item.link or FP.ItemName(item.itemID))
    end
    return table.concat(parts, ", ")
end

-- One chat line per recipient, a few items each, and the money.
function Outgoing:Announce()
    for _, p in ipairs(self:Pending()) do
        local list = ItemList(self.AllItems(p), "qty")
        if p.gold > 0 then list = list == "" and FP.Prices:Format(p.gold) or (FP.Prices:Format(p.gold) .. ", " .. list) end
        FP:Print(L["Send to %s: %s"]:format(FP.Alts:Label(p), list))
    end
end

-- The whole plan for `key`'s queue in chat: what each character, this one included, should send it, and what no one has.
function Outgoing:AnnouncePlan(key)
    local plan, me, rec = FP.Queue:TransferNeeds(key), FP.Alts:GetCharacterKey(), FP.db.characters[key]
    local to = FP.Alts:Label(rec)
    for _, c in ipairs(plan.characters) do
        local list = ItemList(c.items, "transfer")
        if c.key == me then
            FP:Print(L["Send to %s: %s"]:format(to, list))
        else
            FP:Print(L["%s sends %s: %s"]:format(FP.Alts:Label(c), to, list))
        end
    end
    local missing = {}
    for _, it in ipairs(plan.items) do
        if it.stillMissing > 0 then missing[#missing + 1] = { itemID = it.itemID, qty = it.stillMissing } end
    end
    if #missing > 0 then FP:Print(L["Still missing for %s: %s"]:format(to, ItemList(missing, "qty"))) end
end

-- Mail sent to one of your other characters is in its mailbox now: items is { [itemID] = n }, money the copper sent
-- (not cash on delivery), which comes off the money it was to get from this character. Its queue's part comes
-- off by itself, since the mail counts as the recipient's; what the mail carries beyond that comes off what it asked
-- this character for by hand. Gear asked for drops at this character's next bag scan (PruneGear).
function Outgoing:RecordSent(recipient, items, money)
    local key = FP.Alts:KeyByName(recipient)
    if not key then return end
    local me = FP.Alts:GetCharacterKey()
    if money > 0 and self:Gold(key, me) > 0 then self:SetGold(key, me, self:Gold(key, me) - money) end
    local asked = Asks(key, "manual", me)
    if asked then
        local queued = QueuePart(key)
        for itemID, n in pairs(items) do
            local a = asked[itemID]
            if a then
                local left = a - math.max(0, n - (queued[itemID] or 0))
                asked[itemID] = left > 0 and left or nil
            end
        end
        self.Tidy(key)
    end
    FP.Alts:AddMail(key, items)
    FP:Changed("sends")
end

---------------------------------------------------------------------------
-- Mailbox
---------------------------------------------------------------------------
local function ReadAttachments()
    local out = {}
    for i = 1, ATTACHMENTS_MAX_SEND do
        local _, itemID, _, count = GetSendMailItem(i)
        if type(itemID) == "number" and itemID > 0 then out[itemID] = (out[itemID] or 0) + (count or 1) end
    end
    return out
end

-- Switches the open mailbox to Send Mail and fills in the recipient when the To box is empty.
function Outgoing.StartMail(name)
    if not SendMailFrame:IsShown() then MailFrameTab_OnClick(nil, 2) end -- the Send Mail tab
    if SendMailNameEditBox:GetText() == "" then SendMailNameEditBox:SetText(name) end
end

-- The first attachment slot that is free and not taken by `used` (marked taken there), or nil when the mail is full.
local function FreeAttachment(used)
    for i = 1, ATTACHMENTS_MAX_SEND do
        if not used[i] and not GetSendMailItem(i) then
            used[i] = true
            return i
        end
    end
end

local function AttachTo(i, bag, slot)
    ClearCursor()
    C_Container.PickupContainerItem(bag, slot)
    ClickSendMailItemButton(i)
    ClearCursor() -- in case the slot refused it
end

-- Split stacks on their way to an empty bag slot, attached once they are there: { bag, slot, i (the attachment slot
-- kept for it), itemID, count }. A split stack can't go straight from the cursor onto a mail: the mail takes the
-- whole stack it came from.
local landing = {}

local function AttachLanded()
    if #landing == 0 then return end
    if not SendMailFrame:IsShown() then wipe(landing) return end
    -- Off the list before attaching: each attach fires ITEM_LOCK_CHANGED straight away, which runs this again.
    local ready = {}
    for n = #landing, 1, -1 do
        local s = landing[n]
        local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
        if info and not info.isLocked then ready[#ready + 1] = table.remove(landing, n) end
    end
    for _, s in ipairs(ready) do
        local i = GetSendMailItem(s.i) and FreeAttachment({}) or s.i -- its slot taken by hand meanwhile
        if i then AttachTo(i, s.bag, s.slot) end
    end
end
FP:RegisterEvent("BAG_UPDATE_DELAYED", AttachLanded)
FP:RegisterEvent("ITEM_LOCK_CHANGED", AttachLanded)
FP:RegisterEvent("MAIL_CLOSED", function() wipe(landing) end)

-- Attaches what is in a bag slot to the mail being written, in its first free attachment slot: `count` of the stack,
-- or all of it without one. A part of a stack is split off into an empty bag slot first and attached a moment later,
-- once it is there. The game fills the attachment and bag slots a moment after each move, so a caller attaching
-- several things passes the same `used` table each time to keep track of them. False when every attachment slot is
-- taken, "bags" when there is no empty bag slot to split into.
function Outgoing.AttachSlot(bag, slot, count, used)
    used = used or {}
    local i = FreeAttachment(used)
    if not i then return false end
    if not count then
        AttachTo(i, bag, slot)
        return true
    end
    local toBag, toSlot = FP.Inv:FreeSlot(used)
    if not toBag then
        used[i] = nil
        return "bags"
    end
    ClearCursor()
    C_Container.SplitContainerItem(bag, slot, count)
    C_Container.PickupContainerItem(toBag, toSlot)
    landing[#landing + 1] = { bag = toBag, slot = toSlot, i = i, itemID = C_Container.GetContainerItemID(bag, slot), count = count }
    return true
end

-- Puts what this character should send `p` (an entry of Pending) on a new mail at the open mailbox: switches to Send
-- Mail, fills in their name when the To box is empty, and attaches from the bags as much of each item as is still
-- asked (less what is already attached), whole stacks where they fit and a split stack for the rest, then each piece
-- of gear asked for, found by its GUID, until the attachment slots are full. Soulbound and locked items are skipped
-- (an item attached to the mail is locked in the bag, so clicking again doesn't attach it twice).
function Outgoing:Attach(p)
    if not MailFrame:IsShown() then return end
    Outgoing.StartMail(p.name)
    local attached, used = ReadAttachments(), {}
    for _, s in ipairs(landing) do attached[s.itemID] = (attached[s.itemID] or 0) + s.count end -- split, not on yet
    local filled, full = 0, false
    local wanted = {}
    for _, g in ipairs(p.gear) do wanted[g.guid] = true end
    if next(wanted) then
        for _, bag in ipairs(FP.Inv:CarriedBags()) do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                if full then break end
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and not info.isLocked and wanted[C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot))] then
                    if Outgoing.AttachSlot(bag, slot, nil, used) then filled = filled + 1 else full = true end
                end
            end
        end
    end
    for _, item in ipairs(p.items) do
        local want = item.qty - (attached[item.itemID] or 0)
        for _, bag in ipairs(FP.Inv:CarriedBags()) do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                if want <= 0 or full then break end
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID == item.itemID and not info.isLocked and not info.isBound then
                    local take = math.min(want, info.stackCount)
                    local done = Outgoing.AttachSlot(bag, slot, take < info.stackCount and take or nil, used)
                    if done == "bags" then
                        FP:Print(L["No free bag slot to split %s. Make room in your bags, then click Mail again."]:format(FP.ItemName(item.itemID)))
                        want = 0
                    elseif done then
                        want, filled = want - take, filled + 1
                    else
                        full = true
                    end
                end
            end
        end
    end
    -- Money goes on as Send Money (never cash on delivery), through the mail window's own money box, since that is
    -- what the game sends when Send is pressed.
    if p.gold > 0 then
        local copper = math.min(p.gold, GetMoney())
        if not SendMailSendMoneyButton:GetChecked() then SendMailSendMoneyButton:Click() end
        MoneyInputFrame_SetCopper(SendMailMoney, copper)
        if copper < p.gold then
            FP:Print(L["You have only %s of the %s to send."]:format(FP.Prices:Format(copper), FP.Prices:Format(p.gold)))
        end
    end
    if full then
        FP:Print(L["The mail's attachment slots are full. Send it, then click Mail again for the rest."])
    elseif filled == 0 and (#p.items > 0 or #p.gear > 0) then
        FP:Print(L["None of it is in your bags to attach."])
    end
end

-- Attachments are still in the slots when the send is requested; the send only counts once the game confirms it.
local sending
local function OnSendMail(recipient)
    sending = { recipient = recipient, items = ReadAttachments(), money = GetSendMailMoney() or 0 }
end
hooksecurefunc("SendMail", OnSendMail)

FP:RegisterEvent("MAIL_SEND_SUCCESS", function(self)
    if sending then self.Outgoing:RecordSent(sending.recipient, sending.items, sending.money) end
    sending = nil
end)
FP:RegisterEvent("MAIL_FAILED", function() sending = nil end)
FP:RegisterEvent("MAIL_SHOW", function(self)
    -- Something to send, or something for the queue waiting to be collected.
    if self.db.mailPrompt and (#self.Outgoing:Pending() > 0 or #self.Transfer.MailNeeds(self.Queue:TransferNeeds()) > 0) then
        self.UI:OpenSidePanelFor(self.Transfer, "mail") -- and it closes with the mailbox
    end
    self:Changed("sends") -- the Mail buttons follow the mailbox; the redraw comes a frame later, once it is shown
end)
FP:RegisterEvent("MAIL_CLOSED", function(self)
    self.UI:CloseSidePanelsOpenedBy("mail")
    self:Changed("sends")
end)

-- The current character's inbox, read while its mailbox is open: what waits there is counted as its own. Mail with a
-- cash-on-delivery charge isn't: it isn't yours until it is paid for. The inbox changes in bursts (opening it, taking
-- several items), so it is read once on the next frame.
local scanPending
local function ScanInbox()
    scanPending = false
    if FP.Alts:UsesSyndicator() then return end -- its own scan is used, and it says when that changed
    if not MailFrame:IsShown() then return end -- closed since: the inbox reads as empty then
    local counts = {}
    for mail = 1, (GetInboxNumItems()) do
        local _, _, _, _, _, cod, _, itemCount = GetInboxHeaderInfo(mail)
        if itemCount and cod == 0 then
            for attachment = 1, ATTACHMENTS_MAX_RECEIVE do
                local _, itemID, _, count = GetInboxItem(mail, attachment)
                if itemID then counts[itemID] = (counts[itemID] or 0) + count end
            end
        end
    end
    FP.Alts:SetMail(counts)
    FP:Changed("inventory")
end
FP:RegisterEvent("MAIL_INBOX_UPDATE", function()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0, ScanInbox)
end)

---------------------------------------------------------------------------
-- Collecting what the queue needs from the open mailbox (the Transfer Planner's Collect from Mailbox button)
---------------------------------------------------------------------------
-- The game hands over one attachment at a time and needs a moment for each, and a mail that is emptied disappears and
-- moves the others up. So one stack is taken per step, then the inbox is looked through again. Whole stacks only (a
-- stack in the mail can't be split), never from cash-on-delivery mail (taking it would pay), and it stops when the bags
-- are full, the mailbox closes, or the queue has what it needs.
local COLLECT_STEP = 0.4
local collecting -- [itemID] = still wanted, while a collect is under way

local function FreeBagSlots()
    local free = 0
    for _, bag in ipairs(FP.Inv:CarriedBags()) do free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0) end
    return free
end

local function CollectStep()
    if not collecting then return end
    if not MailFrame:IsShown() then collecting = nil return end
    for mail = 1, (GetInboxNumItems()) do
        local _, _, _, _, _, cod, _, itemCount = GetInboxHeaderInfo(mail)
        if itemCount and cod == 0 then
            for attachment = 1, ATTACHMENTS_MAX_RECEIVE do
                local _, itemID, _, count = GetInboxItem(mail, attachment)
                local want = itemID and collecting[itemID]
                if want and want > 0 then
                    if FreeBagSlots() == 0 then
                        collecting = nil
                        return FP:Print(L["Your bags are full. Make room, then click Collect from Mailbox again."])
                    end
                    TakeInboxItem(mail, attachment)
                    collecting[itemID] = want - count
                    return C_Timer.After(COLLECT_STEP, CollectStep)
                end
            end
        end
    end
    collecting = nil -- nothing more of what is wanted
end

-- needs: { { itemID, qty } } (Transfer.MailNeeds). Returns false when there is nothing to take.
function Outgoing:Collect(needs)
    if collecting or not MailFrame:IsShown() then return false end
    local want, any = {}, false
    for _, n in ipairs(needs) do
        if n.qty > 0 then want[n.itemID], any = (want[n.itemID] or 0) + n.qty, true end
    end
    if not any then return false end
    collecting = want
    CollectStep()
    return true
end
