--[[
ThreeLightsLib: the small controls. Headings, tooltips, buttons, check boxes, text boxes (with a placeholder, a clear
button or - / + steppers), the money input and the multi-line box. Plain backdrop frames; the only Blizzard templates
are InputBox, UICheckButton, SecureActionButton and UIPanelScrollFrame (whose bar is swapped for the library's thin one).
]]
local _, ns = ...
local UI = ns.UI

-- A gold heading with a rule under it. The rule runs to the panel's right edge (4 in, like the lists), or for a
-- heading over one column of several, width pixels from the heading's left, so rules of side-by-side columns
-- don't run into each other.
function UI:Heading(parent, text, width)
    local fs = UI:Text(parent, "gold")
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.12)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
    if width then line:SetWidth(width) else line:SetPoint("RIGHT", parent, "RIGHT", -4, 0) end
    return fs
end

-- Puts GameTooltip just right of the mouse, its top level with the cursor. Called every frame while hovering, so it
-- follows the mouse; the game keeps it on screen.
function UI.TooltipAtCursor()
    local x, y = GetCursorPosition()
    local scale = GameTooltip:GetEffectiveScale()
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 18, y / scale - 4)
end

-- Shows the game tooltip while the mouse is over w. fill is a line of text, or a function(tooltip, w) that adds the
-- lines (returning false shows nothing). anchor: GameTooltip's anchor, "ANCHOR_RIGHT" when not given.
function UI:Tooltip(w, fill, anchor)
    -- A disabled button gets no hover events unless asked, and its tooltip is often why it is disabled.
    if w.SetMotionScriptsWhileDisabled then w:SetMotionScriptsWhileDisabled(true) end
    w:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, anchor or "ANCHOR_RIGHT")
        if type(fill) == "string" then
            GameTooltip:AddLine(fill, 1, 1, 1, true)
        elseif fill(GameTooltip, s) == false then
            GameTooltip:Hide()
            return
        end
        GameTooltip:Show()
    end)
    w:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
-- True when a button's text is wider than the room it has. Text anchored on both sides has that room; text anchored
-- at one point has the button less a margin.
function UI.TextCutOff(b)
    local fs = b.text
    if not (fs and fs:IsShown()) then return false end
    local room = fs:GetNumPoints() > 1 and fs:GetWidth() or b:GetWidth() - 8
    return fs:GetStringWidth() > room + 0.5
end

-- Hover lights the border with the accent; a selected button keeps it. A label that doesn't fit shows in full above.
local function ButtonEnter(s)
    if s:IsEnabled() then s:SetBackdropBorderColor(unpack(UI:GetAccent())) end
    if UI.TextCutOff(s) then
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:AddLine(s.text:GetText(), 1, 1, 1)
        GameTooltip:Show()
    end
end
local function ButtonLeave(s)
    if s.selected then
        s:SetBackdropBorderColor(unpack(UI:GetAccent()))
    else
        s:SetBackdropBorderColor(unpack(UI.ActiveSkin().button.border))
    end
    if GameTooltip:IsOwned(s) then GameTooltip:Hide() end
end
local function ButtonSetActive(s, on)
    s:SetEnabled(on and true or false)
    s.text:SetAlpha(on and 1 or 0.4)
    if s.arrow then s.arrow:SetAlpha(on and 1 or 0.4) end
end

-- secure: true or "up" makes a SecureActionButton that runs a macro (b:SetAttribute("macrotext", ...)), so it can do
-- what only a key press or click may, such as casting; onClick still runs after the macro. "up" fires on release, so
-- the button can be dragged without acting. name: the button's global name, for a CLICK key binding (Bindings.xml).
function UI:Button(parent, label, w, h, onClick, secure, name)
    local b = CreateFrame("Button", name, parent,
        secure and "SecureActionButtonTemplate,BackdropTemplate" or "BackdropTemplate")
    b:SetSize(w or 100, h or 22)
    UI:Skin(b, "button")
    b.text = UI:Text(b, "normal", "CENTER")
    b.text:SetWordWrap(false)  -- cut off with "..." (and shown in full on hover), even where texts wrap
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetText(label)
    b:SetScript("OnEnter", ButtonEnter)
    b:SetScript("OnLeave", ButtonLeave)
    if secure then
        -- The secure action fires on key-down or key-up depending on this CVar, so both are registered and onClick
        -- runs only on the phase the secure action used.
        b:RegisterForClicks("AnyDown", "AnyUp")
        b:SetAttribute("type", "macro")
        local onUp = secure == "up"
        if onUp then b:SetAttribute("useOnKeyDown", false) end
        b:SetScript("PostClick", function(s, btn, down)
            local keyDown = GetCVarBool("ActionButtonUseKeyDown") and true or false
            if onUp and not down or not onUp and (down and true or false) == keyDown then onClick(s, btn, down) end
        end)
    elseif onClick then
        b:SetScript("OnClick", onClick)
    end
    b.SetActive = ButtonSetActive
    b.SetSelected = UI.SetSelected
    b.SetLabel = function(s, text) s.text:SetText(text) end
    return b
end

function UI:Check(parent, label, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.label = UI:Text(cb, "normal")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText(label or "")
    if onClick then cb:SetScript("OnClick", function(s) onClick(s:GetChecked() and true or false) end) end
    return cb
end

-- Text boxes that take shift-clicked links: while one has focus, a shift-clicked item goes into it (or to its onLink).
local linkBoxes = {}
local linkHooked

local function TakeLinks(eb, onLink)
    linkBoxes[eb] = onLink or function(link) eb:SetText(link) end
    if linkHooked or not (ChatFrameUtil and ChatFrameUtil.InsertLink) then return end
    linkHooked = true
    hooksecurefunc(ChatFrameUtil, "InsertLink", function(link)
        if not link then return end
        for box, fn in pairs(linkBoxes) do
            if box:HasFocus() then fn(link) end
        end
    end)
end

-- Gray hint text in an empty edit box, gap pixels right of where typed text starts, so the blinking cursor sits just
-- before it instead of over its first letter. It follows the box's text inset, which EllesmereUI's restyle changes
-- (UI:EUIWidget calls eb.libPlaceholder again then). The caller shows and hides it.
local PLACEHOLDER_GAP = 3
function UI:AddPlaceholder(eb, text)
    local ph = UI:Text(eb, -1)
    if text then ph:SetText(text) end
    ph:SetTextColor(0.5, 0.5, 0.5)
    eb.libPlaceholder = function()
        ph:SetPoint("LEFT", (eb:GetTextInsets()) + PLACEHOLDER_GAP, 0)
    end
    eb.libPlaceholder()
    return ph
end

-- A red X inside the right end of an edit box that empties it, dimmed while the box is empty. Call it after the box's
-- OnTextChanged script is set, so that script stays in place. tip: the X's tooltip.
function UI:AddClearButton(eb, tip)
    local b = CreateFrame("Button", nil, eb:GetParent())
    b:SetSize(20, 20)
    b:SetPoint("RIGHT", eb, "RIGHT", -3, 0)
    b:SetFrameLevel(eb:GetFrameLevel() + 1)
    b.text = UI:Text(b, 1, "CENTER")
    b.text:SetPoint("CENTER")
    b.text:SetText("X")
    b.text:SetTextColor(1, 0.2, 0.2)
    local left, _, top, bottom = eb:GetTextInsets()
    eb:SetTextInsets(left, 26, top, bottom)
    local function Sync()
        local filled = eb:GetText() ~= ""
        b:SetEnabled(filled)
        b.text:SetAlpha(filled and 1 or 0.4)
    end
    b:SetScript("OnClick", function()
        eb:SetText("")
        eb:ClearFocus()
    end)
    b:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.45, 0.35) end)
    b:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 0.2, 0.2) end)
    if tip then UI:Tooltip(b, tip) end
    eb:HookScript("OnTextChanged", Sync)
    Sync()
    return b
end

-- - / + buttons either side of a numeric edit box (Shift steps by 10); onChange gets the new value. Made for a box
-- from InputBoxTemplate, whose left cap is drawn about 5 pixels outside the frame; EllesmereUI's restyled box has no
-- cap, so there both gaps are equal.
function UI:Stepper(eb, min, max, onChange)
    local function Step(delta)
        local step = IsShiftKeyDown() and 10 or 1
        local v = math.max(min, math.min(max, (tonumber(eb:GetText()) or min) + delta * step))
        eb:ClearFocus()
        eb:SetText(v)
        if onChange then onChange(v) end
    end
    eb:SetJustifyH("CENTER")
    eb.minus = UI:Button(eb:GetParent(), "-", 18, 20, function() Step(-1) end)
    eb.plus = UI:Button(eb:GetParent(), "+", 18, 20, function() Step(1) end)
    eb.plus:SetPoint("LEFT", eb, "RIGHT", 3, 0)
    eb.libEUILayout = function()
        eb.minus:ClearAllPoints()
        eb.minus:SetPoint("RIGHT", eb, "LEFT", UI.EUI() and -3 or -8, 0)
    end
    eb.libEUILayout()
end

-- opts: numeric, onEnter(text), onChange(text), maxLetters, links (true, or a function(link)) to take shift-clicks,
--       placeholder (gray text shown while the box is empty and not being typed in)
function UI:Edit(parent, w, h, opts)
    opts = opts or {}
    -- Our own box in the skin's colors, not Blizzard's InputBoxTemplate.
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(w or 120, h or 20)
    eb:SetAutoFocus(false)
    eb:SetTextInsets(6, 6, 0, 0)
    UI:Font(eb, "normal")
    eb:SetTextColor(1, 1, 1)
    UI:Skin(eb, "input")
    eb:HookScript("OnEditFocusGained", function(s)
        s.libFocus = true
        UI:Reskin(s)
    end)
    eb:HookScript("OnEditFocusLost", function(s)
        s.libFocus = nil
        UI:Reskin(s)
    end)
    if opts.numeric then eb:SetNumeric(true) end
    if opts.maxLetters then eb:SetMaxLetters(opts.maxLetters) end
    eb:SetScript("OnEnterPressed", function(s)
        s:ClearFocus()
        if opts.onEnter then opts.onEnter(s:GetText()) end
    end)
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    if opts.onChange then
        eb:SetScript("OnTextChanged", function(s, user) if user then opts.onChange(s:GetText()) end end)
    end
    if opts.links then TakeLinks(eb, type(opts.links) == "function" and opts.links or nil) end
    if opts.placeholder then
        local hint = UI:Text(eb, "normal")
        hint:SetWordWrap(false)
        hint:SetPoint("LEFT", 6, 0)
        hint:SetPoint("RIGHT", -6, 0)
        hint:SetText(opts.placeholder)
        hint:SetTextColor(0.5, 0.5, 0.5)
        local function Update() hint:SetShown(eb:GetText() == "" and not eb:HasFocus()) end
        eb:HookScript("OnTextChanged", Update)
        eb:HookScript("OnEditFocusGained", Update)
        eb:HookScript("OnEditFocusLost", Update)
    end
    return eb
end

-- An amount of money: gold, silver and copper boxes with their coin icons, like the game's own money inputs.
-- :GetCopper() and :SetCopper(copper); an empty box counts as 0.
local COINS = {
    { "gold", 10000, 70, 6, "Interface\\MoneyFrame\\UI-GoldIcon" },
    { "silver", 100, 40, 2, "Interface\\MoneyFrame\\UI-SilverIcon" },
    { "copper", 1, 40, 2, "Interface\\MoneyFrame\\UI-CopperIcon" },
}

function UI:MoneyInput(parent, h)
    h = h or 22
    local f = CreateFrame("Frame", nil, parent)
    f.boxes = {}
    local x = 0
    for i, coin in ipairs(COINS) do
        local eb = UI:Edit(f, coin[3], h, { numeric = true, maxLetters = coin[4] })
        eb:SetPoint("TOPLEFT", x, 0)
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", eb, "RIGHT", 4, 0)
        icon:SetTexture(coin[5])
        -- Tab moves on to the next coin.
        eb:SetScript("OnTabPressed", function()
            local nextBox = f.boxes[i % #COINS + 1]
            nextBox:SetFocus()
            nextBox:HighlightText()
        end)
        f.boxes[i] = eb
        x = x + coin[3] + 4 + 14 + 12
    end
    f:SetSize(x - 12, h)
    function f:GetCopper()
        local total = 0
        for i, coin in ipairs(COINS) do total = total + (tonumber(self.boxes[i]:GetText()) or 0) * coin[2] end
        return total
    end
    function f:SetCopper(copper)
        copper = math.floor(copper or 0)
        local parts = { math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100 }
        for i, eb in ipairs(self.boxes) do eb:SetText(parts[i] > 0 and tostring(parts[i]) or "") end
    end
    return f
end

-- A scrolling multi-line edit box (exports, long notes). Returns the edit box; its scroll frame is eb.scroll.
local multiSeq = 0
function UI:Multiline(parent, w, h)
    multiSeq = multiSeq + 1
    local scroll = CreateFrame("ScrollFrame", ns.LibHost.name .. "Multiline" .. multiSeq, parent,
        "UIPanelScrollFrameTemplate")
    scroll:SetSize(w, h)
    -- Drawn like the single-line boxes (UI:Edit), accent border while typing.
    local bg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", scroll, -4, 4)
    bg:SetPoint("BOTTOMRIGHT", scroll, UI.BAR_GUTTER, -4)
    UI:Skin(bg, "input")
    bg:SetFrameLevel(scroll:GetFrameLevel() - 1)
    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    UI:Font(eb, "normal")
    eb:SetTextColor(1, 1, 1)
    eb:SetTextInsets(4, 4, 4, 4)
    eb:SetWidth(w)
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    eb:HookScript("OnEditFocusGained", function()
        bg.libFocus = true
        UI:Reskin(bg)
    end)
    eb:HookScript("OnEditFocusLost", function()
        bg.libFocus = nil
        UI:Reskin(bg)
    end)
    scroll:SetScrollChild(eb)
    UI:AttachScrollbar(scroll, scroll.ScrollBar or _G[scroll:GetName() .. "ScrollBar"], bg, { top = 4, bottom = 4 }, eb)
    -- The edit box is only as tall as its text, so a click anywhere in the box puts the cursor at the end.
    local function Focus()
        if not eb:IsEnabled() or eb:HasFocus() then return end
        eb:SetFocus()
        eb:SetCursorPosition(#eb:GetText())
    end
    for _, f in ipairs({ scroll, bg }) do
        f:EnableMouse(true)
        f:SetScript("OnMouseDown", Focus)
    end
    eb.scroll = scroll
    return eb
end
