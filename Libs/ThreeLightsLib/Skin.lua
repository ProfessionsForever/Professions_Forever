--[[
ThreeLightsLib: skins, fonts, the accent color and window stacking. Every frame is registered with UI:Skin(frame, kind),
kind = "window" | "panel" | "button" | "input", and every text is made with UI:Text, so changing the skin, accent,
font or font size restyles everything already built.

The library is a set of files each addon carries its own copy of (Libs/ThreeLightsLib), loaded from its .toc after a file that
sets ns.LibHost (see the library's README). Everything hangs off ns.UI, the addon's own table: two addons using the library
share no state.
]]
local _, ns = ...
local host = ns.LibHost
local L = host.L
local UI = {}
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8x8"
UI.WHITE = WHITE
-- White fading to clear from left to right, tinted with the accent for a title bar's or banner's glow.
UI.FADE = "Interface\\AddOns\\" .. host.name .. "\\Libs\\ThreeLightsLib\\Media\\fade"
UI.GAME_FONT = "Fonts\\FRIZQT__.TTF"
UI.SCALE_MIN, UI.SCALE_MAX = 0.6, 1.6
-- Height of a window's title strip; EllesmereUI's window shell sizes its top bar to it. A window whose header is taller
-- sets f.libTitleH before UI:Skin.
UI.TITLE_H = 30

-- Crops the border drawn into the game's icons, so a texture shows only the picture.
function UI.TrimIcon(texture) texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

-- Text colors that carry a meaning. They stay the same in every skin.
UI.colors = {
    gold = { 1, 0.82, 0 },
    dim = { 0.5, 0.53, 0.58 },     -- secondary text, hints: a darker slate, so it never reads as white beside it
    light = { 0.76, 0.76, 0.74 },  -- body text under a title, halfway between dim and white
    good = { 0.33, 0.87, 0.33 },   -- done, yes, can do
    bad = { 1, 0.38, 0.38 },       -- missing, no, refused
    warn = { 0.95, 0.75, 0.25 },   -- a caution
    alert = { 1, 0.56, 0.31 },     -- wants your attention: new, waiting for you
}

-- text in one of UI.colors, for use inside a longer string.
function UI.Color(name, text)
    local c = UI.colors[name]
    return format("|cff%02x%02x%02x%s|r", c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5, text)
end

-- Appearance options and their defaults. accent has none: nil uses the skin's own. The host's saved table
-- (host.options()) holds only the ones that were changed.
UI.DEFAULTS = { skin = host.skin and host.skin.key or "dark", font = UI.GAME_FONT, fontSize = 12, opacity = 0.96,
    scale = 1, locked = false }

function UI.Opt(key)
    local v = host.options()[key]
    if v == nil then return UI.DEFAULTS[key] end
    return v
end

function UI.SetOpt(key, value)
    host.options()[key] = value
end

---------------------------------------------------------------------------
-- Skins
---------------------------------------------------------------------------
UI.skinOrder = { "dark", "blackout", "classic", "minimal", "ellesmere" }
UI.skins = {
    dark = {
        name = L["Modern Dark"], accent = { 0.2, 0.6, 1 },
        window = { bg = { 0.06, 0.06, 0.08, 1 }, border = { 0.22, 0.22, 0.28, 1 } },
        panel = { bg = { 0.11, 0.11, 0.14, 0.9 }, border = { 0.2, 0.2, 0.25, 1 } },
        button = { bg = { 0.16, 0.16, 0.2, 1 }, border = { 0.3, 0.3, 0.36, 1 } },
    },
    -- The EllesmereUI look without EllesmereUI: black windows, thin gray borders, teal accent.
    blackout = {
        name = L["Blackout"], accent = { 0.047, 0.824, 0.616 },
        window = { bg = { 0, 0, 0, 0.95 }, border = { 0.2, 0.2, 0.2, 1 } },
        panel = { bg = { 0.04, 0.04, 0.04, 0.85 }, border = { 0.2, 0.2, 0.2, 1 } },
        button = { bg = { 0.08, 0.08, 0.08, 1 }, border = { 0.2, 0.2, 0.2, 1 } },
    },
    classic = {
        name = L["Classic"], accent = { 1, 0.82, 0 },
        window = { bg = { 1, 1, 1, 1 }, border = { 1, 1, 1, 1 }, bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16, inset = 4, edge = 5 },
        panel = { bg = { 0, 0, 0, 0.45 }, border = { 0.6, 0.5, 0.2, 1 } },
        button = { bg = { 0.25, 0.15, 0.05, 1 }, border = { 0.8, 0.65, 0.2, 1 } },
    },
    minimal = {
        name = L["Minimal"], accent = { 0.9, 0.9, 0.9 },
        window = { bg = { 0, 0, 0, 0.85 }, border = { 0, 0, 0, 0 } },
        panel = { bg = { 1, 1, 1, 0.04 }, border = { 0, 0, 0, 0 } },
        button = { bg = { 1, 1, 1, 0.08 }, border = { 0, 0, 0, 0 } },
    },
    -- EllesmereUI's window-skin palette. Windows get its shell instead (ApplyBackdrop); accent and font come from it live.
    ellesmere = {
        name = L["EllesmereUI"], accent = { 0.047, 0.824, 0.616 },
        window = { bg = { 0.08, 0.08, 0.08, 0.92 }, border = { 0.2, 0.2, 0.2, 1 } },
        panel = { bg = { 0.04, 0.04, 0.04, 0.85 }, border = { 0.2, 0.2, 0.2, 1 } },
        button = { bg = { 0.08, 0.08, 0.08, 0.92 }, border = { 0.2, 0.2, 0.2, 1 } },
    },
}

-- The host's own skin (host.skin = { key, name, accent, window, panel, button }) is listed first and is the default.
if host.skin then
    UI.skins[host.skin.key] = host.skin
    table.insert(UI.skinOrder, 1, host.skin.key)
end

-- EllesmereUI's skinning facade, set once it hands us one (EllesmereUI.RegisterSkin below).
UI.eui = nil
local function EUI()
    local S = UI.eui
    if S and UI.Opt("skin") == "ellesmere" and S.IsEnabled() then return S end
end
UI.EUI = EUI

function UI:SkinAvailable(key)
    if key == "ellesmere" then return UI.eui ~= nil and UI.eui.IsEnabled() end
    return UI.skins[key] ~= nil
end

local function Skin()
    local key = UI.Opt("skin")
    if key == "ellesmere" and not EUI() then return UI.skins[UI.DEFAULTS.skin] end
    return UI.skins[key] or UI.skins[UI.DEFAULTS.skin]
end
UI.ActiveSkin = Skin

local accentBuf = {}
function UI:GetAccent()
    local S = EUI()
    if S then
        accentBuf[1], accentBuf[2], accentBuf[3] = S.GetAccentColor()
        return accentBuf
    end
    return UI.Opt("accent") or Skin().accent
end

-- The accent as a color code for text ("|cffrrggbb"), for highlights inside a string.
function UI:AccentCode()
    local a = UI:GetAccent()
    return format("|cff%02x%02x%02x", a[1] * 255, a[2] * 255, a[3] * 255)
end

local skinned, texts, listeners, fontListeners, euiWidgets = {}, {}, {}, {}, {}

-- fn() runs after every skin, accent or font change, for things drawn with the accent outside a backdrop.
function UI:OnSkinChanged(fn)
    listeners[#listeners + 1] = fn
end

-- fn() runs after every font or font size change (and again on the retry a moment later), for layouts that depend on
-- the size of their text.
function UI:OnFontsChanged(fn)
    fontListeners[#fontListeners + 1] = fn
end

-- Marks a button as the current choice (open panel, open page): an accent border and a faint accent fill.
function UI.SetSelected(b, on)
    b.selected = on and true or nil
    local c = Skin().button
    local bg = c.bg
    if b.selected then
        local a = UI:GetAccent()
        b:SetBackdropColor(bg[1] * 0.75 + a[1] * 0.25, bg[2] * 0.75 + a[2] * 0.25, bg[3] * 0.75 + a[3] * 0.25, bg[4])
        b:SetBackdropBorderColor(a[1], a[2], a[3], 1)
    else
        b:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        b:SetBackdropBorderColor(unpack(c.border))
    end
end

local function ApplyBackdrop(f)
    if f.libOpaque then
        -- A solid layer under the skin, so see-through skins stay readable over the game world.
        f.libBacking = f.libBacking or f:CreateTexture(nil, "BACKGROUND", nil, -8)
        f.libBacking:SetAllPoints()
        if UI.Opt("skin") == "classic" then
            f.libBacking:SetColorTexture(0.1, 0.07, 0.03, 1)
        else
            local bg = Skin().window.bg
            f.libBacking:SetColorTexture(bg[1], bg[2], bg[3], 1)
        end
    end
    local S = f.libKind == "window" and EUI()
    if S then
        -- EllesmereUI draws the window itself; our backdrop would cover its art.
        f:SetBackdrop(nil)
        -- Shell fades every texture already on the frame. Ours come back after it; the opaque backing stays faded.
        local keep = {}
        for _, r in ipairs({ f:GetRegions() }) do
            if r:IsObjectType("Texture") and r ~= f.libBacking and r:GetAlpha() > 0 then keep[r] = r:GetAlpha() end
        end
        S.Shell(f)
        for r, alpha in pairs(keep) do r:SetAlpha(alpha) end
        -- Its own top bar is the texture on BACKGROUND sublevel -5; size it to our title strip.
        if not f.libTopBar then
            for _, r in ipairs({ f:GetRegions() }) do
                if r:IsObjectType("Texture") then
                    local layer, sub = r:GetDrawLayer()
                    if layer == "BACKGROUND" and sub == -5 then
                        f.libTopBar = r
                        break
                    end
                end
            end
        end
        if f.libTopBar then f.libTopBar:SetHeight(f.libTitleH or UI.TITLE_H) end
        UI.euiApplied = true
        return
    end
    local c = Skin()[f.libKind] or Skin().panel
    local inset = c.inset or 1
    f:SetBackdrop({ bgFile = c.bgFile or WHITE, edgeFile = c.edgeFile or WHITE, edgeSize = c.edgeSize or 1,
        insets = { left = inset, right = inset, top = inset, bottom = inset } })
    if f.libKind == "input" then
        -- Text boxes: the panel colors, darker and solid so typed text reads well; the accent border while typing.
        f:SetBackdropColor(c.bg[1] * 0.55, c.bg[2] * 0.55, c.bg[3] * 0.55, 1)
        if f.libFocus then
            local a = UI:GetAccent()
            f:SetBackdropBorderColor(a[1], a[2], a[3], 1)
        else
            f:SetBackdropBorderColor(unpack(c.border))
        end
        return
    end
    local alpha = c.bg[4] * (f.libKind == "button" and 1 or UI.Opt("opacity"))
    f:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], alpha)
    f:SetBackdropBorderColor(unpack(c.border))
    if f.selected then UI.SetSelected(f, true) end
end

-- Draws a skinned frame again after its state changed (a text box gaining or losing focus).
function UI:Reskin(f) ApplyBackdrop(f) end

-- How far in from a window's edge its border art reaches (edge: what the art draws past the backdrop's inset), so
-- something drawn edge to edge, like a header's glow, stays inside it.
function UI:WindowEdge()
    if EUI() then return 1 end
    local c = Skin().window
    return c.edge or c.inset or 1
end

-- Edit boxes made from Blizzard's InputBoxTemplate that EllesmereUI restyles while its skin is on. Its styling can't
-- be undone without a reload. A box placed to allow for the template's caps, which EllesmereUI's square box doesn't
-- have, re-anchors itself in w.libEUILayout; a placeholder (UI:AddPlaceholder) follows the new text inset.
local PAD_INPUT = { padInput = true }
local function ApplyEUIWidget(w)
    local S = EUI()
    if not S then return end
    S.EditBox(w, w.libEUI == "editbox" and PAD_INPUT or nil)
    UI.euiApplied = true
    if w.libEUILayout then w.libEUILayout() end
    if w.libPlaceholder then w.libPlaceholder() end
end

-- kind: "editbox" (left-aligned text) or "numbox" (centered number). Call after anchoring.
function UI:EUIWidget(w, kind)
    if not w then return end
    w.libEUI = kind
    euiWidgets[#euiWidgets + 1] = w
    ApplyEUIWidget(w)
end

-- opaque: a solid layer under the skin, for windows that sit over the game world (see-through skins stay readable).
function UI:Skin(f, kind, opaque)
    f.libKind = kind or "panel"
    f.libOpaque = opaque or nil
    skinned[#skinned + 1] = f
    ApplyBackdrop(f)
    return f
end

-- A soft dark shadow around the outside of a floating window, so its edges stand out against the window behind it.
-- Rings of black fading outward, drawn under the frame's own art; they hide and show with the frame.
local SHADOW_STEPS = 6

function UI:Shadow(f, size)
    size = size or 14
    local step = size / SHADOW_STEPS
    for i = 1, SHADOW_STEPS do
        local inner, outer = (i - 1) * step, i * step
        local a = 0.45 * ((SHADOW_STEPS - i + 1) / SHADOW_STEPS) ^ 2
        local function Band(p1, x1, y1, p2, x2, y2)
            local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
            t:SetColorTexture(0, 0, 0, a)
            t:SetPoint("TOPLEFT", f, p1, x1, y1)
            t:SetPoint("BOTTOMRIGHT", f, p2, x2, y2)
        end
        Band("TOPLEFT", -outer, outer, "TOPRIGHT", outer, inner)               -- top, corners included
        Band("BOTTOMLEFT", -outer, -inner, "BOTTOMRIGHT", outer, -outer)       -- bottom, corners included
        Band("TOPLEFT", -outer, inner, "BOTTOMLEFT", -inner, -inner)           -- left
        Band("TOPRIGHT", inner, inner, "BOTTOMRIGHT", outer, -inner)           -- right
    end
    return f
end

---------------------------------------------------------------------------
-- Stacking. Three tiers, so a window opened from another always shows in front of it:
--   main  (HIGH)              the main window
--   child (DIALOG)            windows opened from it or by events: forms, options, the addon's other windows
--   popup (FULLSCREEN_DIALOG) confirmations, prompts and drop-down menus, which can open over any of the above
-- Each window is toplevel and raises itself when shown, so within a tier the last one opened or clicked is in front.
---------------------------------------------------------------------------
UI.STRATA = { main = "HIGH", child = "DIALOG", popup = "FULLSCREEN_DIALOG" }

function UI:Layer(f, tier)
    f:SetFrameStrata(UI.STRATA[tier])
    f:SetToplevel(true)
    f:HookScript("OnShow", f.Raise)
    return f
end

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------
-- size: "small", "normal", "title", "gold" (normal size in gold) or a number of points added to the font size.
local DELTAS = { small = -2, normal = 0, title = 4, gold = 0 }

local function SetFontSafe(fs)
    local size = UI.Opt("fontSize") + fs.libDelta
    local path, flag = UI.Opt("font"), ""
    if path == UI.GAME_FONT then path = STANDARD_TEXT_FONT end
    local S = EUI()
    if S then path, flag = S.GetFont() end
    -- A font file that isn't there raises an error on this client rather than returning false (EllesmereUI 9.9.5
    -- renamed its fonts and still handed out an old path), so the call is guarded and falls back to the game's font.
    local ok, set = pcall(fs.SetFont, fs, path, size, flag or "")
    if not ok or set == false then fs:SetFont(STANDARD_TEXT_FONT, size, "") end
end

-- Gives a font string or edit box the chosen font at a size, and keeps it following font changes.
function UI:Font(obj, size)
    obj.libDelta = type(size) == "number" and size or DELTAS[size or "normal"] or 0
    texts[#texts + 1] = obj
    SetFontSafe(obj)
end

function UI:Text(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    UI:Font(fs, size)
    fs:SetJustifyH(justify or "LEFT")
    -- host.textWraps: texts wrap unless told not to (the game's default); otherwise they stay on one line.
    if not host.textWraps then fs:SetWordWrap(false) end
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    if size == "gold" or size == "title" then fs:SetTextColor(unpack(UI.colors.gold)) else fs:SetTextColor(1, 1, 1) end
    return fs
end

local function ApplyAllFonts()
    for _, fs in ipairs(texts) do SetFontSafe(fs) end
    for _, fn in ipairs(fontListeners) do fn() end
end

-- A font file the game hasn't used yet may not draw on the first pass, so the fonts are applied again a moment later.
function UI:ApplyFonts()
    ApplyAllFonts()
    if UI.fontsRetry then return end
    UI.fontsRetry = true
    C_Timer.After(0.3, function()
        UI.fontsRetry = false
        ApplyAllFonts()
    end)
end

function UI:ApplySkin()
    for _, f in ipairs(skinned) do ApplyBackdrop(f) end
    for _, w in ipairs(euiWidgets) do ApplyEUIWidget(w) end
    UI:ApplyFonts()
    for _, fn in ipairs(listeners) do fn() end
end

if EllesmereUI and EllesmereUI.RegisterSkin then
    -- Runs at login, and only while EllesmereUI's third-party skinning is on for this addon.
    EllesmereUI.RegisterSkin(host.name, function(S)
        UI.eui = S
        -- Adopt its look the first time it's seen; the Skin option can switch away afterwards.
        local ui = host.options()
        if not ui.euiAdopted then ui.euiAdopted, ui.skin = true, "ellesmere" end
        S.OnLooksChanged(function() if EUI() then UI:ApplySkin() end end)
        UI:ApplySkin()
        if ns.Options and ns.Options.frame then ns.Options:Refresh() end
    end)
end
