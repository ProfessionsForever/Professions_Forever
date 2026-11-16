local _, FP = ...
local L = FP.L
local UI = FP.UI
local TILE_W, TILE_GAP = UI.TILE_W, UI.TILE_GAP
local STATUS_COLORS, DIFF_COLORS, DIFF_LABELS, WHITE_RGB = UI.STATUS_COLORS, UI.DIFF_COLORS, UI.DIFF_LABELS, UI.WHITE_RGB
local ItemName, SourceSummary = FP.ItemName, UI.SourceSummary
local UpdateProfit, UpdateReagentCards, LayoutReagentCards = UI.UpdateProfit, UI.UpdateReagentCards, UI.LayoutReagentCards

local BANNER_MSGS = { full = "All materials are in your bags.", bank = "Materials complete, but some are in the bank.",
    none = "This recipe has no reagents." }

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
        tip:AddLine(L["Show only: other characters' materials don't reduce what you buy."], 0.6, 0.6, 0.6, true)
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
    local base = color or STATUS_COLORS.full
    local col = n > 0 and base or STATUS_COLORS.none
    t.num:SetText(fmt:format(n))
    t.num:SetTextColor(col[1], col[2], col[3])
    -- The label keeps its colour even at zero, so the three tiles read as a legend.
    t.label:SetTextColor(base[1], base[2], base[3])
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
    if not descriptionRequested[recipeID] then
        descriptionRequested[recipeID] = true
        local function Refresh() UI:QueueRefresh() end
        Spell:CreateFromSpellID(recipeID):ContinueOnSpellLoad(Refresh)
        local output = FP.Recipes:OutputInfo(recipeID)
        if output and output.itemID then Item:CreateFromItemID(output.itemID):ContinueOnItemLoad(Refresh) end
    end
end

-- Detail panel sections; UpdateDetail runs them in order.
local UpdateDetailHeader, UpdateDetailSummary, UpdateDetailActions

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

-- The name auto-sizes to its text (width 0) so the favorite star can anchor to its right edge; long names are capped
-- short of the tiles and wrap.
local function FitName(d)
    local _, nameSize = d.name:GetFont()
    nameSize = nameSize or 16
    d.name:SetWidth(0)
    local left, limit = d.name:GetLeft(), d.statBags:GetLeft()
    local reserve = nameSize + 2 + 10 + 8
    if left and limit and d.name:GetStringWidth() > limit - left - reserve then d.name:SetWidth(math.max(40, limit - left - reserve)) end
    d.fav:SetSize(nameSize + 2, nameSize + 2)
    d.fav:ClearAllPoints()
    d.fav:SetPoint("LEFT", d.name, "TOPRIGHT", 10, -nameSize * 0.6 + 1)
end

-- Icon, name, favorite star, difficulty, where it is learned from, and the description.
-- Returns whether a location is known for an unlearned recipe.
function UpdateDetailHeader(d, e)
    d.icon:SetTexture(e.icon)
    d.name:SetText(e.name)
    FitName(d)
    local dc = DIFF_COLORS[e.difficulty] or WHITE_RGB
    d.name:SetTextColor(dc[1], dc[2], dc[3])
    local status = e.learned and L["Learned"] or L["Not Learned"]
    local required = not e.learned and UI.RequiredSkillText(e.id)
    if required then status = status .. "  -  " .. required end
    status = status .. (DIFF_LABELS[e.difficulty] and ("  -  " .. L[DIFF_LABELS[e.difficulty]]) or "")
    -- The skill up chance in the recipe's difficulty colour, as in the list; nothing once it is grey.
    local chance = e.learned and FP.Recipes:SkillUpChance(e.id, select(2, FP.RankInfo()) or 0)
    if chance and chance > 0 then
        status = status .. "  -  " .. RGBToColorCode(dc[1], dc[2], dc[3])
            .. L["Skill Up Chance: %d%%"]:format(math.floor(chance * 100 + 0.5)) .. "|r"
    end
    d.sub:SetText(status)
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
    d.fav:SetShown(not FP:IsReadOnly())
    return sourceKnown
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
local function CraftBlockReason(e, crafts, target, salvage)
    if FP:IsReadOnly() then
        local viewing = FP.AltProfs.viewing
        return viewing and L["Log in on %s to craft this."]:format(viewing.owner) or L["You can't craft from another player's profession."]
    end
    if not e.learned then return L["You haven't learned this recipe."] end
    if InCombatLockdown() then return L["Cannot do that in combat."] end
    if FP.Cooldowns:IsOnCooldown(e.id) then return L["This recipe is on cooldown."] end
    -- An enchant needs no target, as in Blizzard's window: without one the cast gives a targeting cursor, which is how
    -- an item in the trade window's "Will not be traded" slot gets enchanted.
    if salvage and not target then return L["Choose an item first."] end
    if crafts < 1 then return salvage and L["Not enough of the chosen item."] or L["Not enough materials in your bags."] end
    local missing = FP.Tools:Missing(e.id)
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
    local covered, inMail = ev.altsCover, ev.mailCovers
    local msg = ev.anyShort and (inMail and "Missing materials are waiting in the mailbox"
        or covered and "Missing materials are available on other characters" or "Items missing - queue it to put them on the shopping list")
        or (not salvage and BANNER_MSGS[ev.status]) or nil
    local c = inMail and UI.MAIL_COLOR or covered and UI.ALT_COLOR or STATUS_COLORS[ev.status]
    -- Short only of things you can craft: say so, in place of the missing-items prompt.
    local chain = ev.anyShort and not covered and not inMail and e.learned and not salvage and not FP:IsReadOnly() and FP.Chain:Describe(e.id, count)
    if chain then c = UI.CHAIN_COLOR end
    d.banner:SetText(chain or (msg and L[msg]) or "")
    d.banner:SetTextColor(c[1], c[2], c[3])
    -- With alts counting toward planning there is nothing left to buy.
    d.bannerBtn:SetShown(ev.anyShort and not chain and not inMail and not (covered and FP.Planner:Applies()))

    d.tools:SetText(ToolsText(e.id))
    local hasReagents = ev.status ~= "none"
    SetTile(d.statBags, one.craftBags, "%d", hasReagents, STATUS_COLORS.full)
    SetTile(d.statBank, one.craftTotal - one.craftBags, "+%d", hasReagents, STATUS_COLORS.bank)
    d.statAlts.ev = one
    SetTile(d.statAlts, (one.craftWithAlts or one.craftTotal) - one.craftTotal, "+%d", hasReagents and FP.Planner:Mode() ~= "never", UI.ALT_COLOR)

    local totalCost, priced, unpriced = FP.Prices:CraftCost(ev.reagents)
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

-- The action buttons' labels and spacing, shorter while the panel is narrow; d.actions is what UpdateDetailActions
-- last set: the recipe's craft verbs, whether it is learned, and whether it is tracked.
local function LayoutActions(d)
    local a = d.actions
    -- The game names some crafts after what they do ("Transmute", "Prospect"); the recipe info carries that verb.
    local verb = a.verb
    SetButtonLabel(d.craft, verb or L["Craft"], 90)
    SetButtonLabel(d.craftAll, a.allVerb or (verb and L["%s All"]:format(verb)) or L["Craft All"], 90)
    local compactActions = d.content:GetWidth() < 500
    local queueLabel = a.queueFor and L["Queue for %s"]:format(a.queueFor)
        or verb and L["Queue %s"]:format(verb) or (compactActions and L["Queue"] or L["Add to Queue"])
    SetButtonLabel(d.addQueue, queueLabel, compactActions and 80 or 110)
    if compactActions then d.addQueue:SetWidth(math.min(d.addQueue:GetWidth(), 120)) end
    SetButtonLabel(d.queueAll, L["Queue All"], compactActions and 80 or 90)
    local trackText = compactActions and L["Track"] or L["Track Location"]
    if a.learned then
        trackText = compactActions and (a.tracked and L["Untrack"] or L["Track"]) or (a.tracked and L["Untrack Recipe"] or L["Track Recipe"])
    end
    SetButtonLabel(d.track, trackText, compactActions and 80 or 120)
    d.addQueue:ClearAllPoints()
    d.queueAll:ClearAllPoints()
    d.track:ClearAllPoints()
    d.addQueue:SetPoint("BOTTOMLEFT", 12, 46)
    d.queueAll:SetPoint("LEFT", d.addQueue, "RIGHT", compactActions and 4 or 6, 0)
    d.track:SetPoint("LEFT", d.queueAll, "RIGHT", compactActions and 4 or 6, 0)
end

-- Track button, enchant / salvage target, and the state and labels of the craft buttons.
function UpdateDetailActions(d, e, ev, one, count, salvage, sourceKnown)
    local linked = FP:IsReadOnly()
    local tracked = false
    if e.learned and not linked then tracked = C_TradeSkillUI.IsRecipeTracked(e.id, false) and true or false end
    -- Learned recipes track their reagents in the objective tracker; unlearned ones set a waypoint to where they are learned.
    d.track:SetActive(not linked and (e.learned or (sourceKnown and FP.Waypoint:NavAvailable())))

    local enchant = FP.Recipes:IsEnchant(e.id)
    local targeted = (enchant or salvage) and not linked -- nothing can be enchanted or salvaged from someone else's profession
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

    d.craftBlock = CraftBlockReason(e, crafts, target, salvage)
    local canCraft = d.craftBlock == nil
    d.craft:SetActive(canCraft)
    d.craftAll:SetActive(canCraft)
    d.queueAllCount = e.learned and not linked and (salvage and crafts or FP.Queue:RoomFor(e.id)) or 0
    d.queueAll:SetActive(d.queueAllCount > 0)
    d.enchantBtn:SetActive(canCraft)
    -- Another player's or character's profession can't be crafted or tracked from here, so those buttons give way to a
    -- line saying why. One of your other characters' learned recipes can still be queued for that character, with a
    -- quantity.
    local viewing = FP.AltProfs.viewing
    local queueFor = viewing and e.learned and not enchant and not salvage
    local plain = not enchant and not linked
    for _, w in ipairs({ d.craft, d.craftAll, d.queueAll }) do w:SetShown(plain) end
    for _, w in ipairs({ d.qtyLabel, d.qty, d.qty.minus, d.qty.plus, d.addQueue }) do w:SetShown(plain or queueFor) end
    d.addQueue:SetActive(not linked or queueFor)
    d.enchantBtn:SetShown(enchant and not linked)
    d.track:SetShown(not linked)
    d.readOnly:SetShown(linked)
    d.readOnly:ClearAllPoints()
    if queueFor then d.readOnly:SetPoint("LEFT", d.qty.plus, "RIGHT", 12, 0) else d.readOnly:SetPoint("BOTTOMLEFT", 12, 23) end
    d.readOnly:SetPoint("RIGHT", -12, 0)
    if linked then d.readOnly:SetText(d.craftBlock) end

    local a = d.actions or {}
    d.actions = a
    a.verb, a.allVerb, a.learned, a.tracked = e.verb, e.allVerb, e.learned, tracked
    a.queueFor = queueFor and viewing.owner:match("^%S+") or nil -- first name only, to keep the button short
    LayoutActions(d)
end

-- Only what follows the panel's size, from what UpdateDetail last showed. Runs on its own while the window is
-- being resized, when the recipe and its materials haven't changed.
function UI:LayoutDetail()
    local d = self.frame.detail
    if not d.content:IsShown() then return end
    LayoutTiles(d)
    FitName(d)
    LayoutReagentCards(d, d.cardCount, d.cardTargeted)
    LayoutActions(d)
end
