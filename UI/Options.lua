local _, FP = ...
local L = FP.L
local UI = FP.UI
local O = FP.Options
local refreshers = O.refreshers

local WIDTH, MIN_HEIGHT = 624, 260
local NAV_W, NAV_ROW_H = 140, 32
local PAGE_LEFT, PAGE_TOP = 168, -44
O.PAGE_W = WIDTH - PAGE_LEFT - 16

local FONTS = {
    { "Friz Quadrata", "Fonts\\FRIZQT__.TTF" }, { "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "Skurri", "Fonts\\skurri.ttf" }, { "Morpheus", "Fonts\\MORPHEUS.ttf" },
}

local function SkinItems()
    local db = FP.db
    local items = {}
    for _, key in ipairs(FP.skinOrder) do
        if UI:SkinAvailable(key) then
            items[#items + 1] = { text = L[FP.skins[key].name], checked = db.skin == key, onSelect = function()
                local was = db.skin
                db.skin = key
                UI:ApplySkin()
                O:Refresh()
                if was == "ellesmere" and key ~= was and UI.euiApplied then
                    FP:Print(L["Reload your UI to fully remove the EllesmereUI skin."])
                end
            end }
        end
    end
    return items
end

local function FontItems()
    local db = FP.db
    local items = {}
    for _, font in ipairs(FONTS) do
        items[#items + 1] = { text = font[1], checked = db.font == font[2], onSelect = function()
            db.font = font[2]
            UI:ApplyFonts()
            O:Refresh()
        end }
    end
    return items
end

local function PickAccent()
    local db = FP.db
    local a = UI:GetAccent()
    if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
    -- The picker is DIALOG strata and opens at screen centre like this window, which is above it, so it would be hidden.
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    if not O.pickerHooked then
        O.pickerHooked = true
        ColorPickerFrame:HookScript("OnHide", function(s) s:SetFrameStrata("DIALOG") end)
    end
    local function Apply()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        db.accent = { r, g, b }
        UI:ApplySkin()
        O:Refresh()
    end
    ColorPickerFrame:SetupColorPickerAndShow({ r = a[1], g = a[2], b = a[3], hasOpacity = false,
        swatchFunc = Apply, cancelFunc = function()
            db.accent = { a[1], a[2], a[3] }
            UI:ApplySkin()
            O:Refresh()
        end })
    ColorPickerFrame:Raise()
end

local function BuildAppearance(page)
    local db = FP.db
    O.Section(page, L["Theme"])
    O.DropList(page, L["Skin"], function() return L[UI.ActiveSkin().name] end, SkinItems)
    local fontDD = O.DropList(page, L["Font"], function()
        for _, font in ipairs(FONTS) do
            if font[2] == db.font then return font[1] end
        end
        return FONTS[1][1]
    end, FontItems)

    O.Label(page, L["Accent Color"])
    local accentBtn = UI:Button(page, L["Choose Color"], O.CTRL_W, 24, PickAccent)
    accentBtn:SetPoint("LEFT", page, "TOPLEFT", O.CTRL_X, page.y - O.ROW_H / 2)
    page.y = page.y - O.ROW_H
    local swatch = accentBtn:CreateTexture(nil, "OVERLAY")
    swatch:SetSize(14, 14)
    swatch:SetPoint("LEFT", 8, 0)
    refreshers[#refreshers + 1] = function() swatch:SetColorTexture(unpack(UI:GetAccent())) end
    refreshers[#refreshers]()

    -- EllesmereUI supplies the font and accent while its skin is active, so these two would have no effect.
    local function SyncEUILocks()
        local locked = UI.EUI() ~= nil
        fontDD:SetActive(not locked)
        accentBtn:SetActive(not locked)
    end
    refreshers[#refreshers + 1] = SyncEUILocks
    SyncEUILocks()
    for _, w in ipairs({ fontDD, accentBtn }) do
        UI:Tooltip(w, "ANCHOR_RIGHT", function(tip)
            if not UI.EUI() then return false end
            tip:AddLine(L["Set by EllesmereUI while its skin is active."], 1, 1, 1, true)
        end)
    end

    O.Section(page, L["Size and Opacity"])
    local scale = O.Slider(page, "ProfessionsForeverOptScale", L["Scale"], UI.SCALE_MIN, UI.SCALE_MAX, 0.05,
        function() return db.scale end, function(v) UI:SetScale(v) end, "%.2f")
    UI:Tooltip(scale, "ANCHOR_RIGHT", L["Ctrl+Mouse wheel on the title bar changes scale."])
    O.Slider(page, "ProfessionsForeverOptFont", L["Font Size"], 9, 18, 1,
        function() return db.fontSize end, function(v) db.fontSize = v UI:ApplyFonts() end, "%d")
    O.Slider(page, "ProfessionsForeverOptOpacity", L["Background Opacity"], 0.3, 1, 0.05,
        function() return db.opacity end, function(v) db.opacity = v UI:ApplySkin() end, "%.2f")

    O.Section(page, L["Window"])
    O.Check(page, L["Lock Window Position and Size"], function() return db.locked end, function(v)
        db.locked = v
        UI:ApplyLock()
    end)
    O.ActionButton(page, L["Reset Window Size and Position"], 240, function() UI:ResetWindow() end)
end

local function BuildGeneral(page)
    local db = FP.db
    O.Section(page, L["Professions Window"])
    O.Check(page, L["Replace Default Professions Window"], function() return db.replaceDefault end, function(v)
        db.replaceDefault = v
        if not v then FP:RestoreBlizzard() end
    end)
    local warn = UI:Text(page, -1)
    warn:SetPoint("LEFT", page, "TOPLEFT", 34, page.y - O.ROW_H / 2)
    warn:SetTextColor(1, 0.6, 0.2)
    warn:SetText(L["Changing this needs a UI reload to take full effect."])
    local reload = UI:Button(page, L["Reload UI"], 100, 22, function() ReloadUI() end)
    reload:SetPoint("RIGHT", page, "TOPRIGHT", 0, page.y - O.ROW_H / 2)
    page.y = page.y - O.ROW_H

    O.Section(page, L["Shopping List"])
    O.Check(page, L["Shopping List Scope"] .. ": " .. L["Account-Wide"], function() return db.shoppingScope == "account" end, function(v)
        db.shoppingScope = v and "account" or "char"
        FP.Shop:Update()
    end)

    O.Section(page, L["Interface"])
    O.Check(page, L["Hide Minimap Button"], function() return db.minimap.hide end, function(v)
        db.minimap.hide = v
        FP.Minimap:Update()
    end)
    O.Check(page, L["Show Ready Cooldowns at Login"], function() return db.cooldownNotice end, function(v)
        db.cooldownNotice = v
    end)
end

local function ResetGeneral()
    local db, d = FP.db, FP.defaults
    local replaced = db.replaceDefault
    db.replaceDefault, db.shoppingScope, db.cooldownNotice = d.replaceDefault, d.shoppingScope, d.cooldownNotice
    db.minimap.hide = d.minimap.hide
    FP.Minimap:Update()
    FP.Shop:Update()
    if replaced ~= db.replaceDefault then FP:Print(L["Changing this needs a UI reload to take full effect."]) end
end

local function ResetAppearance()
    local db, d = FP.db, FP.defaults
    local was = db.skin
    db.skin, db.font, db.fontSize, db.opacity, db.accent, db.locked = d.skin, d.font, d.fontSize, d.opacity, nil, d.locked
    UI:ResetWindow()
    UI:ApplyLock()
    UI:ApplySkin()
    if was == "ellesmere" and UI.euiApplied then FP:Print(L["Reload your UI to fully remove the EllesmereUI skin."]) end
end

local function ResetAlts() FP.Planner:SetMode(FP.defaults.altMode) end

local PAGES = {
    { key = "general", label = "General", build = BuildGeneral, reset = ResetGeneral },
    { key = "appearance", label = "Appearance", build = BuildAppearance, reset = ResetAppearance },
    { key = "alts", label = "Alt Inventory", build = O.BuildAlts, reset = ResetAlts },
    { key = "about", label = "About", build = O.BuildAbout },
}

-- Two clicks, because a reset can't be undone; the second must follow within a few seconds.
local function ResetButton(parent, label, w, onConfirm)
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

function O:Select(key)
    self.tab = key
    for _, page in ipairs(PAGES) do page.frame:SetShown(page.key == key) end
    self:RefreshNav()
end

function O:RefreshNav()
    local accent = UI:GetAccent()
    for _, page in ipairs(PAGES) do
        local sel = page.key == self.tab
        page.nav.bar:SetShown(sel)
        page.nav.bar:SetColorTexture(accent[1], accent[2], accent[3])
        if sel then page.nav.text:SetTextColor(1, 0.82, 0) else page.nav.text:SetTextColor(1, 1, 1) end
    end
end

local function BuildNav(p, page, i)
    local b = UI:Button(p, L[page.label], NAV_W, 28, function()
        UI.TabSound()
        O:Select(page.key)
    end)
    b:SetPoint("TOPLEFT", 12, PAGE_TOP - (i - 1) * NAV_ROW_H)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", 12, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetJustifyH("LEFT")
    b.bar = b:CreateTexture(nil, "OVERLAY")
    b.bar:SetWidth(3)
    b.bar:SetPoint("TOPLEFT", 1, -1)
    b.bar:SetPoint("BOTTOMLEFT", 1, 1)
    page.nav = b
end

function O:Init()
    local p = CreateFrame("Frame", "ProfessionsForeverOptionsFrame", UIParent, "BackdropTemplate")
    self.frame = p
    p:SetSize(WIDTH, MIN_HEIGHT)
    p:SetPoint("CENTER")
    p:SetFrameStrata("FULLSCREEN_DIALOG") -- above the main window and Blizzard's Settings panel
    p:SetMovable(true)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    p.fpOpaque = true
    UI:Skin(p, "window")
    tinsert(UISpecialFrames, "ProfessionsForeverOptionsFrame")

    local titleBar = CreateFrame("Frame", nil, p)
    titleBar:SetPoint("TOPLEFT", 4, -2)
    titleBar:SetPoint("TOPRIGHT", -4, -2)
    titleBar:SetHeight(UI.TITLE_H - 4)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() p:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
    local title = UI:Text(titleBar, 2)
    title:SetPoint("LEFT", 10, 0)
    title:SetText("ProfessionsForever")
    title:SetTextColor(1, 0.82, 0)
    local close = UI:Button(titleBar, "X", 22, 20, function() p:Hide() end)
    close:SetPoint("RIGHT", -2, 0)

    local divider = p:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.12)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", NAV_W + 18, PAGE_TOP)
    divider:SetPoint("BOTTOMLEFT", NAV_W + 18, 12)

    local tallest = MIN_HEIGHT
    for i, page in ipairs(PAGES) do
        BuildNav(p, page, i)
        local f = CreateFrame("Frame", nil, p)
        f:SetPoint("TOPLEFT", PAGE_LEFT, PAGE_TOP)
        f:SetPoint("BOTTOMRIGHT", -16, 12)
        f.y = 0
        page.frame = f
        page.build(f)
        if page.reset then
            ResetButton(f, L["Reset This Page"], 150, page.reset):SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        end
        tallest = math.max(tallest, 56 - f.y) -- top gap, content, bottom gap
    end
    p:SetHeight(tallest)

    ResetButton(p, L["Reset All Options"], NAV_W, function() FP:ResetOptions() end):SetPoint("BOTTOMLEFT", 12, 12)

    self:Select(self.tab or PAGES[1].key)
    p:Hide()
    -- Set after the first Hide so building the window makes no sound. Refresh because the EllesmereUI
    -- skin can be adopted at login after this window was built.
    p:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
        O:Refresh()
        O:RefreshNav()
    end)
    p:SetScript("OnHide", function()
        UI.CloseMenu()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    end)
    self:RegisterSettings()
end

function O:Open()
    if not self.frame then self:Init() end
    self.frame:Show()
end

function O:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Open() end
end
