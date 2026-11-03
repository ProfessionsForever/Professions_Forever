local _, FP = ...
local L = FP.L
local Outgoing = {}
FP.Outgoing = Outgoing

-- What the crafting character asked each alt to send it, saved account-wide so the alt sees it on login:
-- FP.db.transfers[recipientKey] = { name, realm, class, senders = { [senderKey] = { [itemID] = quantity left to send } } }
-- Publishing replaces the recipient's whole entry; mailing items to that recipient counts them off the alt's share.

-- Saves the crafter's current transfer plan (after any materials unticked in the Transfer Planner).
function Outgoing:Publish()
    local rec, me = FP.Alts:Current()
    if not rec then return end
    local senders = {}
    for _, c in ipairs(FP.Queue:TransferNeeds().characters) do
        local mine = {}
        for _, item in ipairs(c.items) do mine[item.itemID] = item.transfer end
        if next(mine) then senders[c.key] = mine end
    end
    if next(senders) == nil then
        FP.db.transfers[me] = nil
        FP:Print(L["Nothing to publish; cleared your published transfers."])
    else
        FP.db.transfers[me] = { name = rec.name, realm = rec.realm, class = rec.class, senders = senders }
        local n = 0
        for _ in pairs(senders) do n = n + 1 end
        FP:Print(L["Published transfers from %d character(s)."]:format(n))
    end
end

-- What this character should still send: { { key, name, realm, class, items = { { itemID, qty } } } }, by name.
function Outgoing:Pending()
    local out, me = {}, FP.Alts:GetCharacterKey()
    for key, entry in pairs(FP.db.transfers) do
        local mine = entry.senders[me]
        if mine then
            local p = { key = key, name = entry.name or key, realm = entry.realm, class = entry.class, items = {} }
            for itemID, qty in pairs(mine) do p.items[#p.items + 1] = { itemID = itemID, qty = qty } end
            table.sort(p.items, function(a, b) return a.itemID < b.itemID end)
            out[#out + 1] = p
        end
    end
    table.sort(out, function(a, b)
        local na, nb = a.name:lower(), b.name:lower()
        if na ~= nb then return na < nb end
        return a.key < b.key
    end)
    return out
end

-- One chat line per recipient, a few items each.
function Outgoing:Announce()
    for _, p in ipairs(self:Pending()) do
        local parts = {}
        for i, item in ipairs(p.items) do
            if i > 4 then
                parts[#parts + 1] = L["and %d more"]:format(#p.items - 4)
                break
            end
            parts[#parts + 1] = item.qty .. "x " .. FP.UI.ItemName(item.itemID)
        end
        FP:Print(L["Send to %s: %s"]:format(FP.Alts:Label(p), table.concat(parts, ", ")))
    end
end

-- Counts mailed items off this character's share of the recipient's plan.
function Outgoing:RecordSent(recipient, items)
    local me = FP.Alts:GetCharacterKey()
    local name = strlower((recipient or ""):match("^[^-]+") or "")
    if name == "" or not me then return end
    for key, entry in pairs(FP.db.transfers) do
        local mine = strlower(entry.name or "") == name and entry.senders[me]
        if mine then
            for itemID, count in pairs(items) do
                if mine[itemID] then mine[itemID] = mine[itemID] > count and mine[itemID] - count or nil end
            end
            if next(mine) == nil then entry.senders[me] = nil end
            if next(entry.senders) == nil then FP.db.transfers[key] = nil end
        end
    end
    FP.Transfer:QueueUpdate()
end

---------------------------------------------------------------------------
-- Mailbox
---------------------------------------------------------------------------
local function ReadAttachments()
    local get = C_Mail and C_Mail.GetSendMailItem or GetSendMailItem
    local out = {}
    if not get then return out end
    for i = 1, ATTACHMENTS_MAX_SEND or 12 do
        local _, itemID, _, count = get(i)
        if type(itemID) == "number" and itemID > 0 then out[itemID] = (out[itemID] or 0) + (count or 1) end
    end
    return out
end

-- Attachments are still in the slots when the send is requested; the send only counts once the game confirms it.
local sending
local function OnSendMail(recipient) sending = { recipient = recipient, items = ReadAttachments() } end
if SendMail then hooksecurefunc("SendMail", OnSendMail) end
if C_Mail and C_Mail.SendMail then hooksecurefunc(C_Mail, "SendMail", OnSendMail) end

FP:RegisterEvent("MAIL_SEND_SUCCESS", function(self)
    if sending then self.Outgoing:RecordSent(sending.recipient, sending.items) end
    sending = nil
end)
FP:RegisterEvent("MAIL_FAILED", function() sending = nil end)
FP:RegisterEvent("MAIL_SHOW", function(self)
    if #self.Outgoing:Pending() > 0 then self.Transfer:Open() end
end)
