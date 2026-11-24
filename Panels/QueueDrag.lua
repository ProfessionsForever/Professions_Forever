local _, FP = ...
local Queue, UI = FP.Queue, FP.UI

-- Dragging a crafting queue row to a new place: the ghost row, the insertion line, and scrolling at the edges.

local ROWS, ROW_H = Queue.ROWS, Queue.ROW_H
local EDGE, SCROLL_SPEED = ROW_H / 2, ROW_H * 8

local ghost, line, lastGap
local driver = CreateFrame("Frame")
driver:Hide()

local function Cursor(frame)
    local x, y = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    return x / scale, y / scale
end

-- The entry's new place: `slot` entries stay above it, `gap` is the same position counted from the first visible row.
local function Target()
    local scroll = Queue.frame.scroll
    local _, y = Cursor(scroll)
    local offset = FauxScrollFrame_GetOffset(scroll)
    local gap = math.floor((scroll:GetTop() - y) / ROW_H + 0.5)
    gap = math.max(0, math.min(gap, math.min(ROWS, #Queue:Data(Queue:ViewKey()) - offset)))
    local slot = offset + gap
    return slot < Queue.dragFrom and slot + 1 or slot, gap
end

local function Build()
    local f = Queue.frame
    ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ghost:SetSize(220, ROW_H)
    ghost:SetFrameStrata("TOOLTIP")
    UI:Skin(ghost, "button")
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetSize(ROW_H - 6, ROW_H - 6)
    ghost.icon:SetPoint("LEFT", 4, 0)
    ghost.text = UI:Text(ghost, 0)
    ghost.text:SetPoint("LEFT", ghost.icon, "RIGHT", 4, 0)
    ghost.text:SetPoint("RIGHT", -4, 0)
    ghost.text:SetWordWrap(false)
    ghost:Hide()

    line = CreateFrame("Frame", nil, f)
    line:SetHeight(2)
    line:SetFrameLevel(f:GetFrameLevel() + 15)
    line.tex = line:CreateTexture(nil, "OVERLAY")
    line.tex:SetAllPoints()
    line.tex:SetColorTexture(1, 0.82, 0, 1)
    line:Hide()
end

local function End(apply)
    driver:Hide()
    ghost:Hide()
    line:Hide()
    local from = Queue.dragFrom
    local to = apply and Queue.frame:IsShown() and Target()
    Queue.dragFrom = nil
    if to and to ~= from then Queue:MoveTo(from, to, Queue:ViewKey()) else Queue:Update() end
end

driver:SetScript("OnUpdate", function(_, elapsed)
    local f = Queue.frame
    if not f:IsShown() then return End(false) end
    local scroll = f.scroll
    local x, y = Cursor(ghost)
    ghost:ClearAllPoints()
    ghost:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x + 10, y)
    if y > scroll:GetTop() - EDGE then
        scroll.fpScrollTo(scroll:GetVerticalScroll() - SCROLL_SPEED * elapsed)
    elseif y < scroll:GetBottom() + EDGE then
        scroll.fpScrollTo(scroll:GetVerticalScroll() + SCROLL_SPEED * elapsed)
    end
    local to, gap = Target()
    line:SetShown(to ~= Queue.dragFrom)
    if gap ~= lastGap then
        lastGap = gap
        line:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 1 - gap * ROW_H)
        line:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 1 - gap * ROW_H)
    end
end)

-- Rows are dragged anywhere on their body; the quantity box and buttons keep their own clicks.
function Queue:AttachDrag(row)
    -- Two columns of three dots; textures take no mouse, so the drag still starts from the row.
    for col = 0, 1 do
        for r = -1, 1 do
            local dot = row:CreateTexture(nil, "ARTWORK")
            dot:SetSize(2, 2)
            dot:SetPoint("LEFT", 5 + col * 4, r * 5)
            dot:SetColorTexture(0.65, 0.65, 0.65, 0.9)
        end
    end
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function(s)
        local q = s.index and Queue:Data(Queue:ViewKey())[s.index]
        if not q then return end
        if not ghost then Build() end
        Queue.dragFrom, lastGap = s.index, nil
        ghost.icon:SetTexture(q.icon)
        ghost.text:SetText(q.name)
        ghost:Show()
        GameTooltip:Hide()
        driver:Show()
        Queue:Update()
    end)
    row:SetScript("OnDragStop", function()
        if Queue.dragFrom then End(true) end
    end)
end
