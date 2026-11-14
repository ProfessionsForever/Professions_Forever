local _, FP = ...
local L = FP.L
local UI = FP.UI

-- Shared by the crafting queue, transfer planner and shopping list windows: docked beside the main window (or the
-- mailbox or bank while the main window is closed), or pinned to the screen.

local panels, openCount = {}, 0 -- [key] = frame; counts dockings so panels stack in the order they were opened

-- A pinned side panel reopens at its saved screen position instead of docking to the main window.
local function SavePin(f)
    -- A docked panel's anchor is relative to the main window, so save its screen position instead.
    local x, y = f:GetLeft(), f:GetTop()
    if not (x and y) then return end
    FP.db.sidePanels[f.fpPanelKey] = { "TOPLEFT", "BOTTOMLEFT", x, y }
    f.floating, f.dockX = nil, nil
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local function RefreshPin(f)
    local b = f.pinBtn
    if not b then return end
    local c = FP.db.sidePanels[f.fpPanelKey] and UI:GetAccent() or { 1, 1, 1 }
    b.text:SetTextColor(c[1], c[2], c[3])
end

-- Docked panels sit beside the main window in two rows. A panel takes the leftmost free position, top row first: the
-- preferred order is column 1 top, column 1 bottom, column 2 top. A position starts GAP from the main window or GAP past
-- the right edge of an open panel, so a blocker never leaves a gap after it. Opening a panel moves nothing else;
-- closing or unpinning one reflows the docked panels, in the order they opened. Pinned and hand-dragged panels never
-- move and block whatever they cover.
--
-- Docked panels stay on the screen, whatever its size and UI scale (DockLayout): when two full-height rows don't fit
-- below the main window's top, both rows get shorter (the lists show fewer rows); when even short rows wouldn't leave
-- room for a useful list, there is one row. A position that would run off the right edge isn't used; when nothing is
-- left on screen, a panel docks over the right side of the main window instead.
local GAP = 6
local MIN_ROW_H = 300 -- shorter than this, two stacked panels would show too few rows: one row instead
local BASE_H = 460 -- the side panels' own height (UI:CreateSidePanel's o.height; Recipe Search is a little shorter)

-- {left, bottom, right, top} in screen pixels for a pinned panel, from its saved position.
local function PinnedRect(p)
    local pin = FP.db.sidePanels[p.fpPanelKey]
    if not pin then return end
    local s = p:GetEffectiveScale()
    return pin[3] * s, (pin[4] - p:GetHeight()) * s, (pin[3] + p:GetWidth()) * s, pin[4] * s
end

-- Where a panel the user dragged but did not pin currently sits.
local function FloatingRect(p)
    local l, b, w, h = p:GetRect()
    if not l then return end
    local s = p:GetEffectiveScale()
    return l * s, b * s, (l + w) * s, (b + h) * s
end

-- A docked panel's height: its own, or the row height when the rows had to be made shorter than BASE_H to fit.
local function DockedHeight(p, h)
    local base = p.fpBaseHeight or p:GetHeight()
    return h < BASE_H and math.min(base, h) or base
end

-- The same rectangle for `p` if it were docked x to the right of the main window (negative: over it), in this row.
local function SlotRect(main, p, x, row, h)
    local ms, ps = main:GetEffectiveScale(), p:GetEffectiveScale()
    local right, top = main:GetRight(), main:GetTop()
    if not (right and top) then return end
    local left = right * ms + x * ps
    local t = top * ms - row * (h + GAP) * ps
    return left, t - DockedHeight(p, h) * ps, left + p:GetWidth() * ps, t
end

-- The screen's right edge, in the same screen pixels as the rectangles.
local function ScreenRight() return UIParent:GetRight() * UIParent:GetEffectiveScale() end

local function Overlap(a, b)
    return a[1] < b[3] - 2 and b[1] < a[3] - 2 and a[2] < b[4] - 2 and b[2] < a[4] - 2
end

-- The docked rows' height and how many rows there are, from the room between the main window's top and the bottom of
-- the screen: two full rows when they fit, else two shorter ones, else one.
local function DockLayout(main)
    local top = main:GetTop()
    if not top then return BASE_H, 2 end
    local room = top * main:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if 2 * BASE_H + GAP <= room then return BASE_H, 2 end
    local half = math.floor((room - GAP) / 2)
    if half >= MIN_ROW_H then return half, 2 end
    return math.min(BASE_H, math.floor(room)), 1
end

-- Pinned and hand-dragged panels stay put; every other open panel is docked.
local function IsDocked(q)
    return not (q.floating or FP.db.sidePanels[q.fpPanelKey])
end

-- Screen rectangles of the other open panels that don't move: pinned or dragged, plus docked ones unless fixedOnly.
local function BlockedRects(main, except, h, fixedOnly)
    local blocked = {}
    for _, q in pairs(panels) do
        if q ~= except and q:IsShown() then
            local l, b, r, t
            if not IsDocked(q) then
                if q.floating then l, b, r, t = FloatingRect(q) else l, b, r, t = PinnedRect(q) end
            elseif not fixedOnly and q.dockX then
                l, b, r, t = SlotRect(main, q, q.dockX, q.dockRow, h)
            end
            if l then blocked[#blocked + 1] = { l, b, r, t } end
        end
    end
    return blocked
end

local function Free(rect, blocked)
    for _, other in ipairs(blocked) do
        if Overlap(rect, other) then return false end
    end
    return true
end

-- The leftmost free position for `p` (top row first at equal x) as an offset from the main window and a row: beside
-- the main window while it stays on the screen, else over the main window's right side, then further left over it.
local function FirstFreeSlot(main, p, h, rows, blocked)
    local right = main:GetRight()
    if not (right and main:GetTop()) then return GAP, 0 end
    local ms, ps = main:GetEffectiveScale(), p:GetEffectiveScale()
    local xs = { GAP }
    for _, rect in ipairs(blocked) do
        local x = (rect[3] - right * ms) / ps + GAP
        if x > GAP then xs[#xs + 1] = x end
    end
    table.sort(xs)
    local edge = ScreenRight()
    for _, x in ipairs(xs) do
        for row = 0, rows - 1 do
            local l, b, r, t = SlotRect(main, p, x, row, h)
            if r > edge + 2 then break end -- off the screen: so is everything further right
            if Free({ l, b, r, t }, blocked) then return x, row end
        end
    end
    -- No room beside it: over the main window, its right side first.
    local step = p:GetWidth() + GAP
    for k = 1, 3 do
        for row = 0, rows - 1 do
            local l, b, r, t = SlotRect(main, p, -k * step, row, h)
            if Free({ l, b, r, t }, blocked) then return -k * step, row end
        end
    end
    return -step, 0
end

-- What docked panels sit beside: the main window while it is shown, else the game's open mailbox or bank (the Transfer
-- Planner opens at either by itself), else where the main window would be. Opening or closing any of them re-docks the
-- panels (see the events below); the main window closing closes them anyway (UI:CloseSidePanels).
-- Bag addons' bank windows come before the game's, which they may leave shown but out of sight.
local BANK_FRAMES = { "EUI_BankFrame", "BankFrame" } -- EllesmereUI Bags, then the game's
local function DockHost()
    local main = UI.frame
    if main and main:IsShown() then return main end
    if MailFrame and MailFrame:IsShown() then return MailFrame end
    for _, name in ipairs(BANK_FRAMES) do
        local bank = _G[name]
        if bank and bank:IsShown() then return bank end
    end
    return main
end

-- The main window and the side panels share a strata and are all toplevel, so whichever was clicked last is on top.
-- A panel docked over the main window has to stay above it even after the main window is clicked (opening a panel
-- from its footer does that), so it goes one strata up; panels beside it, pinned or dragged stay with the main window.
local function SetOverMain(f, over)
    local strata = over and "HIGH" or "MEDIUM"
    if f:GetFrameStrata() == strata then return end
    f:SetFrameStrata(strata)
    f:SetFrameLevel(UI.WINDOW_LEVEL)
end

local function AnchorDocked(f, host, x, row, h)
    f.dockHost, f.dockX, f.dockRow, f.dockH = host, x, row, h
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", host, "TOPRIGHT", x, -row * (h + GAP))
    f:SetHeight(DockedHeight(f, h))
    SetOverMain(f, x < 0)
end

-- Opens a panel: pinned ones at their saved spot, others in the first free slot without moving any other panel.
function UI:PlaceSidePanel(f)
    f:ClearAllPoints()
    f.floating, f.dockX = nil, nil
    local pin = FP.db.sidePanels[f.fpPanelKey]
    if pin then
        f:SetHeight(f.fpBaseHeight)
        SetOverMain(f, false)
        f:SetPoint(pin[1], UIParent, pin[2], pin[3], pin[4])
        RefreshPin(f)
        return
    end
    RefreshPin(f)
    local host = DockHost()
    if not host then return f:SetPoint("CENTER") end
    openCount = openCount + 1
    f.dockSeq = openCount
    local h, rows = DockLayout(host)
    local x, row = FirstFreeSlot(host, f, h, rows, BlockedRects(host, f, h))
    AnchorDocked(f, host, x, row, h)
end

-- Re-packs the open docked panels, in the order they opened, into the earliest positions the fixed panels leave free.
-- Safe to call at any time: a panel is only re-anchored when its position or height changes. Run when a panel closes
-- or is unpinned, when the main window moves or changes scale, when it, the mailbox or the bank opens or closes (they
-- can change what the panels dock to), and when the screen or UI scale changes.
function UI:ReflowSidePanels()
    local main = DockHost()
    if not main then return end
    local docked = {}
    for _, p in pairs(panels) do
        if p:IsShown() and IsDocked(p) then
            if not p.dockSeq then openCount = openCount + 1 p.dockSeq = openCount end
            docked[#docked + 1] = p
        end
    end
    table.sort(docked, function(a, b) return a.dockSeq < b.dockSeq end)
    local h, rows = DockLayout(main)
    local blocked = BlockedRects(main, nil, h, true)
    for _, p in ipairs(docked) do
        local x, row = FirstFreeSlot(main, p, h, rows, blocked)
        if not (p.dockHost == main and p.dockX and math.abs(p.dockX - x) < 0.5 and p.dockRow == row and p.dockH == h)
            and not UI.CombatBlocked(p) then
            AnchorDocked(p, main, x, row, h)
        end
        local l, b, r, t = SlotRect(main, p, p.dockX, p.dockRow, h)
        if l then blocked[#blocked + 1] = { l, b, r, t } end
    end
end

local reflowPending
local function ScheduleReflow()
    if reflowPending then return end
    reflowPending = true
    C_Timer.After(0, function()
        reflowPending = false
        UI:ReflowSidePanels()
    end)
end

-- A new screen size or UI scale changes the room the docked panels have; the mailbox or bank opening or closing can
-- change what they dock to (a frame later, once the game has shown or hidden its window).
for _, e in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "MAIL_SHOW", "MAIL_CLOSED", "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED" }) do
    FP:RegisterEvent(e, ScheduleReflow)
end
UI.ScheduleSidePanelReflow = ScheduleReflow

-- Hides the docked side panels; pinned ones stay open.
function UI:CloseSidePanels()
    for _, p in pairs(panels) do
        if not FP.db.sidePanels[p.fpPanelKey] and not UI.CombatBlocked(p) then p:Hide() end
    end
end

-- key names the panel in the saved pin positions.
function UI:MakeSidePanelDraggable(f, key)
    f.fpPanelKey = key
    panels[key] = f
    f:SetFrameLevel(UI.WINDOW_LEVEL)
    f:HookScript("OnHide", function(s)
        s.dockSeq, s.dockX, s.floating, s.fpOpenedBy = nil, nil, nil, nil
        UI:RefreshFooterSelection()
        ScheduleReflow()
    end)
    f:HookScript("OnShow", function() UI:RefreshFooterSelection() end)
    f:SetScript("OnDragStart", function(s)
        s.floating, s.dockX = true, nil
        s:SetHeight(s.fpBaseHeight) -- a panel dragged away from the dock gets its full height back
        SetOverMain(s, false)
        s:StartMoving()
    end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        if FP.db.sidePanels[key] then SavePin(s) end
    end)
end

function UI:AddPinButton(f, closeButton)
    local b = self:Button(f, L["Pin"], 40, 20, function()
        local pins = FP.db.sidePanels
        if pins[f.fpPanelKey] then
            pins[f.fpPanelKey] = nil
            UI:ReflowSidePanels()
        else
            SavePin(f)
            f.fpOpenedBy = nil -- pinned: kept open when the window that opened it closes
        end
        RefreshPin(f)
    end)
    b:SetPoint("RIGHT", closeButton, "LEFT", -4, 0)
    self:Tooltip(b, "ANCHOR_BOTTOM", function(tip)
        tip:AddLine(FP.db.sidePanels[f.fpPanelKey] and L["Unpin (Dock to Main Window)"] or L["Pin Position"], 1, 1, 1)
    end)
    f.pinBtn = b
    RefreshPin(f)
    return b
end

---------------------------------------------------------------------------
-- Building, opening and closing a side panel
---------------------------------------------------------------------------
-- The window every side panel starts from: named so Escape closes it, skinned, draggable and pinnable under o.key,
-- with its title and its close and pin buttons. Returns the frame and the close button.
-- o: name, key, title, width, height, onShow(f), onHide(f), openSound, closeSound (default: the quest log's).
function UI:CreateSidePanel(o)
    local f = CreateFrame("Frame", o.name, UIParent, "BackdropTemplate")
    f:Hide() -- frames start shown, which would skip OnShow and leave unpopulated rows visible
    f:SetSize(o.width, o.height)
    f.fpBaseHeight = o.height -- docked panels can be shorter (DockLayout); pinned and dragged ones get this back
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    self:Skin(f, "window")
    tinsert(UISpecialFrames, o.name)
    local openSound = o.openSound or SOUNDKIT.IG_QUEST_LIST_OPEN
    local closeSound = o.closeSound or SOUNDKIT.IG_QUEST_LIST_CLOSE
    f:SetScript("OnShow", function(s)
        PlaySound(openSound)
        if o.onShow then o.onShow(s) end
    end)
    f:SetScript("OnHide", function(s)
        PlaySound(closeSound)
        if o.onHide then o.onHide(s) end
    end)
    -- After the scripts are set: it hooks OnShow and OnHide, and setting a script later would drop those hooks.
    self:MakeSidePanelDraggable(f, o.key)

    local title = self:Text(f, 2)
    title:SetPoint("LEFT", f, "TOPLEFT", 12, -UI.TITLE_H / 2)
    title:SetText(o.title)
    title:SetTextColor(1, 0.82, 0)
    local close = self:Button(f, "X", 22, 20, function() f:Hide() end)
    close:SetPoint("RIGHT", f, "TOPRIGHT", -6, -UI.TITLE_H / 2)
    self:AddPinButton(f, close)
    return f, close
end

-- A side panel's scrolling list: up to o.rows rows of o.rowH from o.top below the window's top edge, the list ending
-- o.bottom above its bottom edge, with the thin scrollbar and mouse-wheel scrolling. Sets f.scroll and f.rows. A docked
-- panel can be shorter than its own height, so only the rows that fit are used: UI.PanelRows(f) says how many, and the
-- list redraws when the height changes.
-- o: name (of the scroll frame), top, bottom, rows, rowH, update(), build(row, i) adds a row's own widgets,
--    rowBg (rows get a background texture to show on header rows), tooltip(row) (fills GameTooltip;
--    returning false shows none), onClick(row, button), rightClick (rows also take right clicks).
function UI:AddPanelList(f, o)
    local rowH, top = o.rowH, o.top
    local scroll = CreateFrame("ScrollFrame", o.name, f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -top)
    scroll:SetPoint("BOTTOMRIGHT", -self.BAR_GUTTER, o.bottom)
    scroll:SetScript("OnVerticalScroll", function(s, offset)
        FauxScrollFrame_OnVerticalScroll(s, offset, rowH, o.update)
    end)
    f.scroll = scroll
    self:AttachScrollbar(scroll, scroll.ScrollBar or _G[o.name .. "ScrollBar"], f, { top = top, bottom = o.bottom })

    f.rows = {}
    for i = 1, o.rows do
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(rowH)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -top - (i - 1) * rowH)
        row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -self.BAR_GUTTER, -top - (i - 1) * rowH)
        if o.rowBg then
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.bg:SetColorTexture(1, 1, 1, 0.07)
        end
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 1, 1, 0.08)
        if o.tooltip then
            row:SetScript("OnEnter", function(s)
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                if o.tooltip(s) == false then GameTooltip:Hide() return end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        if o.rightClick then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
        if o.onClick then row:SetScript("OnClick", o.onClick) end
        o.build(row, i)
        f.rows[i] = row
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        scroll.fpScrollTo(scroll:GetVerticalScroll() - delta * rowH * 3)
    end)
    f.fpListFit = function()
        f.fpVisibleRows = math.max(1, math.min(o.rows, math.floor((f:GetHeight() - top - o.bottom) / rowH)))
    end
    f.fpListFit()
    f:HookScript("OnSizeChanged", function(s)
        local before = s.fpVisibleRows
        s.fpListFit()
        if s.fpVisibleRows ~= before and s:IsShown() then o.update() end
    end)
end

-- How many list rows fit in side panel `f` at its current height (see UI:AddPanelList). Rows past it stay hidden.
function UI.PanelRows(f) return f.fpVisibleRows end

-- Shows a side panel (a table with a frame and Create), building its window on first use.
function UI:ShowSidePanel(panel)
    if not panel.frame then panel:Create() end
    if not panel.frame:IsShown() then
        self:PlaceSidePanel(panel.frame)
        panel.frame:Show()
    end
end

-- A panel opened because a game window opened (the Transfer Planner at a mailbox or bank) closes with that window.
-- `reason` names it ("mail", "bank"). A panel that was already open is left alone and isn't tied to it; pinning it, or
-- closing it, unties it.
function UI:OpenSidePanelFor(panel, reason)
    if panel.frame and panel.frame:IsShown() then return end
    panel:Open()
    panel.frame.fpOpenedBy = reason
end

function UI:CloseSidePanelsOpenedBy(reason)
    for _, p in pairs(panels) do
        if p.fpOpenedBy == reason and p:IsShown() and not UI.CombatBlocked(p) then p:Hide() end
    end
end

-- The game windows themselves say when they close: on WoW: Forever MAIL_CLOSED doesn't reliably arrive (seen
-- 2026-11-13: a planner opened by the mailbox stayed open). So their OnShow and OnHide re-dock the panels, and OnHide
-- closes what they opened. The events stay as well; doing either twice changes nothing. A bag addon's bank window is
-- hooked once it exists (EllesmereUI creates its own at load).
local function WatchGameWindow(frame, reason)
    if not frame or frame.fpWatched then return end
    frame.fpWatched = true
    -- The Transfer Planner's Withdraw and Collect buttons follow the bank and the mailbox.
    local changed = reason == "mail" and "sends" or "inventory"
    frame:HookScript("OnShow", function()
        UI.ScheduleSidePanelReflow()
        FP:Changed(changed)
    end)
    frame:HookScript("OnHide", function()
        UI:CloseSidePanelsOpenedBy(reason)
        UI.ScheduleSidePanelReflow()
        FP:Changed(changed)
    end)
end

FP:RegisterEvent("PLAYER_LOGIN", function()
    WatchGameWindow(_G.MailFrame, "mail")
    WatchGameWindow(_G.BankFrame, "bank")
    WatchGameWindow(_G.EUI_BankFrame, "bank")
end)

-- Every side panel's Toggle: Panel.Toggle = UI.ToggleSidePanel.
function UI.ToggleSidePanel(panel)
    if panel.frame and panel.frame:IsShown() then panel.frame:Hide() else panel:Open() end
end

---------------------------------------------------------------------------
-- Window buttons
---------------------------------------------------------------------------
-- The same row in the crafting queue, transfer planner and shopping list: a button for each of the three, lit while
-- its window is open, each opening or closing its window like the footer cells do (the window it sits in included).
local NAV = { { "queue", "Crafting Queue" }, { "transfer", "Transfer Planner" }, { "shop", "Shopping List" } }
local NAV_GAP = 6
local navRows = {}

local function NavPanel(key) return key == "queue" and FP.Queue or key == "transfer" and FP.Transfer or FP.Shop end

-- Lights each button whose window is open; run whenever a side panel opens or closes (UI:RefreshFooterSelection).
function UI:SyncWindowButtons()
    for _, row in ipairs(navRows) do
        for _, b in ipairs(row) do
            local panel = NavPanel(b.key)
            UI.SetSelected(b, panel.frame ~= nil and panel.frame:IsShown())
        end
    end
end

-- Adds the row to side panel `f`, `y` above its bottom edge, the three buttons sharing its width.
function UI:AddWindowButtons(f, y)
    local row, w = {}, (f:GetWidth() - 28 - 2 * NAV_GAP) / 3
    for i, n in ipairs(NAV) do
        local key = n[1]
        local b = self:Button(f, L[n[2]], w, 24, function() NavPanel(key):Toggle() end)
        b.key = key
        b:SetPoint("BOTTOMLEFT", 14 + (i - 1) * (w + NAV_GAP), y)
        row[i] = b
    end
    navRows[#navRows + 1] = row
    self:SyncWindowButtons()
    return row
end
