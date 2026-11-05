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

-- Flat list for the scroll area: this character's bank, then per character, every needed material it holds, taken or
-- not, then what no one can supply.
function Transfer.BuildRows(plan)
    local rows, groups, byKey = {}, {}, {}
    local bank = Transfer.BankNeeds(plan)
    if #bank > 0 then
        rows[#rows + 1] = { kind = "section", text = L["Withdraw from Your Bank"] }
        for _, b in ipairs(bank) do rows[#rows + 1] = { kind = "bank", it = b } end
    end
    local sending = FP.Outgoing:Pending()
    if #sending > 0 then
        rows[#rows + 1] = { kind = "section", text = L["To Send from This Character"] }
        for _, p in ipairs(sending) do
            rows[#rows + 1] = { kind = "sendto", p = p }
            for _, item in ipairs(p.items) do rows[#rows + 1] = { kind = "send", p = p, item = item } end
        end
    end
    for _, it in ipairs(plan.items) do
        for _, opt in ipairs(it.options) do
            local g = byKey[opt.key]
            if not g then
                g = { key = opt.key, name = opt.name, realm = opt.realm, class = opt.class, opts = {}, usesBank = false }
                byKey[opt.key] = g
                groups[#groups + 1] = g
            end
            g.opts[#g.opts + 1] = { it = it, opt = opt }
            if opt.fromBank > 0 then g.usesBank = true end
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
    elseif e.kind == "send" then
        tip:SetItemByID(e.item.itemID)
        tip:AddLine(" ")
        tip:AddDoubleLine(L["send %d"]:format(e.item.qty), Alts:Label(e.p), 1, 1, 1, Alts:ClassColor(e.p.class))
    elseif e.kind == "item" then
        local o = e.o.opt
        tip:SetItemByID(e.o.it.itemID)
        tip:AddLine(" ")
        tip:AddDoubleLine(L["Transfer Needed"], o.transfer, 0.8, 0.8, 0.8, 1, 1, 1)
        tip:AddDoubleLine(L["Character Owns"], o.owns, 0.8, 0.8, 0.8, 1, 1, 1)
        if o.fromBank > 0 then
            tip:AddDoubleLine(L["In the Bank"], o.fromBank, 0.2, 0.8, 0.9, 0.2, 0.8, 0.9)
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
    elseif e.kind == "missing" then
        tip:SetItemByID(e.it.itemID)
        tip:AddLine(" ")
        tip:AddDoubleLine(L["Need"], e.it.need, 0.8, 0.8, 0.8, 1, 1, 1)
        tip:AddDoubleLine(L["Still Missing"], e.it.stillMissing, 0.8, 0.8, 0.8, 0.9, 0.2, 0.2)
        FP.UI:AddAltLines(tip, e.it)
    else
        return false
    end
end
