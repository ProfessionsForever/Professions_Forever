local _, FP = ...
local L = FP.L
local Queue = FP.Queue -- created in Core/Queue.lua

-- The crafting queue window.
local ROWS, ROW_H = 11, 28
Queue.ROWS, Queue.ROW_H = ROWS, ROW_H
local STOP_MACRO = "/stopcasting"
local MISSING, BANK, MAIL = FP.UI.STATUS_COLORS.missing, FP.UI.STATUS_COLORS.bank, FP.UI.MAIL_COLOR
local WARN, BANK_MARK = RGBToColorCode(unpack(MISSING)) .. "! |r", RGBToColorCode(unpack(BANK)) .. "! |r"
local MAIL_MARK = RGBToColorCode(unpack(MAIL)) .. "! |r"

---------------------------------------------------------------------------
-- Whose queue is shown
---------------------------------------------------------------------------
-- The queue window and the Transfer Planner show the same character's queue and plan: another character's key, or nil
-- for the current one. Opening either window while the other is closed goes back to the current character.
function Queue:ViewKey() return self.viewKey end

FP.Alts:OnRemove(function(key)
    if Queue.viewKey == key then Queue.viewKey = nil end
end)

function Queue:SetView(key)
    self.viewKey = key ~= FP.Alts:GetCharacterKey() and key or nil
    self:Update()
    FP.Transfer:Update()
end

-- For a window's OnShow; `other` is the other window's frame.
function Queue:ResetViewUnless(other)
    if not (other and other:IsShown()) then self.viewKey = nil end
end

-- A character's name in its class colour, marked when it is the current one.
local function CharacterName(key)
    local rec = FP.db.characters[key]
    local r, g, b = FP.Alts:ClassColor(rec.class)
    local name = FP.Alts:Label(rec)
    if key == FP.Alts:GetCharacterKey() then name = L["%s (you)"]:format(name) end
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, name)
end
Queue.CharacterName = CharacterName

-- The picker in a window's title bar: the current character first, then the others with saved professions or a queue.
function Queue:AddViewPicker(f)
    local UI = FP.UI
    f.pick = UI:Dropdown(f, 150, 20, function() return CharacterName(self:ViewKey() or FP.Alts:GetCharacterKey()) end, function()
        local me, keys, items = FP.Alts:GetCharacterKey(), {}, {}
        for key, rec in pairs(FP.db.characters) do
            if key ~= me and ((rec.professions and next(rec.professions)) or (rec.queue and #rec.queue > 0)) then
                keys[#keys + 1] = key
            end
        end
        table.sort(keys, function(a, b) return FP.Alts:Label(FP.db.characters[a]) < FP.Alts:Label(FP.db.characters[b]) end)
        table.insert(keys, 1, me)
        local view = self:ViewKey() or me
        for _, key in ipairs(keys) do
            items[#items + 1] = { text = CharacterName(key), checked = key == view, onSelect = function() self:SetView(key) end }
        end
        return items
    end)
    f.pick:SetPoint("RIGHT", f.pinBtn, "LEFT", -6, 0)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
function Queue:Open()
    local f = self.frame
    -- The craft buttons are secure: their attributes can't be set, nor the window shown, during combat.
    if (not f and InCombatLockdown()) or (f and not f:IsShown() and FP.UI.CombatBlocked(f)) then
        return FP:Print(L["Cannot do that in combat."])
    end
    FP.UI:ShowSidePanel(self)
end

-- After queueing: when alts hold materials the queue needs (and they count toward planning), opens the transfer planner.
function Queue:OpenTransferIfNeeded()
    if not FP.Planner:Applies() then return end
    local chars = self:TransferNeeds().totals.characters
    if chars == 0 then return end
    FP:Print(L["Materials for the queue are on %d other character(s). Opening the transfer planner."]:format(chars))
    FP.Transfer:Open()
end

-- Redraws the window only; a change to the queue redraws the other windows through FP:Changed("queue").
function Queue:Update()
    local f = self.frame
    if not f or not f:IsShown() then return end
    -- Another character's queue can be edited but only crafted on that character, and its shortages are worked out
    -- from its own bags, which the Transfer Planner shows.
    local view = self:ViewKey()
    local data = self:Data(view)
    f.pick:Sync()
    local busy = self.run and not self.run.ready
    f.craft.text:SetText(busy and L["Stop Queue"] or L["Craft Queue"])
    if not InCombatLockdown() then
        local canSkip = self.run and self.run.entry and true or false
        f.craft:SetAttribute("macrotext", busy and STOP_MACRO or "")
        f.stopCraft:SetAttribute("macrotext", busy and canSkip and STOP_MACRO or "")
        f.craft:SetShown(not view)
        f.stopCraft:SetShown(canSkip and not view)
    end
    local short, shortCount = view and {} or self:EntryShortages(), 0
    for _ in pairs(short) do shortCount = shortCount + 1 end
    local inBank, inMail, bankCount, mailCount = {}, {}, 0, 0
    if not view then inBank, inMail = self:EntryFetch() end
    for _ in pairs(inBank) do bankCount = bankCount + 1 end
    for _ in pairs(inMail) do mailCount = mailCount + 1 end
    local unlearnedCount = 0
    for _, q in ipairs(data) do
        if not self:IsLearned(q, view) then unlearnedCount = unlearnedCount + 1 end
    end
    if view then
        f.status:SetText(L["Crafted on %s. The Transfer Planner shows who sends what."]:format(CharacterName(view)))
    else
        f.status:SetText(self.status or (unlearnedCount > 0 and L["%d queued recipe(s) not learned yet."]:format(unlearnedCount))
            or (shortCount > 0 and L["%d queued recipe(s) lack materials."]:format(shortCount))
            or (bankCount > 0 and L["%d queued recipe(s) need materials from the bank."]:format(bankCount))
            or (mailCount > 0 and L["%d queued recipe(s) need materials from your mailbox."]:format(mailCount)) or "")
    end
    local shown = FP.UI.PanelRows(f) -- fewer than ROWS while the panel is docked shorter
    FauxScrollFrame_Update(f.scroll, #data, shown, ROW_H)
    f.scroll.fpSetRange(math.max(0, #data - shown) * ROW_H)
    local offset = FauxScrollFrame_GetOffset(f.scroll)
    f.empty:SetShown(#data == 0)
    for i, row in ipairs(f.rows) do
        local q = i <= shown and data[offset + i] or nil
        if q then
            row.index = offset + i
            row:SetAlpha(self.dragFrom == row.index and 0.4 or 1)
            row.icon:SetTexture(q.icon)
            row.missing, row.fromBank, row.fromMail = short[q], inBank[q], inMail[q]
            -- Only the open profession's requirements can be read, so other professions' rows show this once opened.
            local noTools = not view and self:IsOpen(q) and FP.Tools:Missing(q.id)
            row.noTools = noTools and #noTools > 0 and noTools or nil
            -- Unlearned recipes are grey with a star, as in the recipe list.
            row.unlearned = not self:IsLearned(q, view)
            local name = row.unlearned and (q.name .. " *") or q.name
            row.name:SetText((row.missing or row.noTools) and WARN .. name or (row.fromBank and BANK_MARK .. name)
                or (row.fromMail and MAIL_MARK .. name) or name)
            if row.unlearned then row.name:SetTextColor(0.5, 0.5, 0.5) else row.name:SetTextColor(1, 1, 1) end
            row.icon:SetDesaturated(row.unlearned)
            if not row.qty:HasFocus() then row.qty:SetText(q.qty) end
            row:Show()
        else
            row.index, row.missing, row.fromBank, row.fromMail, row.noTools, row.unlearned = nil, nil, nil, nil, nil, nil
            row:Hide()
        end
    end
end

function Queue:Create()
    local UI = FP.UI
    local f = UI:CreateSidePanel({ name = "ProfessionsForeverQueueFrame", key = "queue", title = L["Crafting Queue"],
        width = 460, height = 460, onShow = function()
            Queue:ResetViewUnless(FP.Transfer.frame)
            Queue:Update()
        end })
    self.frame = f
    UI.CloseInCombat(f)
    self:AddViewPicker(f)

    UI:AddPanelList(f, { name = "ProfessionsForeverQueueScroll", top = 40, bottom = 100, rows = ROWS, rowH = ROW_H,
        update = function() Queue:Update() end,
        onClick = function(row)
            local q = row.index and Queue:Data(Queue:ViewKey())[row.index]
            if q then UI.LinkToChat(C_TradeSkillUI.GetRecipeLink(q.id)) end
        end,
        tooltip = function(row)
            if not (row.missing or row.fromBank or row.fromMail or row.noTools or row.unlearned) then return false end
            if row.unlearned then
                GameTooltip:AddLine(L["Not Learned"], MISSING[1], MISSING[2], MISSING[3])
                GameTooltip:AddLine(L["The queue skips this recipe until it is learned. Its materials are still planned and put on the shopping list."], 0.8, 0.8, 0.8, true)
            end
            if row.noTools then
                GameTooltip:AddLine(L["Missing requirements:"], 1, 1, 1)
                for _, name in ipairs(row.noTools) do
                    GameTooltip:AddLine(name, MISSING[1], MISSING[2], MISSING[3])
                end
            end
            if row.missing then
                GameTooltip:AddLine(L["Missing materials:"], 1, 1, 1)
                for _, m in ipairs(row.missing) do
                    GameTooltip:AddDoubleLine(FP.ItemName(m.itemID), m.qty, 1, 1, 1, MISSING[1], MISSING[2], MISSING[3])
                end
            end
            if row.fromBank then
                GameTooltip:AddLine(L["Needs from the bank:"], 1, 1, 1)
                for _, m in ipairs(row.fromBank) do
                    GameTooltip:AddDoubleLine(FP.ItemName(m.itemID), m.qty, 1, 1, 1, BANK[1], BANK[2], BANK[3])
                end
            end
            if row.fromMail then
                GameTooltip:AddLine(L["Waiting in your mailbox:"], 1, 1, 1)
                for _, m in ipairs(row.fromMail) do
                    GameTooltip:AddDoubleLine(FP.ItemName(m.itemID), m.qty, 1, 1, 1, MAIL[1], MAIL[2], MAIL[3])
                end
            end
        end,
        build = function(row)
            Queue:AttachDrag(row)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ROW_H - 6, ROW_H - 6)
            row.icon:SetPoint("LEFT", 18, 0)
            local rm = UI:Button(row, "x", 18, 18, function() if row.index then Queue:Remove(row.index, Queue:ViewKey()) end end)
            rm:SetPoint("RIGHT", -2, 0)
            row.qty = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            row.qty:SetSize(36, 20)
            row.qty:SetPoint("RIGHT", rm, "LEFT", -32, 0)
            UI:EUIWidget(row.qty, "numbox")
            row.qty:SetAutoFocus(false)
            row.qty:SetNumeric(true)
            row.qty:SetMaxLetters(3)
            row.qty:SetScript("OnTextChanged", function(s, user)
                local q = user and row.index and Queue:Data(Queue:ViewKey())[row.index]
                if q then
                    q.qty = math.max(1, tonumber(s:GetText()) or 1)
                    FP:Changed("queue")
                end
            end)
            row.qty:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
            row.qty:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
            UI:Stepper(row.qty, 1, 999, function(v)
                local q = row.index and Queue:Data(Queue:ViewKey())[row.index]
                if q then q.qty = v FP:Changed("queue") end
            end)
            row.name = UI:Text(row, 0)
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.name:SetPoint("RIGHT", row.qty.minus, "LEFT", -6, 0)
            row.name:SetWordWrap(false)
        end })

    f.empty = UI:Text(f, 0, "CENTER")
    f.empty:SetPoint("CENTER", 0, 20)
    f.empty:SetText(L["Crafting queue is empty"])

    -- What the queue is short of goes on the shopping list by itself (Core/Shopping.lua).
    UI:AddWindowButtons(f, 46)
    local clear = UI:Button(f, L["Clear Queue"], 110, 24, function() Queue:Clear(Queue:ViewKey()) end)
    clear:SetPoint("BOTTOMLEFT", 14, 14)
    f.craft = UI:Button(f, L["Craft Queue"], 130, 24, function() Queue:ToggleRun() end, true)
    f.craft:SetPoint("LEFT", clear, "RIGHT", 6, 0)
    f.stopCraft = UI:Button(f, L["Stop Craft"], 110, 24, function() Queue:SkipCurrent() end, true)
    -- Before their /stopcasting runs, so the interrupt it causes is known to be ours (Core/QueueRunner.lua).
    for _, b in ipairs({ f.craft, f.stopCraft }) do b:SetScript("PreClick", function() Queue:MarkStopping() end) end
    f.stopCraft:SetPoint("BOTTOMLEFT", f.craft, "BOTTOMRIGHT", 6, 0)
    f.stopCraft:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
    f.stopCraft:Hide()
    f.status = UI:Text(f, -1)
    f.status:SetPoint("BOTTOMLEFT", 14, 80)
    f.status:SetPoint("RIGHT", -14, 0)
    f.status:SetWordWrap(false)

    -- Own frame above the rows, so the list can't cover it; it never takes the mouse.
    local notice = CreateFrame("Frame", nil, f, "BackdropTemplate")
    notice:SetPoint("BOTTOMLEFT", 14, 104)
    notice:SetPoint("BOTTOMRIGHT", -14, 104)
    notice:SetHeight(44)
    notice:SetFrameLevel(f:GetFrameLevel() + 20)
    UI:Skin(notice, "button")
    notice:SetBackdropBorderColor(1, 0.82, 0, 1)
    notice.text = UI:Text(notice, 1, "CENTER")
    notice.text:SetPoint("LEFT", 8, 0)
    notice.text:SetPoint("RIGHT", -8, 0)
    notice.text:SetTextColor(1, 0.82, 0)
    notice.text:SetText(L["Profession window changed. Click the game world to craft."])
    notice.anim = notice:CreateAnimationGroup()
    local fade = notice.anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(3)
    fade:SetDuration(4)
    notice.anim:SetScript("OnFinished", function() notice:Hide() end)
    notice:Hide()
    f.notice = notice
end

function Queue:ShowNotice(text)
    local n = self.frame and self.frame.notice
    if not n then return end
    n.text:SetText(text or L["Profession window changed. Click the game world to craft."])
    n.anim:Stop()
    n:SetAlpha(1)
    n:Show()
    if not text then n.anim:Play() end -- a waiting prompt stays until the click or Stop
end

function Queue:HideNotice()
    local n = self.frame and self.frame.notice
    if not n then return end
    n.anim:Stop()
    n:Hide()
end

Queue.Toggle = FP.UI.ToggleSidePanel
