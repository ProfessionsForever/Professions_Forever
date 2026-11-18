local _, FP = ...
local L = FP.L
local UI = FP.UI

-- A small movable bar of buttons that open the footer windows when the main window is closed. Each button carries a
-- count of what is waiting in that window. With Show Profession Buttons on, one more button per profession with a
-- crafting window opens it, like its tab (secure buttons, which the bar already has for Disenchanting Mode). Which
-- professions have one is asked of the game (UI:HasCraftingWindow), so Forever's camp crafting in Herbalism and Fishing
-- counts, and their button opens that window rather than casting the gathering spell.
local Launcher = {}
FP.Launcher = Launcher

local SIZE, GAP, TITLE_H, HANDLE, HANDLE_IN = 34, 4, 14, 16, 6 -- HANDLE_IN: how far the grip overlaps the corner
local REFRESH = 30 -- seconds between count refreshes, for cooldowns that finish with no event
local ICONS = UI.WINDOW_ICONS -- shared with the footer cells (UI/Footer.lua)
-- The main window on its Overview: closes it when it shows the Overview, else opens it there.
local function ToggleOverview()
    local f = UI.frame
    if f and f:IsShown() and UI.page == "overview" then f:Hide() else UI:Show("overview") end
end

-- In bar order: Overview and Settings, which open the main window and the options (toggle, each switched on its own
-- option), then the footer windows in footer order (planning, then activities); the profession buttons come after.
-- The icons match the reagent card badges.
local ITEMS = {
    { key = "overview", label = "Overview", icon = "Interface\\AddOns\\ProfessionsForever\\Media\\icon", color = { 1, 1, 1 },
        toggle = ToggleOverview, tip = "Opens the main window on the Overview.",
        binding = "TOGGLEPROFESSIONBOOK", -- the game's own professions key (K), which opens the main window already
        crop = 0.18, -- the addon icon is a round emblem: zoomed in until it fills the square, its rim cut off
        shown = function() return FP.db.quickOverview end,
        selected = function() return UI.frame ~= nil and UI.frame:IsShown() and UI.page == "overview" end },
    { key = "settings", label = "Settings", icon = "Interface\\Icons\\INV_Misc_Wrench_01", color = { 1, 1, 1 },
        toggle = function() FP.Options:Toggle() end, tip = "Opens the ProfessionsForever options.",
        shown = function() return FP.db.quickSettings end,
        selected = function() return FP.Options.frame ~= nil and FP.Options.frame:IsShown() end },
    { key = "queue", label = "Crafting Queue", icon = ICONS.queue, color = { 1, 1, 1 } },
    { key = "shop", label = "Shopping List", icon = ICONS.shop, color = { 1, 1, 1 } },
    { key = "transfer", label = "Transfer Planner", icon = ICONS.transfer, color = { 1, 1, 1 } },
    { key = "cooldowns", label = "Cooldowns", icon = ICONS.cooldowns, color = { 0.2, 0.9, 0.2 } },
    { key = "skillup", label = "Skill Up Route", icon = ICONS.skillup, color = { 1, 1, 1 },
        shown = function() return FP.SkillUpPanel:Available() and FP.db.quickSkillUp end },
    { key = "camp", label = "Camp", icon = ICONS.camp, color = { 0.9, 0.2, 0.2 }, -- shows a cooldown, not a count
        shown = function() return FP.db.quickCamp end },
    -- Not a footer window: a secure button that casts Enchanting and opens it in Disenchanting Mode.
    { key = "disenchant", label = "Disenchanting Mode", icon = ICONS.disenchant, color = { 1, 1, 1 },
        secure = true,
        shown = function() return FP.db.quickDisenchant and (Launcher.enchanting ~= nil or Launcher.deRecipient ~= nil) end,
        selected = function() return UI.deMode and UI.frame and UI.frame:IsShown() end },
}

-- A plain (not secure) button's click: its own toggle, or its footer window's; no Skill Up Route window without
-- SkillUp Forever.
local function Toggle(item)
    if item.toggle then return item.toggle() end
    local w = UI.FooterWindows()[item.key]
    if w then w:Toggle() end
end

-- What a button shows: the number waiting in its window (blank at 0); Camp shows the camp features' cooldown while
-- it runs instead, since the number of items you hold says little.
local function Count(key)
    if key == "camp" then
        local left = FP.Camp:Remaining(FP.Camp.OBJECTS)
        return left > 0 and FP.Cooldowns.Format(left) or ""
    end
    if key == "disenchant" or key == "skillup" or key == "profession" or key == "overview" or key == "settings" then
        return ""
    end
    local n
    if key == "cooldowns" then n = FP.Cooldowns:ReadyTotal()
    elseif key == "transfer" then n = FP.Queue:TransferNeeds().totals.characters + FP.Outgoing:PendingTotals()
    elseif key == "shop" then n = (FP.Shop:Summary())
    else n = (FP.Queue:Summary()) end
    return n > 99 and "99+" or n > 0 and n or ""
end

local MAX_PROFESSIONS = 5 -- two primary, plus Cooking, Fishing and First Aid
Launcher.MAX_BUTTONS = #ITEMS + MAX_PROFESSIONS -- the Rows and Columns sliders' top

-- Whether the window shows profession `skillLine` right now.
local function ShowingProfession(skillLine)
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    local f = UI.frame
    return base ~= nil and base.professionID == skillLine and C_TradeSkillUI.IsTradeSkillReady() and not FP:IsReadOnly()
        and f ~= nil and f:IsShown() and UI.page == "recipes"
end

-- Before the secure click: whether the profession is open, and showing, before its cast can open it. Checked after
-- the click instead, a cast that opened it at once would read as already showing and close it again.
local function ProfessionPreClick(b)
    local p = b.prof
    local base = p and C_TradeSkillUI.GetBaseProfessionInfo()
    b.wasOpen = base ~= nil and base.professionID == p.skillLine and C_TradeSkillUI.IsTradeSkillReady() and not FP:IsReadOnly()
    b.wasShowing = b.wasOpen and ShowingProfession(p.skillLine)
end

-- After a profession button's secure click: its cast opens the window (TRADE_SKILL_SHOW). When the profession was
-- already open it cast nothing, so the click shows the window on it, or closes the window when it was showing it.
-- Right click finds a trainer, as on the Overview cards.
local function ProfessionClick(b, btn)
    if btn == "RightButton" then return UI.OnProfessionOpenerClick(b, btn) end
    if b.wasOpen then
        if b.wasShowing then UI.frame:Hide() else UI:Show("recipes") end
        return
    end
    UI.TabSound()
end

-- The professions with a crafting window, in tab order, up to MAX_PROFESSIONS: the profession buttons' and keys'.
local function CraftingProfessions()
    local out = {}
    for _, p in ipairs(FP:GetProfessions()) do
        if #out < MAX_PROFESSIONS and UI:HasCraftingWindow(p) then out[#out + 1] = p end
    end
    return out
end

-- Key bindings (Bindings.xml; Key Bindings > AddOns > ProfessionsForever): a hidden named button for each quick
-- button, so the keys work whether or not the quick buttons are shown. Profession N is the Nth profession with a
-- crafting window, the order the profession buttons show in.
local KEY_PREFIX = "ProfessionsForeverKey_"
local function KeyBinding(name) return "CLICK " .. KEY_PREFIX .. name .. ":LeftButton" end
-- A button's binding: the game's own for one that has it (Overview), else the addon's.
local function ItemBinding(item) return item.binding or KeyBinding(item.key) end
for _, item in ipairs(ITEMS) do
    if not item.binding then _G["BINDING_NAME_" .. KeyBinding(item.key)] = L[item.label] end
end
for i = 1, MAX_PROFESSIONS do _G["BINDING_NAME_" .. KeyBinding("profession" .. i)] = L["Profession %d"]:format(i) end

-- Every key binding, in the options' order: { action, label } for the windows, { action, profession = N } for
-- Profession N.
Launcher.BINDINGS = {}
for _, item in ipairs(ITEMS) do Launcher.BINDINGS[#Launcher.BINDINGS + 1] = { action = ItemBinding(item), label = item.label } end
for i = 1, MAX_PROFESSIONS do
    Launcher.BINDINGS[#Launcher.BINDINGS + 1] = { action = KeyBinding("profession" .. i), profession = i }
end
Launcher.CraftingProfessions = CraftingProfessions

-- The corner the buttons grow from, where the handle sits: TOPLEFT when they grow right and down.
local function Corner()
    local db = FP.db
    return (db.quickGrowY == "up" and "BOTTOM" or "TOP") .. (db.quickGrowX == "left" and "RIGHT" or "LEFT")
end

-- The bar is pinned by its growth corner, saved as that corner's offset from the screen's bottom left, so changing
-- the direction or the number of buttons keeps the handle where it is.
function Launcher:Place()
    local bar, pos = self.bar, FP.db.launcherPos
    bar:ClearAllPoints()
    if pos then
        bar:SetPoint(Corner(), UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
    end
end

-- The secure Disenchanting Mode button makes the bar protected in combat: it can't be moved or laid out then.
-- Combat ends a drag as it starts (PLAYER_REGEN_DISABLED, the last moment the bar can still be stopped).
local function OnDragStart()
    if FP.db.quickButtonsLocked or InCombatLockdown() then return end
    Launcher.bar:StartMoving()
    Launcher.moving = true
end

local function OnDragStop()
    if not Launcher.moving or InCombatLockdown() then return end
    Launcher.moving = false
    local bar, db = Launcher.bar, FP.db
    bar:StopMovingOrSizing()
    db.launcherPos = { x = db.quickGrowX == "left" and bar:GetRight() or bar:GetLeft(),
        y = db.quickGrowY == "up" and bar:GetBottom() or bar:GetTop() }
    Launcher:Place()
end

-- On the handle's side of the bar, where nothing grows, lined up with the button.
local function Tooltip(tip, b)
    local bar = Launcher.bar
    tip:SetOwner(b, "ANCHOR_NONE")
    tip:ClearAllPoints()
    if FP.db.quickGrowY == "up" then
        tip:SetPoint("TOP", b, "BOTTOM", 0, bar:GetBottom() - b:GetBottom() - 4)
    else
        tip:SetPoint("BOTTOM", b, "TOP", 0, bar:GetTop() - b:GetTop() + 4)
    end
    tip:AddLine("ProfessionsForever", 1, 0.82, 0)
    if b.prof then
        local p = b.prof
        tip:AddLine(p.name, 1, 1, 1)
        if p.maxRank and p.maxRank > 0 then tip:AddLine(("%d / %d"):format(p.rank or 0, p.maxRank), 0.8, 0.8, 0.8) end
        tip:AddLine(L["Click to open or close. Right-click to find a trainer."], 0.5, 0.8, 1, true)
        return
    end
    tip:AddLine(L[b.item.label], 1, 1, 1)
    if b.item.key == "disenchant" then
        local r = Launcher.deRecipient
        if r then tip:AddLine(L["Gear you could send %s to disenchant"]:format(FP.Alts:Label(r.rec)), 0.2, 0.9, 0.2) end
        if r and #UI:DisenchantRecipients() > 1 then
            tip:AddLine(L["Right-click to choose another enchanter."], 0.5, 0.8, 1, true)
        end
    elseif b.item.tip then
        tip:AddLine(L[b.item.tip], 0.8, 0.8, 0.8, true)
    else
        UI.FillWindowTip(tip, b.item.key)
        tip:AddLine(" ")
    end
    tip:AddLine(FP.db.quickButtonsLocked and L["Click to open or close."] or L["Click to open or close. Drag to move the buttons."],
        0.5, 0.8, 1, true)
end

-- The button's first key, small in its top left corner like an action button's.
function Launcher:CreateHotkey(b)
    b.hotkey = UI:Text(b, -1, "LEFT")
    b.hotkey:SetPoint("TOPLEFT", 3, -3)
    b.hotkey:SetPoint("TOPRIGHT", -3, -3)
    b.hotkey:SetWordWrap(false)
    b.hotkey:SetTextColor(0.8, 0.8, 0.8)
    b.hotkey:SetShadowOffset(1, -1)
end

function Launcher:RefreshHotkeys()
    if not (self.bar and self.bar:IsShown()) then return end
    local show = FP.db.quickShowKeys
    for _, b in ipairs(self.shown) do
        local key = show and GetBindingKey(b.action)
        b.hotkey:SetText(key and GetBindingText(key, true) or "")
    end
end

function Launcher:Create()
    local bar = CreateFrame("Frame", "ProfessionsForeverLauncher", UIParent)
    self.bar = bar
    self.buttons = {}
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", OnDragStart)
    bar:SetScript("OnDragStop", OnDragStop)
    self:Place()

    local title = UI:Text(bar, -1)
    title:SetText("ProfessionsForever")
    title:SetTextColor(1, 0.82, 0)
    self.title = title

    -- While unlocked, a grip just outside the growth corner shows where the buttons grow from and drags the bar.
    local handle = CreateFrame("Frame", nil, bar)
    handle:SetSize(HANDLE, HANDLE)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", OnDragStart)
    handle:SetScript("OnDragStop", OnDragStop)
    handle.tex = handle:CreateTexture(nil, "OVERLAY")
    handle.tex:SetAllPoints()
    handle.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    UI:Tooltip(handle, "ANCHOR_TOP", function(tip)
        tip:AddLine("ProfessionsForever", 1, 0.82, 0)
        tip:AddLine(L["Drag to move the buttons. They grow from this corner."], 0.5, 0.8, 1, true)
    end)
    self.handle = handle

    for i, item in ipairs(ITEMS) do
        local b
        if item.secure then
            b = UI:Button(bar, "", SIZE, SIZE, function(s, btn) UI:QuickDisenchantClick(s, btn) end, "up")
        else
            b = UI:Button(bar, "", SIZE, SIZE, function() Toggle(item) end)
        end
        b.item = item
        if item.key == "disenchant" then self.deButton = b end
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", OnDragStart)
        b:SetScript("OnDragStop", OnDragStop)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 3, -3)
        icon:SetPoint("BOTTOMRIGHT", -3, 3)
        icon:SetTexture(item.icon)
        local crop = item.crop or 0.08 -- 0.08 trims a game icon's border
        icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
        b.count = UI:Text(b, 1, "RIGHT")
        b.count:SetPoint("BOTTOMRIGHT", -3, 3)
        b.count:SetTextColor(unpack(item.color))
        b.count:SetShadowOffset(1, -1)
        b.action = ItemBinding(item)
        self:CreateHotkey(b)
        UI:Tooltip(b, "ANCHOR_TOP", Tooltip)
        self.buttons[i] = b
    end

    -- Profession buttons, given a profession each by Layout.
    self.profButtons = {}
    for i = 1, MAX_PROFESSIONS do
        local b = UI:Button(bar, "", SIZE, SIZE, ProfessionClick, "up")
        b:SetScript("PreClick", ProfessionPreClick)
        b.item = { key = "profession", selected = function() return b.prof ~= nil and ShowingProfession(b.prof.skillLine) end }
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", OnDragStart)
        b:SetScript("OnDragStop", OnDragStop)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 3, -3)
        b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.count = UI:Text(b, 1, "RIGHT") -- unused, so the count refresh can treat every button alike
        b.count:SetPoint("BOTTOMRIGHT", -3, 3)
        b.action = KeyBinding("profession" .. i)
        self:CreateHotkey(b)
        UI:Tooltip(b, "ANCHOR_TOP", Tooltip)
        b:Hide()
        self.profButtons[i] = b
    end
end

-- Filled from the growth corner. Fixed columns: rows of quickColumns buttons, sideways first, then a new row up or
-- down. Fixed rows: columns of quickRows buttons, up or down first, then a new column sideways. The header stays above
-- the buttons, on the corner's side. Buttons switched off are left out; self.shown holds the rest.
function Launcher:Layout()
    -- Without Enchanting, the button lists gear to send your best enchanter instead, when you have one.
    self.enchanting = UI:OwnEnchanting()
    self.deRecipient = not self.enchanting and UI:DisenchantRecipients()[1] or nil
    local shown = {}
    for _, b in ipairs(self.buttons) do
        local on = not b.item.shown or b.item.shown()
        b:SetShown(on)
        if on then shown[#shown + 1] = b end
    end
    if self.enchanting then UI:SetProfessionOpener(self.deButton, self.enchanting)
    else self.deButton:SetAttribute("macrotext1", "") end -- nothing to cast
    -- Profession buttons after the others, for the professions with a crafting window.
    local n = 0
    if FP.db.quickProfessions then
        for _, p in ipairs(CraftingProfessions()) do
            n = n + 1
            local b = self.profButtons[n]
            b.prof = p
            b.icon:SetTexture(p.icon)
            UI:SetProfessionOpener(b, p)
            b:Show()
            shown[#shown + 1] = b
        end
    end
    for i = n + 1, MAX_PROFESSIONS do
        local b = self.profButtons[i]
        b.prof = nil
        b:SetAttribute("macrotext1", "")
        b:Hide()
    end
    self.shown = shown
    local db, n = FP.db, #shown
    local byRows = db.quickLayout == "rows"
    local rows, cols
    if byRows then
        rows = math.min(db.quickRows, n)
        cols = math.ceil(n / rows)
    else
        cols = math.min(db.quickColumns, n)
        rows = math.ceil(n / cols)
    end
    local left, up = db.quickGrowX == "left", db.quickGrowY == "up"
    local top = db.quickHeader and TITLE_H or 0
    local titleW = db.quickHeader and math.ceil(self.title:GetStringWidth()) or 0
    local w = math.max(cols * SIZE + (cols - 1) * GAP, titleW)
    local h = rows * SIZE + (rows - 1) * GAP
    self.bar:SetSize(w, h + top)
    self.title:SetShown(db.quickHeader)
    self.title:ClearAllPoints()
    self.title:SetPoint(left and "TOPRIGHT" or "TOPLEFT", left and -1 or 1, 0)
    local hx, hy = left and "RIGHT" or "LEFT", up and "BOTTOM" or "TOP"
    for i, b in ipairs(shown) do
        local col, row
        if byRows then row, col = (i - 1) % rows, math.floor((i - 1) / rows)
        else col, row = (i - 1) % cols, math.floor((i - 1) / cols) end
        local x, y = col * (SIZE + GAP), row * (SIZE + GAP)
        b:ClearAllPoints()
        b:SetPoint(hy .. hx, left and -x or x, up and y or -top - y)
    end
    self:Place()
    self:LayoutHandle()
end

-- The grip sits diagonally just outside the growth corner, pointing at it; the screen clamp makes room for it.
function Launcher:LayoutHandle()
    local db, handle = FP.db, self.handle
    local unlocked = not db.quickButtonsLocked
    handle:SetShown(unlocked)
    local left, up = db.quickGrowX == "left", db.quickGrowY == "up"
    local corner = Corner()
    local opposite = (up and "TOP" or "BOTTOM") .. (left and "LEFT" or "RIGHT")
    handle:ClearAllPoints()
    handle:SetPoint(opposite, self.bar, corner, left and -HANDLE_IN or HANDLE_IN, up and HANDLE_IN or -HANDLE_IN)
    -- The texture points at its bottom right; flipped to point at the corner.
    local l, r = left and 0 or 1, left and 1 or 0
    local t, b = up and 0 or 1, up and 1 or 0
    handle.tex:SetTexCoord(l, r, t, b)
    local pad = unlocked and HANDLE_IN - HANDLE or 0
    self.bar:SetClampRectInsets(left and 0 or pad, left and -pad or 0, up and 0 or -pad, up and pad or 0)
end

-- The key buttons, unanchored so never seen or clicked with the mouse; made once, at the first update after login.
function Launcher:CreateKeys()
    self.keys = {}
    for _, item in ipairs(ITEMS) do
        if item.binding then -- the game's own key, nothing to click
        elseif item.secure then
            self.keys[item.key] = UI:Button(UIParent, "", 1, 1, function(s, btn) UI:QuickDisenchantClick(s, btn) end,
                "up", KEY_PREFIX .. item.key)
        else
            self.keys[item.key] = UI:Button(UIParent, "", 1, 1, function() Toggle(item) end, nil, KEY_PREFIX .. item.key)
        end
    end
    self.profKeys = {}
    for i = 1, MAX_PROFESSIONS do
        local b = UI:Button(UIParent, "", 1, 1, function(s, btn)
            if s.prof then ProfessionClick(s, btn) end -- fewer professions than this key's number: nothing
        end, "up", KEY_PREFIX .. "profession" .. i)
        b:SetScript("PreClick", ProfessionPreClick)
        self.profKeys[i] = b
    end
end

-- Points the secure keys at their casts, as Layout does the buttons: Enchanting for Disenchanting Mode, and each
-- profession key's profession.
function Launcher:SyncKeys()
    if not self.keys then self:CreateKeys() end
    local enchanting = UI:OwnEnchanting()
    if enchanting then UI:SetProfessionOpener(self.keys.disenchant, enchanting)
    else self.keys.disenchant:SetAttribute("macrotext1", "") end
    local profs = CraftingProfessions()
    for i, b in ipairs(self.profKeys) do
        b.prof = profs[i]
        if b.prof then UI:SetProfessionOpener(b, b.prof) else b:SetAttribute("macrotext1", "") end
    end
end

function Launcher:Update()
    if InCombatLockdown() then
        self.afterCombat = true
        return
    end
    self:SyncKeys()
    if not FP.db.quickButtons then
        self:StopBindMode()
        if self.bar then self.bar:Hide() end
        if self.ticker then self.ticker:Cancel() self.ticker = nil end
        return
    end
    if not self.bar then self:Create() end
    self:Layout()
    self.bar:Show()
    self.ticker = self.ticker or C_Timer.NewTicker(REFRESH, function() Launcher:RefreshCounts() end)
    self:RefreshSelection()
    self:RefreshCounts()
    self:RefreshHotkeys()
end

-- A button is lit while its window is open.
function Launcher:RefreshSelection()
    if not (self.bar and self.bar:IsShown()) then return end
    local windows = UI.FooterWindows()
    for _, b in ipairs(self.shown) do
        local item, w = b.item, windows[b.item.key]
        UI.SetSelected(b, item.selected and item.selected() or w and w.frame and w.frame:IsShown() or false)
    end
end

function Launcher:RefreshCounts()
    if not (self.bar and self.bar:IsShown()) then return end
    for _, b in ipairs(self.shown) do
        b.count:SetText(Count(b.item.key))
    end
end

-- Many changes can land together (bag events, queue edits), so recount once shortly after.
function Launcher:QueueUpdate()
    if self.pending or not (self.bar and self.bar:IsShown()) then return end
    self.pending = true
    C_Timer.After(0.2, function()
        self.pending = false
        self:RefreshCounts()
    end)
end

---------------------------------------------------------------------------
-- Bind mode (/pf bind, or Options, Quick Buttons): hover a quick button and press a key, mouse button or controller
-- button to bind it to that button's key binding, in its first slot. Right-click a button to unbind it, Escape to
-- finish. A tinted overlay on each button takes the mouse meanwhile, so clicks bind or unbind rather than click, and
-- the bar comes to the front, above the options window. Keys pressed while not over a button go to the game.
---------------------------------------------------------------------------
local bindCapture -- the frame that takes the key presses while bind mode is on
local hovered -- the button under the mouse in bind mode

-- What the hovered button is bound to, and how to change it.
local function BindTooltip(overlay)
    local b = overlay:GetParent()
    GameTooltip:SetOwner(overlay, "ANCHOR_TOP")
    GameTooltip:AddLine(b.prof and b.prof.name or L[b.item.label], 1, 1, 1)
    local keys = { GetBindingKey(b.action) }
    for i, key in ipairs(keys) do keys[i] = GetBindingText(key) end
    GameTooltip:AddLine(#keys > 0 and table.concat(keys, ", ") or L["Not Bound"], 1, 0.82, 0)
    GameTooltip:AddLine(L["Press a key to bind it. Right-click to unbind. Escape to finish."], 0.5, 0.8, 1, true)
    GameTooltip:Show()
end

local function Bind(key)
    UI.BindKey(hovered.action, 1, key)
    BindTooltip(hovered.bindOverlay)
end

local function CreateBindCapture()
    bindCapture = CreateFrame("Frame", nil, UIParent)
    bindCapture:Hide()
    bindCapture:SetScript("OnKeyDown", function(f, key)
        if key == "ESCAPE" then
            f:SetPropagateKeyboardInput(false)
            return Launcher:StopBindMode()
        end
        f:SetPropagateKeyboardInput(hovered == nil)
        if hovered and not UI.MODIFIER_KEYS[key] then Bind(UI.KeyWithModifiers(key)) end
    end)
    bindCapture:SetScript("OnGamePadButtonDown", function(f, key)
        f:SetPropagateGamePadInput(hovered == nil)
        if hovered then Bind(key) end
    end)
end

local function CreateBindOverlay(b)
    local o = CreateFrame("Button", nil, b)
    o:SetAllPoints()
    o:SetFrameLevel(b:GetFrameLevel() + 5)
    o:RegisterForClicks("AnyUp")
    o.tint = o:CreateTexture(nil, "OVERLAY") -- the accent color, set as bind mode starts
    o.tint:SetAllPoints()
    local hl = o:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.25)
    o:SetScript("OnEnter", function(s)
        hovered = b
        BindTooltip(s)
    end)
    o:SetScript("OnLeave", function()
        hovered = nil
        GameTooltip:Hide()
    end)
    o:SetScript("OnClick", function(s, btn)
        if btn == "RightButton" then
            UI.UnbindKey(b.action)
            BindTooltip(s)
        elseif UI.MOUSE_KEYS[btn] then
            Bind(UI.MOUSE_KEYS[btn])
        end
    end)
    o:Hide()
    b.bindOverlay = o
end

function Launcher:StartBindMode()
    if InCombatLockdown() then return FP:Print(L["Cannot do that in combat."]) end
    if not (self.bar and self.bar:IsShown()) then return FP:Print(L["Turn on Show Quick Buttons first."]) end
    if self.binding then return end
    if not bindCapture then CreateBindCapture() end
    self.binding = true
    local accent = UI:GetAccent()
    for _, list in ipairs({ self.buttons, self.profButtons }) do
        for _, b in ipairs(list) do
            if not b.bindOverlay then CreateBindOverlay(b) end
            b.bindOverlay.tint:SetColorTexture(accent[1], accent[2], accent[3], 0.3)
            b.bindOverlay:Show()
        end
    end
    self.bar:SetFrameStrata("FULLSCREEN_DIALOG")
    bindCapture:Show()
    bindCapture:EnableKeyboard(true)
    bindCapture:EnableGamePadButton(true)
    FP:Print(L["Hover a quick button and press a key to bind it. Right-click a button to unbind it. Escape to finish."])
end

function Launcher:StopBindMode()
    if not self.binding then return end
    self.binding = false
    hovered = nil
    bindCapture:Hide()
    for _, list in ipairs({ self.buttons, self.profButtons }) do
        for _, b in ipairs(list) do b.bindOverlay:Hide() end
    end
    self.bar:SetFrameStrata("MEDIUM")
    GameTooltip:Hide()
    FP:Print(L["Key binding finished."])
end

function Launcher:ToggleBindMode()
    if self.binding then self:StopBindMode() else self:StartBindMode() end
end

-- Bindings changed here, on the options page or on the game's Key Bindings screen.
FP:RegisterEvent("UPDATE_BINDINGS", function() Launcher:RefreshHotkeys() end)

-- Updates held back by combat run when it ends. Opening or closing a profession, or learning one, changes the
-- Disenchanting Mode button's cast (none while Enchanting is already open) or whether it shows.
FP:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    OnDragStop()
    Launcher:StopBindMode() -- bindings can't change in combat
    -- Disarmed for combat, like the window's own profession buttons; re-armed by the update after it.
    if Launcher.bar then
        Launcher.deButton:SetAttribute("macrotext1", "")
        for _, b in ipairs(Launcher.profButtons) do b:SetAttribute("macrotext1", "") end
    end
    if Launcher.keys then
        Launcher.keys.disenchant:SetAttribute("macrotext1", "")
        for _, b in ipairs(Launcher.profKeys) do b:SetAttribute("macrotext1", "") end
    end
    Launcher.afterCombat = true
end)
FP:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if Launcher.afterCombat then
        Launcher.afterCombat = false
        Launcher:Update()
    end
end)
-- TRADE_SKILL_LIST_UPDATE catches the profession becoming ready, which TRADE_SKILL_SHOW can come before. Runs with
-- the quick buttons off too, for the keys. SPELLS_CHANGED: the spellbook loaded or changed, so the buttons' and keys'
-- casts are worked out again from it.
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE", "SKILL_LINES_CHANGED", "SPELLS_CHANGED" }) do
    FP:RegisterEvent(e, function() Launcher:Update() end)
end

-- Overview and Settings are lit while the main window shows the Overview, or the options are open; neither is a side
-- panel, so nothing else tells the buttons. Both windows are made on first use.
local function Relight() Launcher:RefreshSelection() end
hooksecurefunc(UI, "SetPage", Relight)
hooksecurefunc(UI, "Create", function()
    UI.frame:HookScript("OnShow", Relight)
    UI.frame:HookScript("OnHide", Relight)
end)
hooksecurefunc(FP.Options, "Init", function()
    FP.Options.frame:HookScript("OnShow", Relight)
    FP.Options.frame:HookScript("OnHide", Relight)
end)
