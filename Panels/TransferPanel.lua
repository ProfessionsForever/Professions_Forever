local _, FP = ...
local L = FP.L
local Transfer = FP.Transfer -- created in TransferRows.lua
local BuildRows, RowTooltip = Transfer.BuildRows, Transfer.RowTooltip

local ROWS, ROW_H = 13, 22
local ACTION_BUTTON_H = 24

function Transfer:Open()
    if not self.frame then self:Create() end
    if not self.frame:IsShown() then
        FP.UI:PlaceSidePanel(self.frame)
        self.frame:Show()
    end
end

function Transfer:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Open() end
end

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
    local plan = FP.Queue:TransferNeeds()
    local mode = FP.Planner:Mode()
    local list = BuildRows(plan)
    local t = plan.totals

    if mode == "never" then
        f.banner:SetText(L["Alt inventory is turned off in the options."])
    elseif mode == "show" then
        f.banner:SetText(L["Show only - not applied to shopping"])
    else
        f.banner:SetText("")
    end

    FauxScrollFrame_Update(f.scroll, #list, ROWS, ROW_H)
    f.rowEdge:SetBar(#list > ROWS)
    if f.scroll.fpEUISetRange then f.scroll:fpEUISetRange(math.max(0, #list - ROWS) * ROW_H) end
    local offset = FauxScrollFrame_GetOffset(f.scroll)
    local queued = #FP.Queue:Data() > 0
    f.empty:SetShown(#list == 0)
    if #list == 0 then
        f.empty:SetText(not queued and L["Nothing queued"] or (mode == "never" and L["Alt inventory is off"]
            or (Alts:HasSources() and L["No transfers needed"] or L["No alt inventory known"])))
    end

    for i, row in ipairs(f.rows) do
        local e = list[offset + i]
        row.entry = e
        if not e then
            row:Hide()
        else
            local kind = e.kind
            local isItem = kind == "item" or kind == "missing" or kind == "send" or kind == "bank"
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
                row.name:SetText(UI.ItemName(id))
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
                else
                    local c = UI.STATUS_COLORS.missing
                    row.name:SetTextColor(c[1], c[2], c[3])
                    row.qty:SetText(L["short %d"]:format(e.it.stillMissing))
                    row.qty:SetTextColor(c[1], c[2], c[3])
                    row.owns:SetText(L["of %d needed"]:format(e.it.need))
                end
            elseif kind == "sendto" then
                row.name:SetPoint("LEFT", 8, 0)
                row.name:SetPoint("RIGHT", -8, 0)
                row.name:SetText(L["Send to %s"]:format(Alts:Label(e.p)))
                row.name:SetTextColor(Alts:ClassColor(e.p.class))
            elseif kind == "char" then
                local c = e.c
                row.name:SetPoint("LEFT", 8, 0)
                row.name:SetPoint("RIGHT", -8, 0)
                row.name:SetText(Alts:Label(c) .. (c.usesBank and ("  |cff33ccee" .. L["bank"] .. "|r") or ""))
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

    local bankNeeds = Transfer.BankNeeds(plan)
    local parts = {}
    if #bankNeeds > 0 then parts[#parts + 1] = L["%d to withdraw from your bank"]:format(#bankNeeds) end
    if #list > 0 and t.units > 0 then parts[#parts + 1] = L["%d alts - %d item types"]:format(t.characters, t.itemTypes) end
    if t.missingTypes > 0 then parts[#parts + 1] = L["%d materials still unavailable"]:format(t.missingTypes) end
    f.summary:SetText(table.concat(parts, "  -  "))
    f.withdraw:SetActive(FP.Inv.bankOpen and #bankNeeds > 0)
    f.add:SetActive(plan.applies and t.missingTypes > 0)
end

function Transfer:Create()
    local UI = FP.UI
    local f = CreateFrame("Frame", "ProfessionsForeverTransferFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:Hide() -- frames start shown, which would skip OnShow and leave unpopulated rows visible
    f:SetSize(400, 488)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    UI:Skin(f, "window")
    tinsert(UISpecialFrames, "ProfessionsForeverTransferFrame")
    f:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_QUEST_LIST_OPEN)
        Transfer:Update()
    end)
    f:SetScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_QUEST_LIST_CLOSE)
    end)
    UI:MakeSidePanelDraggable(f, "transfer")

    local title = UI:Text(f, 2)
    title:SetPoint("LEFT", f, "TOPLEFT", 12, -UI.TITLE_H / 2)
    title:SetText(L["Transfer Planner"])
    title:SetTextColor(1, 0.82, 0)
    local close = UI:Button(f, "X", 22, 20, function() f:Hide() end)
    close:SetPoint("RIGHT", f, "TOPRIGHT", -6, -UI.TITLE_H / 2)
    UI:AddPinButton(f, close)

    f.banner = UI:Text(f, -1)
    f.banner:SetPoint("TOPLEFT", 14, -36)
    f.banner:SetPoint("RIGHT", -14, 0)
    f.banner:SetJustifyH("LEFT")
    f.banner:SetWordWrap(false)
    f.banner:SetTextColor(unpack(UI.ALT_COLOR))

    local scroll = CreateFrame("ScrollFrame", "ProfessionsForeverTransferScroll", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -54)
    scroll:SetPoint("BOTTOMRIGHT", -30, 132)
    scroll:SetScript("OnVerticalScroll", function(s, offset)
        FauxScrollFrame_OnVerticalScroll(s, offset, ROW_H, function() Transfer:Update() end)
    end)
    f.scroll = scroll
    local scrollBar = scroll.ScrollBar or _G["ProfessionsForeverTransferScrollScrollBar"]
    if not UI:AttachEUIThinScrollbar(scroll, scrollBar, f, { top = 54, bottom = 132 }) then
        UI:EUIWidget(scrollBar, "scrollbar")
    end

    f.rowEdge = UI:RowEdge(f, 30, 8)
    f.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -54 - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", f.rowEdge, "TOPRIGHT", 0, -54 - (i - 1) * ROW_H)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.07)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 1, 1, 0.08)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ROW_H - 4, ROW_H - 4)
        row.icon:SetPoint("LEFT", 30, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(22, 22)
        row.check:SetPoint("LEFT", 2, 0)
        row.check:SetScript("OnClick", function(s)
            if not (row.charKey and row.itemID) then return end
            FP.Alts:SetTake(row.charKey, row.itemID, s:GetChecked() and row.takeDefault or 0)
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
            if row.charKey and row.itemID then FP.Alts:SetTake(row.charKey, row.itemID, tonumber(s:GetText()) or 0) end
        end)
        UI:Stepper(row.amount, 0, math.huge, function(v)
            if row.charKey and row.itemID then FP.Alts:SetTake(row.charKey, row.itemID, v) end
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
        row:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            if RowTooltip(s) == false then GameTooltip:Hide() return end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(s, button)
            if button == "RightButton" then
                if s.manual and s.charKey then FP.Alts:SetTake(s.charKey, s.itemID, nil) end
            else
                UI.LinkItemToChat(s.linkID)
            end
        end)
        f.rows[i] = row
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        if scroll.fpEUIScrollTo then
            scroll.fpEUIScrollTo(scroll:GetVerticalScroll() - delta * ROW_H * 3)
        elseif scrollBar then
            scrollBar:SetValue(scrollBar:GetValue() - delta * ROW_H * 3)
        end
    end)

    f.empty = UI:Text(f, 0, "CENTER")
    f.empty:SetPoint("CENTER", 0, 20)

    f.summary = UI:Text(f, -1)
    f.summary:SetPoint("BOTTOMLEFT", 14, 96)
    f.summary:SetPoint("RIGHT", -14, 0)
    f.summary:SetJustifyH("LEFT")
    f.summary:SetWordWrap(false)

    f.withdraw = UI:Button(f, L["Withdraw from Bank"], 220, ACTION_BUTTON_H, function()
        local moved = FP.Inv:Withdraw(Transfer.BankNeeds(FP.Queue:TransferNeeds()))
        FP:Print(moved > 0 and L["Withdrawing %d material(s) from the bank."]:format(moved)
            or L["Nothing could be moved. Are your bags full?"])
    end)
    f.withdraw:SetPoint("BOTTOMLEFT", 14, 68)
    f.withdraw:SetPoint("BOTTOMRIGHT", -14, 68)
    UI:Tooltip(f.withdraw, "ANCHOR_TOP", function(tip)
        if f.withdraw:IsEnabled() then return false end
        tip:AddLine(FP.Inv.bankOpen and L["Nothing to withdraw."] or L["Open your bank to withdraw."], 1, 1, 1, true)
    end)

    f.add = UI:Button(f, L["Add Missing to Shopping List"], 220, ACTION_BUTTON_H, function() FP.Queue:AddMissingToShopping() end)
    f.add:SetPoint("BOTTOMLEFT", 14, 40)
    f.add:SetPoint("BOTTOMRIGHT", -14, 40)
    UI:Tooltip(f.add, "ANCHOR_TOP", function(tip)
        tip:AddLine(L["Adds what no enabled character can supply."], 1, 1, 1, true)
        if not FP.Planner:Applies() then
            tip:AddLine(L["Set alt inventory to Include in planning in the options."], 1, 0.6, 0.2, true)
        end
    end)
    local refresh = UI:Button(f, L["Refresh"], 90, ACTION_BUTTON_H, function()
        FP.Planner:Invalidate()
        Transfer:Update()
    end)
    refresh:SetPoint("BOTTOMLEFT", 14, 10)
    local shop = UI:Button(f, L["Open Shopping List"], 150, ACTION_BUTTON_H, function() FP.Shop:Open() end)
    shop:SetPoint("LEFT", refresh, "RIGHT", 6, 0)
    local options = UI:Button(f, L["Publish"], 120, ACTION_BUTTON_H, function()
        FP.Outgoing:Publish()
        Transfer:Update()
    end)
    options:SetPoint("LEFT", shop, "RIGHT", 6, 0)
    UI:Tooltip(options, "ANCHOR_TOP", L["Saves this plan so each character sees what to send you when you log into it."])
end
