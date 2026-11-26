local _, FP = ...
local L = FP.L
local Transfer = FP.Transfer -- created in TransferRows.lua
local ACTION_BUTTON_H = Transfer.ACTION_BUTTON_H

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
        return key and FP.Alts:CharacterName(key) or L["Pick a Character"]
    end, function()
        local items, picked = {}, Picked()
        for _, c in ipairs(Outgoing:SameFaction(Target())) do
            items[#items + 1] = { text = FP.Alts:CharacterName(c.key), checked = c.key == picked, onSelect = function()
                Transfer.pick = c.key
                f.requestPick:Sync()
            end }
        end
        return items
    end)
    f.requestPick = pick
    pick:SetPoint("BOTTOMLEFT", FIELD_X, LINE_CHAR)
    UI:Tooltip(pick, function(tip)
        tip:AddLine(L["Character"], 1, 1, 1)
        tip:AddLine(L["Pick who to send to, or who to ask. Only characters of the same faction are listed."], 0.8, 0.8, 0.8, true)
    end, "ANCHOR_TOP")

    LineLabel(L["Item"], LINE_ITEM)
    local item = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    item:SetHeight(20)
    item:SetAutoFocus(false)
    UI:EUIWidget(item, "editbox")
    local qty = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    qty:SetSize(40, 20)
    UI:EUIWidget(qty, "numbox")
    qty:SetAutoFocus(false)
    qty:SetNumeric(true)
    qty:SetMaxLetters(4)
    qty:SetText("1")
    local ph = UI:AddPlaceholder(item, L["Type a name, or drop an item here"])
    UI:Tooltip(item, function(tip)
        tip:AddLine(L["Item"], 1, 1, 1)
        tip:AddLine(L["Type an item's name, ID or link, or drop a stack from your bags anywhere on this window: the amount becomes the stack's count. Soulbound items can't be mailed."], 0.8, 0.8, 0.8, true)
    end, "ANCHOR_TOP")
    -- An accent outline on the slot and the item box while an item is held on the cursor, to show it can be dropped.
    local glow = CreateFrame("Frame", nil, form, "BackdropTemplate")
    glow:SetPoint("BOTTOMRIGHT", item, 2, -2)
    glow:SetBackdrop({ edgeFile = UI.WHITE, edgeSize = 1 })
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
    item.libEUILayout = function() item:SetPoint("BOTTOMLEFT", FIELD_X + ICON_SLOT + 4 + Cap(), LINE_ITEM) end
    item.libEUILayout()
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
            box.libEUILayout = function() box:SetPoint("BOTTOMLEFT", FIELD_X + Cap(), LINE_GOLD) end
            box.libEUILayout()
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
    local suggest = UI:ItemSuggest(item, function(_, name)
        item:SetText(name)
        ToAmount()
    end, { complete = true, up = true })
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
        UI:Tooltip(b, function(tip)
            local picked = Picked()
            tip:AddLine(L[text.tip], 1, 1, 1)
            if picked then
                local sender, recipient = Pair(mode, picked)
                tip:AddLine(L[text.explain]:format(Label(sender), Label(recipient)), 0.8, 0.8, 0.8, true)
            else
                tip:AddLine(L["Pick a character first."], 0.8, 0.8, 0.8, true)
            end
            tip:AddLine(L["Enter in the amount box repeats the last of Send and Ask you clicked."], 0.6, 0.6, 0.6, true)
        end, "ANCHOR_TOP")
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
