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
    elseif e.kind == "sendgear" then
        Outgoing:SetGearAsked(e.p.key, me, e.gear.guid, nil)
    elseif e.kind == "ask" then
        Outgoing:SetAsked(e.target, e.r.key, e.item.itemID, 0)
    elseif e.kind == "askgear" then
        Outgoing:SetGearAsked(e.target, e.r.key, e.gear.guid, nil)
    elseif e.kind == "sendgold" then
        Outgoing:SetGold(e.p.key, me, 0)
    elseif e.kind == "askgold" then
        Outgoing:SetGold(e.target, e.r.key, 0)
    else
        return false
    end
    return true
end

local ACTION_BUTTON_H = 24
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
    -- Another character's plan: who sends it what. Its bank and shopping are that character's to see to.
    local view = FP.Queue:ViewKey()
    f.pick:Sync()
    local plan = FP.Queue:TransferNeeds(view)
    local mode = FP.Planner:Mode()
    local manualView = self.view == "manual"
    local list = manualView and Transfer.BuildManualRows(view or Alts:GetCharacterKey()) or BuildRows(plan, view)
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
    f.scroll.fpSetRange(math.max(0, #list - shown) * ROW_H)
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
            local isGear = kind == "sendgear" or kind == "askgear" or kind == "mgear"
            local isGold = kind == "sendgold" or kind == "askgold" or kind == "mgold"
            local isAsk = kind == "ask" or kind == "mitem" -- a manual item with its amount box
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
                row.qty:SetText(kind == "sendgold" and L["Send"] or "")
                if kind == "mgold" and e.sender == FP.Alts:GetCharacterKey() then row.qty:SetText(L["Send"]) end
                row.qty:SetTextColor(1, 0.82, 0)
            elseif isItem then
                local id = (kind == "send" or kind == "ask") and e.item.itemID or kind == "mitem" and e.itemID
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
                    local sender, recipient, n
                    if kind == "ask" then sender, recipient, n = e.r.key, e.target, e.item.qty
                    else sender, recipient, n = e.sender, e.recipient, e.qty end
                    row.onAmount = function(v) FP.Outgoing:SetAsked(recipient, sender, id, v) end
                    if not row.amount:HasFocus() then row.amount:SetText(n) end
                    row.amount:SetTextColor(1, 0.82, 0)
                end
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                row.name:SetPoint("RIGHT", row.owns, "LEFT", -4, 0)
                row.icon:SetTexture(C_Item.GetItemIconByID(id))
                row.name:SetText(FP.ItemName(id))
                if isGear then
                    -- The exact piece: its link carries its quality colour and random enchantment.
                    row.link = e.gear.link
                    row.name:SetText(e.gear.link)
                    row.qty:SetText(kind == "sendgear" and L["Send %d"]:format(1) or "1")
                    row.qty:SetTextColor(1, 1, 1)
                elseif kind == "send" then
                    row.name:SetTextColor(0.92, 0.92, 0.92)
                    row.qty:SetText(L["Send %d"]:format(e.item.qty))
                    -- Gold when some of it was asked for by hand (the tooltip splits it).
                    if e.item.asked > 0 then row.qty:SetTextColor(1, 0.82, 0) else row.qty:SetTextColor(1, 1, 1) end
                    row.owns:SetText(FP.Planner:HeldInAll(nil, id))
                elseif isAsk then
                    row.name:SetTextColor(0.92, 0.92, 0.92)
                    row.owns:SetText(FP.Planner:HeldInAll(kind == "ask" and e.r.key or e.sender, id))
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

    local bankNeeds = view and {} or Transfer.BankNeeds(plan)
    local parts = {}
    if #bankNeeds > 0 then parts[#parts + 1] = L["%d to withdraw from your bank"]:format(#bankNeeds) end
    local mailNeeds = #Transfer.MailNeeds(plan, view)
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

-- The Manual Transfers view's form: items or money moved by hand, apart from any queue, between the plan's character
-- (you, or the one picked in the title bar) and another character of its faction (Outgoing:SameFaction). Send: the
-- plan's character sends the picked one. Ask: the picked one sends the plan's character. Either way it is saved as the
-- sender's to-do (Outgoing:SetAsked, SetGold), so it shows in the sender's Transfer Planner, login reminder and mailbox
-- prompt, and its Mail button attaches it, until it is mailed. An item and money can go in one click. Picking a
-- suggestion only fills the box; the amount comes next. An item dropped on the window fills it in too (switching to
-- this view), and clicking a manual transfer in either view loads it here to change it.
local MODES = {
    send = { button = "Send", tip = "Send",
        explain = "Adds the item and gold to what %s sends %s, apart from any queue. At a mailbox the Transfer Planner's Mail button attaches them." },
    ask = { button = "Ask", tip = "Ask",
        explain = "Asks %s to send %s the item and gold, apart from any queue. It shows in their Transfer Planner, login reminder and mailbox prompt until it is mailed." },
}
local COINS = { { 10000, 60, 6, "Interface\\MoneyFrame\\UI-GoldIcon" }, { 100, 34, 2, "Interface\\MoneyFrame\\UI-SilverIcon" },
    { 1, 34, 2, "Interface\\MoneyFrame\\UI-CopperIcon" } } -- copper each, box width, max digits, icon
local LABEL_X, FIELD_X = 14, 90 -- the form's label column and where its fields start
local ICON_SLOT = 20 -- the item's icon in front of the item box, as tall as the box
local LINE_CHAR, LINE_ITEM, LINE_GOLD = 130, 104, 78 -- each line's bottom, above the window buttons

function Transfer.BuildManualForm(f)
    local UI, Outgoing = FP.UI, FP.Outgoing
    local form = CreateFrame("Frame", nil, f)
    form:SetAllPoints()
    form:Hide()
    f.form = form
    local function Target() return FP.Queue:ViewKey() or FP.Alts:GetCharacterKey() end
    -- The character picked in the form, while it still goes with the plan's character.
    local function Picked()
        for _, c in ipairs(Outgoing:SameFaction(Target())) do
            if c.key == Transfer.pick then return c.key end
        end
    end
    -- sender, recipient
    local function Pair(mode, picked)
        if mode == "ask" then return picked, Target() end
        return Target(), picked
    end
    local function Label(key) return FP.Alts:Label(FP.db.characters[key]) end
    local function LineLabel(text, y)
        local l = UI:Text(form, 0)
        l:SetPoint("BOTTOMLEFT", LABEL_X, y + 4)
        l:SetText(text)
        l:SetTextColor(0.7, 0.7, 0.7)
    end

    LineLabel(L["Character"], LINE_CHAR)
    local pick = UI:Dropdown(form, 220, 20, function()
        local key = Picked()
        return key and FP.Queue.CharacterName(key) or L["Pick a Character"]
    end, function()
        local items, picked = {}, Picked()
        for _, c in ipairs(Outgoing:SameFaction(Target())) do
            items[#items + 1] = { text = FP.Queue.CharacterName(c.key), checked = c.key == picked, onSelect = function()
                Transfer.pick = c.key
                f.requestPick:Sync()
            end }
        end
        return items
    end)
    f.requestPick = pick
    pick:SetPoint("BOTTOMLEFT", FIELD_X, LINE_CHAR)
    UI:Tooltip(pick, "ANCHOR_TOP", function(tip)
        tip:AddLine(L["Character"], 1, 1, 1)
        tip:AddLine(L["Pick who to send to, or who to ask. Only characters of the same faction are listed."], 0.8, 0.8, 0.8, true)
    end)

    LineLabel(L["Item"], LINE_ITEM)
    local item = CreateFrame("EditBox", "ProfessionsForeverTransferItem", form, "InputBoxTemplate")
    item:SetHeight(20)
    item:SetAutoFocus(false)
    UI:EUIWidget(item, "editbox")
    local qty = CreateFrame("EditBox", "ProfessionsForeverTransferQty", form, "InputBoxTemplate")
    qty:SetSize(40, 20)
    UI:EUIWidget(qty, "numbox")
    qty:SetAutoFocus(false)
    qty:SetNumeric(true)
    qty:SetMaxLetters(4)
    qty:SetText("1")
    local ph = UI:AddPlaceholder(item, L["Type a name, or drop an item here"])
    UI:Tooltip(item, "ANCHOR_TOP", function(tip)
        tip:AddLine(L["Item"], 1, 1, 1)
        tip:AddLine(L["Type an item's name, ID or link, or drop a stack from your bags anywhere on this window: the amount becomes the stack's count. Soulbound items can't be mailed."], 0.8, 0.8, 0.8, true)
    end)
    -- An accent outline on the slot and the item box while an item is held on the cursor, to show it can be dropped.
    local glow = CreateFrame("Frame", nil, form, "BackdropTemplate")
    glow:SetPoint("BOTTOMRIGHT", item, 2, -2)
    glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    glow:Hide()
    form:SetScript("OnUpdate", function()
        local holding = GetCursorInfo() == "item"
        if holding ~= glow:IsShown() then
            if holding then
                local a = UI:GetAccent()
                glow:SetBackdropBorderColor(a[1], a[2], a[3], 1)
            end
            glow:SetShown(holding)
        end
    end)
    qty:SetPoint("BOTTOMRIGHT", -14 - 18 - 3, LINE_ITEM) -- room for the stepper's plus
    UI:Stepper(qty, 1, 9999)
    -- InputBoxTemplate draws its left cap about 5px outside the box, so the boxes start that much further in to line up
    -- with the character picker and the icon; EllesmereUI's square box has no cap.
    local function Cap() return UI.EUI() and 0 or 5 end
    item.fpEUILayout = function() item:SetPoint("BOTTOMLEFT", FIELD_X + ICON_SLOT + 4 + Cap(), LINE_ITEM) end
    item.fpEUILayout()
    item:SetPoint("RIGHT", qty.minus, "LEFT", -10, 0)

    -- Gold, silver and copper boxes, each with its coin after it, as in the game's mail window.
    LineLabel(L["Gold"], LINE_GOLD)
    local money, prev = {}, nil
    for _, c in ipairs(COINS) do
        local box = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
        box:SetSize(c[2], 20)
        UI:EUIWidget(box, "numbox")
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetMaxLetters(c[3])
        box:SetJustifyH("RIGHT")
        if prev then
            box:SetPoint("LEFT", prev, "RIGHT", 10, 0)
        else
            box.fpEUILayout = function() box:SetPoint("BOTTOMLEFT", FIELD_X + Cap(), LINE_GOLD) end
            box.fpEUILayout()
        end
        local icon = form:CreateTexture(nil, "ARTWORK")
        icon:SetSize(13, 13)
        icon:SetTexture(c[4])
        icon:SetPoint("LEFT", box, "RIGHT", 3, 0)
        box.copper = c[1]
        money[#money + 1] = box
        prev = icon
    end
    local function MoneyCopper()
        local total = 0
        for _, box in ipairs(money) do total = total + (tonumber(box:GetText()) or 0) * box.copper end
        return total
    end
    local function SetMoney(copper)
        for _, box in ipairs(money) do
            local n = math.floor(copper / box.copper)
            copper = copper - n * box.copper
            box:SetText(n > 0 and n or "")
        end
    end

    local buttons, lastMode = {}, "send"
    -- Set while a manual transfer from the list is loaded: { mode, sender, recipient, itemID or gold, name }. That
    -- direction's button then replaces its amount instead of adding to it.
    local editing
    local function SyncButtons()
        for mode, b in pairs(buttons) do
            b.text:SetText(editing and editing.mode == mode and L["Set"] or L[MODES[mode].button])
        end
    end
    item:SetScript("OnTextChanged", function(s)
        ph:SetShown(s:GetText() == "")
        -- A loaded item stays loaded while its name is unchanged.
        if editing and editing.itemID and s:GetText() ~= editing.name then
            editing = nil
            SyncButtons()
        end
    end)

    -- The amount comes next: focused, with its text selected to type over.
    local function ToAmount()
        qty:SetFocus()
        qty:HighlightText()
    end
    local suggest = UI:AttachItemAutocomplete(item, function(name)
        item:SetText(name)
        ToAmount()
    end)
    UI:AddClearButton(item, L["Clear"])
    -- The item's icon in front of the box: drop an item on it, or click it with one held (Drop, below).
    local slot = suggest:IconSlot(ICON_SLOT, L["Type a name, or drop an item here"])
    slot:SetPoint("BOTTOMLEFT", FIELD_X, LINE_ITEM)
    glow:SetPoint("TOPLEFT", slot, -2, 2)

    local function Clear()
        editing = nil
        SyncButtons()
        item:SetText("")
        qty:SetText("1")
        SetMoney(0)
        for _, frame in ipairs({ item, qty, unpack(money) }) do frame:ClearFocus() end
    end

    -- Adds what the form holds: the item with its quantity, the money, or both.
    local function Add(mode)
        lastMode = mode
        local picked = Picked()
        if not picked then return FP:Print(L["Pick a character first."]) end
        local sender, recipient = Pair(mode, picked)
        local e = editing
        local same = e and e.mode == mode and e.sender == sender and e.recipient == recipient
        local typed = suggest:Selected() or strtrim(item:GetText())
        local id = typed ~= "" and suggest:Resolve(typed)
        local copper = MoneyCopper()
        if not id and copper == 0 and not (same and e.gold) then return end
        if id then
            local bindType = select(14, C_Item.GetItemInfo(id))
            if bindType == 1 or bindType == 4 then -- binds when picked up, quest item
                return FP:Print(L["%s is soulbound and can't be mailed."]:format(FP.ItemName(id)))
            end
        end
        if id then
            local n = tonumber(qty:GetText()) or 1
            if same and e.itemID == id then
                Outgoing:SetAsked(recipient, sender, id, n)
            else
                Outgoing:SetAsked(recipient, sender, id, Outgoing:Asked(recipient, sender, id) + n)
            end
        end
        if same and e.gold then
            Outgoing:SetGold(recipient, sender, copper)
        elseif copper > 0 then
            Outgoing:SetGold(recipient, sender, Outgoing:Gold(recipient, sender) + copper)
        end
        Clear()
    end
    -- Enter in the item box goes on to the amount; Enter in the amount or a money box repeats the last button used.
    -- Tab steps item, amount, gold, silver, copper.
    local order = { item, qty, unpack(money) }
    for i, box in ipairs(order) do
        box:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        box:SetScript("OnTabPressed", function() order[i % #order + 1]:SetFocus() end)
        if box ~= item then box:SetScript("OnEnterPressed", function() Add(lastMode) end) end
    end
    item:SetScript("OnEnterPressed", function()
        if strtrim(item:GetText()) ~= "" then ToAmount() end
    end)

    -- Send and Ask share the bottom row, where the planner has Refresh, Withdraw and Collect.
    local half = (f:GetWidth() - 28 - 6) / 2
    for i, mode in ipairs({ "send", "ask" }) do
        local text = MODES[mode]
        local b = UI:Button(form, L[text.button], half, ACTION_BUTTON_H, function() Add(mode) end)
        b:SetPoint("BOTTOMLEFT", 14 + (i - 1) * (half + 6), 14)
        buttons[mode] = b
        UI:Tooltip(b, "ANCHOR_TOP", function(tip)
            local picked = Picked()
            tip:AddLine(L[text.tip], 1, 1, 1)
            if picked then
                local sender, recipient = Pair(mode, picked)
                tip:AddLine(L[text.explain]:format(Label(sender), Label(recipient)), 0.8, 0.8, 0.8, true)
            else
                tip:AddLine(L["Pick a character first."], 0.8, 0.8, 0.8, true)
            end
            tip:AddLine(L["Enter in the amount box repeats the last of Send and Ask you clicked."], 0.6, 0.6, 0.6, true)
        end)
    end

    -- Puts an item in the form, in this view: by ID, then on to the amount. `load` (optional) is a manual transfer from
    -- the list, `count` (optional) the amount to start with.
    function f.loadItem(itemID, load, count)
        local name = C_Item.GetItemNameByID(itemID) or C_Item.GetItemInfo(itemID)
        if not name then return end
        Transfer:SetView("manual")
        editing = load
        if load then
            load.name = name
            Transfer.pick = load.mode == "ask" and load.sender or load.recipient
            pick:Sync()
            SetMoney(0)
        end
        item:SetText(name)
        qty:SetText(load and load.qty or count or 1)
        SyncButtons()
        ToAmount()
    end

    -- Puts a money transfer from the list in the form to change it: `load` is { mode, sender, recipient, gold }.
    function f.loadGold(load)
        Transfer:SetView("manual")
        editing = load
        Transfer.pick = load.mode == "ask" and load.sender or load.recipient
        pick:Sync()
        item:SetText("")
        SetMoney(load.gold)
        SyncButtons()
        money[1]:SetFocus()
        money[1]:HighlightText()
    end

    -- An item dropped on the window from the bags fills in the form, with the stack's count; it goes back to the bags.
    -- A soulbound stack is refused (a piece of gear bound once worn too, so it is checked on the stack held).
    local function Drop()
        local kind, itemID = GetCursorInfo()
        if kind ~= "item" then return false end
        local stack = FP.Inv:CursorStack(itemID)
        ClearCursor()
        if stack and stack.isBound then
            FP:Print(L["%s is soulbound and can't be mailed."]:format(FP.ItemName(itemID)))
        else
            f.loadItem(itemID, nil, stack and stack.stackCount)
        end
        return true
    end
    f.dropItem = Drop
    slot:SetScript("OnReceiveDrag", Drop)
    slot:SetScript("OnClick", Drop)
    for _, frame in ipairs({ f, item, f.scroll }) do
        frame:HookScript("OnReceiveDrag", Drop)
        frame:HookScript("OnMouseUp", Drop)
    end
    for _, row in ipairs(f.rows) do row:HookScript("OnReceiveDrag", Drop) end -- a click is the list's onClick
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
    letter:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI:Tooltip(f.manualBtn, "ANCHOR_BOTTOM", function(tip)
        if Transfer.view == "manual" then
            tip:AddLine(L["Back to the Transfer Planner"], 1, 1, 1)
            return
        end
        tip:AddLine(L["Manual Transfers"], 1, 1, 1)
        tip:AddLine(L["Optional. The planner already works out what to mail for your queued crafts. Use this to send or ask for anything else, items or gold."], 0.8, 0.8, 0.8, true)
    end)

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
                elseif e.kind == "ask" then
                    f.loadItem(e.item.itemID, { mode = "ask", sender = e.r.key, recipient = e.target, itemID = e.item.itemID,
                        qty = e.item.qty })
                elseif e.kind == "mitem" then
                    f.loadItem(e.itemID, { mode = e.sender == (FP.Queue:ViewKey() or me) and "send" or "ask",
                        sender = e.sender, recipient = e.recipient, itemID = e.itemID, qty = e.qty })
                elseif e.kind == "mgold" then
                    f.loadGold({ mode = e.sender == (FP.Queue:ViewKey() or me) and "send" or "ask", sender = e.sender,
                        recipient = e.recipient, gold = e.gold })
                elseif e.kind == "sendgold" then
                    f.loadGold({ mode = "send", sender = me, recipient = e.p.key, gold = e.gold })
                elseif e.kind == "askgold" then
                    f.loadGold({ mode = "ask", sender = e.r.key, recipient = e.target, gold = e.gold })
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
            UI:Tooltip(row.mail, "ANCHOR_RIGHT", function(tip)
                local p = MailTo()
                if not p then return false end
                tip:AddLine(L["Mail to %s"]:format(FP.Alts:Label(p)), 1, 1, 1)
                tip:AddLine(L["Attaches everything to a new mail and fills in their name. Review it and press Send."], 0.8, 0.8, 0.8, true)
                if not MailFrame:IsShown() then tip:AddLine(L["Open a mailbox first."], 1, 0.6, 0.2, true) end
            end)
            row.remove = UI:Button(row, "X", 18, 18, function() RemoveManual(row.entry) end)
            row.remove:SetPoint("LEFT", 4, 0)
            row.remove:Hide()
            UI:Tooltip(row.remove, "ANCHOR_RIGHT", function(tip)
                tip:AddLine(L["Remove Manual Transfer"], 1, 1, 1)
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
    -- Transfers view puts its form in their place (BuildManualForm).
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
            tip:AddLine(L["Takes what your queue and your sends need from your mailbox: whole stacks, never cash-on-delivery mail."], 0.8, 0.8, 0.8, true)
        else
            tip:AddLine(MailFrame:IsShown() and L["Nothing to collect."] or L["Open a mailbox to collect."], 0.8, 0.8, 0.8, true)
        end
    end)

    Transfer.BuildManualForm(f)
    self:SetView(self.view or "plan")
end
