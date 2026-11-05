local _, FP = ...
local UI = FP.UI
local Skin, EUI = UI.ActiveSkin, UI.EUI

-- Shows the game tooltip while the mouse is over `w`. `fill` is a title string, or a function(tooltip, w) that adds the
-- lines (returning false shows nothing).
function UI:Tooltip(w, anchor, fill)
    w:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, anchor)
        if type(fill) == "string" then GameTooltip:AddLine(fill, 1, 1, 1, true)
        elseif fill(GameTooltip, s) == false then GameTooltip:Hide() return end
        GameTooltip:Show()
    end)
    w:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
-- True when a button's text is wider than the room it has. Text anchored on both sides has that room; centered text has the button less a margin.
function UI.TextCutOff(b)
    local fs = b.text
    if not (fs and fs:IsShown()) then return false end
    local room = fs:GetNumPoints() > 1 and fs:GetWidth() or b:GetWidth() - 8
    return fs:GetStringWidth() > room + 0.5
end

-- Shared by every UI:Button so each button doesn't carry its own closures.
local function ButtonOnEnter(s)
    if s:IsEnabled() then s:SetBackdropBorderColor(unpack(UI:GetAccent())) end
    if UI.TextCutOff(s) then
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:AddLine(s.text:GetText(), 1, 1, 1)
        GameTooltip:Show()
    end
end
local function ButtonBorder(s)
    return s.selected and UI:GetAccent() or Skin().button.border
end
local function ButtonOnLeave(s)
    s:SetBackdropBorderColor(unpack(ButtonBorder(s)))
    if GameTooltip:IsOwned(s) then GameTooltip:Hide() end
end
local function ButtonSetActive(s, on)
    s:SetEnabled(on)
    s.text:SetAlpha(on and 1 or 0.4)
end

-- Marks a button as the current choice (open tab, open panel): an accent border and a faint accent fill that hover doesn't clear.
function UI.SetSelected(b, on)
    b.selected = on and true or nil
    local bg = Skin().button.bg
    if b.selected then
        local a = UI:GetAccent()
        b:SetBackdropColor(bg[1] * 0.75 + a[1] * 0.25, bg[2] * 0.75 + a[2] * 0.25, bg[3] * 0.75 + a[3] * 0.25, bg[4])
    else
        b:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    end
    b:SetBackdropBorderColor(unpack(ButtonBorder(b)))
end

function UI:Button(parent, label, w, h, onClick, secure)
    local b = CreateFrame("Button", nil, parent, secure and "SecureActionButtonTemplate,BackdropTemplate" or "BackdropTemplate")
    b:SetSize(w, h)
    b.text = self:Text(b, 0, "CENTER")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    self:Skin(b, "button")
    b:SetScript("OnEnter", ButtonOnEnter)
    b:SetScript("OnLeave", ButtonOnLeave)
    if secure then
        -- The secure action fires on key-down or key-up depending on this CVar, so register both
        -- and run our own handler only on the phase the secure action used.
        -- "up" buttons fire on release instead, because an action on mouse-down would leave no room to drag.
        b:RegisterForClicks("AnyDown", "AnyUp")
        b:SetAttribute("type", "macro")
        local onUp = secure == "up"
        if onUp then b:SetAttribute("useOnKeyDown", false) end
        b:SetScript("PostClick", function(s, btn, down)
            if onUp and not down or not onUp and (down and true or false) == (GetCVarBool("ActionButtonUseKeyDown") and true or false) then
                onClick(s, btn, down)
            end
        end)
    else
        b:SetScript("OnClick", onClick)
    end
    b.SetActive = ButtonSetActive
    return b
end

-- List rows anchor their right side to this frame. :SetBar(true) keeps the column the scroll bar sits in;
-- :SetBar(false) gives it to the rows, for lists that fit. `inset` is the rows' current distance from the right edge.
function UI:RowEdge(parent, barInset, freeInset)
    local edge = CreateFrame("Frame", nil, parent)
    edge:SetSize(1, 1)
    function edge:SetBar(show)
        local inset = show and barInset or freeInset
        if self.inset == inset then return end
        self.inset = inset
        self:ClearAllPoints()
        self:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -inset, 0)
    end
    edge:SetBar(true)
    return edge
end

-- Windows sit at this frame level. Other addons nest frames under siblings of ours (EllesmereUI's unit frames are at 3
-- to 30), and Raise() only reorders siblings, so a fresh window at level 1 draws under them until the user clicks it.
-- Blizzard's action button text (counts, keybinds) is at 500.
UI.WINDOW_LEVEL = 600

-- Adds - / + buttons either side of a numeric edit box (shift steps by 10); onChange gets the new value.
function UI:Stepper(eb, min, max, onChange)
    local function Step(delta)
        local step = IsShiftKeyDown() and 10 or 1
        local v = math.max(min, math.min(max, (tonumber(eb:GetText()) or min) + delta * step))
        eb:ClearFocus()
        eb:SetText(v)
        if onChange then onChange(v) end
    end
    -- InputBoxTemplate draws its left cap about 5px outside the frame, so the minus needs extra room to match the
    -- plus; EllesmereUI's restyled box has no cap sticking out, so there both gaps are equal.
    eb:SetJustifyH("CENTER")
    eb.minus = self:Button(eb:GetParent(), "-", 18, 20, function() Step(-1) end)
    eb.plus = self:Button(eb:GetParent(), "+", 18, 20, function() Step(1) end)
    eb.plus:SetPoint("LEFT", eb, "RIGHT", 3, 0)
    eb.fpStepper = function()
        eb.minus:ClearAllPoints()
        eb.minus:SetPoint("RIGHT", eb, "LEFT", EUI() and -3 or -8, 0)
    end
    eb.fpStepper()
end

---------------------------------------------------------------------------
-- Dropdown menu: a button that opens one shared, scrollable list of choices.
---------------------------------------------------------------------------
local MENU_ROW_H, MENU_MAX_ROWS = 22, 14
local menu

function UI.CloseMenu()
    if menu then
        menu:Hide()
        menu.catcher:Hide()
    end
end

local function RefreshMenu()
    local items, offset = menu.items, menu.offset
    for i = 1, MENU_MAX_ROWS do
        local row, item = menu.rows[i], items[offset + i]
        if item and i <= menu.visible then
            row.item = item
            row.icon:SetShown(item.icon ~= nil)
            row.icon:SetTexture(item.icon)
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", (item.icon and 28 or 8) + (item.indent or 0) * 10, 0)
            row.text:SetPoint("RIGHT", -20, 0)
            row.text:SetText(item.text)
            if item.dim then row.text:SetTextColor(0.6, 0.6, 0.6) else row.text:SetTextColor(1, 1, 1) end
            row.check:SetShown(item.checked)
            row:Show()
        else
            row:Hide()
        end
    end
end

local function CreateMenu()
    -- A screen-sized catcher sits under the menu so a click anywhere else closes it.
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(9) -- above the options window's controls, which share this strata, but under the menu
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", UI.CloseMenu)
    catcher:Hide()

    menu = CreateFrame("Frame", "ProfessionsForeverMenu", UIParent, "BackdropTemplate")
    menu.catcher = catcher
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(10)
    menu:EnableMouse(true)
    menu:EnableMouseWheel(true)
    menu:Hide()
    UI:Skin(menu, "button")
    menu:SetScript("OnMouseWheel", function(s, delta)
        local maxOffset = math.max(0, #s.items - s.visible)
        s.offset = math.max(0, math.min(maxOffset, s.offset - delta * 3))
        RefreshMenu()
    end)
    menu.rows = {}
    for i = 1, MENU_MAX_ROWS do
        local row = CreateFrame("Button", nil, menu)
        row:SetHeight(MENU_ROW_H)
        row:SetPoint("TOPLEFT", 3, -3 - (i - 1) * MENU_ROW_H)
        row:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * MENU_ROW_H)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 1, 1, 0.1)
        row.text = UI:Text(row, 0)
        row.text:SetWordWrap(false)
        row.check = row:CreateTexture(nil, "ARTWORK")
        row.check:SetSize(14, 14)
        row.check:SetPoint("RIGHT", -4, 0)
        row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(MENU_ROW_H - 4, MENU_ROW_H - 4)
        row.icon:SetPoint("LEFT", 4, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        UI:Tooltip(row, "ANCHOR_RIGHT", function(tip, s)
            if s.item and s.item.link then
                tip:SetHyperlink(s.item.link)
            elseif s.text:GetStringWidth() > s.text:GetWidth() + 0.5 then
                tip:AddLine(s.text:GetText(), 1, 1, 1)
            else
                return false
            end
        end)
        row:SetScript("OnClick", function(s)
            local item = s.item
            if item and item.keepOpen then
                if item.onSelect then item.onSelect() end
                RefreshMenu()
            else
                UI.CloseMenu()
                if item and item.onSelect then item.onSelect() end
            end
        end)
        menu.rows[i] = row
    end
end

-- items: { text, checked, indent, icon, link (item hyperlink for the hover tooltip), dim, onSelect }.
-- The menu hangs below `anchor`, or above it when there is no room below.
function UI:OpenMenu(anchor, items, width)
    if not menu then CreateMenu() end
    menu.items = items
    menu.visible = math.min(#items, MENU_MAX_ROWS)
    menu.offset = 0
    -- Scroll so the current choice is visible.
    for i, item in ipairs(items) do
        if item.checked and i > menu.visible then
            menu.offset = math.min(i - 3, #items - menu.visible)
            break
        end
    end
    menu:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
    menu:SetSize(math.max(width or 0, anchor:GetWidth(), 160), menu.visible * MENU_ROW_H + 6)
    menu:ClearAllPoints()
    local roomBelow = (anchor:GetBottom() or 0) * anchor:GetEffectiveScale()
    if roomBelow < menu.visible * MENU_ROW_H * anchor:GetEffectiveScale() + 20 then
        menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    else
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    end
    RefreshMenu()
    menu.catcher:Show()
    menu:Show()
end

-- A button showing getLabel() with a down arrow; clicking opens getItems(). Call :Sync() to refresh the label.
function UI:Dropdown(parent, w, h, getLabel, getItems)
    local b = self:Button(parent, "", w, h, function(s) UI:OpenMenu(s, getItems()) end)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", 8, 0)
    b.text:SetPoint("RIGHT", -22, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b.arrow = b:CreateTexture(nil, "OVERLAY")
    b.arrow:SetSize(12, 12)
    b.arrow:SetPoint("RIGHT", -6, 0)
    b.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    function b:Sync() self.text:SetText(getLabel()) end
    return b
end
