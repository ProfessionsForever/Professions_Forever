local _, FP = ...
local UI = FP.UI

local STEP, THUMB_MIN, TRACK_W, HIT_W, RIGHT_INSET = 45, 30, 4, 14, 2

-- How far list rows and scroll frames stop short of the right edge, leaving the bar's column clear.
UI.BAR_GUTTER = RIGHT_INSET + TRACK_W + 4

-- Replaces a scroll frame's template bar with a thin one: smooth wheel scrolling and a draggable thumb, shown only when
-- the content overflows. `nativeBar` is the template bar to retire, `insets` is { top, bottom } for the track inside
-- `trackParent`. A real scroll frame passes its scroll child; list frames pass none and call scroll.fpSetRange(extra)
-- with the height that overflows. scroll.fpScrollTo(v) scrolls at once.
function UI:AttachScrollbar(scroll, nativeBar, trackParent, insets, child)
    insets = insets or {}
    trackParent = trackParent or scroll
    local top = insets.top or 4
    local bottom = insets.bottom or top
    local range = child
    if not range then
        range = CreateFrame("Frame", nil, scroll)
        range:SetSize(1, 1)
        range:Hide()
    end

    local track = CreateFrame("Frame", nil, trackParent)
    track:SetWidth(TRACK_W)
    track:SetPoint("TOPRIGHT", trackParent, "TOPRIGHT", -RIGHT_INSET, -top)
    track:SetPoint("BOTTOMRIGHT", trackParent, "BOTTOMRIGHT", -RIGHT_INSET, bottom)
    -- Moves the track's bottom end, for a list whose bottom edge moves (UI.SetPanelListBottom).
    scroll.fpSetBottom = function(b) track:SetPoint("BOTTOMRIGHT", trackParent, "BOTTOMRIGHT", -RIGHT_INSET, b) end
    track:SetFrameLevel(trackParent:GetFrameLevel() + 2)
    track:Hide()
    local bg = track:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.02)
    -- The button is wider than the thumb so it is easy to grab.
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(HIT_W)
    thumb:SetFrameLevel(track:GetFrameLevel() + 1)
    local grip = thumb:CreateTexture(nil, "ARTWORK")
    grip:SetPoint("TOPRIGHT")
    grip:SetPoint("BOTTOMRIGHT")
    grip:SetWidth(TRACK_W)
    grip:SetColorTexture(1, 1, 1, 0.27)

    local function MaxScroll() return math.max(0, range:GetHeight() - scroll:GetHeight()) end
    local function UpdateThumb()
        local maxScroll = MaxScroll()
        if maxScroll <= 0 then track:Hide() return end
        track:Show()
        local trackH, viewH = track:GetHeight(), scroll:GetHeight()
        local thumbH = math.max(THUMB_MIN, trackH * viewH / (viewH + maxScroll))
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -(scroll:GetVerticalScroll() / maxScroll * (trackH - thumbH)))
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

    thumb:SetScript("OnMouseDown", function(s, button)
        if button ~= "LeftButton" then return end
        Stop()
        local _, startY = GetCursorPosition()
        startY = startY / s:GetEffectiveScale()
        local startScroll = scroll:GetVerticalScroll()
        s:SetScript("OnUpdate", function(self)
            if not IsMouseButtonDown("LeftButton") then self:SetScript("OnUpdate", nil) return end
            local maxTravel = track:GetHeight() - self:GetHeight()
            if maxTravel <= 0 then return end
            local _, y = GetCursorPosition()
            target = math.max(0, math.min(MaxScroll(), startScroll + (startY - y / self:GetEffectiveScale()) / maxTravel * MaxScroll()))
            Set(target)
        end)
    end)
    thumb:SetScript("OnMouseUp", function(s) s:SetScript("OnUpdate", nil) end)

    scroll:HookScript("OnScrollRangeChanged", UpdateThumb)
    if child then scroll:HookScript("OnVerticalScroll", UpdateThumb) end

    scroll.fpScrollTo = function(v)
        Stop()
        target = math.max(0, math.min(MaxScroll(), v))
        Set(target)
    end
    scroll.fpSetRange = function(extraHeight)
        -- With nothing to scroll the range must be strictly below the viewport, or float rounding leaves a sliver of range and the bar stays.
        if extraHeight > 0 then
            range:SetHeight(scroll:GetHeight() + extraHeight)
        else
            range:SetHeight(1)
            scroll.fpScrollTo(0)
        end
        UpdateThumb()
    end

    if nativeBar then
        nativeBar:EnableMouse(false)
        nativeBar:HookScript("OnShow", nativeBar.Hide)
        nativeBar:Hide()
    end
end
