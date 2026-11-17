local _, FP = ...
local L = FP.L
local UI = FP.UI
local O = {}
FP.Options = O

-- Each control adds a function that re-reads its value, so the window follows changes made elsewhere.
local refreshers = {}
O.refreshers = refreshers

local LABEL_X, CTRL_X, ROW_H, CTRL_W = 8, 176, 28, 200
O.CTRL_X, O.ROW_H, O.CTRL_W = CTRL_X, ROW_H, CTRL_W

-- Controls are stacked down a page: page.y is the offset of the next row from the page's top.
local function RowCenter(page) return page.y - ROW_H / 2 end

function O.Section(page, title)
    if page.y ~= 0 then page.y = page.y - 12 end
    local t = UI:Text(page, 1)
    t:SetPoint("TOPLEFT", 0, page.y)
    t:SetText(title)
    t:SetTextColor(1, 0.82, 0)
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.12)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, page.y - 20)
    line:SetPoint("TOPRIGHT", 0, page.y - 20)
    page.y = page.y - 28
    return t
end

function O.Label(page, text)
    local t = UI:Text(page, 0)
    t:SetPoint("LEFT", page, "TOPLEFT", LABEL_X, RowCenter(page))
    t:SetText(text)
    return t
end

-- fmt: a format string for the value, or a function that returns its text. The label is s.label.
function O.Slider(page, name, label, min, max, step, get, set, fmt)
    local labelText = O.Label(page, label)
    local s = CreateFrame("Slider", name, page, "OptionsSliderTemplate")
    s.label = labelText
    local function Text(v) return type(fmt) == "function" and fmt(v) or fmt:format(v) end
    s:SetPoint("LEFT", page, "TOPLEFT", CTRL_X, RowCenter(page))
    s:SetWidth(CTRL_W)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    for _, part in ipairs({ "Low", "High", "Text" }) do _G[name .. part]:Hide() end
    local val = UI:Text(page, 0)
    val:SetPoint("LEFT", s, "RIGHT", 10, 0)
    local refreshing
    s:SetScript("OnValueChanged", function(_, v)
        if refreshing then return end
        v = math.floor(v / step + 0.5) * step
        set(v)
        val:SetText(Text(v))
    end)
    refreshers[#refreshers + 1] = function()
        refreshing = true
        s:SetValue(get())
        refreshing = false
        val:SetText(Text(get()))
    end
    refreshers[#refreshers]()
    page.y = page.y - ROW_H
    return s
end

function O.Check(page, label, get, set)
    local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("LEFT", page, "TOPLEFT", LABEL_X - 2, RowCenter(page))
    cb:SetScript("OnClick", function(s) set(s:GetChecked() and true or false) end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
    refreshers[#refreshers]()
    local t = UI:Text(page, 0)
    t:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    t:SetText(label)
    cb.label = t
    page.y = page.y - ROW_H
    return cb
end

-- Label, then a drop list of choices: getLabel() names the current one, getItems() lists them for UI:OpenMenu.
function O.DropList(page, label, getLabel, getItems)
    O.Label(page, label)
    local dd = UI:Dropdown(page, CTRL_W, 24, getLabel, getItems)
    dd:SetPoint("LEFT", page, "TOPLEFT", CTRL_X, RowCenter(page))
    refreshers[#refreshers + 1] = function() dd:Sync() end
    dd:Sync()
    page.y = page.y - ROW_H
    return dd
end

-- Label, then two buttons that bind keys to a Bindings.xml action, like the game's Key Bindings screen: click one and
-- press a key (with Alt, Ctrl or Shift), a mouse button or a controller button; Escape cancels and right-click unbinds.
-- The binding itself is UI.BindKey's (UI/Common/KeyBinding.lua).

-- One hidden frame takes the key press for every key row: a frame with a key handler gets keyboard input even when
-- not asked, so handlers on the buttons themselves all listened at once. Hidden, it gets nothing.
local capture = CreateFrame("Frame", nil, UIParent)
capture:Hide()
capture:SetFrameStrata("FULLSCREEN_DIALOG")
local listening -- the key button waiting for a key, if any: its .action and .index say what to bind
local keySyncs = {} -- every key row's Sync, so all of them redraw when listening starts or stops

local function SyncKeys()
    for _, sync in ipairs(keySyncs) do sync() end
end

local function StopListening()
    if not listening then return end
    listening = nil
    capture:Hide()
    SyncKeys()
end

local function BindKey(b, key)
    UI.BindKey(b.action, b.index, key)
    StopListening()
end

local function StartListening(b)
    StopListening()
    listening = b
    capture:Show()
    capture:EnableKeyboard(true)
    capture:SetPropagateKeyboardInput(false)
    capture:EnableGamePadButton(true)
    SyncKeys()
end

capture:SetScript("OnKeyDown", function(_, key)
    if not listening then return end
    if key == "ESCAPE" then return StopListening() end
    if UI.MODIFIER_KEYS[key] then return end
    BindKey(listening, UI.KeyWithModifiers(key))
end)
capture:SetScript("OnGamePadButtonDown", function(_, key)
    if listening then BindKey(listening, key) end
end)

-- Returns the label, for rows whose name can change.
function O.KeyBind(page, label, action)
    local labelText = O.Label(page, label)
    local buttons = {}
    local function Sync()
        local keys = { GetBindingKey(action) }
        for i, b in ipairs(buttons) do
            b.text:SetText(b == listening and L["Press a key..."] or keys[i] and GetBindingText(keys[i]) or L["Not Bound"])
        end
    end
    for i = 1, 2 do
        local b = UI:Button(page, "", (CTRL_W - 4) / 2, 24, function(s, btn)
            if InCombatLockdown() then return FP:Print(L["Cannot do that in combat."]) end
            if listening == s and UI.MOUSE_KEYS[btn] then return BindKey(s, UI.MOUSE_KEYS[btn]) end
            if btn == "RightButton" then
                StopListening()
                UI.UnbindKey(action, s.index)
                return SyncKeys()
            end
            if listening == s then return StopListening() end
            StartListening(s)
        end)
        b.action, b.index = action, i
        b:RegisterForClicks("AnyUp")
        b:SetPoint("LEFT", page, "TOPLEFT", CTRL_X + (i - 1) * (CTRL_W + 4) / 2, RowCenter(page))
        b:SetScript("OnHide", StopListening)
        UI:Tooltip(b, "ANCHOR_RIGHT", L["Click, then press a key or controller button. Right-click to unbind."])
        buttons[i] = b
    end
    keySyncs[#keySyncs + 1] = Sync
    FP:RegisterEvent("UPDATE_BINDINGS", Sync)
    refreshers[#refreshers + 1] = Sync
    Sync()
    page.y = page.y - ROW_H
    return labelText
end

-- A button in the label column, for actions that have no value to show.
function O.ActionButton(page, label, w, onClick)
    local b = UI:Button(page, label, w, 24, onClick)
    b:SetPoint("LEFT", page, "TOPLEFT", LABEL_X, RowCenter(page))
    page.y = page.y - ROW_H
    return b
end

-- Puts the named options back to their defaults; each page's reset names its own.
function O.ResetKeys(...)
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        FP.db[key] = FP.defaults[key]
    end
end

function O:Refresh()
    for _, refresh in ipairs(refreshers) do refresh() end
end
