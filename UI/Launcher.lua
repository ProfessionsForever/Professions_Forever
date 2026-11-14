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
local ITEMS = { -- in footer order; the icons match the reagent card badges
    { key = "cooldowns", label = "Cooldowns", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", color = { 0.2, 0.9, 0.2 } },
    { key = "skillup", label = "Skill Up Route", icon = "Interface\\Icons\\INV_Misc_Map_01", color = { 1, 1, 1 },
        shown = function() return FP.SkillUpPanel:Available() and FP.db.quickSkillUp end },
    { key = "transfer", label = "Transfer Planner", icon = "Interface\\Icons\\INV_Letter_15", color = { 1, 1, 1 } },
    { key = "shop", label = "Shopping List", icon = "Interface\\Icons\\INV_Misc_Coin_01", color = { 1, 1, 1 } },
    { key = "queue", label = "Crafting Queue", icon = "Interface\\Icons\\INV_Misc_Gear_01", color = { 1, 1, 1 } },
    -- Not a footer window: a secure button that casts Enchanting and opens it in Disenchanting Mode.
    { key = "disenchant", label = "Disenchanting Mode", icon = "Interface\\Icons\\INV_Enchant_DustStrange", color = { 1, 1, 1 },
        secure = true, shown = function() return Launcher.enchanting ~= nil or Launcher.deRecipient ~= nil end,
        selected = function() return UI.deMode and UI.frame and UI.frame:IsShown() end },
}

-- Your Enchanting from the profession list, once you know Disenchant; nil otherwise. Set by Layout.
local function FindEnchanting()
    if not IsPlayerSpell(FP.Disenchant.SPELL) then return end
    for _, p in ipairs(FP:GetProfessions()) do
        if p.skillLine == FP.ENCHANTING then return p end
    end
end

-- The number shown on a button: what is waiting in its window.
local function Count(key)
    if key == "disenchant" or key == "skillup" or key == "profession" then return 0 end
    if key == "cooldowns" then return FP.Cooldowns:ReadyTotal() end
    if key == "transfer" then return FP.Queue:TransferNeeds().totals.characters + FP.Outgoing:PendingTotals() end
    if key == "shop" then return (FP.Shop:Summary()) end
    return (FP.Queue:Summary())
end

local MAX_PROFESSIONS = 7 -- two primary and up to five secondary
Launcher.MAX_COLUMNS = #ITEMS + MAX_PROFESSIONS

-- Whether the window shows profession `skillLine` right now.
local function ShowingProfession(skillLine)
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    local f = UI.frame
    return base ~= nil and base.professionID == skillLine and C_TradeSkillUI.IsTradeSkillReady() and not FP:IsReadOnly()
        and f ~= nil and f:IsShown() and UI.page == "recipes"
end

-- After a profession button's secure click: its cast opens the window (TRADE_SKILL_SHOW). When the profession is
-- already open it casts nothing, so the click shows the window on it, or closes the window when it is showing it.
-- Right click finds a trainer, as on the Overview cards.
local function ProfessionClick(b, btn)
    if btn == "RightButton" then return UI.OnProfessionOpenerClick(b, btn) end
    local p = b.prof
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    if base and base.professionID == p.skillLine and C_TradeSkillUI.IsTradeSkillReady() and not FP:IsReadOnly() then
        if ShowingProfession(p.skillLine) then UI.frame:Hide() else UI:Show("recipes") end
        return
    end
    UI.TabSound()
end

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
    else
        UI.FillWindowTip(tip, b.item.key)
        tip:AddLine(" ")
    end
    tip:AddLine(FP.db.quickButtonsLocked and L["Click to open or close."] or L["Click to open or close. Drag to move the buttons."],
        0.5, 0.8, 1, true)
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
            b = UI:Button(bar, "", SIZE, SIZE, function() UI.FooterWindows()[item.key]:Toggle() end)
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
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.count = UI:Text(b, 1, "RIGHT")
        b.count:SetPoint("BOTTOMRIGHT", -3, 3)
        b.count:SetTextColor(unpack(item.color))
        b.count:SetShadowOffset(1, -1)
        UI:Tooltip(b, "ANCHOR_TOP", Tooltip)
        self.buttons[i] = b
    end

    -- Profession buttons, given a profession each by Layout.
    self.profButtons = {}
    for i = 1, MAX_PROFESSIONS do
        local b = UI:Button(bar, "", SIZE, SIZE, ProfessionClick, "up")
        b:RegisterForClicks("AnyDown", "AnyUp")
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
        UI:Tooltip(b, "ANCHOR_TOP", Tooltip)
        b:Hide()
        self.profButtons[i] = b
    end
end

-- Rows of quickColumns buttons, filled from the growth corner: sideways first, then a new row up or down. The header
-- stays above the buttons, on the corner's side. Buttons switched off are left out; self.shown holds the rest.
function Launcher:Layout()
    -- Without Enchanting, the button lists gear to send your best enchanter instead, when you have one.
    self.enchanting = FindEnchanting()
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
        for _, p in ipairs(FP:GetProfessions()) do
            if n < MAX_PROFESSIONS and UI:HasCraftingWindow(p) then
                n = n + 1
                local b = self.profButtons[n]
                b.prof = p
                b.icon:SetTexture(p.icon)
                UI:SetProfessionOpener(b, p)
                b:Show()
                shown[#shown + 1] = b
            end
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
    local cols = math.min(db.quickColumns, n)
    local rows = math.ceil(n / cols)
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
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
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

function Launcher:Update()
    if InCombatLockdown() then
        self.afterCombat = true
        return
    end
    if not FP.db.quickButtons then
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
        local n = Count(b.item.key)
        b.count:SetText(n > 99 and "99+" or n > 0 and n or "")
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

-- Updates held back by combat run when it ends. Opening or closing a profession, or learning one, changes the
-- Disenchanting Mode button's cast (none while Enchanting is already open) or whether it shows.
FP:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    OnDragStop()
    -- Disarmed for combat, like the window's own profession buttons; re-armed by the update after it.
    if Launcher.bar then
        Launcher.deButton:SetAttribute("macrotext1", "")
        for _, b in ipairs(Launcher.profButtons) do b:SetAttribute("macrotext1", "") end
    end
    Launcher.afterCombat = true
end)
FP:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if Launcher.afterCombat then
        Launcher.afterCombat = false
        Launcher:Update()
    end
end)
-- TRADE_SKILL_LIST_UPDATE catches the profession becoming ready, which TRADE_SKILL_SHOW can come before.
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE", "SKILL_LINES_CHANGED" }) do
    FP:RegisterEvent(e, function()
        if Launcher.bar and Launcher.bar:IsShown() then Launcher:Update() end
    end)
end
