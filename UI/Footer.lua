local _, FP = ...
local L = FP.L
local UI = FP.UI

-- Summary cells along the bottom of the window on every page; each one toggles its window.
local CELL_H, GAP = 56, 6
UI.FOOTER_RESERVE = CELL_H + GAP -- height the panels above leave free

---------------------------------------------------------------------------
-- Window tooltips: everything a footer window holds at a glance. The footer cells and the quick buttons both use them.
---------------------------------------------------------------------------
local MAX_ROWS = 10
local WHITE, GREY, GOLD = { 1, 1, 1 }, { 0.8, 0.8, 0.8 }, { 1, 0.82, 0 }

local function Section(tip, text)
    tip:AddLine(" ")
    tip:AddLine(text, GOLD[1], GOLD[2], GOLD[3])
end

-- rows: { left, right, leftColor, rightColor }; stops at `limit` (MAX_ROWS by default) with "and N more".
local function AddRows(tip, rows, limit)
    limit = limit or MAX_ROWS
    for i, row in ipairs(rows) do
        if i > limit then
            tip:AddLine(L["and %d more"]:format(#rows - limit), 0.6, 0.6, 0.6)
            break
        end
        local lc, rc = row[3] or WHITE, row[4] or WHITE
        tip:AddDoubleLine(row[1], row[2], lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
    end
end

-- A name with its icon in front, trimmed like Blizzard's own icons; 134400 is the question mark.
local function WithIcon(icon, text)
    return ("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(icon or 134400, text)
end

local function ItemRows(items, field, color)
    local rows = {}
    for _, item in ipairs(items) do
        rows[#rows + 1] = { WithIcon(C_Item.GetItemIconByID(item.itemID), FP.ItemName(item.itemID)), item[field], GREY, color }
    end
    return rows
end

local TIPS = {}

local OTHER_ROWS = 5 -- crafts listed per other character

-- A character's queue: its name with the totals, then each craft with its icon. `colorOf(q)` colours a craft's name.
local function AddQueue(tip, key, data, limit, colorOf)
    local crafts, rows = 0, {}
    for _, q in ipairs(data) do
        crafts = crafts + q.qty
        rows[#rows + 1] = { WithIcon(q.icon, q.name), q.qty .. "x",
            colorOf and colorOf(q) or WHITE }
    end
    tip:AddLine(" ")
    tip:AddDoubleLine(FP.Queue.CharacterName(key), L["%d recipes, %d crafts"]:format(#data, crafts), 1, 1, 1,
        GREY[1], GREY[2], GREY[3])
    AddRows(tip, rows, limit)
end

function TIPS.queue(tip)
    local Q, colors = FP.Queue, UI.STATUS_COLORS
    local me, data = FP.Alts:GetCharacterKey(), Q:Data()
    if #data == 0 then
        tip:AddLine(L["Nothing queued"], GREY[1], GREY[2], GREY[3])
    else
        local short = Q:EntryShortages()
        local bank, mail = Q:EntryFetch()
        AddQueue(tip, me, data, MAX_ROWS, function(q)
            return not Q:IsLearned(q) and colors.none or short[q] and colors.missing or bank[q] and colors.bank
                or mail[q] and UI.MAIL_COLOR or WHITE
        end)
        local missing = {}
        for _, it in ipairs(Q:TrueShortages()) do missing[#missing + 1] = { itemID = it.itemID, qty = it.shortage } end
        if #missing > 0 then
            Section(tip, L["Missing materials:"])
            AddRows(tip, ItemRows(missing, "qty", colors.missing))
        end
    end
    local others = {}
    for key, rec in pairs(FP.db.characters) do
        if key ~= me and rec.queue and #rec.queue > 0 then others[#others + 1] = key end
    end
    local chars = FP.db.characters
    table.sort(others, function(a, b) return FP.Alts:Label(chars[a]) < FP.Alts:Label(chars[b]) end)
    for _, key in ipairs(others) do AddQueue(tip, key, chars[key].queue, OTHER_ROWS) end
end

function TIPS.cooldowns(tip)
    local any = false
    for _, g in ipairs(FP.Cooldowns:List()) do
        local rows = {}
        for _, c in ipairs(g.entries) do
            if not (c.unknown or c.ignored) then
                local ready = c.remaining == 0
                rows[#rows + 1] = { c.name, ready and L["Ready"] or FP.Cooldowns.Format(c.remaining), GREY,
                    ready and UI.STATUS_COLORS.full or WHITE }
            end
        end
        if #rows > 0 then
            any = true
            Section(tip, FP.Queue.CharacterName(g.key))
            AddRows(tip, rows)
        end
    end
    if not any then tip:AddLine(L["No recipes with a cooldown known yet. Open a profession that has one."], GREY[1], GREY[2], GREY[3], true) end
end

function TIPS.transfer(tip)
    local plan, colors, any = FP.Queue:TransferNeeds(), UI.STATUS_COLORS, false
    for _, c in ipairs(plan.characters) do
        any = true
        Section(tip, L["From %s:"]:format(FP.Queue.CharacterName(c.key)))
        AddRows(tip, ItemRows(c.items, "transfer"))
    end
    for _, p in ipairs(FP.Outgoing:Pending()) do
        any = true
        Section(tip, L["Send to %s"]:format(FP.Queue.CharacterName(p.key)) .. ":")
        AddRows(tip, ItemRows(p.items, "qty"))
    end
    local waiting = FP.Transfer.MailNeeds(plan)
    if #waiting > 0 then
        any = true
        Section(tip, L["Collect from Your Mailbox"] .. ":")
        AddRows(tip, ItemRows(waiting, "qty", UI.MAIL_COLOR))
    end
    local missing = {}
    for _, it in ipairs(plan.items) do
        if it.stillMissing > 0 then missing[#missing + 1] = { itemID = it.itemID, qty = it.stillMissing } end
    end
    if #missing > 0 then
        any = true
        Section(tip, L["Still Unavailable"] .. ":")
        AddRows(tip, ItemRows(missing, "qty", colors.missing))
    end
    if not any then
        local text = FP.Planner:Mode() == "never" and L["Alt inventory is off"] or L["No transfers needed"]
        tip:AddLine(text, GREY[1], GREY[2], GREY[3])
    end
end

function TIPS.shop(tip)
    local data, P, rows = FP.Shop:Aggregate(), FP.Prices, {}
    local priced = P:Available()
    for _, e in ipairs(data) do
        if e.toBuy > 0 then
            local right = tostring(e.toBuy)
            if priced then right = right .. "   " .. (e.cost and P:Format(e.cost) or "-") end
            rows[#rows + 1] = { WithIcon(C_Item.GetItemIconByID(e.itemID), e.name), right, GREY }
        end
    end
    if #rows == 0 then
        tip:AddLine(L["Nothing to buy"], GREY[1], GREY[2], GREY[3])
        return
    end
    AddRows(tip, rows)
    if priced then
        local _, cost, unpriced = FP.Shop:Summary(data)
        tip:AddLine(" ")
        if cost > 0 then tip:AddDoubleLine(L["Estimated Cost"], P:Format(cost), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1) end
        if unpriced > 0 then tip:AddLine(L["%d without an auction price"]:format(unpriced), 0.6, 0.6, 0.6) end
    end
end

function TIPS.skillup(tip)
    local list = FP.SkillUpPanel:NextSteps()
    if #list == 0 then
        tip:AddLine(L["No route steps"], GREY[1], GREY[2], GREY[3])
        return
    end
    for _, p in ipairs(list) do
        local s = p.steps[1]
        Section(tip, p.name)
        tip:AddLine(s and s.text or L["No route steps"], 1, 1, 1, true)
        if s and s.detail then tip:AddLine(s.detail, GREY[1], GREY[2], GREY[3], true) end
    end
end

-- Adds the lines for the window under `key` (queue, cooldowns, transfer, shop, skillup) to `tip`.
function UI.FillWindowTip(tip, key)
    TIPS[key](tip)
end

local function MakeCell(f, key, title, onClick)
    local c = UI:Button(f, "", 100, CELL_H, onClick)
    c.title = UI:Text(c, 1)
    c.title:SetPoint("TOPLEFT", 12, -8)
    c.title:SetText(title)
    c.title:SetTextColor(1, 0.82, 0)
    c.line = UI:Text(c, 0)
    c.line:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
    c.sub = UI:Text(c, -1)
    c.sub:SetPoint("TOPLEFT", c.line, "BOTTOMLEFT", 0, -2)
    c.sub:SetTextColor(0.65, 0.65, 0.65)
    for _, fs in ipairs({ c.line, c.sub }) do
        fs:SetPoint("RIGHT", c, "RIGHT", -12, 0)
        fs:SetWordWrap(false)
    end
    UI:Tooltip(c, "ANCHOR_TOP", function(tip)
        tip:AddLine(title, 1, 0.82, 0)
        UI.FillWindowTip(tip, key)
        tip:AddLine(" ")
        tip:AddLine(L["Click to open or close."], 0.5, 0.8, 1)
    end)
    return c
end

function UI:CreateFooter(f)
    local footer = {}
    footer.queue = MakeCell(f, "queue", L["Crafting Queue"], function() FP.Queue:Toggle() end)
    footer.cooldowns = MakeCell(f, "cooldowns", L["Cooldowns"], function() FP.CooldownPanel:Toggle() end)
    footer.transfer = MakeCell(f, "transfer", L["Transfer Planner"], function() FP.Transfer:Toggle() end)
    footer.shop = MakeCell(f, "shop", L["Shopping List"], function() FP.Shop:Toggle() end)
    if FP.SkillUpPanel:Available() then
        footer.skillup = MakeCell(f, "skillup", L["Skill Up Route"], function() FP.SkillUpPanel:Toggle() end)
    end
    f.footer = footer
    self:LayoutFooter()
    self:RefreshFooterSelection()
end

-- The window each footer cell opens, by cell key. The panels load after this file, so it is built on first use.
local windows
function UI.FooterWindows()
    windows = windows or { cooldowns = FP.CooldownPanel, transfer = FP.Transfer, shop = FP.Shop, queue = FP.Queue,
        skillup = FP.SkillUpPanel:Available() and FP.SkillUpPanel or nil }
    return windows
end

-- A cell is lit while its window is open.
function UI:RefreshFooterSelection()
    FP.Launcher:RefreshSelection()
    self:SyncWindowButtons() -- the side panels' own row of window buttons
    local footer = self.frame and self.frame.footer
    if not footer then return end
    for key, window in pairs(UI.FooterWindows()) do
        UI.SetSelected(footer[key], window.frame and window.frame:IsShown())
    end
end

-- Sized from the window, as its own size can lag behind while it is being resized.
-- The Skill Up Route cell is left out while its option is off.
function UI:LayoutFooter()
    local f = self.frame
    local footer = f and f.footer
    if not footer then return end
    local cells = { footer.cooldowns, footer.transfer, footer.shop, footer.queue }
    if footer.skillup then
        footer.skillup:SetShown(FP.db.footerSkillUp)
        if FP.db.footerSkillUp then table.insert(cells, 2, footer.skillup) end
    end
    local n = #cells
    local w = (f:GetWidth() - 16 - GAP * (n - 1)) / n
    for i, c in ipairs(cells) do
        c:SetWidth(w)
        c:ClearAllPoints()
        if i == 1 then c:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
        else c:SetPoint("BOTTOMLEFT", cells[i - 1], "BOTTOMRIGHT", GAP, 0) end
    end
end

function UI:RefreshFooter()
    local f = self.frame
    local footer = f and f.footer
    if not (footer and f:IsShown()) then return end

    local n, crafts, missing = FP.Queue:Summary()
    local plan = FP.Queue:TransferNeeds()
    footer.queue.line:SetText(n == 0 and L["Nothing queued"] or L["%d recipes, %d crafts"]:format(n, crafts))
    local covered = plan.applies and plan.totals.units > 0
    -- This character's own queue comes first; with nothing queued here, say whether other characters have crafts queued.
    local others = n == 0 and FP.Queue:OthersQueued() or 0
    footer.queue.sub:SetText(n > 0 and (missing > 0 and L["%d materials still missing"]:format(missing)
        or (covered and L["Available on Other Characters"] or L["All materials on hand"]))
        or (others > 0 and L["Crafts queued on %d other character(s)"]:format(others)) or "")

    -- What other characters should send this one comes first, then what this one should send them.
    local t, mode = plan.totals, FP.Planner:Mode()
    local sendTo, sendTypes = FP.Outgoing:PendingTotals()
    local sendText = sendTo > 0 and L["Send %d item types to %d character(s)"]:format(sendTypes, sendTo)
    if mode ~= "never" and t.units > 0 then
        footer.transfer.line:SetText(L["%d characters - %d item types"]:format(t.characters, t.itemTypes))
        footer.transfer.sub:SetText(t.missingTypes > 0 and L["%d materials still unavailable"]:format(t.missingTypes)
            or sendText or (mode == "show" and L["Show only: not counted in shopping"] or ""))
    elseif sendText then
        footer.transfer.line:SetText(sendText)
        footer.transfer.sub:SetText("")
    elseif mode == "never" then
        footer.transfer.line:SetText(L["Alt inventory is off"])
        footer.transfer.sub:SetText("")
    else
        footer.transfer.line:SetText(L["No transfers needed"])
        footer.transfer.sub:SetText(FP.Alts:HasSources() and "" or L["No alt inventory known"])
    end

    local items, cost, unpriced = FP.Shop:Summary()
    footer.shop.line:SetText(items == 0 and L["Nothing to buy"] or L["%d items to buy"]:format(items))
    local sub = ""
    if items > 0 and FP.Prices:Available() then
        sub = cost > 0 and (L["Estimated Cost"] .. ": " .. FP.Prices:Format(cost)) or ""
        if unpriced > 0 then sub = sub .. (sub ~= "" and "  -  " or "") .. L["%d without an auction price"]:format(unpriced) end
    end
    footer.shop.sub:SetText(sub)

    local ready, chars, soon, soonOwner = 0, 0, nil, nil
    for _, g in ipairs(FP.Cooldowns:List()) do
        ready = ready + g.ready
        if g.ready > 0 then chars = chars + 1 end
        for _, c in ipairs(g.entries) do
            if not (c.unknown or c.ignored) and c.remaining > 0 and (not soon or c.remaining < soon.remaining) then
                soon, soonOwner = c, g.rec
            end
        end
    end
    if ready == 0 then
        footer.cooldowns.line:SetText(L["Nothing ready"])
    else
        local text = chars > 1 and L["%d ready on %d characters"]:format(ready, chars) or L["%d ready"]:format(ready)
        footer.cooldowns.line:SetText("|cff33e633" .. text .. "|r")
    end
    footer.cooldowns.sub:SetText(soon and L["Next: %s in %s (%s)"]:format(soon.name, FP.Cooldowns.Format(soon.remaining),
        FP.Alts:Label(soonOwner)) or "")

    if footer.skillup then
        local profession, step, detail = FP.SkillUpPanel:Summary()
        footer.skillup.line:SetText(step or L["No route steps"])
        footer.skillup.sub:SetText(profession and (detail and (profession .. " - " .. detail) or profession) or "")
    end
end
