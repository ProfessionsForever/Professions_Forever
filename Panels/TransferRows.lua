local _, FP = ...
local L = FP.L
local Transfer = {}
FP.Transfer = Transfer

-- What this character's bank must supply for the queue: for each material, the part bags don't cover that the bank does.
function Transfer.BankNeeds(plan)
    local out = {}
    for _, it in ipairs(plan.items) do
        local qty = math.min(it.bank, math.max(0, it.need - it.bags))
        if qty > 0 then out[#out + 1] = { itemID = it.itemID, qty = qty, bank = it.bank } end
    end
    return out
end

-- What this character has to collect from its mailbox for the queue: for each material, the part bags and bank don't
-- cover that the mailbox does.
function Transfer.MailNeeds(plan)
    local out = {}
    for _, it in ipairs(plan.items) do
        if it.fromMail > 0 then out[#out + 1] = { itemID = it.itemID, qty = it.fromMail, mail = it.mail } end
    end
    return out
end

-- What the plan's character asked others for by hand: per sender, its items and pieces of gear. Your own sender row
-- gets the Mail button when the plan is another character's.
local function AddRequests(rows, target, mailTo)
    local requests = FP.Outgoing:Requests(target)
    if #requests == 0 then return end
    local me = FP.Alts:GetCharacterKey()
    rows[#rows + 1] = { kind = "section", text = L["Expected from Other Characters"] }
    for _, r in ipairs(requests) do
        rows[#rows + 1] = { kind = "askfrom", r = r, me = r.key == me, mailTo = r.key == me and mailTo or nil }
        if r.gold > 0 then rows[#rows + 1] = { kind = "askgold", r = r, gold = r.gold, target = target } end
        for _, item in ipairs(r.items) do rows[#rows + 1] = { kind = "ask", r = r, item = item, target = target } end
        for _, g in ipairs(r.gear) do rows[#rows + 1] = { kind = "askgear", r = r, gear = g, target = target } end
    end
end

-- Flat list for the scroll area: this character's bank and mailbox, then what this character should send others, then
-- what it asked others for by hand, then per character, every needed material it holds, taken or not, then what no
-- one can supply. For another character's plan (`view`, its key): what waits in that character's mailbox (to show why
-- it needs no more of it; only it can collect it), what it asked others for, then the groups, where the current
-- character is one of them, with its Mail button, and what no one can supply.
function Transfer.BuildRows(plan, view)
    local rows, groups, byKey = {}, {}, {}
    local me, mailTo = FP.Alts:GetCharacterKey(), nil
    if view then
        for _, p in ipairs(FP.Outgoing:Pending()) do
            if p.key == view then mailTo = p end
        end
        local mail = Transfer.MailNeeds(plan)
        if #mail > 0 then
            rows[#rows + 1] = { kind = "section", text = L["Waiting in %s's Mailbox"]:format(FP.Alts:Label(FP.db.characters[view])) }
            for _, m in ipairs(mail) do rows[#rows + 1] = { kind = "mail", it = m } end
        end
        AddRequests(rows, view, mailTo)
    else
        local bank = Transfer.BankNeeds(plan)
        if #bank > 0 then
            rows[#rows + 1] = { kind = "section", text = L["Withdraw from Bank"] }
            for _, b in ipairs(bank) do rows[#rows + 1] = { kind = "bank", it = b } end
        end
        local mail = Transfer.MailNeeds(plan)
        if #mail > 0 then
            rows[#rows + 1] = { kind = "section", text = L["Collect from Your Mailbox"] }
            for _, m in ipairs(mail) do rows[#rows + 1] = { kind = "mail", it = m } end
        end
        local sending = FP.Outgoing:Pending()
        if #sending > 0 then
            rows[#rows + 1] = { kind = "section", text = L["To Send from This Character"] }
            for _, p in ipairs(sending) do
                rows[#rows + 1] = { kind = "sendto", p = p }
                if p.gold > 0 then rows[#rows + 1] = { kind = "sendgold", p = p, gold = p.gold } end
                for _, item in ipairs(p.items) do rows[#rows + 1] = { kind = "send", p = p, item = item } end
                for _, g in ipairs(p.gear) do rows[#rows + 1] = { kind = "sendgear", p = p, gear = g } end
            end
        end
        AddRequests(rows, me)
    end
    for _, it in ipairs(plan.items) do
        for _, opt in ipairs(it.options) do
            local g = byKey[opt.key]
            if not g then
                g = { key = opt.key, name = opt.name, realm = opt.realm, class = opt.class, opts = {}, usesBank = false, usesMail = false,
                    me = opt.key == me, mailTo = opt.key == me and mailTo or nil }
                byKey[opt.key] = g
                groups[#groups + 1] = g
            end
            g.opts[#g.opts + 1] = { it = it, opt = opt }
            if opt.fromBank > 0 then g.usesBank = true end
            if opt.fromMail > 0 then g.usesMail = true end
        end
    end
    table.sort(groups, function(a, b)
        local na, nb = a.name:lower(), b.name:lower()
        if na ~= nb then return na < nb end
        return a.key < b.key
    end)
    if #groups > 0 then
        rows[#rows + 1] = { kind = "section", text = L["Materials to Retrieve from Other Characters"] }
        for _, g in ipairs(groups) do
            rows[#rows + 1] = { kind = "char", c = g }
            for _, o in ipairs(g.opts) do rows[#rows + 1] = { kind = "item", c = g, o = o } end
        end
    end
    local first = true
    for _, it in ipairs(plan.items) do
        if it.stillMissing > 0 then
            if first then
                rows[#rows + 1] = { kind = "section", text = L["Still Unavailable"] }
                first = false
            end
            rows[#rows + 1] = { kind = "missing", it = it }
        end
    end
    return rows
end

-- The Manual Transfers view's list, for `target` (the plan's character): what it sends by hand, then what it gets by
-- hand, each grouped by the other character. Rows: "mhead" { c, from, mailTo }, and "mitem" { itemID, qty },
-- "mgear" { gear }, "mgold" { gold }, each with sender and recipient.
function Transfer.BuildManualRows(target)
    local rows, Outgoing = {}, FP.Outgoing
    local me = FP.Alts:GetCharacterKey()
    local function Add(c, sender, recipient)
        for _, item in ipairs(c.items) do
            rows[#rows + 1] = { kind = "mitem", sender = sender, recipient = recipient, itemID = item.itemID, qty = item.qty }
        end
        for _, g in ipairs(c.gear) do rows[#rows + 1] = { kind = "mgear", sender = sender, recipient = recipient, gear = g } end
        if c.gold > 0 then rows[#rows + 1] = { kind = "mgold", sender = sender, recipient = recipient, gold = c.gold } end
    end
    local sends = Outgoing:ManualSends(target)
    if #sends > 0 then
        rows[#rows + 1] = { kind = "section", text = target == me and L["To Send from This Character"]
            or L["To Send from %s"]:format(FP.Alts:Label(FP.db.characters[target])) }
        for _, c in ipairs(sends) do
            -- Only the current character can mail, so only its own sends get the Mail button.
            rows[#rows + 1] = { kind = "mhead", c = c, mailTo = target == me and c or nil }
            Add(c, target, c.key)
        end
    end
    local mine = target ~= me and Outgoing:ManualSends(me) or {}
    local requests = Outgoing:Requests(target)
    if #requests > 0 then
        rows[#rows + 1] = { kind = "section", text = L["Expected from Other Characters"] }
        for _, r in ipairs(requests) do
            local mailTo
            if r.key == me then
                for _, c in ipairs(mine) do if c.key == target then mailTo = c end end
            end
            rows[#rows + 1] = { kind = "mhead", c = r, from = true, me = r.key == me, mailTo = mailTo }
            Add(r, r.key, target)
        end
    end
    return rows
end

-- Fills the shared tooltip for a row; returns false when the row has nothing to show.
function Transfer.RowTooltip(row)
    local e = row.entry
    if not e then return false end
    local tip, Alts = GameTooltip, FP.Alts
    if e.kind == "char" then
        local c = e.c
        tip:AddLine(Alts:Label(c), Alts:ClassColor(c.class))
        if c.usesBank then
            tip:AddLine(L["Some of these items are in this character's bank."], 0.2, 0.8, 0.9, true)
        end
        if c.usesMail then
            tip:AddLine(L["Some of these items are in this character's mailbox."], unpack(FP.UI.MAIL_COLOR))
        end
    elseif e.kind == "send" then
        local item = e.item
        tip:SetItemByID(item.itemID)
        tip:AddLine(" ")
        tip:AddDoubleLine(L["Send %d"]:format(item.qty), Alts:Label(e.p), 1, 1, 1, Alts:ClassColor(e.p.class))
        if item.asked > 0 then
            if item.qty > item.asked then
                tip:AddDoubleLine(L["For Their Queue"], item.qty - item.asked, 0.8, 0.8, 0.8, 1, 1, 1)
            end
            tip:AddDoubleLine(L["Manual Transfer"], item.asked, 0.8, 0.8, 0.8, 1, 0.82, 0)
            tip:AddLine(L["Click to change the amount. Click X or right-click to remove the manual transfer."], 0.8, 0.8, 0.8, true)
        end
    elseif e.kind == "sendgear" then
        tip:SetHyperlink(e.gear.link)
        tip:AddLine(" ")
        tip:AddDoubleLine(L["Send %d"]:format(1), Alts:Label(e.p), 1, 1, 1, Alts:ClassColor(e.p.class))
        tip:AddLine(L["Asked for from Disenchanting Mode."], 0.8, 0.8, 0.8, true)
        tip:AddLine(L["Click X or right-click to remove the manual transfer."], 0.8, 0.8, 0.8, true)
    elseif e.kind == "mhead" then
        tip:AddLine(Alts:Label(e.c), Alts:ClassColor(e.c.class))
        tip:AddLine(L["Manual transfers, apart from any queue. They show in the sender's Transfer Planner as things to send until they are mailed."], 0.8, 0.8, 0.8, true)
    elseif e.kind == "mitem" then
        tip:SetItemByID(e.itemID)
        tip:AddLine(" ")
        tip:AddDoubleLine(L["Manual Transfer"], e.qty, 0.8, 0.8, 0.8, 1, 0.82, 0)
        tip:AddDoubleLine(L["Character Owns"], select(3, FP.Planner:Holding(e.sender, e.itemID)), 0.8, 0.8, 0.8, 1, 1, 1)
        tip:AddLine(L["Click to change the amount. Click X or right-click to remove the manual transfer."], 0.8, 0.8, 0.8, true)
    elseif e.kind == "mgear" then
        tip:SetHyperlink(e.gear.link)
        tip:AddLine(" ")
        tip:AddLine(L["Asked for from Disenchanting Mode."], 0.8, 0.8, 0.8, true)
        tip:AddLine(L["Click X or right-click to remove the manual transfer."], 0.8, 0.8, 0.8, true)
    elseif e.kind == "mgold" then
        tip:AddLine(L["Money"], 1, 1, 1)
        tip:AddDoubleLine(L["Manual Transfer"], FP.Prices:Format(e.gold), 0.8, 0.8, 0.8, 1, 1, 1)
        tip:AddLine(L["Mail puts it on the mail as Send Money, never cash on delivery."], 0.8, 0.8, 0.8, true)
        tip:AddLine(L["Click to change the amount. Click X or right-click to remove the manual transfer."], 0.8, 0.8, 0.8, true)
    elseif e.kind == "sendgold" or e.kind == "askgold" then
        tip:AddLine(L["Money"], 1, 1, 1)
        tip:AddDoubleLine(L["Manual Transfer"], FP.Prices:Format(e.gold), 0.8, 0.8, 0.8, 1, 1, 1)
        if e.kind == "sendgold" then
            tip:AddLine(L["Mail puts it on the mail as Send Money, never cash on delivery."], 0.8, 0.8, 0.8, true)
        end
        tip:AddLine(L["Click to change the amount. Click X or right-click to remove the manual transfer."], 0.8, 0.8, 0.8, true)
    elseif e.kind == "askfrom" then
        tip:AddLine(Alts:Label(e.r), Alts:ClassColor(e.r.class))
        tip:AddLine(L["Manual transfers, apart from any queue. They show in this character's Transfer Planner as things to send."], 0.8, 0.8, 0.8, true)
    elseif e.kind == "ask" then
        tip:SetItemByID(e.item.itemID)
        tip:AddLine(" ")
        tip:AddDoubleLine(L["Manual Transfer"], e.item.qty, 0.8, 0.8, 0.8, 1, 0.82, 0)
        tip:AddDoubleLine(L["Character Owns"], select(3, FP.Planner:Holding(e.r.key, e.item.itemID)), 0.8, 0.8, 0.8, 1, 1, 1)
        tip:AddLine(L["Click to change the amount. Click X or right-click to remove the manual transfer."], 0.8, 0.8, 0.8, true)
    elseif e.kind == "askgear" then
        tip:SetHyperlink(e.gear.link)
        tip:AddLine(" ")
        tip:AddLine(L["Click X or right-click to remove the manual transfer."], 0.8, 0.8, 0.8, true)
    elseif e.kind == "item" then
        local o = e.o.opt
        tip:SetItemByID(e.o.it.itemID)
        tip:AddLine(" ")
        tip:AddDoubleLine(L["Transfer Needed"], o.transfer, 0.8, 0.8, 0.8, 1, 1, 1)
        tip:AddDoubleLine(L["Character Owns"], o.owns, 0.8, 0.8, 0.8, 1, 1, 1)
        if o.fromBank > 0 then
            tip:AddDoubleLine(L["In the Bank"], o.fromBank, 0.2, 0.8, 0.9, 0.2, 0.8, 0.9)
        end
        if o.fromMail > 0 then
            local c = FP.UI.MAIL_COLOR
            tip:AddDoubleLine(L["In the Mailbox"], o.fromMail, c[1], c[2], c[3], c[1], c[2], c[3])
        end
        if o.off then
            tip:AddLine(L["Turned off: this material is not taken from this character."], 1, 0.6, 0.2, true)
        end
        if o.manual then
            tip:AddLine(L["Right-click to let the planner decide again."], 0.8, 0.8, 0.8, true)
        end
    elseif e.kind == "bank" then
        tip:SetItemByID(e.it.itemID)
        tip:AddLine(" ")
        tip:AddDoubleLine(L["Take"], e.it.qty, 0.8, 0.8, 0.8, 1, 1, 1)
        tip:AddDoubleLine(L["In the Bank"], e.it.bank, 0.2, 0.8, 0.9, 0.2, 0.8, 0.9)
    elseif e.kind == "mail" then
        local c = FP.UI.MAIL_COLOR
        tip:SetItemByID(e.it.itemID)
        tip:AddLine(" ")
        tip:AddDoubleLine(L["Take"], e.it.qty, 0.8, 0.8, 0.8, 1, 1, 1)
        tip:AddDoubleLine(L["In the Mailbox"], e.it.mail, c[1], c[2], c[3], c[1], c[2], c[3])
    elseif e.kind == "missing" then
        tip:SetItemByID(e.it.itemID)
        tip:AddLine(" ")
        tip:AddDoubleLine(L["Need"], e.it.need, 0.8, 0.8, 0.8, 1, 1, 1)
        tip:AddDoubleLine(L["Still Missing"], e.it.stillMissing, 0.8, 0.8, 0.8, 0.9, 0.2, 0.2)
        FP.UI:AddAltLines(tip, e.it, true)
    else
        return false
    end
end
