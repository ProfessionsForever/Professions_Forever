local _, FP = ...
local UI = FP.UI

-- Constants, colors and small helpers shared by the main window, the side panels and the options.
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

-- The colour code for an { r, g, b } colour, from Blizzard's own helper.
function UI.Hex(c) return RGBToColorCode(unpack(c)) end

-- Chat-link click (shift by default): puts the link in the active chat box. True when it did, so the click is spent.
function UI.LinkToChat(link)
    if not (link and IsModifiedClick("CHATLINK")) then return false end
    return ChatFrameUtil.InsertLink(link) and true or false
end

function UI.LinkItemToChat(itemID)
    return itemID and UI.LinkToChat(select(2, C_Item.GetItemInfo(itemID))) or false
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

local STATUS_COLORS = {
    full = { 0.2, 0.9, 0.2 }, bank = { 0.2, 0.8, 0.9 }, partial = { 1, 0.82, 0 },
    missing = { 0.9, 0.2, 0.2 }, none = { 0.5, 0.5, 0.5 },
}
UI.STATUS_COLORS = STATUS_COLORS
UI.ALT_COLOR = { 0.75, 0.6, 1 } -- materials on other characters
UI.MAIL_COLOR = { 1, 0.55, 0.75 } -- materials waiting in the mailbox
UI.CHAIN_COLOR = { 1, 0.6, 0.25 } -- craftable after crafting its reagents

-- Tooltip section for one planned item (a plan item from FP.Planner): who holds it, what the plan takes from each,
-- and what is still missing. Returns false when no other character is known to hold any.
function UI:AddAltLines(tip, it)
    local L, Alts, Planner = FP.L, FP.Alts, FP.Planner
    local b = Alts:GetAltBreakdown(it.itemID)
    if #b.enabled == 0 and #b.ignored == 0 then return false end
    local send = {}
    for _, s in ipairs(it.sources) do send[s.key] = s.transfer end
    local alt = self.ALT_COLOR
    tip:AddLine(" ")
    if #b.enabled > 0 then
        tip:AddLine(L["Other Characters:"], 1, 0.82, 0)
        for _, e in ipairs(b.enabled) do
            local r, g, bl = Alts:ClassColor(e.class)
            local text = e.bank > 0 and L["%d (%d in bank)"]:format(e.count, e.bank) or tostring(e.count)
            if send[e.key] then text = text .. "  " .. L["send %d"]:format(send[e.key]) end
            tip:AddDoubleLine(Alts:Label(e), text, r, g, bl, 1, 1, 1)
        end
        tip:AddLine(" ")
        tip:AddDoubleLine(L["Available on Enabled Characters"], b.enabledTotal, 0.8, 0.8, 0.8, alt[1], alt[2], alt[3])
        if it.transfer > 0 then
            tip:AddDoubleLine(Planner:Applies() and L["Transfer Needed"] or L["Suggested Transfer"], it.transfer, 0.8, 0.8, 0.8, 1, 1, 1)
        end
        if it.localShort > 0 then
            local c = it.stillMissing > 0 and STATUS_COLORS.missing or STATUS_COLORS.full
            tip:AddDoubleLine(L["Still Missing After Transfers"], it.stillMissing, 0.8, 0.8, 0.8, c[1], c[2], c[3])
        end
    end
    if #b.ignored > 0 then
        tip:AddLine(" ")
        tip:AddLine(L["Ignored Characters:"], 0.6, 0.6, 0.6)
        for _, e in ipairs(b.ignored) do
            tip:AddDoubleLine("  " .. Alts:Label(e), e.count, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
        end
    end
end

-- The "Skill: 120 / 150" tooltip line of a profession; nothing when it has no cap to show.
function UI.AddSkillLine(tip, rank, maxRank)
    if maxRank and maxRank > 0 then
        tip:AddLine(("%s: %d / %d"):format(FP.L["Skill"], rank or 0, maxRank), 0.8, 0.8, 0.8)
    end
end

-- A learned profession's waypoint hint; a secondary profession past Journeyman needs a vendor's skill book, and later a quest, not a trainer.
function UI.AddTrainerHint(tip, skillLine, rank, maxRank)
    local L, W = FP.L, FP.Waypoint
    local book, quest = W.SkillBook(skillLine, rank, maxRank), W.ArtisanQuest(skillLine, rank, maxRank)
    if book then
        tip:AddLine(L["The next rank needs a skill book from a vendor: %s."]:format(W.SkillBookName(book)), 1, 0.82, 0, true)
    elseif quest then
        tip:AddLine(L["The next rank needs a quest, finished with %s."]:format(quest.name), 1, 0.82, 0, true)
    end
    if W:NavAvailable() then
        tip:AddLine(book and L["Right-click: waypoint to the nearest skill book vendor"]
            or quest and L["Right-click: waypoint to the quest giver"] or L["Right-click: waypoint to the nearest trainer"], 0.5, 0.8, 1)
    end
end
-- Enum.TradeskillRelativeDifficulty: 0 optimal, 1 medium, 2 easy, 3 trivial
local DIFF_COLORS = { [0] = { 1, 0.5, 0.25 }, [1] = { 1, 1, 0 }, [2] = { 0.25, 0.75, 0.25 }, [3] = { 0.55, 0.55, 0.55 } }
local DIFF_LABELS = { [0] = "Skill Up: Optimal", [1] = "Skill Up: Medium", [2] = "Skill Up: Easy", [3] = "Skill Up: Trivial" }
local WHITE_RGB = { 1, 1, 1 }
UI.DIFF_COLORS, UI.DIFF_LABELS, UI.WHITE_RGB = DIFF_COLORS, DIFF_LABELS, WHITE_RGB
