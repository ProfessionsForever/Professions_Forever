local _, FP = ...
local L = FP.L
local Shop = FP.Shop

-- On-screen tracker for the shopping list. The game's objective tracker takes no custom entries from addons
-- (only its own tracked recipes, which carry no quantities), so this is a small movable frame of our own.
local TRACKER_ROWS, TRACKER_W = 12, 250

-- At its saved position, or the default spot on the right.
function Shop:PlaceTracker()
    local t, pos = self.tracker, FP.db.trackerPos
    t:ClearAllPoints()
    if pos then
        t:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        t:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
    end
end

function Shop:CreateTracker()
    local UI = FP.UI
    local t = CreateFrame("Frame", "ProfessionsForeverTracker", UIParent, "BackdropTemplate")
    self.tracker = t
    t:SetWidth(TRACKER_W)
    t:SetFrameStrata("MEDIUM")
    t:SetMovable(true)
    t:SetClampedToScreen(true)
    t:EnableMouse(true)
    t:RegisterForDrag("LeftButton")
    self:PlaceTracker()
    t:SetScript("OnDragStart", function(s) s:StartMoving() end)
    t:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local point, _, relPoint, x, y = s:GetPoint()
        FP.db.trackerPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    t:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then Shop:Open() end end)
    t:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["Shopping List"], 1, 1, 1)
        GameTooltip:AddLine(L["Drag to move. Right-click to open the shopping list."], 0.5, 0.8, 1, true)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI:Skin(t, "panel")

    t.title = UI:Text(t, 1)
    t.title:SetPoint("TOPLEFT", 10, -8)
    t.title:SetText(L["Shopping List"])
    t.title:SetTextColor(1, 0.82, 0)
    t.rows = {}
    for i = 1, TRACKER_ROWS do
        local row = CreateFrame("Frame", nil, t)
        row:SetHeight(16)
        row:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 18)
        row:SetPoint("TOPRIGHT", -10, -28 - (i - 1) * 18)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(14, 14)
        row.icon:SetPoint("LEFT")
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.count = UI:Text(row, 0, "RIGHT")
        row.count:SetPoint("RIGHT")
        row.name = UI:Text(row, 0)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
        row.name:SetWordWrap(false)
        t.rows[i] = row
    end
    t.more = UI:Text(t, -1)
    t.more:SetTextColor(0.65, 0.65, 0.65)
end

-- Shows what is still to buy, each with owned/needed; hidden while tracking is off or nothing is left to buy.
-- data: an Aggregate result, when the caller already has one.
function Shop:UpdateTracker(data)
    if not FP.db then return end
    local t = self.tracker
    if not FP.db.trackShopping then
        if t then t:Hide() end
        return
    end
    local list = {}
    for _, e in ipairs(data or self:Aggregate()) do
        if e.toBuy > 0 then list[#list + 1] = e end
    end
    if #list == 0 then
        if t then t:Hide() end
        return
    end
    if not t then
        self:CreateTracker()
        t = self.tracker
    end
    local shown = math.min(#list, TRACKER_ROWS)
    local colors = FP.UI.STATUS_COLORS
    for i = 1, TRACKER_ROWS do
        local row, e = t.rows[i], list[i]
        if e and i <= shown then
            local c = e.owned > 0 and colors.partial or colors.missing
            row.icon:SetTexture(C_Item.GetItemIconByID(e.itemID))
            row.name:SetText(e.name)
            row.count:SetText(("%d/%d"):format(e.owned, e.needed))
            row.count:SetTextColor(c[1], c[2], c[3])
            row:Show()
        else
            row:Hide()
        end
    end
    local extra = #list - shown
    t.more:ClearAllPoints()
    t.more:SetPoint("TOPLEFT", 10, -28 - shown * 18)
    t.more:SetText(extra > 0 and L["+%d more"]:format(extra) or "")
    t:SetHeight(28 + shown * 18 + (extra > 0 and 16 or 0) + 8)
    t:Show()
end
