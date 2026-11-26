--[[
ThreeLightsLib: thin scrollbars (UI:AttachScrollbar, UI:RowScrollbar). Taken from ProfessionsForever.

A 4-pixel track and thumb at the right edge, shown only when the content overflows, with a wider invisible grab area
on the thumb. Two kinds:
  UI:AttachScrollbar  for a scroll frame: smooth wheel scrolling by pixels, and it retires the template's own bar.
                      Either the frame has a scroll child (a text box, a reading pane), or the caller draws what
                      shows itself, following the scroll offset, and tells the bar how much overflows.
  UI:RowScrollbar     for content the caller draws a row at a time (lists, boxes of cards): the caller keeps the
                      offset in rows and the bar shows and drags it.
]]
local _, ns = ...
local UI = ns.UI

local STEP, THUMB_MIN, TRACK_W, HIT_W, RIGHT_INSET = 45, 30, 4, 14, 2

-- How far rows and scroll frames stop short of the right edge, leaving the bar's column clear.
UI.BAR_GUTTER = RIGHT_INSET + TRACK_W + 4

-- The track inside `parent` (insets { top, bottom }) and its thumb. track.SetBottom(b) moves the track's bottom inset.
local function NewBar(parent, insets)
    insets = insets or {}
    local top = insets.top or 4
    local bottom = insets.bottom or top
    local track = CreateFrame("Frame", nil, parent)
    track:SetWidth(TRACK_W)
    track:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -RIGHT_INSET, -top)
    track:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -RIGHT_INSET, bottom)
    track.SetBottom = function(b) track:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -RIGHT_INSET, b) end
    track:SetFrameLevel(parent:GetFrameLevel() + 5)
    track:Hide()
    local bg = track:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.02)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(HIT_W)
    thumb:SetFrameLevel(track:GetFrameLevel() + 1)
    local grip = thumb:CreateTexture(nil, "ARTWORK")
    grip:SetPoint("TOPRIGHT")
    grip:SetPoint("BOTTOMRIGHT")
    grip:SetWidth(TRACK_W)
    grip:SetColorTexture(1, 1, 1, 0.27)
    thumb:SetScript("OnEnter", function() grip:SetColorTexture(1, 1, 1, 0.45) end)
    thumb:SetScript("OnLeave", function() grip:SetColorTexture(1, 1, 1, 0.27) end)
    return track, thumb
end

-- Places the thumb for a view `view` tall over content that overflows by `over`, scrolled `at` (same units).
local function PlaceThumb(track, thumb, view, over, at)
    if over <= 0 then
        track:Hide()
        return
    end
    track:Show()
    local trackH = track:GetHeight()
    local thumbH = math.max(THUMB_MIN, trackH * view / (view + over))
    thumb:SetHeight(thumbH)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -(at / over * (trackH - thumbH)))
end

-- Dragging the thumb: onMove(fraction) with 0 at the top and 1 at the bottom of its travel.
local function DragThumb(track, thumb, onMove, onStart)
    thumb:SetScript("OnMouseDown", function(s, button)
        if button ~= "LeftButton" then return end
        local startFrac = onStart()
        local _, startY = GetCursorPosition()
        startY = startY / s:GetEffectiveScale()
        s:SetScript("OnUpdate", function(self)
            if not IsMouseButtonDown("LeftButton") then self:SetScript("OnUpdate", nil) return end
            local travel = track:GetHeight() - self:GetHeight()
            if travel <= 0 then return end
            local _, y = GetCursorPosition()
            onMove(math.max(0, math.min(1, startFrac + (startY - y / self:GetEffectiveScale()) / travel)))
        end)
    end)
    thumb:SetScript("OnMouseUp", function(s) s:SetScript("OnUpdate", nil) end)
end

---------------------------------------------------------------------------
-- Replaces a scroll frame's template bar with a thin one. `nativeBar` is the template bar to retire (or nil),
-- `trackParent` holds the track (default the scroll frame), `insets` is { top, bottom } inside it, and `child` is the
-- scroll child. Without a child the caller draws what shows at each scroll offset, and calls scroll.barSetRange(extra)
-- with the height that overflows after each layout.
-- scroll.barScrollTo(v) scrolls at once; scroll.barSetBottom(b) moves the track's bottom inset, for a frame whose
-- bottom edge moves.
---------------------------------------------------------------------------
function UI:AttachScrollbar(scroll, nativeBar, trackParent, insets, child)
    local track, thumb = NewBar(trackParent or scroll, insets)
    scroll.barSetBottom = track.SetBottom
    local range = child
    if not range then
        range = CreateFrame("Frame", nil, scroll)
        range:SetSize(1, 1)
        range:Hide()
    end

    local function MaxScroll() return math.max(0, range:GetHeight() - scroll:GetHeight()) end
    local function UpdateThumb()
        PlaceThumb(track, thumb, scroll:GetHeight(), MaxScroll(), scroll:GetVerticalScroll())
    end
    track:SetScript("OnSizeChanged", UpdateThumb)

    -- The smoothing frame only runs (and is shown) while the scroll position eases toward its target.
    local target, smoothing = 0, false
    local smoother = CreateFrame("Frame", nil, scroll)
    smoother:Hide()
    local function Stop()
        smoothing = false
        smoother:Hide()
    end
    local function Set(v)
        scroll:SetVerticalScroll(v)
        UpdateThumb()
    end
    smoother:SetScript("OnUpdate", function(_, elapsed)
        local cur = scroll:GetVerticalScroll()
        target = math.max(0, math.min(MaxScroll(), target))
        local diff = target - cur
        if math.abs(diff) < 0.3 then
            Stop()
            Set(target)
            return
        end
        Set(cur + diff * math.min(1, 12 * elapsed))
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(s, delta)
        local maxScroll = MaxScroll()
        if maxScroll <= 0 then return end
        local base = smoothing and target or s:GetVerticalScroll()
        target = math.max(0, math.min(maxScroll, base - delta * STEP))
        if not smoothing then
            smoothing = true
            smoother:Show()
        end
    end)

    DragThumb(track, thumb, function(frac)
        target = frac * MaxScroll()
        Set(target)
    end, function()
        Stop()
        local m = MaxScroll()
        return m > 0 and scroll:GetVerticalScroll() / m or 0
    end)

    scroll:HookScript("OnScrollRangeChanged", UpdateThumb)
    scroll:HookScript("OnVerticalScroll", UpdateThumb)

    scroll.barScrollTo = function(v)
        Stop()
        target = math.max(0, math.min(MaxScroll(), v))
        Set(target)
    end
    if not child then
        scroll.barSetRange = function(extra)
            -- With nothing to scroll the range must be strictly below the view, or float rounding leaves a sliver of
            -- range and the bar stays.
            if extra > 0 then
                range:SetHeight(scroll:GetHeight() + extra)
            else
                range:SetHeight(1)
                scroll.barScrollTo(0)
            end
            UpdateThumb()
        end
    end

    if nativeBar then
        nativeBar:EnableMouse(false)
        nativeBar:HookScript("OnShow", nativeBar.Hide)
        nativeBar:Hide()
    end
end

---------------------------------------------------------------------------
-- A bar for content drawn a row at a time. After each layout call bar:Update(offset, total, fit): the first row shown,
-- how many rows there are and how many fit. Dragging the thumb calls onScroll(offset) with the new first row.
---------------------------------------------------------------------------
function UI:RowScrollbar(parent, onScroll, insets)
    local track, thumb = NewBar(parent, insets)
    local bar = { offset = 0, total = 0, fit = 1 }
    function bar:Update(offset, total, fit)
        self.offset, self.total, self.fit = offset, total, fit
        PlaceThumb(track, thumb, fit, total - fit, offset)
    end
    track:SetScript("OnSizeChanged", function() bar:Update(bar.offset, bar.total, bar.fit) end)
    DragThumb(track, thumb, function(frac)
        local new = math.floor(frac * (bar.total - bar.fit) + 0.5)
        if new ~= bar.offset then onScroll(new) end
    end, function()
        local over = bar.total - bar.fit
        return over > 0 and bar.offset / over or 0
    end)
    return bar
end
