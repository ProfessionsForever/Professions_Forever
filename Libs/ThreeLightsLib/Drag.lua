--[[
ThreeLightsLib: drag and drop between the addon's own frames (UI:DragSource, UI:DropTarget).

A drag carries a value (whatever the source says it is). While dragging, a ghost with the source's icon and label
follows the cursor, and every visible target that accepts the value is tinted with the accent; the one under the
cursor more strongly. Releasing over an accepting target calls its drop function. When targets overlap (a card inside
a box), the one drawn on top (highest frame level) gets the drop. Releasing anywhere else does nothing.
]]
local _, ns = ...
local UI = ns.UI

local targets = {}
local drag  -- { value, source } while dragging
local ghost

local function CursorXY()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

-- The accepting target under the cursor, the one on top when several are.
local function TargetUnderCursor()
    local best
    for t in pairs(targets) do
        if t:IsVisible() and t:IsMouseOver() and t.libAccept(drag.value, t)
                and (not best or t:GetFrameLevel() > best:GetFrameLevel()) then
            best = t
        end
    end
    return best
end

local function Tint()
    local a = UI:GetAccent()
    local over = TargetUnderCursor()
    for t in pairs(targets) do
        local on = drag and t:IsVisible() and t.libAccept(drag.value, t)
        t.libGlow:SetColorTexture(a[1], a[2], a[3], t == over and 0.22 or 0.07)
        t.libGlow:SetShown(on and true or false)
    end
end

local function Finish()
    if not drag then return end
    local over = TargetUnderCursor()
    local value = drag.value
    drag = nil
    ghost:Hide()
    for t in pairs(targets) do t.libGlow:Hide() end
    if over then over.libDrop(value, over) end
end

local function Ghost()
    if ghost then return ghost end
    ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    UI:Layer(ghost, "popup")
    ghost:SetSize(160, 24)
    UI:Skin(ghost, "button", true)
    ghost:SetAlpha(0.9)
    ghost:EnableMouse(false)
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetSize(18, 18)
    ghost.icon:SetPoint("LEFT", 4, 0)
    ghost.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ghost.text = UI:Text(ghost, "normal")
    ghost.text:SetPoint("LEFT", ghost.icon, "RIGHT", 6, 0)
    ghost.text:SetPoint("RIGHT", -6, 0)
    ghost.text:SetWordWrap(false)
    ghost:Hide()
    ghost:SetScript("OnUpdate", function(g)
        -- The button can come up over a frame that never sees it (or the source can be hidden by a refresh).
        if not IsMouseButtonDown("LeftButton") then return Finish() end
        local x, y = CursorXY()
        g:ClearAllPoints()
        g:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x + 12, y)
        Tint()
    end)
    return ghost
end

---------------------------------------------------------------------------
-- Makes frame f draggable with the left button. value(f) gives what it carries, or nil when it can't be dragged now.
-- look(f, value) gives the ghost's icon (texture path or nil) and label.
---------------------------------------------------------------------------
function UI:DragSource(f, value, look)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s)
        local v = value(s)
        if v == nil then return end
        drag = { value = v, source = s }
        local g = Ghost()
        local icon, label = look(s, v)
        g.icon:SetTexture(icon)
        g.icon:SetShown(icon ~= nil)
        g.text:SetText(label or "")
        g:Show()
        Tint()
    end)
    f:SetScript("OnDragStop", Finish)
end

---------------------------------------------------------------------------
-- Makes frame f a drop target. accept(value, f) says whether it takes a dragged value; drop(value, f) takes it.
---------------------------------------------------------------------------
function UI:DropTarget(f, accept, drop)
    f.libAccept, f.libDrop = accept, drop
    f.libGlow = f:CreateTexture(nil, "OVERLAY")
    f.libGlow:SetAllPoints()
    f.libGlow:Hide()
    targets[f] = true
end

-- Whether a drag is under way (for sources that also react to clicks).
function UI:Dragging() return drag ~= nil end
