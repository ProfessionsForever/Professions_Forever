--[[
ThreeLightsLib: the options window. A page list on the left with categories that open one at a time, the selected page on the
right, a reset on each page, and the controls that stack down a page.

The host adds its pages in the order they should be listed, before the window first opens:

  O:AddPage({ key, label, cat = true, banner = function(page) ... end })            a category
  O:AddPage({ key, label, parent = "category key", build = function(page) ... end,
              reset = function() ... end, desc = "one line", visible = function() ... end, mine = true,
              status = function() return text end })
  O:AddAppearancePages()     the Appearance category: skin, font, accent, scale, font size, opacity, window lock

A page with no parent and no cat is a plain top-level page. visible(), when given, hides the entry (and its pages)
while it returns false. mine marks a page whose reset belongs to "Reset My Options". status(), when given, is a short
text shown beside the page's link on its category's page (an integration's "Installed", say).

Optional host fields for the window: optionsWidth (default 760); resetAll, a function that puts every option back,
which turns the button under the page list into "Reset All Options"; and for the appearance pages lockLabel (the lock
check's label), applyLock() (run when the lock changes) and scaleTip (the scale slider's tooltip).

Controls stack down a page: page.y is the offset of the next row from the page's top. Each control adds a refresher
that re-reads its value, so the window follows changes made elsewhere (O:Refresh()).
]]
local _, ns = ...
local host = ns.LibHost
local L = host.L
local UI = ns.UI
local O = {}
ns.Options = O

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------
local refreshers = {}

local LABEL_X, CTRL_X, ROW_H, CTRL_W = 8, 176, 28, 200
O.LABEL_X, O.CTRL_X, O.ROW_H, O.CTRL_W = LABEL_X, CTRL_X, ROW_H, CTRL_W

local function RowCenter(page) return page.y - ROW_H / 2 end

local function Add(fn)
    refreshers[#refreshers + 1] = fn
    fn()
end
O.AddRefresher = Add

function O.Section(page, title)
    if page.y ~= 0 then page.y = page.y - 12 end
    local t = UI:Text(page, 1)
    t:SetPoint("TOPLEFT", 0, page.y)
    t:SetText(title)
    t:SetTextColor(unpack(UI.colors.gold))
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

-- A line of grey text across the page, wrapped.
function O.Note(page, text)
    local t = UI:Text(page, -1)
    t:SetPoint("TOPLEFT", LABEL_X, page.y - 4)
    t:SetPoint("RIGHT", page, "RIGHT", -8, 0)
    t:SetWordWrap(true)
    t:SetText(text)
    t:SetTextColor(0.7, 0.7, 0.7)
    page.y = page.y - math.ceil(t:GetStringHeight()) - 10
    return t
end

-- fmt: a format string for the value, or a function that returns its text.
local sliderSeq = 0
function O.Slider(page, label, min, max, step, get, set, fmt)
    sliderSeq = sliderSeq + 1
    local name = host.name .. "OptSlider" .. sliderSeq
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
    Add(function()
        refreshing = true
        s:SetValue(get())
        refreshing = false
        val:SetText(Text(get()))
    end)
    page.y = page.y - ROW_H
    return s
end

function O.Check(page, label, get, set)
    local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("LEFT", page, "TOPLEFT", LABEL_X - 2, RowCenter(page))
    cb:SetScript("OnClick", function(s) set(s:GetChecked() and true or false) end)
    local t = UI:Text(page, 0)
    t:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    t:SetText(label)
    cb.label = t
    Add(function() cb:SetChecked(get()) end)
    page.y = page.y - ROW_H
    return cb
end

-- Label, then a drop list of choices: getLabel() names the current one, getItems() lists them for UI:OpenMenu.
-- The label is dd.label.
function O.DropList(page, label, getLabel, getItems)
    local labelText = O.Label(page, label)
    local dd = UI:Dropdown(page, CTRL_W, 24, getLabel, getItems)
    dd.label = labelText
    dd:SetPoint("LEFT", page, "TOPLEFT", CTRL_X, RowCenter(page))
    Add(function() dd:Refresh() end)
    page.y = page.y - ROW_H
    return dd
end

---------------------------------------------------------------------------
-- Key rows: a label, then two buttons that bind keys to a Bindings.xml action, like the game's Key Bindings screen.
-- Click one and press a key (with Alt, Ctrl or Shift), a mouse button or a controller button; Escape cancels and
-- right-click unbinds. The binding itself is UI.BindKey's (KeyBinding.lua).
---------------------------------------------------------------------------
-- One hidden frame takes the key press for every key row: a frame with a key handler gets keyboard input even when
-- not asked, so handlers on the buttons themselves all listened at once. Hidden, it gets nothing.
local capture = CreateFrame("Frame", nil, UIParent)
capture:Hide()
capture:SetFrameStrata(UI.STRATA.popup)
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

-- Another addon or the Key Bindings screen can change bindings while the window is open.
capture:RegisterEvent("UPDATE_BINDINGS")
capture:SetScript("OnEvent", SyncKeys)

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
            if InCombatLockdown() then
                local msg = L["Cannot do that in combat."]
                if host.print then host.print(msg) else print(msg) end
                return
            end
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
        UI:Tooltip(b, L["Click, then press a key or controller button. Right-click to unbind."])
        buttons[i] = b
    end
    keySyncs[#keySyncs + 1] = Sync
    Add(Sync)
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

-- Two clicks, because a reset can't be undone; the second must follow within a few seconds.
function O.ResetButton(parent, label, w, onConfirm)
    return UI:Button(parent, label, w, 24, function(s)
        if not s.confirming then
            s.confirming = true
            s.text:SetText(L["Click again to confirm"])
            C_Timer.After(4, function()
                s.confirming = false
                s.text:SetText(label)
            end)
            return
        end
        s.confirming = false
        s.text:SetText(label)
        onConfirm()
        O:Refresh()
    end)
end

function O:Refresh()
    for _, refresh in ipairs(refreshers) do refresh() end
end

---------------------------------------------------------------------------
-- The window's layout and its pages
---------------------------------------------------------------------------
local WIDTH, MIN_HEIGHT = host.optionsWidth or 760, 300
local NAV_W, NAV_ROW_H = 156, 32
local PAGE_LEFT, PAGE_TOP = 184, -44
O.PAGE_W = WIDTH - PAGE_LEFT - 16
local SUB_INDENT, SUB_ROW_H = 14, 26

local PAGES, BY_KEY = {}, {}

function O:AddPage(page)
    PAGES[#PAGES + 1] = page
    BY_KEY[page.key] = page
    if page.cat then page.children = {} end
    if page.parent then table.insert(BY_KEY[page.parent].children, page) end
end

local function Visible(page)
    if page.parent and not Visible(BY_KEY[page.parent]) then return false end
    return not page.visible or page.visible()
end

local function TabSound() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end

---------------------------------------------------------------------------
-- Appearance
---------------------------------------------------------------------------
local FONTS = {
    { L["Game Default"], UI.GAME_FONT }, { "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "Skurri", "Fonts\\skurri.ttf" }, { "Morpheus", "Fonts\\MORPHEUS.ttf" },
}

-- The game's own fonts, then any that LibSharedMedia lists: other addons register theirs there.
local function FontList()
    local list, seen = {}, {}
    for _, font in ipairs(FONTS) do
        list[#list + 1] = font
        seen[font[2]:lower()] = true
    end
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    if media then
        local extra = {}
        for name, path in pairs(media:HashTable("font")) do
            if type(path) == "string" and not seen[path:lower()] then extra[#extra + 1] = { name, path } end
        end
        table.sort(extra, function(a, b) return a[1] < b[1] end)
        for _, font in ipairs(extra) do list[#list + 1] = font end
    end
    return list
end

local RELOAD_POPUP = host.name:upper() .. "_RELOAD_SKIN"
StaticPopupDialogs[RELOAD_POPUP] = {
    text = L["Reload your UI to fully remove the EllesmereUI skin."],
    button1 = L["Reload UI"],
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function OfferSkinReload() StaticPopup_Show(RELOAD_POPUP) end

local function SkinItems()
    local items = {}
    for _, key in ipairs(UI.skinOrder) do
        if UI:SkinAvailable(key) then
            items[#items + 1] = { text = UI.skins[key].name, checked = UI.Opt("skin") == key, onSelect = function()
                local was = UI.Opt("skin")
                UI.SetOpt("skin", key)
                UI:ApplySkin()
                O:Refresh()
                if was == "ellesmere" and key ~= was and UI.euiApplied then OfferSkinReload() end
            end }
        end
    end
    return items
end

local function FontItems()
    local items = {}
    for _, font in ipairs(FontList()) do
        items[#items + 1] = { text = font[1], checked = UI.Opt("font") == font[2], onSelect = function()
            UI.SetOpt("font", font[2])
            UI:ApplyFonts()
            O:Refresh()
        end }
    end
    return items
end

local function PickAccent()
    local a = UI:GetAccent()
    local old = { a[1], a[2], a[3] }
    -- The picker opens at screen centre like this window; lift it to the popup tier while we use it.
    ColorPickerFrame:SetFrameStrata(UI.STRATA.popup)
    if not O.pickerHooked then
        O.pickerHooked = true
        ColorPickerFrame:HookScript("OnHide", function(s) s:SetFrameStrata("DIALOG") end)
    end
    local function Apply()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        UI.SetOpt("accent", { r, g, b })
        UI:ApplySkin()
        O:Refresh()
    end
    ColorPickerFrame:SetupColorPickerAndShow({ r = old[1], g = old[2], b = old[3], hasOpacity = false,
        swatchFunc = Apply, cancelFunc = function()
            UI.SetOpt("accent", old)
            UI:ApplySkin()
            O:Refresh()
        end })
    ColorPickerFrame:Raise()
end

local function BuildTheme(page)
    O.Section(page, L["Theme"])
    O.DropList(page, L["Skin"], function() return UI.ActiveSkin().name end, SkinItems)
    local fontDD = O.DropList(page, L["Font"], function()
        for _, font in ipairs(FontList()) do
            if font[2] == UI.Opt("font") then return font[1] end
        end
        return FONTS[1][1]
    end, FontItems)

    O.Label(page, L["Accent Color"])
    -- The button, a swatch and "Use the Skin's" share the row: the button gives up width so the row fits the page.
    local accentW = math.min(O.CTRL_W, O.PAGE_W - O.CTRL_X - (10 + 18 + 10 + 110))
    local accentBtn = UI:Button(page, L["Choose Color"], accentW, 24, PickAccent)
    accentBtn:SetPoint("LEFT", page, "TOPLEFT", O.CTRL_X, page.y - O.ROW_H / 2)
    local swatch = page:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(18, 18)
    swatch:SetPoint("LEFT", accentBtn, "RIGHT", 10, 0)
    local useSkin = UI:Button(page, L["Use the Skin's"], 110, 24, function()
        UI.SetOpt("accent", nil)
        UI:ApplySkin()
        O:Refresh()
    end)
    useSkin:SetPoint("LEFT", swatch, "RIGHT", 10, 0)
    page.y = page.y - O.ROW_H
    -- EllesmereUI sets the font and accent while its skin is on.
    O.AddRefresher(function()
        local a = UI:GetAccent()
        swatch:SetColorTexture(a[1], a[2], a[3])
        local eui = UI.EUI() ~= nil
        fontDD:SetActive(not eui)
        accentBtn:SetActive(not eui)
        useSkin:SetActive(not eui and UI.Opt("accent") ~= nil)
    end)
    UI:Tooltip(fontDD, function(tip)
        if not UI.EUI() then return false end
        tip:AddLine(L["Set by EllesmereUI while its skin is active."], 1, 1, 1, true)
    end)
end

local function ResetTheme()
    local was = UI.Opt("skin")
    for _, key in ipairs({ "skin", "font", "accent" }) do UI.SetOpt(key, nil) end
    UI:ApplySkin()
    if was == "ellesmere" and UI.euiApplied then OfferSkinReload() end
end

local function BuildSize(page)
    O.Section(page, L["Size and Opacity"])
    local scale = O.Slider(page, L["Scale"], UI.SCALE_MIN, UI.SCALE_MAX, 0.05, function() return UI.Opt("scale") end,
        function(v)
            UI.SetOpt("scale", v)
            host.applyWindow()
        end, "%.2f")
    if host.scaleTip then UI:Tooltip(scale, host.scaleTip) end
    O.Slider(page, L["Font Size"], 9, 18, 1, function() return UI.Opt("fontSize") end, function(v)
        UI.SetOpt("fontSize", v)
        UI:ApplyFonts()
    end, "%d")
    O.Slider(page, L["Background Opacity"], 0.3, 1, 0.05, function() return UI.Opt("opacity") end, function(v)
        UI.SetOpt("opacity", v)
        UI:ApplySkin()
    end, "%.2f")
    O.Section(page, L["Window"])
    O.Check(page, host.lockLabel or L["Lock the Window's Position"], function() return UI.Opt("locked") end, function(v)
        UI.SetOpt("locked", v)
        if host.applyLock then host.applyLock() end
    end)
    O.ActionButton(page, L["Reset Window Size and Position"], 240, function()
        host.resetWindow()
        O:Refresh()
    end)
end

local function ResetSize()
    for _, key in ipairs({ "fontSize", "opacity", "locked", "scale" }) do UI.SetOpt(key, nil) end
    host.resetWindow()
    if host.applyLock then host.applyLock() end
    UI:ApplySkin()
end

function O:AddAppearancePages()
    O:AddPage({ key = "appearance", label = L["Appearance"], cat = true })
    O:AddPage({ key = "theme", parent = "appearance", label = L["Theme"], build = BuildTheme, reset = ResetTheme,
        mine = true, desc = L["Skin, font and accent color."] })
    O:AddPage({ key = "size", parent = "appearance", label = L["Size and Window"], build = BuildSize,
        reset = ResetSize, mine = true,
        desc = L["Scale, font size, background opacity, and locking or resetting the window."] })
end

---------------------------------------------------------------------------
-- The page list
---------------------------------------------------------------------------
-- A category's own page: a link to each page under it, with a line on what it holds.
local function BuildLinks(page, cat)
    if cat.banner then cat.banner(page) end
    O.Section(page, cat.label)
    for _, child in ipairs(cat.children) do
        local row = CreateFrame("Button", nil, page)
        row:SetPoint("TOPLEFT", 0, page.y)
        row:SetPoint("RIGHT", page, "RIGHT", 0, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnClick", function()
            TabSound()
            O:Select(child.key)
        end)
        local name = UI:Text(row, 1)
        name:SetPoint("TOPLEFT", 8, -6)
        name:SetText(child.label)
        name:SetTextColor(0.4, 0.75, 1)
        if child.status then
            local status = UI:Text(row, -1)
            status:SetPoint("LEFT", name, "RIGHT", 10, 0)
            O.AddRefresher(function() status:SetText(child.status()) end)
        end
        local desc = UI:Text(row, -1)
        desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
        desc:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        desc:SetWordWrap(true)
        desc:SetTextColor(0.7, 0.7, 0.7)
        desc:SetText(child.desc or "")
        local h = 6 + math.ceil(name:GetStringHeight()) + 3 + math.ceil(desc:GetStringHeight()) + 6
        row:SetHeight(h)
        O.AddRefresher(function() row:SetShown(Visible(child)) end)
        page.y = page.y - h - 4
    end
end

local function ResetCategory(cat)
    for _, child in ipairs(cat.children) do
        if child.reset and Visible(child) then child.reset() end
    end
end

-- Places the list's rows: every visible top-level entry, and the pages of the open category under it.
local function LayoutNav()
    local y = 0
    for _, page in ipairs(PAGES) do
        local shown = Visible(page) and (not page.parent or page.parent == O.open)
        page.nav:SetShown(shown)
        if shown then
            page.nav:ClearAllPoints()
            page.nav:SetPoint("TOPLEFT", 12 + (page.parent and SUB_INDENT or 0), PAGE_TOP - y)
            y = y + (page.parent and SUB_ROW_H or NAV_ROW_H)
        end
        if page.cat then
            page.nav.sign:SetTexture(O.open == page.key and "Interface\\Buttons\\UI-MinusButton-Up"
                or "Interface\\Buttons\\UI-PlusButton-Up")
        end
    end
end

-- Shows a page, opening the category it is in (or that it is); a plain top-level page closes the open one.
function O:Select(key)
    local page = BY_KEY[key]
    if not page or not Visible(page) then page = PAGES[1] end
    self.tab = page.key
    self.open = page.parent or (page.cat and page.key) or nil
    for _, p in ipairs(PAGES) do p.frame:SetShown(p == page) end
    LayoutNav()
    self:RefreshNav()
end

-- The selected page's row is marked, and so is its category's while that is closed.
function O:RefreshNav()
    local tab = BY_KEY[self.tab]
    for _, page in ipairs(PAGES) do
        local sel = page == tab or (tab and tab.parent == page.key and self.open ~= page.key)
        page.nav:SetSelected(sel)
        if sel then page.nav.text:SetTextColor(unpack(UI.colors.gold)) else page.nav.text:SetTextColor(1, 1, 1) end
    end
end

-- A category's row opens it on its links page; when it is open already, it closes and its links page shows.
local function NavClick(page)
    TabSound()
    local closing = page.cat and O.open == page.key
    O:Select(page.key)
    if closing then
        O.open = nil
        LayoutNav()
        O:RefreshNav()
    end
end

local function BuildNav(p, page)
    local sub = page.parent ~= nil
    local b = UI:Button(p, page.label, NAV_W - (sub and SUB_INDENT or 0), sub and 22 or 28, function() NavClick(page) end)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", page.cat and 26 or 12, 0)
    b.text:SetPoint("RIGHT", -8, 0)
    b.text:SetJustifyH("LEFT")
    if page.cat then
        b.sign = b:CreateTexture(nil, "OVERLAY")
        b.sign:SetSize(14, 14)
        b.sign:SetPoint("LEFT", 7, 0)
    end
    page.nav = b
end

-- Resets every page that is this account's own (mine): appearance and whatever the host marked.
local function ResetMine()
    for _, page in ipairs(PAGES) do
        if page.mine and page.reset and Visible(page) then page.reset() end
    end
end

function O:Init()
    local p = CreateFrame("Frame", host.name .. "OptionsFrame", UIParent, "BackdropTemplate")
    self.frame = p
    p:SetSize(WIDTH, MIN_HEIGHT)
    p:SetPoint("CENTER")
    UI:Layer(p, "child")
    p:SetMovable(true)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    UI:Skin(p, "window", true)
    tinsert(UISpecialFrames, host.name .. "OptionsFrame")

    local title = UI:Text(p, 2)
    title:SetPoint("TOPLEFT", 14, -9)
    title:SetText(host.optionsTitle)
    title:SetTextColor(unpack(UI.colors.gold))
    local close = UI:Button(p, "X", 22, 20, function() p:Hide() end)
    close:SetPoint("TOPRIGHT", -6, -6)

    local divider = p:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.12)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", NAV_W + 18, PAGE_TOP)
    divider:SetPoint("BOTTOMLEFT", NAV_W + 18, 12)

    local tallest, topRows, mostChildren = MIN_HEIGHT, 0, 0
    for _, page in ipairs(PAGES) do
        BuildNav(p, page)
        if not page.parent then topRows = topRows + 1 end
        if page.cat then mostChildren = math.max(mostChildren, #page.children) end
        local f = CreateFrame("Frame", nil, p)
        f:SetPoint("TOPLEFT", PAGE_LEFT, PAGE_TOP)
        f:SetPoint("BOTTOMRIGHT", -16, 12)
        f:SetWidth(O.PAGE_W)
        f.y = 0
        page.frame = f
        if page.cat then BuildLinks(f, page) else page.build(f) end
        local reset = page.cat and function() ResetCategory(page) end or page.reset
        if reset then
            O.ResetButton(f, page.cat and L["Reset This Category"] or L["Reset This Page"], 150, reset)
                :SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        end
        tallest = math.max(tallest, 56 - f.y)
    end
    -- Tall enough for the list with its longest category open, and the reset button under it.
    local navH = topRows * NAV_ROW_H + mostChildren * SUB_ROW_H
    p:SetHeight(math.max(tallest, -PAGE_TOP + navH + 12 + 24 + 12))

    if host.resetAll then
        O.ResetButton(p, L["Reset All Options"], NAV_W, host.resetAll):SetPoint("BOTTOMLEFT", 12, 12)
    else
        O.ResetButton(p, L["Reset My Options"], NAV_W, ResetMine):SetPoint("BOTTOMLEFT", 12, 12)
    end

    self:Select(self.tab or PAGES[1].key)
    p:Hide()
    -- Set after the first Hide so building the window makes no sound.
    p:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
        O:Refresh()
        O:Select(O.tab) -- pages can come and go (visible) while the window is closed
    end)
    p:SetScript("OnHide", function()
        UI:CloseMenu()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    end)
end

function O:Open(key)
    if not self.frame then self:Init() end
    if key then self.tab = key end
    self.frame:Show()
end

function O:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Open() end
end


UI:OnSkinChanged(function() if O.frame then O:RefreshNav() end end)
