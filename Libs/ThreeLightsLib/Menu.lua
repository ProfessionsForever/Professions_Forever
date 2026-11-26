--[[
ThreeLightsLib: one shared pop-up menu (UI:OpenMenu) and the dropdown button that opens it (UI:Dropdown).
]]
local _, ns = ...
local UI = ns.UI

---------------------------------------------------------------------------
-- Dropdown: a button that opens one shared list of choices.
-- getItems() returns { { text, checked, onSelect, dim, header, icon, indent, link, keepOpen }, ... }; getLabel()
-- returns the button text. icon: a texture shown before the text; indent: steps of 10 pixels; link: an item link for
-- the row's tooltip; keepOpen: picking it leaves the menu open (and redraws it).
---------------------------------------------------------------------------
local MENU_ROW, MENU_ROWS = 22, 14
local menu

-- The narrowest a button's or dropdown's menu is drawn; the addon may raise it.
UI.MENU_MIN_W = 0

function UI:CloseMenu()
    if menu then
        menu:Hide()
        menu.catcher:Hide()
    end
end

local function DrawMenu()
    for i = 1, MENU_ROWS do
        local row, item = menu.rows[i], menu.items[menu.offset + i]
        if item and i <= menu.visible then
            row.item = item
            row.icon:SetShown(item.icon ~= nil)
            row.icon:SetTexture(item.icon)
            row.text:SetPoint("LEFT", (item.icon and 28 or 8) + (item.indent or 0) * 10, 0)
            row.text:SetText(item.text)
            row.text:SetAlpha(item.dim and 0.5 or 1)
            -- A heading: in the accent colour, and not a choice (no highlight, does nothing when clicked).
            if item.header then row.text:SetTextColor(unpack(UI:GetAccent())) else row.text:SetTextColor(1, 1, 1) end
            row:SetEnabled(not item.header)
            row.check:SetShown(item.checked and true or false)
            row:Show()
        else
            row:Hide()
        end
    end
end

-- The menu: a check mark on the current choice, scrolls with the wheel, opens above its button
-- when there is no room below.
local function MakeMenu()
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata(UI.STRATA.popup)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() UI:CloseMenu() end)
    catcher:Hide()
    menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu.catcher = catcher
    menu:SetFrameStrata(UI.STRATA.popup)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:EnableMouseWheel(true)
    UI:Skin(menu, "button", true)
    UI:Shadow(menu, 8)
    menu:Hide()
    menu:SetScript("OnMouseWheel", function(s, delta)
        s.offset = math.max(0, math.min(#s.items - s.visible, s.offset - delta * 3))
        DrawMenu()
    end)
    menu.rows = {}
    for i = 1, MENU_ROWS do
        local row = CreateFrame("Button", nil, menu)
        row:SetHeight(MENU_ROW)
        row:SetPoint("TOPLEFT", 3, -3 - (i - 1) * MENU_ROW)
        row:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * MENU_ROW)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)
        row.text = UI:Text(row, "normal")
        row.text:SetWordWrap(false)
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -20, 0)
        row.check = row:CreateTexture(nil, "ARTWORK")
        row.check:SetSize(14, 14)
        row.check:SetPoint("RIGHT", -4, 0)
        row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(MENU_ROW - 4, MENU_ROW - 4)
        row.icon:SetPoint("LEFT", 4, 0)
        UI.TrimIcon(row.icon)
        -- The item's tooltip for a row with a link; otherwise the full text when it doesn't fit.
        UI:Tooltip(row, function(tip, s)
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
            if item.keepOpen then
                if item.onSelect then item.onSelect() end
                DrawMenu()
            else
                UI:CloseMenu()
                if item.onSelect then item.onSelect() end
            end
            if menu.owner and menu.owner.Refresh then menu.owner:Refresh() end
        end)
        menu.rows[i] = row
    end
end

function UI:OpenMenu(owner, items, width)
    if not menu then MakeMenu() end
    menu.owner, menu.items, menu.offset = owner, items, 0
    menu.visible = math.min(#items, MENU_ROWS)
    -- Scroll so the current choice is visible.
    for i, item in ipairs(items) do
        if item.checked and i > menu.visible then
            menu.offset = math.min(i - 3, #items - menu.visible)
            break
        end
    end
    menu:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
    local height = menu.visible * MENU_ROW + 6
    menu:ClearAllPoints()
    if owner.libList then
        -- A list row's menu opens at the mouse, as wide as it needs, not under the whole list.
        menu:SetSize(width or 180, height)
        local x, y = GetCursorPosition()
        local scale = menu:GetEffectiveScale()
        x, y = x / scale, y / scale
        if y - height < 20 then
            menu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x + 2, y + 2)
        else
            menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + 2, y - 2)
        end
    else
        -- A button's or dropdown's menu opens under it (above when there's no room), at least as wide.
        menu:SetSize(math.max(width or 0, owner:GetWidth(), UI.MENU_MIN_W), height)
        local roomBelow = (owner:GetBottom() or 0) * owner:GetEffectiveScale()
        if roomBelow < menu.visible * MENU_ROW * owner:GetEffectiveScale() + 20 then
            menu:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
        else
            menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
        end
    end
    DrawMenu()
    -- Raised in this order each time, so the menu is in front of a confirmation dialog it opens over and the click
    -- catcher sits between the two.
    menu.catcher:Show()
    menu.catcher:Raise()
    menu:Show()
    menu:Raise()
end

function UI:Dropdown(parent, w, h, getLabel, getItems)
    local b = UI:Button(parent, "", w, h)
    b.text:SetJustifyH("LEFT")
    -- The down arrow.
    b.arrow = b:CreateTexture(nil, "OVERLAY")
    b.arrow:SetSize(12, 12)
    b.arrow:SetPoint("RIGHT", -6, 0)
    b.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    b.text:SetPoint("RIGHT", -20, 0)
    function b:Refresh() b.text:SetText(getLabel()) end
    b.Sync = b.Refresh
    b:SetScript("OnClick", function(s)
        if menu and menu:IsShown() and menu.owner == s then
            UI:CloseMenu()
            return
        end
        local items = getItems()
        if #items > 0 then UI:OpenMenu(s, items) end
    end)
    -- The label is drawn at once and again whenever the dropdown is shown, so it is never stale; call :Refresh() for
    -- a change while it is on screen.
    b:Refresh()
    b:HookScript("OnShow", b.Refresh)
    return b
end
