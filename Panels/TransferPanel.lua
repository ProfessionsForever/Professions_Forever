local _, FP = ...
local L = FP.L
local Transfer = FP.Transfer -- created in TransferRows.lua
local BuildRows, RowTooltip = Transfer.BuildRows, Transfer.RowTooltip

local ROWS, ROW_H = 13, 22
local ACTION_BUTTON_H = 24

function Transfer:Open() FP.UI:ShowSidePanel(self) end
Transfer.Toggle = FP.UI.ToggleSidePanel

-- Several changes can land together (bag events, queue edits), so redraw once shortly after.
function Transfer:QueueUpdate()
    if self.pending or not (self.frame and self.frame:IsShown()) then return end
    self.pending = true
    C_Timer.After(0.1, function()
        self.pending = false
        self:Update()
    end)
end

function Transfer:Update()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local UI, Alts = FP.UI, FP.Alts
    -- Another character's plan: who sends it what. Its bank and shopping are that character's to see to.
    local view = FP.Queue:ViewKey()
    f.pick:Sync()
    local plan = FP.Queue:TransferNeeds(view)
    local mode = FP.Planner:Mode()
    local list = BuildRows(plan, view)
    local t = plan.totals
    f.withdraw:SetShown(not view)

    if mode == "never" then
        f.banner:SetText(L["Alt inventory is turned off in the options."])
    elseif mode == "show" then
        f.banner:SetText(L["Show only: not counted in shopping"])
    else
        f.banner:SetText("")
    end

    local shown = FP.UI.PanelRows(f) -- fewer than ROWS while the panel is docked shorter
    FauxScrollFrame_Update(f.scroll, #list, shown, ROW_H)
    f.scroll.fpSetRange(math.max(0, #list - shown) * ROW_H)
    local offset = FauxScrollFrame_GetOffset(f.scroll)
    local queued = #FP.Queue:Data(view) > 0
    f.empty:SetShown(#list == 0)
    if #list == 0 then
        f.empty:SetText(not queued and L["Nothing queued"] or (mode == "never" and L["Alt inventory is off"]
            or (Alts:HasSources() and L["No transfers needed"] or L["No alt inventory known"])))
    end

    for i, row in ipairs(f.rows) do
        local e = i <= shown and list[offset + i] or nil
        row.entry = e
        if not e then
            row:Hide()
        else
            local kind = e.kind
            local isItem = kind == "item" or kind == "missing" or kind == "send" or kind == "bank" or kind == "mail"
            local hasCheck = kind == "item"
            local hasCount = hasCheck or kind == "send"
            row.bg:SetShown(not isItem)
            row.icon:SetShown(isItem)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", hasCheck and 30 or 8, 0)
            row.check:SetShown(hasCheck)
            row.take:SetShown(hasCheck)
            row.qty:SetText("")
            row.owns:SetText("")
            row.hasLabel:SetShown(hasCount)
            row.owns:SetWidth(hasCount and 50 or 72)
            row.owns:ClearAllPoints()
            row.owns:SetPoint("RIGHT", hasCheck and row.takeLabel or row.qty, "LEFT", hasCheck and -8 or -6, 0)
            row.name:ClearAllPoints()
            row.mail:SetShown(kind == "sendto" or (kind == "char" and e.c.mailTo ~= nil))
            row.charKey, row.itemID, row.linkID, row.takeDefault, row.manual = nil, nil, nil, nil, nil
            if isItem then
                local id = kind == "send" and e.item.itemID or kind == "item" and e.o.it.itemID or e.it.itemID
                row.linkID = id
                if hasCheck then
                    local it, opt = e.o.it, e.o.opt
                    row.charKey, row.itemID, row.manual = e.c.key, id, opt.manual
                    -- Ticking on takes what is still missing, or everything short when other characters already cover it.
                    row.takeDefault = math.min(opt.owns, it.stillMissing > 0 and it.stillMissing or it.localShort)
                    row.check:SetChecked(opt.transfer > 0)
                    if not row.amount:HasFocus() then row.amount:SetText(opt.transfer) end
                    if opt.manual then row.amount:SetTextColor(1, 0.82, 0) else row.amount:SetTextColor(1, 1, 1) end
                end
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                row.name:SetPoint("RIGHT", row.owns, "LEFT", -4, 0)
                row.icon:SetTexture(C_Item.GetItemIconByID(id))
                row.name:SetText(FP.ItemName(id))
                if kind == "send" then
                    local bags, bank = FP.Inv:Owned(id)
                    row.name:SetTextColor(0.92, 0.92, 0.92)
                    row.qty:SetText(L["send %d"]:format(e.item.qty))
                    row.qty:SetTextColor(1, 1, 1)
                    row.owns:SetText(bags + bank)
                elseif kind == "item" then
                    local opt = e.o.opt
                    if opt.transfer > 0 then row.name:SetTextColor(0.92, 0.92, 0.92) else row.name:SetTextColor(0.55, 0.55, 0.55) end
                    row.owns:SetText(opt.owns)
                elseif kind == "bank" then
                    local c = UI.STATUS_COLORS.bank
                    row.name:SetTextColor(0.92, 0.92, 0.92)
                    row.qty:SetText(L["take %d"]:format(e.it.qty))
                    row.qty:SetTextColor(c[1], c[2], c[3])
                    row.owns:SetText(L["%d in bank"]:format(e.it.bank))
                elseif kind == "mail" then
                    local c = UI.MAIL_COLOR
                    row.name:SetTextColor(0.92, 0.92, 0.92)
                    row.qty:SetText(L["take %d"]:format(e.it.qty))
                    row.qty:SetTextColor(c[1], c[2], c[3])
                    row.owns:SetText(L["%d in mail"]:format(e.it.mail))
                else
                    local c = UI.STATUS_COLORS.missing
                    row.name:SetTextColor(c[1], c[2], c[3])
                    row.qty:SetText(L["short %d"]:format(e.it.stillMissing))
                    row.qty:SetTextColor(c[1], c[2], c[3])
                    row.owns:SetText(L["of %d needed"]:format(e.it.need))
                end
            elseif kind == "sendto" then
                row.mail:SetActive(MailFrame:IsShown())
                row.name:SetPoint("LEFT", 8, 0)
                row.name:SetPoint("RIGHT", row.mail, "LEFT", -6, 0)
                row.name:SetText(L["Send to %s"]:format(Alts:Label(e.p)))
                row.name:SetTextColor(Alts:ClassColor(e.p.class))
            elseif kind == "char" then
                local c = e.c
                row.name:SetPoint("LEFT", 8, 0)
                if c.mailTo then
                    row.mail:SetActive(MailFrame:IsShown())
                    row.name:SetPoint("RIGHT", row.mail, "LEFT", -6, 0)
                else
                    row.name:SetPoint("RIGHT", -8, 0)
                end
                local name = c.me and L["%s (you)"]:format(Alts:Label(c)) or Alts:Label(c)
                row.name:SetText(name .. (c.usesBank and ("  |cff33ccee" .. L["bank"] .. "|r") or "")
                    .. (c.usesMail and ("  " .. UI.Hex(UI.MAIL_COLOR) .. L["mail"] .. "|r") or ""))
                row.name:SetTextColor(Alts:ClassColor(c.class))
            else
                row.name:SetPoint("LEFT", 8, 0)
                row.name:SetPoint("RIGHT", -8, 0)
                row.name:SetText(e.text)
                row.name:SetTextColor(1, 0.82, 0)
            end
            row:Show()
        end
    end

    local bankNeeds = view and {} or Transfer.BankNeeds(plan)
    local parts = {}
    if #bankNeeds > 0 then parts[#parts + 1] = L["%d to withdraw from your bank"]:format(#bankNeeds) end
    local mailNeeds = #Transfer.MailNeeds(plan)
    if mailNeeds > 0 then
        parts[#parts + 1] = view and L["%d waiting in their mailbox"]:format(mailNeeds)
            or L["%d to collect from your mailbox"]:format(mailNeeds)
    end
    if #list > 0 and t.units > 0 then parts[#parts + 1] = L["%d characters - %d item types"]:format(t.characters, t.itemTypes) end
    if t.missingTypes > 0 then parts[#parts + 1] = L["%d materials still unavailable"]:format(t.missingTypes) end
    f.summary:SetText(table.concat(parts, "  -  "))
    f.withdraw:SetActive(FP.Inv.bankOpen and #bankNeeds > 0)
    -- Only for this character's own plan: another character's mailbox isn't this one's to collect.
    f.collect:SetActive(not view and MailFrame:IsShown() and mailNeeds > 0)
end

function Transfer:Create()
    local UI = FP.UI
    local f = UI:CreateSidePanel({ name = "ProfessionsForeverTransferFrame", key = "transfer", title = L["Transfer Planner"],
        width = 460, height = 460, onShow = function()
            FP.Queue:ResetViewUnless(FP.Queue.frame)
            Transfer:Update()
        end })
    self.frame = f
    FP.Queue:AddViewPicker(f)

    f.banner = UI:Text(f, -1)
    f.banner:SetPoint("TOPLEFT", 14, -36)
    f.banner:SetPoint("RIGHT", -14, 0)
    f.banner:SetJustifyH("LEFT")
    f.banner:SetWordWrap(false)
    f.banner:SetTextColor(unpack(UI.ALT_COLOR))

    UI:AddPanelList(f, { name = "ProfessionsForeverTransferScroll", top = 54, bottom = 100, rows = ROWS, rowH = ROW_H,
        update = function() Transfer:Update() end, rowBg = true, tooltip = RowTooltip, rightClick = true,
        onClick = function(s, button)
            if button == "RightButton" then
                if s.manual and s.charKey then FP.Alts:SetTake(s.charKey, s.itemID, nil, FP.Queue:ViewKey()) end
            else
                UI.LinkItemToChat(s.linkID)
            end
        end,
        build = function(row)
            -- On a "Send to" row: attaches what to send that character to a mail at the open mailbox.
            -- Also on your own character row in another character's plan, to mail it your share.
            local function MailTo()
                local e = row.entry
                return e and (e.kind == "sendto" and e.p or e.kind == "char" and e.c.mailTo) or nil
            end
            row.mail = UI:Button(row, L["Mail"], 56, ROW_H - 4, function()
                local p = MailTo()
                if p then FP.Outgoing:Attach(p) end
            end)
            row.mail:SetPoint("RIGHT", -4, 0)
            row.mail:Hide()
            UI:Tooltip(row.mail, "ANCHOR_RIGHT", function(tip)
                local p = MailTo()
                if not p then return false end
                tip:AddLine(L["Mail to %s"]:format(FP.Alts:Label(p)), 1, 1, 1)
                tip:AddLine(L["Attaches everything to a new mail and fills in their name. Review it and press Send."], 0.8, 0.8, 0.8, true)
                if not MailFrame:IsShown() then tip:AddLine(L["Open a mailbox first."], 1, 0.6, 0.2, true) end
            end)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ROW_H - 4, ROW_H - 4)
            row.icon:SetPoint("LEFT", 30, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetSize(22, 22)
            row.check:SetPoint("LEFT", 2, 0)
            row.check:SetScript("OnClick", function(s)
                if not (row.charKey and row.itemID) then return end
                FP.Alts:SetTake(row.charKey, row.itemID, s:GetChecked() and row.takeDefault or 0, FP.Queue:ViewKey())
            end)
            UI:Tooltip(row.check, "ANCHOR_RIGHT", function(tip)
                tip:AddLine(L["Take from This Character"], 1, 1, 1)
                tip:AddLine(L["When off, this material is not taken from this character."], 0.8, 0.8, 0.8, true)
            end)
            row.qty = UI:Text(row, 0, "RIGHT")
            row.qty:SetPoint("RIGHT", -6, 0)
            row.qty:SetWidth(64)
            row.take = CreateFrame("Frame", nil, row)
            row.take:SetSize(150, ROW_H)
            row.take:SetPoint("RIGHT", -4, 0)
            row.amount = CreateFrame("EditBox", nil, row.take, "InputBoxTemplate")
            row.amount:SetSize(44, 20)
            row.amount:SetPoint("RIGHT", -23, 0)
            UI:EUIWidget(row.amount, "numbox")
            row.amount:SetAutoFocus(false)
            row.amount:SetNumeric(true)
            row.amount:SetMaxLetters(5)
            row.amount:SetScript("OnTextChanged", function(s, user) if user then s.dirty = true end end)
            row.amount:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
            row.amount:SetScript("OnEscapePressed", function(s)
                s.dirty = false
                s:ClearFocus()
                Transfer:Update()
            end)
            row.amount:SetScript("OnEditFocusLost", function(s)
                if not s.dirty then return end
                s.dirty = false
                if row.charKey and row.itemID then FP.Alts:SetTake(row.charKey, row.itemID, tonumber(s:GetText()) or 0, FP.Queue:ViewKey()) end
            end)
            UI:Stepper(row.amount, 0, math.huge, function(v)
                if row.charKey and row.itemID then FP.Alts:SetTake(row.charKey, row.itemID, v, FP.Queue:ViewKey()) end
            end)
            row.takeLabel = UI:Text(row.take, -1, "RIGHT")
            row.takeLabel:SetPoint("RIGHT", row.amount.minus, "LEFT", -4, 0)
            row.takeLabel:SetText(L["Take"])
            row.takeLabel:SetTextColor(0.6, 0.6, 0.6)
            row.owns = UI:Text(row, -1, "RIGHT")
            row.owns:SetPoint("RIGHT", row.qty, "LEFT", -6, 0)
            row.owns:SetWidth(64)
            row.owns:SetTextColor(0.6, 0.6, 0.6)
            row.hasLabel = UI:Text(row, -1, "LEFT")
            row.hasLabel:SetPoint("LEFT", row.owns, "LEFT")
            row.hasLabel:SetText(L["has"])
            row.hasLabel:SetTextColor(0.6, 0.6, 0.6)
            row.name = UI:Text(row, 0)
            row.name:SetWordWrap(false)
        end })

    f.empty = UI:Text(f, 0, "CENTER")
    f.empty:SetPoint("CENTER", 0, 20)

    -- Laid out like the crafting queue: a status line, the window buttons, then this window's actions.
    f.summary = UI:Text(f, -1)
    f.summary:SetPoint("BOTTOMLEFT", 14, 80)
    f.summary:SetPoint("RIGHT", -14, 0)
    f.summary:SetJustifyH("LEFT")
    f.summary:SetWordWrap(false)

    UI:AddWindowButtons(f, 46)

    local refresh = UI:Button(f, L["Refresh"], 90, ACTION_BUTTON_H, function()
        FP.Planner:Invalidate()
        Transfer:Update()
    end)
    refresh:SetPoint("BOTTOMLEFT", 14, 14)
    f.withdraw = UI:Button(f, L["Withdraw from Bank"], 220, ACTION_BUTTON_H, function()
        local moved = FP.Inv:Withdraw(Transfer.BankNeeds(FP.Queue:TransferNeeds()))
        FP:Print(moved > 0 and L["Withdrawing %d material(s) from the bank."]:format(moved)
            or L["Nothing could be moved. Are your bags full?"])
    end)
    -- Withdraw and Collect share the rest of the row after Refresh.
    local half = (f:GetWidth() - 28 - 90 - 12) / 2
    f.withdraw:SetPoint("LEFT", refresh, "RIGHT", 6, 0)
    f.withdraw:SetWidth(half)
    UI:Tooltip(f.withdraw, "ANCHOR_TOP", function(tip)
        if f.withdraw:IsEnabled() then return false end
        tip:AddLine(FP.Inv.bankOpen and L["Nothing to withdraw."] or L["Open your bank to withdraw."], 1, 1, 1, true)
    end)
    f.collect = UI:Button(f, L["Collect from Mailbox"], half, ACTION_BUTTON_H, function()
        FP.Outgoing:Collect(Transfer.MailNeeds(FP.Queue:TransferNeeds()))
    end)
    f.collect:SetPoint("LEFT", f.withdraw, "RIGHT", 6, 0)
    f.collect:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    UI:Tooltip(f.collect, "ANCHOR_TOP", function(tip)
        tip:AddLine(L["Collect from Mailbox"], 1, 1, 1)
        if f.collect:IsEnabled() then
            tip:AddLine(L["Takes what the queue needs from your mailbox: whole stacks, never cash-on-delivery mail."], 0.8, 0.8, 0.8, true)
        else
            tip:AddLine(MailFrame:IsShown() and L["Nothing to collect."] or L["Open a mailbox to collect."], 0.8, 0.8, 0.8, true)
        end
    end)
end
