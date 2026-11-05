local _, FP = ...
local UI = FP.UI

-- Constants, colors and small helpers shared by the main window's files.
local ROW_DENSITIES = { compact = 18, normal = 22, roomy = 26, spacious = 30 }
local CARD_H = 44
local TILE_W, TILE_H, TILE_GAP = 54, 36, 3 -- craftable-count tiles
UI.CARD_H, UI.TILE_W, UI.TILE_H, UI.TILE_GAP = CARD_H, TILE_W, TILE_H, TILE_GAP

local function RecipeRowHeight()
    return ROW_DENSITIES[FP.db.recipeDensity] or ROW_DENSITIES.normal
end

-- Same sound Blizzard's own tabs play.
function UI.TabSound() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
UI.RecipeRowHeight = RecipeRowHeight

-- Hoverable badge (icon + number) in a reagent card's top-right corner; onClick is optional.
function UI:Badge(row, texture, onEnter, onClick)
    local b = CreateFrame("Frame", nil, row)
    b:SetHeight(14)
    b:EnableMouse(true)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(12, 12)
    b.icon:SetPoint("LEFT")
    b.icon:SetTexture(texture)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.text = self:Text(b, -1, "LEFT")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 2, 0)
    self:Tooltip(b, "ANCHOR_TOP", function() onEnter(row) end)
    if onClick then
        b:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then onClick(row) end end)
    end
    return b
end

-- A framed icon beside the game tooltip; it hides whenever the tooltip is cleared so other tooltips never show it.
local TIP_ICON_SIZE = 48
local tipIcon
function UI:ShowTooltipIcon(texture)
    if not texture then return end
    if not tipIcon then
        tipIcon = CreateFrame("Frame", nil, GameTooltip, "BackdropTemplate")
        tipIcon:SetSize(TIP_ICON_SIZE, TIP_ICON_SIZE)
        tipIcon:SetFrameStrata("TOOLTIP")
        self:Skin(tipIcon, "button")
        tipIcon.tex = tipIcon:CreateTexture(nil, "ARTWORK")
        tipIcon.tex:SetPoint("TOPLEFT", 3, -3)
        tipIcon.tex:SetPoint("BOTTOMRIGHT", -3, 3)
        tipIcon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        GameTooltip:HookScript("OnTooltipCleared", function() tipIcon:Hide() end)
    end
    tipIcon:ClearAllPoints()
    tipIcon:SetPoint("TOPRIGHT", GameTooltip, "TOPLEFT", -4, 0) -- the right side is taken by the equipped-item comparison tooltips
    tipIcon.tex:SetTexture(texture)
    tipIcon:Show()
end

-- Lays out the vendor / shopping-list / queue badges right-to-left and keeps the name clear of them.
local function LayoutBadges(row)
    local right = -6
    local leftmost
    for _, b in ipairs(row.badges) do
        local n
        if b == row.vBadge then n = row.hasVendor and 1 or 0
        elseif b == row.aBadge then n = row.altQty or 0
        else n = (b == row.sBadge and row.shopQty or row.queueQty) or 0 end
        b:SetShown(n > 0)
        if n > 0 then
            b.text:SetText(b == row.vBadge and "" or n)
            b:SetWidth(14 + b.text:GetStringWidth())
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, -4)
            right = right - b:GetWidth() - 6
            leftmost = b
        end
    end
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
    if leftmost then row.name:SetPoint("RIGHT", leftmost, "LEFT", -4, 0) else row.name:SetPoint("RIGHT", -6, 0) end
end
UI.LayoutBadges = LayoutBadges

local STATUS_COLORS = {
    full = { 0.2, 0.9, 0.2 }, bank = { 0.2, 0.8, 0.9 }, partial = { 1, 0.82, 0 },
    missing = { 0.9, 0.2, 0.2 }, none = { 0.5, 0.5, 0.5 },
}
UI.STATUS_COLORS = STATUS_COLORS
UI.ALT_COLOR = { 0.75, 0.6, 1 } -- materials on other characters
UI.CHAIN_COLOR = { 1, 0.6, 0.25 } -- craftable after crafting its reagents

-- The "Skill: 120 / 150" tooltip line of a profession; nothing when it has no cap to show.
function UI.AddSkillLine(tip, rank, maxRank)
    if maxRank and maxRank > 0 then
        tip:AddLine(("%s: %d / %d"):format(FP.L["Skill"], rank or 0, maxRank), 0.8, 0.8, 0.8)
    end
end
-- Enum.TradeskillRelativeDifficulty: 0 optimal, 1 medium, 2 easy, 3 trivial
local DIFF_COLORS = { [0] = { 1, 0.5, 0.25 }, [1] = { 1, 1, 0 }, [2] = { 0.25, 0.75, 0.25 }, [3] = { 0.55, 0.55, 0.55 } }
local DIFF_LABELS = { [0] = "Skill Up: Optimal", [1] = "Skill Up: Medium", [2] = "Skill Up: Easy", [3] = "Skill Up: Trivial" }
local WHITE_RGB = { 1, 1, 1 }
UI.DIFF_COLORS, UI.DIFF_LABELS, UI.WHITE_RGB = DIFF_COLORS, DIFF_LABELS, WHITE_RGB

local function ItemName(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(itemID) -- GET_ITEM_INFO_RECEIVED triggers a refresh
        name = "item:" .. itemID
    end
    return name
end
UI.ItemName = ItemName
