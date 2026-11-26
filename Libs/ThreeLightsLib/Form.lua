--[[
ThreeLightsLib: form windows (UI:FormWindow) and the form builder that keeps labels and controls aligned (UI:Form).
]]
local _, ns = ...
local L = ns.LibHost.L
local UI = ns.UI


-- Windows opened from the main window that close with it (UI:CloseDialogs): every form window, the confirmation and
-- prompt, and any other window passed to UI:RegisterDialog.
local dialogs = {}

function UI:RegisterDialog(f)
    dialogs[#dialogs + 1] = f
    return f
end

-- Hides every registered dialog and any open drop-down menu. Call when the main window closes.
function UI:CloseDialogs()
    for _, f in ipairs(dialogs) do f:Hide() end
    UI:CloseMenu()
end

-- A movable window for a form (child tier): title bar with a close button, closes with Escape. name is its global
-- frame name (needed for Escape).
function UI:FormWindow(name, title, w, h)
    local win = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    win:SetSize(w, h)
    win:SetPoint("CENTER", 0, 60)
    UI:Layer(win, "child")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    UI:Skin(win, "window", true)
    UI:Shadow(win)
    UI:RegisterDialog(win)
    tinsert(UISpecialFrames, name)
    win.title = UI:Text(win, "title")
    win.title:SetPoint("TOPLEFT", 12, -10)
    win.title:SetText(title)
    local close = UI:Button(win, "X", 22, 20, function() win:Hide() end)
    close:SetPoint("TOPRIGHT", -6, -6)
    return win
end

-- Lays out a form: a label column and a control column. Every control starts on the same left edge, single-line
-- controls are 22 high, and each label is centred on its control's first line. form.y is the top of the next row.
-- Use with UI:FormWindow, or any frame (the event editor).
local FORM_H, FORM_GAP = 22, 8

function UI:Form(parent, labelW, top)
    local form = { parent = parent, x = 16 + (labelW or 110), y = top or -46 }

    function form:Label(text, at)
        local t = UI:Text(parent, "normal")
        t:SetPoint("LEFT", parent, "TOPLEFT", 16, (at or self.y) - FORM_H / 2)
        t:SetText(text)
        return t
    end

    -- Starts a row: the label, and the row's top for placing controls by hand.
    function form:Row(label, h)
        local at = self.y
        if label then self:Label(label, at) end
        self.y = self.y - (h or FORM_H) - FORM_GAP
        return at
    end

    function form:Place(ctrl, label, h)
        ctrl:SetPoint("TOPLEFT", parent, "TOPLEFT", self.x, self:Row(label, h))
        return ctrl
    end

    function form:Edit(label, w, opts) return self:Place(UI:Edit(parent, w, FORM_H, opts), label) end

    function form:Money(label) return self:Place(UI:MoneyInput(parent, FORM_H), label) end

    function form:Dropdown(label, w, getLabel, getItems)
        return self:Place(UI:Dropdown(parent, w, FORM_H, getLabel, getItems), label)
    end

    -- A multi-line box w wide and h high (its frame included), on the same edge as the other controls.
    function form:Multiline(label, w, h)
        local at = self:Row(label, h)
        local eb = UI:Multiline(parent, w - 28, h - 8)  -- its frame reaches 4 left and up, 24 right, 4 down
        eb.scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", self.x + 4, at - 4)
        return eb
    end

    function form:Check(label, text)
        local cb = UI:Check(parent, text)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", self.x - 2, self:Row(label))
        return cb
    end

    -- Gray help text in the control column, under the previous control; lines: how many lines to leave room for.
    function form:Note(lines, w)
        local t = UI:Text(parent, "small")
        t:SetPoint("TOPLEFT", parent, "TOPLEFT", self.x, self.y + FORM_GAP - 4)
        t:SetWidth(w or 300)
        t:SetWordWrap(true)
        t:SetTextColor(unpack(UI.colors.dim))
        self.y = self.y - (lines or 1) * 14
        return t
    end

    -- OK and Cancel at the bottom, and the window sized to the rows.
    function form:Buttons(okLabel, onOk, onCancel)
        local ok = UI:Button(parent, okLabel, 120, 24, onOk)
        ok:SetPoint("BOTTOMRIGHT", parent, "BOTTOM", -6, 14)
        local cancel = UI:Button(parent, L["Cancel"], 120, 24, onCancel or function() parent:Hide() end)
        cancel:SetPoint("BOTTOMLEFT", parent, "BOTTOM", 6, 14)
        parent:SetHeight(-self.y + 8 + 24 + 14)
        return ok, cancel
    end

    return form
end
