local _, FP = ...
local L = FP.L
local UI = FP.UI
local RecipeRowHeight = UI.RecipeRowHeight

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
UI.search = ""
UI.filtered = {}
UI.categoryName = nil -- category name filter (slot, armor type...)
UI.display = {}
UI.rows = {}
UI.numRows = 10

-- Rows that fit in the recipe list for a window `height` tall; the rest is the header, filter bar and margins.
function UI:SetNumRows(height)
    self.numRows = math.max(1, math.floor((height - 192 - self:FooterReserve()) / RecipeRowHeight()))
end

function UI:QueueRefresh()
    FP.Launcher:QueueUpdate()
    if self.pending or not self.frame or not self.frame:IsShown() then return end
    self.pending = true
    C_Timer.After(0.1, function()
        self.pending = false
        self:Refresh()
    end)
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    FP.Recipes:ResetEvalCache()
    self:RefreshProfessions()
    self:UpdateExtraSpellButtons()
    self:RefreshFilter()
    self:UpdateList()
    if self.scrollToSelected then
        self.scrollToSelected = false
        self:ScrollToSelected()
    end
    self:UpdateDetail()
    self:RefreshOverview()
    self:RefreshFooter()
end

function UI:Show(page)
    if self.frame and not self.frame:IsShown() and self.CombatBlocked(self.frame) then
        return FP:Print(L["Cannot do that in combat."])
    end
    -- New frames start shown, so IsShown() can't detect the first open.
    local new = not self.frame
    -- A new frame starts shown, so its OnShow never runs: move panels opened before it over from its stand-in.
    if new then self:Create() self.ScheduleSidePanelReflow() end
    local opening = new or not self.frame:IsShown()
    if opening then
        FP.Recipes:Reload()
        self.frame:Show()
    end
    if not self.stationTicker then self.stationTicker = C_Timer.NewTicker(0.75, function() UI:PollStations() end) end
    if page or new then self:SetPage(page or "overview") end
    if opening then
        PlaySound(self.page == "overview" and SOUNDKIT.IG_SPELLBOOK_OPEN or SOUNDKIT.IG_CHARACTER_INFO_OPEN)
    end
    self:Refresh()
end

function UI:OnTradeSkillClosed()
    -- The overview and another character's profession have no trade skill open, so a close event isn't about them.
    if self.page == "overview" or FP.AltProfs.viewing then return end
    if self.frame and self.frame:IsShown() and not self.CombatBlocked(self.frame) then
        self.closing = true
        self.frame:Hide()
        self.closing = false
    end
end

function UI:ResetWindow()
    local db, d = FP.db, FP.defaults
    db.point, db.relPoint, db.x, db.y, db.width, db.height = d.point, d.relPoint, d.x, d.y, d.width, d.height
    if self.frame then
        self.frame:ClearAllPoints()
        self.frame:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
        self.frame:SetSize(db.width, db.height + self:FooterExtra())
    end
    self:SetScale(1)
end

UI.SCALE_MIN, UI.SCALE_MAX = 0.6, 1.6

-- The one place the window scale changes, so Ctrl+wheel and the options slider stay in step.
function UI:SetScale(scale)
    FP.db.scale = math.max(UI.SCALE_MIN, math.min(UI.SCALE_MAX, math.floor(scale * 20 + 0.5) / 20))
    if self.frame then self.frame:SetScale(FP.db.scale) end
    self:ReflowSidePanels() -- its top moved on the screen: docked panels may need other heights or places
    FP.Options:Refresh()
end

---------------------------------------------------------------------------
-- Frame construction
---------------------------------------------------------------------------
-- The saved height leaves out a second footer row, which the window adds while the footer has one.
local function SavePosition(f)
    local db = FP.db
    local point, _, relPoint, x, y = f:GetPoint()
    db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
    db.width, db.height = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() - UI:FooterExtra() + 0.5)
end

-- How far the window can be resized; a second footer row raises both heights by its own.
function UI:SetWindowBounds()
    local extra = self:FooterExtra()
    self.frame:SetResizeBounds(920, 640 + extra, 1500, 1000 + extra)
end

function UI:Create()
    local db = FP.db
    local f = CreateFrame("Frame", "ProfessionsForeverFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(db.width, db.height)
    f:SetPoint(db.point, UIParent, db.relPoint or db.point, db.x, db.y)
    f:SetScale(db.scale)
    f:SetFrameStrata("MEDIUM") -- same strata as Blizzard's panels; toplevel raises it on click
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    self:SetWindowBounds()
    self:Skin(f, "window")
    tinsert(UISpecialFrames, "ProfessionsForeverFrame")
    UI.CloseInCombat(f)
    f:SetFrameLevel(UI.WINDOW_LEVEL)
    f:SetScript("OnHide", function()
        if UI.stationTicker then UI.stationTicker:Cancel() UI.stationTicker = nil end
        UI.CloseMenu()
        UI:CloseSidePanels()
        UI:SetDisenchantMode(false)
        UI:ResetCraftQty()
        FP.AltProfs:Stop()
        UI.overviewChar = nil
        PlaySound(UI.page == "overview" and SOUNDKIT.IG_SPELLBOOK_CLOSE or SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
        -- With the replacement off, Blizzard's window shares this trade skill, so leave it open.
        if not UI.closing and FP.db.replaceDefault then C_TradeSkillUI.CloseTradeSkill() end
    end)

    -- Docked side panels move over from the mailbox or bank to the main window when it opens there.
    f:HookScript("OnShow", function() UI.ScheduleSidePanelReflow() end)

    self:CreateTitleBar(f)
    self:CreateHeader(f)
    self:CreateRecipePanel(f)
    self:CreateDetailPanel(f)
    self:CreateResizeGrip(f)
    self:CreateOverview()
    self:CreateFooter(f)
    self:ApplySkin()
end

-- Title bar (drag to move, Ctrl+wheel to scale)
function UI:CreateTitleBar(f)
    local tb = CreateFrame("Frame", "ProfessionsForeverTitleBar", f)
    tb:SetPoint("TOPLEFT", 4, -2)
    tb:SetPoint("TOPRIGHT", -4, -2)
    tb:SetHeight(UI.TITLE_H - 4)
    tb:EnableMouse(true)
    tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function() if not FP.db.locked then f:StartMoving() end end)
    tb:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        SavePosition(f)
        UI:ReflowSidePanels() -- the room below and beside it changed
    end)
    tb:EnableMouseWheel(true)
    tb:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown() and not FP.db.locked then UI:SetScale(FP.db.scale + delta * 0.05) end
    end)
    f.title = self:Text(tb, 2)
    f.titleBar = tb
    f.title:SetPoint("LEFT", tb, "LEFT", 8, 0)
    f.title:SetJustifyH("CENTER")
    f.title:SetText("ProfessionsForever")
    f.title:SetTextColor(1, 0.82, 0)

    local close = self:Button(tb, "X", 22, 20, function() FP:Close() end)
    close:SetPoint("RIGHT", -2, 0)
    local opts = self:Button(tb, "", 22, 20, function() FP.Options:Toggle() end)
    opts:SetPoint("RIGHT", close, "LEFT", -4, 0)
    local gear = opts:CreateTexture(nil, "ARTWORK")
    gear:SetSize(14, 14)
    gear:SetPoint("CENTER")
    gear:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    self:Tooltip(opts, "ANCHOR_BOTTOM", L["Options"])
    local reagents = FP.ReagentSearch:CreateButton(tb, 20)
    reagents:SetPoint("RIGHT", opts, "LEFT", -4, 0)
    f.leftButton = reagents
    f.clearWay = self:Button(tb, L["Clear Waypoint"], 110, 20, function() FP.Waypoint:Clear() end)
    f.clearWay:SetPoint("RIGHT", reagents, "LEFT", -4, 0)
    f.clearWay:SetShown(FP.Waypoint:HasActive())
    self:Tooltip(f.clearWay, "ANCHOR_BOTTOM", function(tip)
        tip:AddLine(L["Clear Waypoint"])
        tip:AddLine(L["Removes the waypoint ProfessionsForever set in Polestar or TomTom. It also clears itself when you arrive."], 1, 1, 1, true)
    end)
    f.title:SetPoint("RIGHT", f.clearWay, "LEFT", -4, 0)
end

-- Resize grip, and the re-layout while resizing.
function UI:CreateResizeGrip(f)
    local grip = CreateFrame("Button", "ProfessionsForeverResizeGrip", f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    local function Relayout()
        UI:SetNumRows(f:GetHeight())
        UI:UpdateList()
        UI:UpdateDetail()
        UI:RefreshProfessions()
        UI:LayoutOverview()
        UI:LayoutFooter()
    end
    grip:SetScript("OnMouseDown", function()
        f.resizing = true
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        f.resizing = false
        SavePosition(f)
        Relayout()
    end)
    f.grip = grip

    -- While the grip is held this fires every frame, so only sizes and positions change then (the list redraws only
    -- when a row is gained or lost); the full refresh follows on release. Other size changes refresh at once.
    f:SetScript("OnSizeChanged", function(_, _, h)
        if not f.resizing then return Relayout() end
        local rows = UI.numRows
        UI:SetNumRows(h)
        if UI.numRows ~= rows then UI:UpdateList() end
        UI:LayoutDetail()
        UI:LayoutProfessionBar()
        UI:LayoutOverview()
        UI:LayoutFooter()
    end)
    UI:SetNumRows(FP.db.height)
    UI:ApplyLock()
end

-- A locked window can't be moved, resized or scaled by the mouse; the resize grip is hidden.
function UI:ApplyLock()
    local f = self.frame
    if f and f.grip then f.grip:SetShown(not FP.db.locked) end
end
