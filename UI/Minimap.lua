local _, FP = ...
local L = FP.L
local M = {}
FP.Minimap = M

local atan2 = math.atan2 or math.atan

function M:Position()
    local a = math.rad(FP.db.minimap.angle)
    local r = Minimap:GetWidth() / 2 + 5
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function M:Update()
    if not self.button then return end
    self.button:SetShown(not FP.db.minimap.hide)
end

function M:Init()
    local b = CreateFrame("Button", "ProfessionsForeverMinimapButton", Minimap)
    self.button = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(FP.ICON)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    b:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then FP.Options:Open() else FP:Toggle() end
    end)
    b:SetScript("OnDragStart", function(s)
        s:SetScript("OnUpdate", function()
            local cx, cy = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local mx, my = GetCursorPosition()
            FP.db.minimap.angle = math.deg(atan2(my / scale - cy, mx / scale - cx))
            M:Position()
        end)
    end)
    b:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:AddLine("ProfessionsForever")
        GameTooltip:AddLine(L["Left-click: toggle window"], 1, 1, 1)
        GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
        local ready = FP.Cooldowns:ReadyTotal()
        if ready > 0 then GameTooltip:AddLine(L["%d cooldowns ready"]:format(ready), 0.2, 0.9, 0.2) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self:Position()
    self:Update()
end
