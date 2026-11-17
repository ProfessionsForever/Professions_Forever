local _, FP = ...
local L = FP.L
local UI = FP.UI

-- Summary cells along the bottom of the window on every page; each one toggles its window. From TWO_ROWS cells on
-- they take two rows, and the window grows by one row so the panels above keep their size.
local CELL_H, GAP = 56, 6
local TWO_ROWS = 6
UI.FOOTER_ROW = CELL_H + GAP -- height one row of cells takes
UI.footerRows = 1
local ICON = 16 -- as tall as the title

-- Each window's icon, on its footer cell and its quick button (UI/Launcher.lua).
UI.WINDOW_ICONS = {
    cooldowns = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    skillup = "Interface\\Icons\\INV_Misc_Map_01",
    transfer = "Interface\\Icons\\INV_Letter_15",
    shop = "Interface\\Icons\\INV_Misc_Coin_01",
    queue = "Interface\\Icons\\INV_Misc_Gear_01",
    disenchant = "Interface\\Icons\\INV_Enchant_DustStrange",
    camp = "Interface\\Icons\\Spell_Fire_Fire",
}

-- Height the panels above leave free.
function UI:FooterReserve()
    return self.footerRows * self.FOOTER_ROW
end

-- Height the window adds for the rows past the first.
function UI:FooterExtra()
    return (self.footerRows - 1) * self.FOOTER_ROW
end

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
        local rows = ItemRows(FP.Outgoing.AllItems(p), "qty")
        if p.gold > 0 then
            table.insert(rows, 1, { WithIcon("Interface\\Icons\\INV_Misc_Coin_01", L["Money"]), FP.Prices:Format(p.gold), GREY })
        end
        AddRows(tip, rows)
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

local campTick -- a camp cooldown redraw is waiting (UI:RefreshFooter)

function TIPS.camp(tip)
    local Camp = FP.Camp
    -- The cooldowns: the two shared ones in white, then each extra you hold (sleeping bag, toy), which has its own,
    -- with its icon in grey like the item rows below. Only the list's heading is gold.
    local cooldowns = { { L["Camp Features"], Camp:Remaining(Camp.OBJECTS), WHITE },
        { L["Campfires"], Camp:Remaining(Camp.CAMPFIRES), WHITE } }
    local rows = {}
    for _, e in ipairs(Camp:List()) do
        local left = Camp:EntryRemaining(e)
        if e.extra and e.bags > 0 then
            cooldowns[#cooldowns + 1] = { WithIcon(C_Item.GetItemIconByID(e.id), e.name), left, GREY }
        end
        -- Listed below only when you could use it right now: in the bags, its profession known, its cooldown not running.
        if e.bags > 0 and e.canPlace and left == 0 then
            -- The extras are only ever one, so no count.
            rows[#rows + 1] = { WithIcon(C_Item.GetItemIconByID(e.id), e.name), not e.extra and (e.bags .. "x") or "", GREY }
        end
    end
    for _, c in ipairs(cooldowns) do
        local left, color = c[2], c[3]
        tip:AddDoubleLine(c[1], left == 0 and L["Ready"] or FP.Cooldowns.Format(left), color[1], color[2], color[3],
            left == 0 and 0.2 or 0.9, left == 0 and 0.9 or 0.2, 0.2)
    end
    Section(tip, L["Camp Features Ready to Place"])
    if #rows == 0 then tip:AddLine(L["Nothing to place"], GREY[1], GREY[2], GREY[3]) else AddRows(tip, rows) end
end

-- Disenchanting Mode isn't a window: the cell and quick button open Enchanting in the mode, or, without Enchanting, the
-- gear you could send your best enchanter (UI:QuickDisenchantClick).
function TIPS.disenchant(tip)
    local r = not UI:OwnEnchanting() and UI:DisenchantRecipients()
    if not r then
        tip:AddLine(L["Lists the gear in your bags that can be disenchanted, what each may give and what that is worth."],
            GREY[1], GREY[2], GREY[3], true)
        return
    end
    tip:AddLine(L["Lists the gear in your bags you could send %s to disenchant, what each may give and what that is worth."]
        :format(FP.Alts:Label(r[1].rec)), GREY[1], GREY[2], GREY[3], true)
    if #r > 1 then tip:AddLine(L["Right-click to choose another enchanter."], 0.5, 0.8, 1, true) end
end

-- Adds the lines for the window under `key` (queue, cooldowns, transfer, shop, skillup, camp, disenchant) to `tip`.
function UI.FillWindowTip(tip, key)
    TIPS[key](tip)
end

-- `secure`: the cell casts (UI:Button's secure argument).
local function MakeCell(f, key, title, onClick, secure)
    local c = UI:Button(f, "", 100, CELL_H, onClick, secure)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(ICON, ICON)
    c.icon:SetPoint("TOPLEFT", 12, -7)
    c.icon:SetTexture(UI.WINDOW_ICONS[key]) -- uncropped, keeping the icon's own edge, like the profession tabs
    c.title = UI:Text(c, 1)
    c.title:SetPoint("LEFT", c.icon, "RIGHT", 5, 0)
    c.title:SetText(title)
    c.title:SetTextColor(1, 0.82, 0)
    c.line = UI:Text(c, 0)
    c.line:SetPoint("TOPLEFT", c.icon, "BOTTOMLEFT", 0, -3)
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
UI.MakeFooterCell = MakeCell -- for Core/Debug.lua's test cells

function UI:CreateFooter(f)
    local footer = {}
    footer.queue = MakeCell(f, "queue", L["Crafting Queue"], function() FP.Queue:Toggle() end)
    footer.cooldowns = MakeCell(f, "cooldowns", L["Cooldowns"], function() FP.CooldownPanel:Toggle() end)
    footer.transfer = MakeCell(f, "transfer", L["Transfer Planner"], function() FP.Transfer:Toggle() end)
    footer.shop = MakeCell(f, "shop", L["Shopping List"], function() FP.Shop:Toggle() end)
    if FP.SkillUpPanel:Available() then
        footer.skillup = MakeCell(f, "skillup", L["Skill Up Route"], function() FP.SkillUpPanel:Toggle() end)
    end
    footer.camp = MakeCell(f, "camp", L["Camp"], function() FP.CampPanel:Toggle() end)
    footer.disenchant = MakeCell(f, "disenchant", L["Disenchanting Mode"],
        function(s, btn) UI:QuickDisenchantClick(s, btn) end, "up")
    f.footer = footer
    self:SyncDisenchantCell()
    self:LayoutFooter()
    self:RefreshFooterSelection()
end

-- The window each footer cell opens, by cell key. The panels load after this file, so it is built on first use.
local windows
function UI.FooterWindows()
    windows = windows or { cooldowns = FP.CooldownPanel, transfer = FP.Transfer, shop = FP.Shop, queue = FP.Queue,
        skillup = FP.SkillUpPanel:Available() and FP.SkillUpPanel or nil, camp = FP.CampPanel }
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
    UI.SetSelected(footer.disenchant, self.deMode and self.page == "recipes")
end

-- The Disenchanting Mode cell shows for an enchanter (it casts Enchanting, unless Enchanting is already open) and for a
-- character with an enchanter to send gear to. Its cast is set out of combat only. True when it was shown or hidden.
function UI:SyncDisenchantCell()
    local footer = self.frame.footer
    local c = footer.disenchant
    local enchanting = self:OwnEnchanting()
    footer.deRecipient = not enchanting and self:DisenchantRecipients()[1] or nil
    if enchanting then self:SetProfessionOpener(c, enchanting) else c:SetAttribute("macrotext1", "") end
    local show = (enchanting or footer.deRecipient) and true or false
    if c:IsShown() == show then return false end
    c:SetShown(show)
    return true
end

-- The window grows or shrinks by the rows the footer gained or lost, and the panels above end where the footer starts,
-- so they keep their size.
local function FitPanels(f)
    local extra = UI:FooterExtra()
    UI:SetWindowBounds()
    f:SetHeight(f:GetHeight() + extra - (f.fpFooterExtra or 0))
    f.fpFooterExtra = extra
    local bottom = 8 + UI:FooterReserve()
    f.left:SetPoint("BOTTOMLEFT", 8, bottom)
    f.right:SetPoint("BOTTOMRIGHT", -8, bottom)
    f.overview:SetPoint("BOTTOMRIGHT", -8, bottom)
    UI:SetNumRows(f:GetHeight())
    UI:UpdateList()
    UI:LayoutOverview()
end

FP:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if UI.footerLayoutPending then UI:LayoutFooter() end
end)

-- Sized from the window, as its own size can lag behind while it is being resized. The Skill Up Route cell is left
-- out while its option is off, the Disenchanting Mode cell while it has nothing to do. With two rows the top one takes
-- the extra cell. The window and the Disenchanting Mode cell are protected, so in combat this waits for it to end.
function UI:LayoutFooter()
    local f = self.frame
    local footer = f and f.footer
    if not footer then return end
    if UI.CombatBlocked(f) then
        self.footerLayoutPending = true
        return
    end
    self.footerLayoutPending = nil
    -- Planning first (the queue decides what to buy and what to mail), then the activities; the quick buttons match.
    local cells = { footer.queue, footer.shop, footer.transfer, footer.cooldowns, footer.camp }
    if footer.skillup then
        footer.skillup:SetShown(FP.db.footerSkillUp)
        if FP.db.footerSkillUp then table.insert(cells, 5, footer.skillup) end -- after Cooldowns
    end
    if footer.disenchant:IsShown() then cells[#cells + 1] = footer.disenchant end
    for _, c in ipairs(footer.extra or {}) do cells[#cells + 1] = c end
    local n = #cells
    local rows = n >= TWO_ROWS and 2 or 1
    local top = math.ceil(n / rows) -- cells in the top row
    for i, c in ipairs(cells) do
        local row, col, count = 1, i, top -- row 1 is the top one
        if rows == 2 and i > top then row, col, count = 2, i - top, n - top end
        local w = (f:GetWidth() - 16 - GAP * (count - 1)) / count
        c:SetWidth(w)
        c:ClearAllPoints()
        c:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8 + (col - 1) * (w + GAP), 8 + (rows - row) * self.FOOTER_ROW)
    end
    if rows ~= self.footerRows then
        self.footerRows = rows
        FitPanels(f)
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

    -- Camp: the two shared cooldowns, camp features then campfires.
    local Camp = FP.Camp
    local objects, fires = Camp:Remaining(Camp.OBJECTS), Camp:Remaining(Camp.CAMPFIRES)
    -- Green when ready, red while running, as in the Camp window and on the quick button.
    footer.camp.line:SetText(objects > 0 and ("|cffe63333" .. L["Camp Features in %s"]:format(FP.Cooldowns.Format(objects)) .. "|r")
        or ("|cff33e633" .. L["Camp Features Ready"] .. "|r"))
    footer.camp.sub:SetText(fires > 0 and ("|cffe63333" .. L["Campfires in %s"]:format(FP.Cooldowns.Format(fires)) .. "|r")
        or ("|cff33e633" .. L["Campfires Ready"] .. "|r"))
    -- No event fires as a cooldown counts down, so redraw now and then while one runs.
    if (objects > 0 or fires > 0) and not campTick then
        campTick = true
        C_Timer.After(30, function()
            campTick = false
            FP:Changed("camp")
        end)
    end

    -- Disenchanting Mode: the gear you could disenchant, or without Enchanting the unbound gear you could mail.
    if not self.CombatBlocked(f) and self:SyncDisenchantCell() then self:LayoutFooter() end
    if footer.disenchant:IsShown() then
        local to = footer.deRecipient
        local bags, bank = 0, 0
        for _, it in ipairs(FP.Disenchant:Scan()) do
            if not (to and it.bound) then
                if it.inBank then bank = bank + 1 else bags = bags + 1 end
            end
        end
        if to then
            local name = FP.Alts:Label(to.rec)
            footer.disenchant.line:SetText(bags == 0 and L["Nothing to send %s"]:format(name)
                or L["%d to send %s"]:format(bags, name))
        else
            footer.disenchant.line:SetText(bags == 0 and L["Nothing to disenchant"] or L["%d to disenchant"]:format(bags))
        end
        footer.disenchant.sub:SetText(bank > 0 and L["%d more in the bank"]:format(bank) or "")
    end
end
