local _, FP = ...
local L = FP.L
local UI = FP.UI

-- Shared by the crafting queue, transfer planner and shopping list windows: docked beside the main window, or pinned to the screen.

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
local ROWS, GAP = 2, 6

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

-- The same rectangle for `p` if it were docked x to the right of the main window, in this row.
local function SlotRect(main, p, x, row, h)
    local ms, ps = main:GetEffectiveScale(), p:GetEffectiveScale()
    local right, top = main:GetRight(), main:GetTop()
    if not (right and top) then return end
    local left = right * ms + x * ps
    local t = top * ms - row * (h + GAP) * ps
    return left, t - p:GetHeight() * ps, left + p:GetWidth() * ps, t
end

local function Overlap(a, b)
    return a[1] < b[3] - 2 and b[1] < a[3] - 2 and a[2] < b[4] - 2 and b[2] < a[4] - 2
end

local function SlotHeight()
    local q = panels.queue
    return q and q:GetHeight() or 460
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

-- The leftmost free position for `p` (top row first at equal x) as an offset from the main window and a row.
local function FirstFreeSlot(main, p, h, blocked)
    local right = main:GetRight()
    if not (right and main:GetTop()) then return GAP, 0 end
    local ms, ps = main:GetEffectiveScale(), p:GetEffectiveScale()
    local xs = { GAP }
    for _, rect in ipairs(blocked) do
        local x = (rect[3] - right * ms) / ps + GAP
        if x > GAP then xs[#xs + 1] = x end
    end
    table.sort(xs)
    for _, x in ipairs(xs) do
        for row = 0, ROWS - 1 do
            local l, b, r, t = SlotRect(main, p, x, row, h)
            local free = true
            for _, rect in ipairs(blocked) do
                if Overlap({ l, b, r, t }, rect) then free = false break end
            end
            if free then return x, row end
        end
    end
end

local function AnchorDocked(f, x, row, h)
    f.dockX, f.dockRow = x, row
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UI.frame, "TOPRIGHT", x, -row * (h + GAP))
end

-- Opens a panel: pinned ones at their saved spot, others in the first free slot without moving any other panel.
function UI:PlaceSidePanel(f)
    f:ClearAllPoints()
    f.floating, f.dockX = nil, nil
    local pin = FP.db.sidePanels[f.fpPanelKey]
    if pin then
        f:SetPoint(pin[1], UIParent, pin[2], pin[3], pin[4])
        RefreshPin(f)
        return
    end
    RefreshPin(f)
    if not self.frame then return f:SetPoint("CENTER") end
    openCount = openCount + 1
    f.dockSeq = openCount
    local h = SlotHeight()
    local x, row = FirstFreeSlot(self.frame, f, h, BlockedRects(self.frame, f, h))
    AnchorDocked(f, x, row, h)
end

-- Re-packs the open docked panels, in the order they opened, into the earliest positions the fixed panels leave free.
-- Safe to call at any time: a panel is only re-anchored when its position changes.
function UI:ReflowSidePanels()
    local main = self.frame
    if not main then return end
    local docked = {}
    for _, p in pairs(panels) do
        if p:IsShown() and IsDocked(p) then
            if not p.dockSeq then openCount = openCount + 1 p.dockSeq = openCount end
            docked[#docked + 1] = p
        end
    end
    table.sort(docked, function(a, b) return a.dockSeq < b.dockSeq end)
    local h = SlotHeight()
    local blocked = BlockedRects(main, nil, h, true)
    for _, p in ipairs(docked) do
        local x, row = FirstFreeSlot(main, p, h, blocked)
        if not (p.dockX and math.abs(p.dockX - x) < 0.5 and p.dockRow == row) and not UI.CombatBlocked(p) then
            AnchorDocked(p, x, row, h)
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
        s.dockSeq, s.dockX, s.floating = nil, nil, nil
        UI:RefreshFooterSelection()
        ScheduleReflow()
    end)
    f:HookScript("OnShow", function() UI:RefreshFooterSelection() end)
    f:SetScript("OnDragStart", function(s)
        s.floating, s.dockX = true, nil
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
