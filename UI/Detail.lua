local _, FP = ...
local L = FP.L
local UI = FP.UI
local CARD_H, TILE_W, TILE_GAP = UI.CARD_H, UI.TILE_W, UI.TILE_GAP
local STATUS_COLORS, DIFF_COLORS, DIFF_LABELS, WHITE_RGB = UI.STATUS_COLORS, UI.DIFF_COLORS, UI.DIFF_LABELS, UI.WHITE_RGB
local LayoutBadges, ItemName, SourceSummary = UI.LayoutBadges, UI.ItemName, UI.SourceSummary
local EstimateCraftCost, UpdateProfit = UI.EstimateCraftCost, UI.UpdateProfit

local BANNER_MSGS = { full = "All materials are in your bags.", bank = "Materials complete, but some are in the bank.",
    none = "This recipe has no reagents." }

-- Tooltip section for one planned item (a plan item from FP.Planner): who holds it, what the plan takes from each,
-- and what is still missing. Returns false when no other character is known to hold any.
function UI:AddAltLines(tip, it)
    local Alts, Planner = FP.Alts, FP.Planner
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
        tip:AddDoubleLine(L["Available on Enabled Alts"], b.enabledTotal, 0.8, 0.8, 0.8, alt[1], alt[2], alt[3])
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

-- Tooltip of the From alts tile; ev is the single-craft evaluation, whose planMax is the plan for the most crafts alts allow.
function UI:FillAltTileTip(tip, ev)
    tip:AddLine(L["From Alts"], 1, 1, 1)
    if not (ev and ev.craftWithAlts) then return end
    local extra = ev.craftWithAlts - ev.craftTotal
    if extra > 0 then
        local full = STATUS_COLORS.full
        tip:AddLine(L["%d additional crafts possible"]:format(extra), full[1], full[2], full[3])
        tip:AddLine(L["%d total after transfers"]:format(ev.craftWithAlts), 1, 1, 1)
    else
        tip:AddLine(L["No additional crafts from other characters."], 0.8, 0.8, 0.8, true)
    end
    local plan = ev.planMax
    if plan and plan.totals.units > 0 then
        tip:AddLine(" ")
        tip:AddLine(L["Materials Required from Other Characters:"], 1, 0.82, 0)
        for _, c in ipairs(plan.characters) do
            local r, g, b = FP.Alts:ClassColor(c.class)
            tip:AddLine(FP.Alts:Label(c), r, g, b)
            for _, item in ipairs(c.items) do
                local name = "  " .. ItemName(item.itemID) .. (item.fromBank > 0 and " |cff33ccee(" .. L["bank"] .. ")|r" or "")
                tip:AddDoubleLine(name, item.transfer, 0.9, 0.9, 0.9, 1, 1, 1)
            end
        end
        tip:AddLine(" ")
        tip:AddLine(L["Characters with Relevant Materials: %d"]:format(plan.totals.characters), 0.8, 0.8, 0.8)
    end
    if not FP.Planner:Applies() then
        tip:AddLine(L["Shown only: alt materials do not change shopping or queue shortages."], 0.6, 0.6, 0.6, true)
    end
end

-- Tiles shrink to leave room for the recipe name; the From alts tile drops out (and the others shift) when alts are off.
local function LayoutTiles(d)
    local useAlts = FP.Planner:Mode() ~= "never"
    local n = useAlts and 3 or 2
    local cw, w = d.content:GetWidth(), TILE_W
    if cw and cw > 100 then w = math.max(38, math.min(TILE_W, math.floor((cw - 24 - 56 - 90 - TILE_GAP * (n - 1)) / n))) end
    local key = n .. ":" .. w
    if d.tileLayout == key then return end
    d.tileLayout = key
    for _, t in ipairs(d.tiles) do t:SetWidth(w) end
    d.statBank:ClearAllPoints()
    if useAlts then
        d.statBank:SetPoint("RIGHT", d.statAlts, "LEFT", -TILE_GAP, 0)
    else
        d.statBank:SetPoint("TOPRIGHT", d.content, "TOPRIGHT", -12, -12)
    end
end

local function SetTile(t, n, fmt, shown, color)
    local col = n > 0 and (color or STATUS_COLORS.full) or STATUS_COLORS.none
    t.num:SetText(fmt:format(n))
    t.num:SetTextColor(col[1], col[2], col[3])
    t:SetShown(shown)
end

-- Sets a button's text and widens it to fit, since the game's own craft verbs vary in length.
local function SetButtonLabel(b, text, minWidth)
    b.text:SetText(text)
    b:SetWidth(math.max(minWidth, b.text:GetStringWidth() + 24))
end

local descriptionRequested = {}

-- Blizzard's recipe description: C_TradeSkillUI.GetRecipeDescription(recipeID, reagentInfos). Its schematic form
-- only asks once the recipe spell and output item have loaded, so we wait for the same.
-- reagentInfos holds only optional/finishing reagents placed in the form, so it is empty here.
function UI.RecipeDescription(recipeID)
    local ok, value = pcall(C_TradeSkillUI.GetRecipeDescription, recipeID, {})
    if ok and type(value) == "string" and value ~= "" then return value end
    if not descriptionRequested[recipeID] and ContinuableContainer then
        descriptionRequested[recipeID] = true
        local container = ContinuableContainer:Create()
        container:AddContinuable(Spell:CreateFromSpellID(recipeID))
        local output = UI.RecipeOutputInfo(recipeID)
        if output and output.itemID then container:AddContinuable(Item:CreateFromItemID(output.itemID)) end
        container:ContinueOnLoad(function() UI:QueueRefresh() end)
    end
end

function UI.RecipeOutputInfo(recipeID)
    local T = C_TradeSkillUI
    if T.GetRecipeOutputItemData then
        local ok, output = pcall(T.GetRecipeOutputItemData, recipeID)
        if ok and output then return output end
    end
    if T.GetRecipeSchematic then
        local ok, schematic = pcall(T.GetRecipeSchematic, recipeID, false)
        if ok and schematic and schematic.outputItemID then return { itemID = schematic.outputItemID } end
    end
end

-- Detail panel sections; UpdateDetail runs them in order.
local UpdateDetailHeader, UpdateReagentCards, UpdateDetailSummary, UpdateDetailActions

function UI:UpdateDetail()
    local f = self.frame
    if not f then return end
    local d = f.detail
    local e = FP.selected and FP.Recipes.byID[FP.selected]
    if not e then
        d.content:Hide()
        d.hint:SetText(#FP:GetProfessions() == 0 and L["No professions found. Learn or open a profession."] or L["Select a recipe."])
        d.hint:Show()
        return
    end
    d.hint:Hide()
    d.content:Show()

    local count = FP.Recipes:IsEnchant(e.id) and 1 or self:GetCount()
    local salvage = FP.Recipes:IsSalvage(e.id)
    local ev = FP.Recipes:Evaluate(e.id, count)
    local one = FP.Recipes:Evaluate(e.id, 1)
    FP.Recipes:EvaluateAlts(ev)
    FP.Recipes:EvaluateAlts(one)
    LayoutTiles(d)
    local sourceKnown = UpdateDetailHeader(d, e)
    UpdateReagentCards(d, e, ev)
    UpdateDetailSummary(d, e, ev, one, count, salvage)
    UpdateDetailActions(d, e, ev, one, count, salvage, sourceKnown)
end

-- Icon, name, favorite star, difficulty, where it is learned from, and the description.
-- Returns whether a location is known for an unlearned recipe.
function UpdateDetailHeader(d, e)
    d.icon:SetTexture(e.icon)
    d.name:SetText(e.name)
    local _, nameSize = d.name:GetFont()
    nameSize = nameSize or 16
    -- The name auto-sizes to its text (width 0) so the star can anchor to its right edge; long names are capped and wrap.
    d.name:SetWidth(0)
    local left, limit = d.name:GetLeft(), d.statBags:GetLeft()
    local reserve = nameSize + 2 + 10 + 8
    if left and limit and d.name:GetStringWidth() > limit - left - reserve then d.name:SetWidth(math.max(40, limit - left - reserve)) end
    d.fav:SetSize(nameSize + 2, nameSize + 2)
    d.fav:ClearAllPoints()
    d.fav:SetPoint("LEFT", d.name, "TOPRIGHT", 10, -nameSize * 0.6 + 1)
    local dc = DIFF_COLORS[e.difficulty] or WHITE_RGB
    d.name:SetTextColor(dc[1], dc[2], dc[3])
    d.sub:SetText((e.learned and L["Learned"] or L["Not Learned"]) .. (DIFF_LABELS[e.difficulty] and ("  -  " .. L[DIFF_LABELS[e.difficulty]]) or ""))
    local sourceKnown = false
    if e.learned then
        d.source:SetText("")
        d.sourceHit:Hide()
    else
        local text
        text, sourceKnown = SourceSummary(e.id)
        d.source:SetText(text)
        d.source:SetTextColor(sourceKnown and 1 or 0.6, sourceKnown and 0.82 or 0.6, sourceKnown and 0 or 0.6)
        d.sourceHit:Show()
    end

    d.desc:SetText(UI.RecipeDescription(e.id) or "")
    d.cooldown:SetText(FP.Cooldowns:DetailText(e.id))
    d.fav.star:SetDesaturated(not e.favorite)
    d.fav.star:SetAlpha(e.favorite and 1 or 0.45)
    return sourceKnown
end

local REAGENT_TOP, REAGENT_GAP, CARD_MIN = 140, 4, 30

-- Cards shrink so the last line stays clear of the cost line, or of the enchant target above it.
local function LayoutReagentCards(d, count, targeted)
    local lines = math.max(1, math.ceil(count / 2))
    local contentH, h = d.content:GetHeight(), CARD_H
    if contentH > 100 then
        local free = contentH - REAGENT_TOP - (targeted and 206 or 134)
        h = math.max(CARD_MIN, math.min(CARD_H, math.floor((free - (lines - 1) * REAGENT_GAP) / lines)))
    end
    local key = h .. ":" .. #d.rows
    if d.cardLayout == key then return end
    d.cardLayout = key
    local c = d.content
    for i, row in ipairs(d.rows) do
        local y = -REAGENT_TOP - math.floor((i - 1) / 2) * (h + REAGENT_GAP)
        row:SetHeight(h)
        row.icon:SetSize(h - 10, h - 10)
        row:ClearAllPoints()
        if i % 2 == 1 then
            row:SetPoint("TOPLEFT", c, "TOPLEFT", 12, y)
            row:SetPoint("TOPRIGHT", c, "TOP", -3, y)
        else
            row:SetPoint("TOPLEFT", c, "TOP", 3, y)
            row:SetPoint("TOPRIGHT", c, "TOPRIGHT", -12, y)
        end
    end
end

-- One card per reagent: icon, name, owned / needed, and the queue, shopping list and vendor badges.
function UpdateReagentCards(d, e, ev)
    for i = #d.rows + 1, #ev.reagents do d.AddReagentCard(i) end
    LayoutReagentCards(d, #ev.reagents, FP.Recipes:IsEnchant(e.id) or FP.Recipes:IsSalvage(e.id))
    for i = 1, #d.rows do
        local row, r = d.rows[i], ev.reagents[i]
        if r then
            local col
            if r.total < r.need then
                if r.totalWithAlts and r.totalWithAlts >= r.need then
                    col = UI.ALT_COLOR -- short locally, but enabled alts could cover the whole quantity
                else
                    col = r.total > 0 and STATUS_COLORS.partial or STATUS_COLORS.missing
                end
            else
                col = r.bags < r.need and STATUS_COLORS.bank or STATUS_COLORS.full
            end
            row.itemID, row.need = r.itemID, r.need
            row.icon:SetTexture(C_Item.GetItemIconByID(r.itemID))
            row.name:SetText(ItemName(r.itemID))
            row.name:SetTextColor(0.92, 0.92, 0.92)
            row.stripe:SetColorTexture(col[1], col[2], col[3], 1)
            row.count:SetText(("%d / %d"):format(r.total, r.need))
            row.count:SetTextColor(col[1], col[2], col[3])
            row.bankTag:SetText(r.bank > 0 and L["%d in bank"]:format(r.bank) or "")
            row.queueQty = FP.Queue:QueuedAmount(r.itemID)
            row.shopQty = FP.Shop:Data()[r.itemID] or 0
            row.owned = r.total
            row.altQty = r.alts or 0
            row.reagent = r
            row.hasVendor = FP.Waypoint:VendorNavAvailable(r.itemID)
            LayoutBadges(row)
            row:Show()
        else
            row.itemID = nil
            row:Hide()
        end
    end
end

-- The "Requires:" line, each requirement coloured by whether it is met.
local function ToolsText(recipeID)
    local parts = {}
    for _, r in ipairs(FP.Tools:Get(recipeID)) do
        local col = r.state == "bags" and "|cff33e633" or (r.state == "bank" and "|cff33ccee" or "|cffe63333")
        local note = r.tool and r.state == "bank" and L["in bank"] or (r.tool and r.state == "missing" and L["not in bags"]) or nil
        parts[#parts + 1] = col .. r.name .. (note and (" (" .. note .. ")") or "") .. "|r"
    end
    return #parts > 0 and (L["Requires:"] .. " " .. table.concat(parts, ", ")) or ""
end

-- Why the craft buttons are off, or nil when crafting is possible.
local function CraftBlockReason(e, crafts, targeted, target, salvage)
    if not e.learned then return L["You haven't learned this recipe."] end
    if InCombatLockdown() then return L["Cannot do that in combat."] end
    if FP.Cooldowns:IsOnCooldown(e.id) then return L["This recipe is on cooldown."] end
    if targeted and not target then return L["Choose an item first."] end
    if crafts < 1 then return salvage and L["Not enough of the chosen item."] or L["Not enough materials in your bags."] end
    local missing = {}
    for _, r in ipairs(FP.Tools:Get(e.id)) do
        if r.state ~= "bags" then missing[#missing + 1] = r.name end
    end
    if #missing > 0 then return L["Missing requirement: %s"]:format(table.concat(missing, ", ")) end
end

-- Walking up to a forge or anvil fires no event, so while the recipe page is open its requirements and cooldown are re-read every 0.75s, as Blizzard's page does.
function UI:PollStations()
    local d = self.frame and self.frame.detail
    local e = FP.selected and FP.Recipes.byID[FP.selected]
    if not (e and self.page == "recipes" and d.content:IsVisible()) then return end
    if ToolsText(e.id) ~= d.tools:GetText() or FP.Cooldowns:DetailText(e.id) ~= d.cooldown:GetText() then self:UpdateDetail() end
end

-- Status banner, tool requirements, craftable-count tiles and the cost estimate.
function UpdateDetailSummary(d, e, ev, one, count, salvage)
    local covered = ev.altsCover
    local msg = ev.anyShort and (covered and "Missing materials are available on other characters" or "Items missing - click to add to shopping list")
        or (not salvage and BANNER_MSGS[ev.status]) or nil
    local c = covered and UI.ALT_COLOR or STATUS_COLORS[ev.status]
    d.banner:SetText(msg and L[msg] or "")
    d.banner:SetTextColor(c[1], c[2], c[3])
    -- With alts counting toward planning there is nothing left to buy.
    d.bannerBtn:SetShown(ev.anyShort and not (covered and FP.Planner:Applies()))

    d.tools:SetText(ToolsText(e.id))
    local hasReagents = ev.status ~= "none"
    SetTile(d.statBags, one.craftBags, "%d", hasReagents, STATUS_COLORS.full)
    SetTile(d.statBank, one.craftTotal - one.craftBags, "+%d", hasReagents, STATUS_COLORS.bank)
    d.statAlts.ev = one
    SetTile(d.statAlts, (one.craftWithAlts or one.craftTotal) - one.craftTotal, "+%d", hasReagents and FP.Planner:Mode() ~= "never", UI.ALT_COLOR)

    local totalCost, priced, unpriced = EstimateCraftCost(ev.reagents)
    d.costInfo = #ev.reagents > 0 and { reagents = ev.reagents, count = count, total = totalCost, priced = priced } or nil
    if #ev.reagents == 0 then
        d.cost:SetText(L["No reagents to price."])
    elseif priced == 0 then
        d.cost:SetText(L["Cost unavailable: no known prices."])
    else
        local costText = L["Cost to Craft x%d: %s"]:format(count, FP.Prices:Format(totalCost))
        if unpriced > 0 then costText = costText .. "  -  " .. L["%d reagent prices unavailable."]:format(unpriced) end
        d.cost:SetText(costText)
    end
    UpdateProfit(d, e, ev, count, salvage, totalCost, priced, unpriced)
end

-- Track button, enchant / salvage target, and the state and labels of the craft buttons.
function UpdateDetailActions(d, e, ev, one, count, salvage, sourceKnown)
    local tracked = false
    if e.learned then tracked = C_TradeSkillUI.IsRecipeTracked(e.id, false) and true or false end
    -- Learned recipes track their reagents in the objective tracker; unlearned ones set a waypoint to where they are learned.
    d.track:SetActive(e.learned or (sourceKnown and FP.Waypoint:NavAvailable()))

    local enchant = FP.Recipes:IsEnchant(e.id)
    local targeted = enchant or salvage
    local target = targeted and UI.CurrentTarget(e.id)
    d.target:SetShown(targeted)
    d.targetTitle:SetShown(targeted)
    d.targetName:SetShown(targeted)
    local crafts = one.craftBags
    if targeted then
        d.targetTitle:SetText(salvage and L["Salvage Item"] or L["Enchant Target"])
        d.target.icon:SetTexture(target and target:GetItemIcon() or nil)
        d.target.plus:SetShown(not target)
        local name = target and (target:GetItemLink() or target:GetItemName())
        if name and salvage then name = name .. " x" .. (target:GetStackCount() or 1) end
        d.targetName:SetText(name or L["Click to choose"])
        d.targetName:SetTextColor(target and 1 or 0.6, target and 1 or 0.6, target and 1 or 0.6)
    end
    -- A salvage craft has no reagents to count; it uses a set number of the chosen stack.
    if salvage then
        crafts = target and math.floor((target:GetStackCount() or 0) / FP.Recipes:SalvageQuantity(e.id)) or 0
    end

    d.craftBlock = CraftBlockReason(e, crafts, targeted, target, salvage)
    local canCraft = d.craftBlock == nil
    d.craft:SetActive(canCraft)
    d.craftAll:SetActive(canCraft)
    d.enchantBtn:SetActive(canCraft)
    local plain = not enchant
    for _, w in ipairs({ d.qtyLabel, d.qty, d.qty.minus, d.qty.plus, d.craft, d.craftAll, d.addQueue }) do
        w:SetShown(plain)
    end
    d.enchantBtn:SetShown(enchant)
    d.addMissing:SetActive(ev.anyShort)

    -- The game names some crafts after what they do ("Transmute", "Prospect"); the recipe info carries that verb.
    local verb = e.verb
    SetButtonLabel(d.craft, verb or L["Craft"], 90)
    SetButtonLabel(d.craftAll, e.allVerb or (verb and L["%s All"]:format(verb)) or L["Craft All"], 90)
    local compactActions = d.content:GetWidth() < 500
    SetButtonLabel(d.addMissing, compactActions and L["Add Missing"] or L["Add Missing to Shopping List"], compactActions and 110 or 210)
    local queueLabel = verb and L["Queue %s"]:format(verb) or (compactActions and L["Queue"] or L["Add to Queue"])
    SetButtonLabel(d.addQueue, queueLabel, compactActions and 80 or 110)
    if compactActions then d.addQueue:SetWidth(math.min(d.addQueue:GetWidth(), 120)) end
    local trackText = compactActions and L["Track"] or L["Track Location"]
    if e.learned then
        trackText = compactActions and (tracked and L["Untrack"] or L["Track"]) or (tracked and L["Untrack Recipe"] or L["Track Recipe"])
    end
    SetButtonLabel(d.track, trackText, compactActions and 80 or 120)
    d.addMissing:ClearAllPoints()
    d.addQueue:ClearAllPoints()
    d.track:ClearAllPoints()
    d.addMissing:SetPoint("BOTTOMLEFT", 12, 46)
    d.addQueue:SetPoint("LEFT", d.addMissing, "RIGHT", compactActions and 4 or 6, 0)
    d.track:SetPoint("LEFT", d.addQueue, "RIGHT", compactActions and 4 or 6, 0)
end
