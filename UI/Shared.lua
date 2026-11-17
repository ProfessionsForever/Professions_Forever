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
-- and what is still missing, each part as Options, Tooltips, Alts and Transfers says. Returns false when it adds
-- nothing. `missingShown`: the tooltip already says what is still missing, so Still to Buy is left off. `b`: the alt
-- breakdown to show instead of the real one (the options' previewer).
function UI:AddAltLines(tip, it, missingShown, b)
    local L, Alts, db, Tips = FP.L, FP.Alts, FP.db, FP.Tooltips
    b = b or Alts:GetAltBreakdown(it.itemID)
    if #b.enabled == 0 and #b.ignored == 0 then return false end
    local send = {}
    for _, s in ipairs(it.sources) do send[s.key] = s.transfer end
    -- While alts don't count toward planning, a transfer is only a suggestion.
    local sendText = (Tips.preview or FP.Planner:Applies()) and L["Send %d"] or L["Could Send %d"]
    local alt = self.ALT_COLOR
    -- Gathered first, so a block with nothing to show adds no blank line either.
    local lines = {}
    local function Line(...)
        local args = { ... }
        lines[#lines + 1] = function() tip:AddDoubleLine(unpack(args)) end
    end
    if #b.enabled > 0 then
        -- One line per character: "Has 66 (26 bank), Send 42".
        if db.altTipChars then
            for _, e in ipairs(b.enabled) do
                local r, g, bl = Alts:ClassColor(e.class)
                local text = (db.altTipBank and e.bank > 0) and L["Has %d (%d bank)"]:format(e.count, e.bank)
                    or L["Has %d"]:format(e.count)
                if db.altTipSend and send[e.key] and send[e.key] > 0 then text = text .. ", " .. sendText:format(send[e.key]) end
                Line(Alts:Label(e), text, r, g, bl, 1, 1, 1)
            end
        end
        local total = db.altTipTotal
        if total == "always" or (total == "multi" and #b.enabled > 1) then
            Line(L["Available on Enabled Characters"], b.enabledTotal, 0.8, 0.8, 0.8, alt[1], alt[2], alt[3])
        end
        -- The shopping list's Buy column: after transfers while alts count toward planning, before them otherwise.
        if db.altTipToBuy and it.localShort > 0 and not missingShown then
            local c = it.shortage > 0 and STATUS_COLORS.missing or STATUS_COLORS.full
            Line(L["Still to Buy"], it.shortage, 0.8, 0.8, 0.8, c[1], c[2], c[3])
        end
    end
    if db.altTipIgnored and #b.ignored > 0 then
        if #lines > 0 and db.tipSpacing then lines[#lines + 1] = function() tip:AddLine(" ") end end
        lines[#lines + 1] = function() tip:AddLine(L["Ignored Characters:"], 0.6, 0.6, 0.6) end
        for _, e in ipairs(b.ignored) do
            Line(Tips:Indent(1) .. Alts:Label(e), e.count, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
        end
    end
    if #lines == 0 then return false end
    Tips:Space(tip)
    for _, add in ipairs(lines) do add() end
    return true
end

-- Click hints at the bottom of an item tooltip in the addon's windows, as Options, Tooltips, Prices and Hints says:
-- one line ("Click: Quantity, Ctrl: Auction House"), a line per action, or none. hints: { { short, full }, ... }.
-- `keyHidden`: the tooltip holds back detail for the detail key, so the key goes in too.
function UI:AddHints(tip, hints, keyHidden, color)
    local L, db, Tips = FP.L, FP.db, FP.Tooltips
    local keyHint = keyHidden and db.tipKeyHint
    if db.tipHints == "line" then
        local parts = {}
        for _, h in ipairs(hints) do parts[#parts + 1] = h[1] end
        if keyHint then parts[#parts + 1] = L["%s: Details"]:format(Tips:KeyName()) end
        if #parts > 0 then tip:AddLine(table.concat(parts, ", "), 0.6, 0.6, 0.6, true) end
        return
    end
    if db.tipHints == "full" then
        for _, h in ipairs(hints) do tip:AddLine(h[2], color[1], color[2], color[3]) end
    end
    if keyHint then Tips:AddKeyHint(tip) end
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
