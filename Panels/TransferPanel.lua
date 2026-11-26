local _, FP = ...
local L = FP.L
local Transfer = FP.Transfer -- created in TransferRows.lua
local BuildRows, RowTooltip = Transfer.BuildRows, Transfer.RowTooltip

local ROWS, ROW_H = 13, 22
-- Where the list ends above the window's bottom edge: the planner's status line and buttons, or the Manual Transfers
-- form (UI.SetPanelListBottom).
local PLAN_BOTTOM, MANUAL_BOTTOM = 100, 158

-- Removes the manual transfer a list row shows (the X button and right-click): the part added to a send row, an item,
-- a piece of gear or money. False when the row has none.
local function RemoveManual(e)
    local Outgoing, me = FP.Outgoing, FP.Alts:GetCharacterKey()
    if not e then return false end
    if e.kind == "mitem" then
        Outgoing:SetAsked(e.recipient, e.sender, e.itemID, 0)
    elseif e.kind == "mgear" then
        Outgoing:SetGearAsked(e.recipient, e.sender, e.gear.guid, nil)
    elseif e.kind == "mgold" then
        Outgoing:SetGold(e.recipient, e.sender, 0)
    elseif e.kind == "send" and e.item.asked > 0 then
        Outgoing:SetAsked(e.p.key, me, e.item.itemID, 0)
    else
        return false
    end
    return true
end

local ACTION_BUTTON_H = 24
Transfer.ACTION_BUTTON_H = ACTION_BUTTON_H -- the Manual Transfers form's buttons match (Panels/TransferForm.lua)
local MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

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
    local me = Alts:GetCharacterKey()
    -- Another character's plan: who sends it what. Its bank and shopping are that character's to see to.
    local view = FP.Queue:ViewKey()
    f.pick:Sync()
    local plan = FP.Queue:TransferNeeds(view)
    local mode = FP.Planner:Mode()
    local manualView = self.view == "manual"
    local list = manualView and Transfer.BuildManualRows(view or me) or BuildRows(plan, view)
    local t = plan.totals
    f.withdraw:SetShown(not view and not manualView)
    f.requestPick:Sync()

    if manualView then
        f.banner:SetText("")
    elseif mode == "never" then
        f.banner:SetText(L["Alt inventory is turned off in the options."])
    elseif mode == "show" then
        f.banner:SetText(L["Show only: not counted in shopping"])
    else
        f.banner:SetText("")
    end

    local shown = FP.UI.PanelRows(f) -- fewer than ROWS while the panel is docked shorter
    FauxScrollFrame_Update(f.scroll, #list, shown, ROW_H)
    f.scroll.barSetRange(math.max(0, #list - shown) * ROW_H)
    local offset = FauxScrollFrame_GetOffset(f.scroll)
    local queued = #FP.Queue:Data(view) > 0
    f.empty:SetShown(#list == 0)
    if #list == 0 then
        f.empty:SetText(manualView and L["No manual transfers yet. Add one below."] or not queued and L["Nothing queued"] or (mode == "never" and L["Alt inventory is off"]
            or (Alts:HasSources() and L["No transfers needed"] or L["No alt inventory known"])))
    end

    for i, row in ipairs(f.rows) do
        local e = i <= shown and list[offset + i] or nil
        row.entry = e
        if not e then
            row:Hide()
        else
            local kind = e.kind
            local isGear, isGold = kind == "mgear", kind == "mgold"
            local isAsk = kind == "mitem" -- a manual item with its amount box
            local isItem = isGear or isGold or isAsk or kind == "item" or kind == "missing" or kind == "send" or kind == "bank"
                or kind == "mail"
            local hasCheck = kind == "item"
            local hasAmount = hasCheck or isAsk
            local hasCount = hasAmount or kind == "send"
            -- Manual transfers get an X in front, where the planner's rows have their tick box.
            local isManual = isGear or isGold or isAsk or (kind == "send" and e.item.asked > 0)
            row.bg:SetShown(not isItem)
            row.icon:SetShown(isItem)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", (hasCheck or isManual) and 30 or 8, 0)
            row.check:SetShown(hasCheck)
            row.remove:SetShown(isManual)
            row.take:SetShown(hasAmount)
            row.takeLabel:SetText(hasCheck and L["Take"] or L["Amount"])
            row.qty:SetText("")
            row.owns:SetText("")
            row.hasLabel:SetShown(hasCount)
            row.owns:SetWidth(hasCount and 50 or 72)
            row.owns:ClearAllPoints()
            row.owns:SetPoint("RIGHT", hasAmount and row.takeLabel or row.qty, "LEFT", hasAmount and -8 or -6, 0)
            row.name:ClearAllPoints()
            row.mail:SetShown(kind == "sendto" or (kind == "char" and e.c.mailTo or (kind == "askfrom" or kind == "mhead") and e.mailTo
                or nil) ~= nil)
            row.charKey, row.itemID, row.linkID, row.link, row.takeDefault, row.manual, row.onAmount =
                nil, nil, nil, nil, nil, nil, nil
            if isGold then
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                row.name:SetPoint("RIGHT", row.owns, "LEFT", -4, 0)
                row.icon:SetTexture(MONEY_ICON)
                row.name:SetText(FP.Prices:Format(e.gold))
                row.name:SetTextColor(0.92, 0.92, 0.92)
                row.qty:SetText(e.sender == me and L["Send"] or "")
                row.qty:SetTextColor(1, 0.82, 0)
            elseif isItem then
                local id = kind == "send" and e.item.itemID or isAsk and e.itemID
                    or kind == "item" and e.o.it.itemID or isGear and e.gear.itemID or e.it.itemID
                row.linkID = id
                if hasCheck then
                    local it, opt = e.o.it, e.o.opt
                    row.charKey, row.itemID, row.manual = e.c.key, id, opt.manual
                    -- Ticking on takes what is still missing, or everything short when other characters already cover it.
                    row.takeDefault = math.min(opt.owns, it.stillMissing > 0 and it.stillMissing or it.localShort)
                    row.onAmount = function(v) Alts:SetTake(e.c.key, id, v, view) end
                    row.check:SetChecked(opt.transfer > 0)
                    if not row.amount:HasFocus() then row.amount:SetText(opt.transfer) end
                    if opt.manual then row.amount:SetTextColor(1, 0.82, 0) else row.amount:SetTextColor(1, 1, 1) end
                elseif isAsk then
                    row.onAmount = function(v) FP.Outgoing:SetAsked(e.recipient, e.sender, id, v) end
                    if not row.amount:HasFocus() then row.amount:SetText(e.qty) end
                    row.amount:SetTextColor(1, 0.82, 0)
                end
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                row.name:SetPoint("RIGHT", row.owns, "LEFT", -4, 0)
                row.icon:SetTexture(C_Item.GetItemIconByID(id))
                row.name:SetText(FP.ItemName(id))
                if isGear then
                    -- The exact piece: its link carries its quality color and random enchantment.
                    row.link = e.gear.link
                    row.name:SetText(e.gear.link)
                    row.qty:SetText(e.sender == me and L["Send %d"]:format(1) or "1")
                    row.qty:SetTextColor(1, 1, 1)
                elseif kind == "send" then
                    row.name:SetTextColor(0.92, 0.92, 0.92)
                    row.qty:SetText(L["Send %d"]:format(e.item.qty))
                    -- Gold when some of it was asked for by hand (the tooltip splits it).
                    if e.item.asked > 0 then row.qty:SetTextColor(1, 0.82, 0) else row.qty:SetTextColor(1, 1, 1) end
                    row.owns:SetText(FP.Planner:HeldInAll(nil, id))
                elseif isAsk then
                    row.name:SetTextColor(0.92, 0.92, 0.92)
                    row.owns:SetText(FP.Planner:HeldInAll(e.sender, id))
                elseif kind == "item" then
                    local opt = e.o.opt
                    if opt.transfer > 0 then row.name:SetTextColor(0.92, 0.92, 0.92) else row.name:SetTextColor(0.55, 0.55, 0.55) end
                    row.owns:SetText(opt.owns)
                elseif kind == "bank" then
                    local c = UI.STATUS_COLORS.bank
                    row.name:SetTextColor(0.92, 0.92, 0.92)
                    row.qty:SetText(L["Take %d"]:format(e.it.qty))
                    row.qty:SetTextColor(c[1], c[2], c[3])
                    row.owns:SetText(L["%d in bank"]:format(e.it.bank))
                elseif kind == "mail" then
                    local c = UI.MAIL_COLOR
                    row.name:SetTextColor(0.92, 0.92, 0.92)
                    if e.it.either then row.name:SetText(FP.ItemName(id) .. "  |cff999999" .. L["(or)"] .. "|r") end
                    row.qty:SetText(L["Take %d"]:format(e.it.qty))
                    row.qty:SetTextColor(c[1], c[2], c[3])
                    row.owns:SetText(L["%d in mail"]:format(e.it.mail))
                else
                    local c = UI.STATUS_COLORS.missing
                    row.name:SetTextColor(c[1], c[2], c[3])
                    row.qty:SetText(L["Short %d"]:format(e.it.stillMissing))
                    row.qty:SetTextColor(c[1], c[2], c[3])
                    row.owns:SetText(L["Of %d Needed"]:format(e.it.need))
                end
            elseif kind == "sendto" then
                row.mail:SetActive(MailFrame:IsShown())
                row.name:SetPoint("LEFT", 8, 0)
                row.name:SetPoint("RIGHT", row.mail, "LEFT", -6, 0)
                row.name:SetText(L["Send to %s"]:format(Alts:Label(e.p)))
                row.name:SetTextColor(Alts:ClassColor(e.p.class))
            elseif kind == "char" or kind == "askfrom" or kind == "mhead" then
                local c = kind == "askfrom" and e.r or e.c
                local mailTo = kind == "char" and c.mailTo or e.mailTo
                local me = kind == "char" and c.me or e.me
                row.name:SetPoint("LEFT", 8, 0)
                if mailTo then
                    row.mail:SetActive(MailFrame:IsShown())
                    row.name:SetPoint("RIGHT", row.mail, "LEFT", -6, 0)
                else
                    row.name:SetPoint("RIGHT", -8, 0)
                end
                local name = me and L["%s (you)"]:format(Alts:Label(c)) or Alts:Label(c)
                if kind == "mhead" and not e.from then name = L["Send to %s"]:format(name) end
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

    local bankNeeds = view and {} or FP.Planner.BankNeeds(plan)
    local parts = {}
    if #bankNeeds > 0 then parts[#parts + 1] = L["%d to withdraw from your bank"]:format(#bankNeeds) end
    local mailNeeds = #FP.Planner.MailNeeds(plan, view)
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

-- Switches the window between the planner ("plan") and the Manual Transfers view ("manual").
function Transfer:SetView(v)
    local f = self.frame
    self.view = v
    local manual = v == "manual"
    f.titleText:SetText(manual and L["Manual Transfers"] or L["Transfer Planner"])
    f.form:SetShown(manual)
    for _, w in ipairs({ f.summary, f.refresh, f.collect }) do w:SetShown(not manual) end
    FP.UI.SetPanelListBottom(f, manual and MANUAL_BOTTOM or PLAN_BOTTOM)
    self:Update()
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
    -- Switches to the Manual Transfers view and back.
    f.manualBtn = UI:Button(f, "", 22, 20, function()
        Transfer:SetView(Transfer.view == "manual" and "plan" or "manual")
    end)
    f.manualBtn:SetPoint("RIGHT", f.pick, "LEFT", -6, 0)
    local letter = f.manualBtn:CreateTexture(nil, "ARTWORK")
    letter:SetPoint("TOPLEFT", 3, -2)
    letter:SetPoint("BOTTOMRIGHT", -3, 2)
    letter:SetTexture("Interface\\Icons\\INV_Letter_15")
    UI.TrimIcon(letter)
    UI:Tooltip(f.manualBtn, function(tip)
        if Transfer.view == "manual" then
            tip:AddLine(L["Back to the Transfer Planner"], 1, 1, 1)
            return
        end
        tip:AddLine(L["Manual Transfers"], 1, 1, 1)
        tip:AddLine(L["Optional. The planner already works out what to mail for your queued crafts. Use this to send or ask for anything else, items or gold."], 0.8, 0.8, 0.8, true)
    end, "ANCHOR_BOTTOM")

    f.banner = UI:Text(f, -1)
    f.banner:SetPoint("TOPLEFT", 14, -36)
    f.banner:SetPoint("RIGHT", -14, 0)
    f.banner:SetJustifyH("LEFT")
    f.banner:SetWordWrap(false)
    f.banner:SetTextColor(unpack(UI.ALT_COLOR))

    UI:AddPanelList(f, { name = "ProfessionsForeverTransferScroll", top = 54, bottom = PLAN_BOTTOM, rows = ROWS, rowH = ROW_H,
        update = function() Transfer:Update() end, rowBg = true, tooltip = RowTooltip, rightClick = true,
        onClick = function(s, button)
            local e = s.entry
            if button == "RightButton" then
                -- Removes a manual transfer, or lets the planner decide an amount chosen by hand again.
                if RemoveManual(e) then
                    return
                elseif s.manual and s.charKey then
                    FP.Alts:SetTake(s.charKey, s.itemID, nil, FP.Queue:ViewKey())
                end
            elseif f.dropItem() then
                return -- an item held on the cursor was dropped on the list
            elseif s.link then
                UI.LinkToChat(s.link)
            elseif not UI.LinkItemToChat(s.linkID) and e then
                -- A request made by hand goes back into the request row to change its amount; any other send row's
                -- item and recipient go there to add to it.
                local me = FP.Alts:GetCharacterKey()
                if e.kind == "send" then
                    if e.item.asked > 0 then
                        f.loadItem(e.item.itemID, { mode = "send", sender = me, recipient = e.p.key, itemID = e.item.itemID,
                            qty = e.item.asked })
                    else
                        Transfer.pick = e.p.key
                        f.requestPick:Sync()
                        f.loadItem(e.item.itemID)
                    end
                elseif e.kind == "mitem" or e.kind == "mgold" then
                    -- Sent by the plan's character, it is that character's Send; otherwise its Ask.
                    local load = { mode = e.sender == (FP.Queue:ViewKey() or me) and "send" or "ask", sender = e.sender,
                        recipient = e.recipient, itemID = e.itemID, qty = e.qty, gold = e.gold }
                    if e.gold then f.loadGold(load) else f.loadItem(e.itemID, load) end
                end
            end
        end,
        build = function(row)
            -- On a "Send to" row: attaches what to send that character to a mail at the open mailbox.
            -- Also on your own character row in another character's plan, to mail it your share, and on your own row
            -- among what that character asked for.
            local function MailTo()
                local e = row.entry
                return e and (e.kind == "sendto" and e.p or e.kind == "char" and e.c.mailTo
                    or (e.kind == "askfrom" or e.kind == "mhead") and e.mailTo) or nil
            end
            row.mail = UI:Button(row, L["Mail"], 56, ROW_H - 4, function()
                local p = MailTo()
                if p then FP.Outgoing:Attach(p) end
            end)
            row.mail:SetPoint("RIGHT", -4, 0)
            row.mail:Hide()
            UI:Tooltip(row.mail, function(tip)
                local p = MailTo()
                if not p then return false end
                tip:AddLine(L["Mail to %s"]:format(FP.Alts:Label(p)), 1, 1, 1)
                tip:AddLine(L["Attaches everything to a new mail and fills in their name. Review it and press Send."], 0.8, 0.8, 0.8, true)
                if not MailFrame:IsShown() then tip:AddLine(L["Open a mailbox first."], 1, 0.6, 0.2, true) end
            end)
            row.remove = UI:Button(row, "X", 18, 18, function() RemoveManual(row.entry) end)
            row.remove:SetPoint("LEFT", 4, 0)
            row.remove:Hide()
            UI:Tooltip(row.remove, function(tip)
                tip:AddLine(L["Remove Manual Transfer"], 1, 1, 1)
            end)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ROW_H - 4, ROW_H - 4)
            row.icon:SetPoint("LEFT", 30, 0)
            UI.TrimIcon(row.icon)
            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetSize(22, 22)
            row.check:SetPoint("LEFT", 2, 0)
            row.check:SetScript("OnClick", function(s)
                if not (row.charKey and row.itemID) then return end
                FP.Alts:SetTake(row.charKey, row.itemID, s:GetChecked() and row.takeDefault or 0, FP.Queue:ViewKey())
            end)
            UI:Tooltip(row.check, function(tip)
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
                if row.onAmount then row.onAmount(tonumber(s:GetText()) or 0) end
            end)
            UI:Stepper(row.amount, 0, math.huge, function(v)
                if row.onAmount then row.onAmount(v) end
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
            row.hasLabel:SetText(L["Has"])
            row.hasLabel:SetTextColor(0.6, 0.6, 0.6)
            row.name = UI:Text(row, 0)
            row.name:SetWordWrap(false)
        end })

    f.empty = UI:Text(f, 0, "CENTER")
    f.empty:SetPoint("CENTER", 0, 20)

    -- Laid out like the crafting queue: a status line, the window buttons, then this window's actions. The Manual
    -- Transfers view puts its form in their place (Panels/TransferForm.lua).
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
    f.refresh = refresh
    f.withdraw = UI:Button(f, L["Withdraw from Bank"], 220, ACTION_BUTTON_H, function()
        local moved = FP.Inv:Withdraw(FP.Planner.BankNeeds(FP.Queue:TransferNeeds()))
        FP:Print(moved > 0 and L["Withdrawing %d material(s) from the bank."]:format(moved)
            or L["Nothing could be moved. Are your bags full?"])
    end)
    -- Withdraw and Collect share the rest of the row after Refresh.
    local half = (f:GetWidth() - 28 - 90 - 12) / 2
    f.withdraw:SetPoint("LEFT", refresh, "RIGHT", 6, 0)
    f.withdraw:SetWidth(half)
    UI:Tooltip(f.withdraw, function(tip)
        if f.withdraw:IsEnabled() then return false end
        tip:AddLine(FP.Inv.bankOpen and L["Nothing to withdraw."] or L["Open your bank to withdraw."], 1, 1, 1, true)
    end, "ANCHOR_TOP")
    f.collect = UI:Button(f, L["Collect from Mailbox"], half, ACTION_BUTTON_H, function()
        FP.Outgoing:Collect(FP.Planner.MailNeeds(FP.Queue:TransferNeeds()))
    end)
    f.collect:SetPoint("LEFT", f.withdraw, "RIGHT", 6, 0)
    f.collect:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    UI:Tooltip(f.collect, function(tip)
        tip:AddLine(L["Collect from Mailbox"], 1, 1, 1)
        if f.collect:IsEnabled() then
            tip:AddLine(L["Takes what your queue and your sends need from your mailbox: whole stacks, never cash-on-delivery mail."], 0.8, 0.8, 0.8, true)
        else
            tip:AddLine(MailFrame:IsShown() and L["Nothing to collect."] or L["Open a mailbox to collect."], 0.8, 0.8, 0.8, true)
        end
    end, "ANCHOR_TOP")

    Transfer.BuildManualForm(f)
    self:SetView(self.view or "plan")
end
