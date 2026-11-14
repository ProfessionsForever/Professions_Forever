local _, FP = ...
local L = FP.L
local Outgoing = {}
FP.Outgoing = Outgoing

-- What each character should mail the others. It is worked out from each recipient's queue (Core/Queue.lua, kept
-- account-wide) every time it is asked, so it always matches the queues. Only what can't be worked out is saved:
-- FP.db.transfers[recipientKey] = { manual = { [senderKey] = { [itemID] = quantity } } }
-- `manual` is for requests not tied to a queue (planned, see TODO.md).
-- What has been mailed is not kept here: it is in the recipient's mailbox, which its record counts as its own
-- (Alts/AltInventory.lua, "Mail"), so its plan no longer asks for it.

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
    for _, entry in pairs(FP.db.transfers) do
        if entry.manual then entry.manual[key] = nil end
    end
end)

-- What this character should still send: { { key, name, realm, class, items = { { itemID, qty } } } }, by name.
function Outgoing:Pending()
    local out, me = {}, FP.Alts:GetCharacterKey()
    for key, rec in pairs(FP.db.characters) do
        if key ~= me then
            local want = {}
            if rec.queue and #rec.queue > 0 then
                local c = FP.Queue:TransferNeeds(key).byCharacter[me]
                for _, item in ipairs(c and c.items or EMPTY) do want[item.itemID] = item.transfer end
            end
            local manual = FP.db.transfers[key] and FP.db.transfers[key].manual
            for itemID, qty in pairs(manual and manual[me] or EMPTY) do want[itemID] = (want[itemID] or 0) + qty end
            if next(want) then
                local p = { key = key, name = rec.name or key, realm = rec.realm, class = rec.class, items = {} }
                for itemID, qty in pairs(want) do p.items[#p.items + 1] = { itemID = itemID, qty = qty } end
                table.sort(p.items, function(a, b) return a.itemID < b.itemID end)
                out[#out + 1] = p
            end
        end
    end
    table.sort(out, function(a, b)
        local na, nb = a.name:lower(), b.name:lower()
        if na ~= nb then return na < nb end
        return a.key < b.key
    end)
    return out
end

-- How many characters this one should still mail, and how many item types in all.
function Outgoing:PendingTotals()
    local recipients, itemTypes = 0, 0
    for _, p in ipairs(self:Pending()) do recipients, itemTypes = recipients + 1, itemTypes + #p.items end
    return recipients, itemTypes
end

-- "2x Linen Cloth, 4x Coarse Thread and 3 more": the first few of `items`, each { itemID, [field] = quantity }.
local function ItemList(items, field)
    local parts = {}
    for i, item in ipairs(items) do
        if i > 4 then
            parts[#parts + 1] = L["and %d more"]:format(#items - 4)
            break
        end
        parts[#parts + 1] = item[field] .. "x " .. FP.ItemName(item.itemID)
    end
    return table.concat(parts, ", ")
end

-- One chat line per recipient, a few items each.
function Outgoing:Announce()
    for _, p in ipairs(self:Pending()) do
        FP:Print(L["Send to %s: %s"]:format(FP.Alts:Label(p), ItemList(p.items, "qty")))
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

-- Mail sent to one of your other characters is in its mailbox now: items is { [itemID] = n }.
function Outgoing:RecordSent(recipient, items)
    local key = FP.Alts:KeyByName(recipient)
    if not key then return end
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

-- Attaches what is in a bag slot to the mail being written, in its first free attachment slot: `count` of the stack,
-- or all of it without one. The game fills the attachment slots a moment after each attach, so a caller attaching
-- several things passes the same `used` table each time to keep track of them. False when every slot is taken.
function Outgoing.AttachSlot(bag, slot, count, used)
    for i = 1, ATTACHMENTS_MAX_SEND do
        if not (used and used[i]) and not GetSendMailItem(i) then
            ClearCursor()
            if count then C_Container.SplitContainerItem(bag, slot, count) else C_Container.PickupContainerItem(bag, slot) end
            ClickSendMailItemButton(i)
            ClearCursor() -- in case the slot refused it
            if used then used[i] = true end
            return true
        end
    end
    return false
end

-- Puts what this character should send `p` (an entry of Pending) on a new mail at the open mailbox: switches to Send
-- Mail, fills in their name when the To box is empty, and attaches from the bags as much of each item as is still
-- asked (less what is already attached), whole stacks where they fit and a split stack for the rest, until the
-- attachment slots are full. Soulbound and locked items are skipped.
function Outgoing:Attach(p)
    if not MailFrame:IsShown() then return end
    Outgoing.StartMail(p.name)
    local attached, used = ReadAttachments(), {}
    local filled, full = 0, false
    for _, item in ipairs(p.items) do
        local want = item.qty - (attached[item.itemID] or 0)
        for _, bag in ipairs(FP.Inv:CarriedBags()) do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                if want <= 0 or full then break end
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID == item.itemID and not info.isLocked and not info.isBound then
                    local take = math.min(want, info.stackCount)
                    if Outgoing.AttachSlot(bag, slot, take < info.stackCount and take or nil, used) then
                        want, filled = want - take, filled + 1
                    else
                        full = true
                    end
                end
            end
        end
    end
    if full then
        FP:Print(L["The mail's attachment slots are full. Send it, then click Mail again for the rest."])
    elseif filled == 0 then
        FP:Print(L["None of it is in your bags to attach."])
    end
end

-- Attachments are still in the slots when the send is requested; the send only counts once the game confirms it.
local sending
local function OnSendMail(recipient) sending = { recipient = recipient, items = ReadAttachments() } end
hooksecurefunc("SendMail", OnSendMail)

FP:RegisterEvent("MAIL_SEND_SUCCESS", function(self)
    if sending then self.Outgoing:RecordSent(sending.recipient, sending.items) end
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
