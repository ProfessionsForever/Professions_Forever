local _, FP = ...
local UI = {}
FP.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8x8"
UI.WHITE = WHITE

---------------------------------------------------------------------------
-- Skins. Every frame is registered with UI:Skin(frame, kind) and styled via SetBackdrop*,
-- so skin addons can also hook these named frames.
---------------------------------------------------------------------------
FP.skinOrder = { "dark", "blackout", "classic", "minimal", "ellesmere" }
FP.skins = {
    dark = {
        name = "Modern Dark", accent = { 0.2, 0.6, 1 },
        window = { bg = { 0.06, 0.06, 0.08, 1 }, border = { 0.22, 0.22, 0.28, 1 } },
        panel = { bg = { 0.11, 0.11, 0.14, 0.9 }, border = { 0.2, 0.2, 0.25, 1 } },
        button = { bg = { 0.16, 0.16, 0.2, 1 }, border = { 0.3, 0.3, 0.36, 1 } },
    },
    -- The EllesmereUI look without EllesmereUI: black windows, thin grey borders, teal accent.
    blackout = {
        name = "Blackout", accent = { 0.047, 0.824, 0.616 },
        window = { bg = { 0, 0, 0, 0.95 }, border = { 0.2, 0.2, 0.2, 1 } },
        panel = { bg = { 0.04, 0.04, 0.04, 0.85 }, border = { 0.2, 0.2, 0.2, 1 } },
        button = { bg = { 0.08, 0.08, 0.08, 1 }, border = { 0.2, 0.2, 0.2, 1 } },
    },
    classic = {
        name = "Classic", accent = { 1, 0.82, 0 },
        window = { bg = { 1, 1, 1, 1 }, border = { 1, 1, 1, 1 }, bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16, inset = 4 },
        panel = { bg = { 0, 0, 0, 0.45 }, border = { 0.6, 0.5, 0.2, 1 } },
        button = { bg = { 0.25, 0.15, 0.05, 1 }, border = { 0.8, 0.65, 0.2, 1 } },
    },
    minimal = {
        name = "Minimal", accent = { 0.9, 0.9, 0.9 },
        window = { bg = { 0, 0, 0, 0.85 }, border = { 0, 0, 0, 0 } },
        panel = { bg = { 1, 1, 1, 0.04 }, border = { 0, 0, 0, 0 } },
        button = { bg = { 1, 1, 1, 0.08 }, border = { 0, 0, 0, 0 } },
    },
    -- EllesmereUI's window-skin palette. Windows get its shell instead (ApplyBackdrop); accent and font come from it live.
    ellesmere = {
        name = "EllesmereUI", accent = { 0.047, 0.824, 0.616 },
        window = { bg = { 0.08, 0.08, 0.08, 0.92 }, border = { 0.2, 0.2, 0.2, 1 } },
        panel = { bg = { 0.04, 0.04, 0.04, 0.85 }, border = { 0.2, 0.2, 0.2, 1 } },
        button = { bg = { 0.08, 0.08, 0.08, 0.92 }, border = { 0.2, 0.2, 0.2, 1 } },
    },
}

-- EllesmereUI's skinning facade (EllesmereUI.RegisterSkin), set once it hands us one.
UI.eui = nil
local function EUI()
    local S = UI.eui
    if S and FP.db.skin == "ellesmere" and S.IsEnabled() then return S end
end
UI.EUI = EUI

function UI:SkinAvailable(key)
    if key == "ellesmere" then return UI.eui ~= nil and UI.eui.IsEnabled() end
    return FP.skins[key] ~= nil
end

local function Skin()
    if FP.db.skin == "ellesmere" and not EUI() then return FP.skins.dark end
    return FP.skins[FP.db.skin] or FP.skins.dark
end
UI.ActiveSkin = Skin

local accentBuf = {}
function UI:GetAccent()
    local S = EUI()
    if S then
        accentBuf[1], accentBuf[2], accentBuf[3] = S.GetAccentColor()
        return accentBuf
    end
    return FP.db.accent or Skin().accent
end

local skinned, texts, euiWidgets = {}, {}, {}

-- Height of the title strip in every window; titles and header buttons are centred on it.
local WINDOW_TITLE_H = 30
UI.TITLE_H = WINDOW_TITLE_H

local function ApplyBackdrop(f)
    if f.fpOpaque then
        -- A solid layer under the skin so text behind the window never shows through.
        f.fpBacking = f.fpBacking or f:CreateTexture(nil, "BACKGROUND", nil, -8)
        f.fpBacking:SetAllPoints()
        if FP.db.skin == "classic" then f.fpBacking:SetColorTexture(0.1, 0.07, 0.03, 1)
        else
            local bg = Skin().window.bg
            f.fpBacking:SetColorTexture(bg[1], bg[2], bg[3], 1)
        end
    end
    local S = f.fpKind == "window" and EUI()
    if S then
        -- EllesmereUI draws the window itself; our backdrop would cover its art.
        f:SetBackdrop(nil)
        S.Shell(f)
        -- Shell and its restrips fade any texture they didn't create, so resize its own 25px bar (BACKGROUND sublevel -5).
        if not f.fpTopBar then
            for _, r in ipairs({ f:GetRegions() }) do
                if r:IsObjectType("Texture") then
                    local layer, sub = r:GetDrawLayer()
                    if layer == "BACKGROUND" and sub == -5 then f.fpTopBar = r break end
                end
            end
        end
        if f.fpTopBar then f.fpTopBar:SetHeight(WINDOW_TITLE_H) end
        UI.euiApplied = true
        return
    end
    local s = Skin()
    local c = s[f.fpKind] or s.panel
    local inset = c.inset or 1
    f:SetBackdrop({ bgFile = c.bgFile or WHITE, edgeFile = c.edgeFile or WHITE, edgeSize = c.edgeSize or 1,
        insets = { left = inset, right = inset, top = inset, bottom = inset } })
    local alpha = c.bg[4] * (f.fpKind == "button" and 1 or FP.db.opacity)
    f:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], alpha)
    f:SetBackdropBorderColor(unpack(c.border))
end

function UI:Skin(f, kind)
    f.fpKind = kind
    skinned[#skinned + 1] = f
    ApplyBackdrop(f)
    return f
end

-- Edit boxes EllesmereUI restyles. Its styling can't be undone without a reload. A box placed to allow for
-- InputBoxTemplate's caps, which EllesmereUI's square box doesn't have, re-anchors itself in w.fpEUILayout.
local PAD_INPUT = { padInput = true }
local function ApplyEUIWidget(w)
    local S = EUI()
    if not S then return end
    S.EditBox(w, w.fpEUI == "editbox" and PAD_INPUT or nil)
    UI.euiApplied = true
    if w.fpEUILayout then w.fpEUILayout() end
    if w.fpPlaceholder then w.fpPlaceholder() end
end

-- kind: "editbox" (left-aligned text) or "numbox" (centered number). Call after anchoring.
function UI:EUIWidget(w, kind)
    if not w then return end
    w.fpEUI = kind
    euiWidgets[#euiWidgets + 1] = w
    ApplyEUIWidget(w)
end

function UI:ApplySkin()
    for _, f in ipairs(skinned) do ApplyBackdrop(f) end
    for _, w in ipairs(euiWidgets) do ApplyEUIWidget(w) end
    self:ApplyFonts()
    if self.frame then
        self:SyncFilters() self:UpdateList() -- ApplyFonts above redraws the detail panel
        self:RefreshProfessions() self:RefreshFooterSelection()
    end
end

if EllesmereUI and EllesmereUI.RegisterSkin then
    -- Runs at login, and only while EllesmereUI's third-party skinning is on for this addon.
    EllesmereUI.RegisterSkin("ProfessionsForever", function(S)
        UI.eui = S
        -- Adopt its look the first time it's seen; the Skin option can switch away afterwards.
        if not FP.db.euiAdopted then FP.db.euiAdopted, FP.db.skin = true, "ellesmere" end
        S.OnLooksChanged(function() if EUI() then UI:ApplySkin() end end)
        UI:ApplySkin()
        if FP.Options.Refresh then FP.Options:Refresh() end
    end)
end

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------
local function SetFontSafe(fs)
    local size = FP.db.fontSize + fs.fpDelta
    local path, flag = FP.db.font, ""
    local S = EUI()
    if S then path, flag = S.GetFont() end
    if fs:SetFont(path, size, flag or "") == false then fs:SetFont(STANDARD_TEXT_FONT, size, "") end
end

function UI:Text(parent, delta, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs.fpDelta = delta or 0
    texts[#texts + 1] = fs
    SetFontSafe(fs)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    return fs
end

local function ApplyAllFonts()
    for _, fs in ipairs(texts) do SetFontSafe(fs) end
    -- The star's position depends on the name's font size.
    if UI.frame and UI.frame.detail then UI:UpdateDetail() end
end

-- A font file the game hasn't used yet may not draw on the first pass, so the fonts are applied again a moment later.
function UI:ApplyFonts()
    ApplyAllFonts()
    if self.fontsRetry then return end
    self.fontsRetry = true
    C_Timer.After(0.3, function()
        self.fontsRetry = false
        ApplyAllFonts()
    end)
end
