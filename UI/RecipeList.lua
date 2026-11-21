local _, FP = ...
local L = FP.L
local UI = FP.UI
local STATUS_COLORS, DIFF_COLORS, DIFF_LABELS, WHITE_RGB = UI.STATUS_COLORS, UI.DIFF_COLORS, UI.DIFF_LABELS, UI.WHITE_RGB
local RecipeRowHeight, RankInfo = UI.RecipeRowHeight, FP.RankInfo
local PreviewLink, Hex = UI.PreviewLink, UI.Hex -- UI/RecipeInfo.lua, UI/Shared.lua
local MAX_ROWS = 60
local GREY_RGB = { 0.5, 0.5, 0.5 }

-- Where the recipe last clicked in the shown profession is remembered (FP.db.lastRecipe): by skill line, or for
-- another character's profession by its key and skill line, so the two don't move each other's selection. nil until the
-- game says which profession is open: right after a login or reload it reports 0 for a moment (seen 2026-11-13).
local function LastRecipeKey()
    local viewing = FP.AltProfs.viewing
    if viewing then return viewing.key .. ":" .. viewing.skillLine end
    local skillLine = select(5, RankInfo())
    if skillLine and skillLine ~= 0 then return skillLine end
end

---------------------------------------------------------------------------
-- Recipe list
---------------------------------------------------------------------------
local filterOpts = {}
function UI:RefreshFilter()
    local db, o = FP.db, filterOpts
    local R = FP.Recipes
    if self.categoryName and self.categoryName ~= R.FAVORITES then
        local found = false
        for _, c in ipairs(R:CategoryNames()) do
            if c.name == self.categoryName then found = true break end
        end
        if not found then self.categoryName = nil end
    end
    o.search, o.showUnlearned, o.unlearnedOnly, o.matsOnly = self.search, db.showUnlearned, db.unlearnedOnly, db.hasMatsOnly
    o.categoryName = self.categoryName
    o.skillUps, o.hideTrivial, o.sortKey, o.sortDesc = db.skillUpsOnly, db.hideTrivial, db.sortKey, db.sortDesc
    o.favoritesOnly = db.favoritesOnly
    o.skill = select(2, RankInfo()) or 0
    self.filtered = FP.Recipes:GetFiltered(o)
    self.display = FP.Recipes:BuildDisplay(self.filtered, db.collapsedCategories, (self.search or "") ~= "", not db.hideCategories, db.favoritesOnly)
    if self.pendingRecipe and FP.Recipes.byID[self.pendingRecipe] then
        FP.selected, self.pendingRecipe, self.scrollToSelected = self.pendingRecipe, nil, true
        self.selectionStandIn = nil -- a recipe asked for (Recipe Search, a chat link) wins over the remembered one
    end
    -- Back on a profession: the recipe last clicked in it, if the current filters still show it. When it can't be found
    -- yet, the first listed recipe stands in and the remembered one is tried again on later refreshes: right after a
    -- login or reload the list can be built before the game says which profession is open, the key it is saved under.
    -- A click (UI:Select) ends the waiting.
    if not FP.selected or not FP.Recipes.byID[FP.selected] or self.selectionStandIn then
        local lastKey = LastRecipeKey()
        local last = lastKey and db.lastRecipe[lastKey]
        local found
        for _, e in ipairs(self.filtered) do
            if e.id == last then found = last break end
        end
        if found then
            if FP.selected ~= found then FP.selected, self.scrollToSelected = found, true end
            self.selectionStandIn = nil
        elseif not FP.selected or not FP.Recipes.byID[FP.selected] then
            FP.selected = self.filtered[1] and self.filtered[1].id or nil
            self.scrollToSelected = true
            self.selectionStandIn = last ~= nil or lastKey == nil -- something to wait for
        end
    end
    self:SyncFilters()
end

-- Brings the selected recipe into view, centred, when it isn't already (a recipe inside a collapsed category isn't listed).
function UI:ScrollToSelected()
    local f = self.frame
    for i, item in ipairs(self.display) do
        if item.recipe and item.recipe.id == FP.selected then
            local offset = FauxScrollFrame_GetOffset(f.scroll)
            if i > offset and i <= offset + self.numRows then return end
            local top = math.max(0, math.min(i - 1 - math.floor(self.numRows / 2), #self.display - self.numRows))
            local y = top * RecipeRowHeight()
            f.scroll.fpScrollTo(y)
            return
        end
    end
end

-- Rebuilds the recipe list at the top after a search, filter or sort change.
function UI:Relist()
    self:RefreshFilter()
    self.scrollToSelected = false -- a search or filter change starts at the top
    self.frame.scroll.fpScrollTo(0)
    self:UpdateList()
    self:UpdateDetail()
end

-- Redraws the search, sort, category, row spacing and filter rows (UI/Common/ListHeader.lua).
function UI:SyncFilters()
    local f = self.frame
    if f and f.listHeader then f.listHeader:Sync() end
end

-- Crafts from bags, the extra the bank adds, and the extra enabled alts add: the same split as the detail tiles.
local function Craftable(recipeID)
    local ev = FP.Recipes:Evaluate(recipeID)
    local withAlts = ev.craftTotal
    if #ev.reagents > 0 and FP.Planner:Mode() ~= "never" then
        withAlts = math.max(ev.craftTotal, FP.Planner:MaxCrafts(ev.reagents, FP.Recipes:Crafter()))
    end
    return ev, ev.craftBags, ev.craftTotal - ev.craftBags, withAlts - ev.craftTotal
end

-- A recipe row's tooltip, on GameTooltip or on `tip` (the options' previewer). `pv` stands in for what needs the
-- profession open: { itemID, chance, reagents, satisfied, bags, bank, alts, source = { trainer } }.
function UI.FillRecipeTooltip(e, tip, pv)
    tip = tip or GameTooltip
    local output = not pv and FP.Recipes:OutputInfo(e.id)
    if pv then tip:SetItemByID(pv.itemID)
    elseif output and output.hyperlink then tip:SetHyperlink(output.hyperlink)
    elseif output and output.itemID then tip:SetItemByID(output.itemID)
    else tip:AddLine(e.name, 1, 1, 1) end
    tip:AddLine(e.name, 1, 0.82, 0)
    tip:AddLine(e.learned and L["Learned"] or L["Not Learned"], 0.6, 0.6, 0.6)
    local required = not e.learned and UI.RequiredSkillText(e.id)
    if required then tip:AddLine(required) end
    local difficulty = DIFF_LABELS[e.difficulty]
    if difficulty then tip:AddLine(L[difficulty], 1, 0.82, 0) end
    local chance
    if pv then chance = pv.chance
    else chance = e.learned and FP.Recipes:SkillUpChance(e.id, select(2, RankInfo()) or 0) end
    if chance and chance > 0 and chance < 1 then
        tip:AddLine(L["Skill Up Chance: %d%%"]:format(math.floor(chance * 100 + 0.5)), 0.8, 0.8, 0.8)
    end
    if not pv then
        local cooldown = FP.Cooldowns:DetailText(e.id)
        if cooldown ~= "" then tip:AddLine(cooldown) end
        local description = UI.RecipeDescription(e.id)
        if description then tip:AddLine(description, 0.9, 0.9, 0.9, true) end
    end
    if UI.ShowsSource(e) then UI.AddSourceLines(e.id, e.learned, tip, pv and pv.source) end
    local reagents, satisfied, bags, bank, alts
    if pv then
        reagents, satisfied, bags, bank, alts = pv.reagents, pv.satisfied, pv.bags, pv.bank, pv.alts
    else
        local ev
        ev, bags, bank, alts = Craftable(e.id)
        reagents, satisfied = #ev.reagents, ev.satisfied
    end
    if reagents > 0 then
        tip:AddLine(" ")
        tip:AddDoubleLine(L["From Bags"], bags, 0.8, 0.8, 0.8, unpack(STATUS_COLORS.full))
        tip:AddDoubleLine(L["From Bank"], "+" .. bank, 0.8, 0.8, 0.8, unpack(STATUS_COLORS.bank))
        if FP.Planner:Mode() ~= "never" then
            tip:AddDoubleLine(L["From Alts"], "+" .. alts, 0.8, 0.8, 0.8, unpack(UI.ALT_COLOR))
        end
        tip:AddDoubleLine(L["Total Craftable"], bags + bank + alts, 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine(L["Reagents in Stock"], satisfied .. " / " .. reagents, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    end
    if not pv and PreviewLink(e.id) then tip:AddLine(L["Ctrl-click: preview"], 0.5, 0.8, 1) end
end

-- The skill up chance of a learned recipe, in its difficulty colour; nothing once it is grey or when the option is off.
local function ChanceText(e, skill)
    if not (FP.db.showSkillChance and e.learned) then return "" end
    local chance = FP.Recipes:SkillUpChance(e.id, skill)
    if not chance or chance <= 0 then return "" end
    return Hex(DIFF_COLORS[e.difficulty] or WHITE_RGB) .. math.floor(chance * 100 + 0.5) .. "%|r "
end

-- "4 +7 +12": bags in green, then what the bank adds in cyan, then what alts add in purple. With nothing craftable it
-- shows how many reagents you have enough of instead, e.g. "2/3", in the recipe's status colour.
local function CraftableText(ev, bags, bank, alts)
    local parts = {}
    if bags > 0 then parts[#parts + 1] = Hex(STATUS_COLORS.full) .. bags .. "|r" end
    if bank > 0 then parts[#parts + 1] = Hex(STATUS_COLORS.bank) .. "+" .. bank .. "|r" end
    if alts > 0 then parts[#parts + 1] = Hex(UI.ALT_COLOR) .. "+" .. alts .. "|r" end
    if #parts > 0 then return table.concat(parts, " ") end
    return Hex(STATUS_COLORS[ev.status] or STATUS_COLORS.none) .. ev.satisfied .. "/" .. #ev.reagents .. "|r"
end

-- A recipe row's tooltip docked outside the main window (Options, Tooltips, Recipes), so it doesn't cover the recipe
-- panel: on the chosen side of the window, or the other one when the screen has no room there. "beside" is level
-- with the row, "corner" with the list's top row. The icon UI:ShowTooltipIcon hangs on the tooltip's left counts.
-- Returns whether it went left.
local DOCK_GAP, DOCK_ICON = 4, 52
local function DockRowTooltip(row)
    local db, f, tip = FP.db, UI.frame, GameTooltip
    local scale, tipScale = f:GetEffectiveScale(), tip:GetEffectiveScale()
    local level = db.tipRecipePlace == "beside" and row or UI.rows[1]
    local y = (level:GetTop() - f:GetTop()) * scale / tipScale
    local need = (tip:GetWidth() + DOCK_GAP + DOCK_ICON) * tipScale
    local left
    if db.tipRecipeSide == "left" then left = f:GetLeft() * scale >= need
    else left = UIParent:GetRight() * UIParent:GetEffectiveScale() - f:GetRight() * scale < need end
    tip:ClearAllPoints()
    if left then tip:SetPoint("TOPRIGHT", f, "TOPLEFT", -DOCK_GAP, y)
    else tip:SetPoint("TOPLEFT", f, "TOPRIGHT", DOCK_GAP + DOCK_ICON, y) end
    return left
end

-- The worn-gear comparison tooltips of a docked tooltip build away from the window: leftwards past the icon on the
-- left, rightwards on the right. The game would put them wherever the screen has room, over the window.
local function DockCompareTooltips(left)
    local one, two = ShoppingTooltip1, ShoppingTooltip2
    if not one:IsShown() then return end
    one:ClearAllPoints()
    if left then one:SetPoint("TOPRIGHT", GameTooltip, "TOPLEFT", -DOCK_ICON, 0)
    else one:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT") end
    if not two:IsShown() then return end
    two:ClearAllPoints()
    if left then two:SetPoint("TOPRIGHT", one, "TOPLEFT")
    else two:SetPoint("TOPLEFT", one, "TOPRIGHT") end
end

-- The row under the mouse. With the tooltip shown only while the detail key is held, the key going down or up
-- shows or hides it without the mouse moving.
local hovered
FP:RegisterEvent("MODIFIER_STATE_CHANGED", function()
    if hovered and FP.db.tipRecipeShow == "shift" then hovered:GetScript("OnEnter")(hovered) end
end)

function UI:EnsureRows(n)
    local f = self.frame
    n = math.min(n, MAX_ROWS)
    local rowHeight = RecipeRowHeight()
    for i = #self.rows + 1, n do
        local row = CreateFrame("Button", nil, f.list)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", f.list, "TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetPoint("TOPRIGHT", f.list, "TOPRIGHT", -UI.BAR_GUTTER, -(i - 1) * rowHeight)
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 1, 1, 0.08)
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetSize(4, rowHeight - 4)
        row.bar:SetPoint("LEFT", 2, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(rowHeight - 4, rowHeight - 4)
        row.icon:SetPoint("LEFT", 10, 0)
        row.fav = row:CreateTexture(nil, "OVERLAY")
        row.fav:SetSize(12, 12)
        row.fav:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -4, 3)
        row.fav:SetTexture("Interface\\Common\\ReputationStar")
        row.fav:SetTexCoord(0, 0.5, 0, 0.5)
        row.fav:Hide()
        row.forever = row:CreateTexture(nil, "OVERLAY") -- new or changed in Forever, under the favorite star
        row.forever:SetSize(14, 14)
        row.forever:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMLEFT", -5, -4)
        row.forever:Hide()
        row.mats = self:Text(row, -1, "RIGHT")
        row.mats:SetPoint("RIGHT", -4, 0)
        row.name = self:Text(row, 0)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.name:SetPoint("RIGHT", row.mats, "LEFT", -4, 0)
        row.name:SetWordWrap(false)
        row:SetScript("OnClick", function(s)
            if s.categoryID then
                local collapsed = FP.db.collapsedCategories
                collapsed[s.categoryID] = (not collapsed[s.categoryID]) or nil
                UI:RefreshFilter()
                UI:UpdateList()
                return
            end
            if not s.recipeID then return end
            local e = FP.Recipes.byID[s.recipeID]
            if UI.LinkOrTrack(C_TradeSkillUI.GetRecipeLink(s.recipeID), e) then return end
            if IsControlKeyDown() and e then
                if UI.PreviewRecipe(e.id) then return end
                if not e.learned and FP.Waypoint:Available(e.id) then return FP.Waypoint:ForRecipe(e.id) end
            end
            UI:Select(s.recipeID)
        end)
        row:SetScript("OnEnter", function(s)
            hovered = s
            local e = s.recipeID and FP.Recipes.byID[s.recipeID]
            if not e then return end
            if FP.db.tipRecipeShow == "shift" and not FP.Tooltips:DetailDown() then return GameTooltip:Hide() end
            local docked = FP.db.tipRecipePlace ~= "row"
            GameTooltip:SetOwner(s, docked and "ANCHOR_NONE" or "ANCHOR_RIGHT")
            if docked then DockRowTooltip(s) end
            UI.FillRecipeTooltip(e)
            GameTooltip:Show()
            -- Again, now that its width says which side has room.
            if docked then DockCompareTooltips(DockRowTooltip(s)) end
            UI:ShowTooltipIcon(e.icon)
        end)
        row:SetScript("OnLeave", function()
            hovered = nil
            GameTooltip:Hide()
        end)
        self.rows[i] = row
    end
    for i, row in ipairs(self.rows) do
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.list, "TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetPoint("TOPRIGHT", f.list, "TOPRIGHT", -UI.BAR_GUTTER, -(i - 1) * rowHeight)
        row.bar:SetSize(4, rowHeight - 4)
        row.icon:SetSize(rowHeight - 4, rowHeight - 4)
    end
end

function UI:UpdateList()
    local f = self.frame
    if not f then return end
    self:EnsureRows(self.numRows)
    local data, n = self.display, #self.display
    local rowHeight = RecipeRowHeight()
    FauxScrollFrame_Update(f.scroll, n, self.numRows, rowHeight)
    f.scroll.fpSetRange(math.max(0, n - self.numRows) * rowHeight)
    local offset = FauxScrollFrame_GetOffset(f.scroll)
    local a = self:GetAccent()
    local skill = select(2, RankInfo()) or 0
    for i, row in ipairs(self.rows) do
        local item = (i <= self.numRows) and data[offset + i] or nil
        local e = item and item.recipe
        local category = item and item.category
        row.name:ClearAllPoints()
        if category then
            ---@cast item -?
            row.recipeID, row.categoryID = nil, category.id
            row.icon:Hide()
            row.fav:Hide()
            row.bar:Hide()
            row.mats:SetText("")
            row.name:SetPoint("LEFT", 6 + item.depth * 10, 0)
            row.name:SetPoint("RIGHT", -4, 0)
            row.name:SetTextColor(a[1], a[2], a[3])
            row.name:SetText((item.open and "- " or "+ ") .. category.name .. " (" .. item.count .. ")")
            row.sel:SetColorTexture(1, 1, 1, 0.06)
            row:Show()
        elseif e then
            ---@cast item -?
            row.categoryID = nil
            row.icon:Show()
            row.fav:SetShown(e.favorite)
            local forever = UI.ForeverIcon(e.id)
            row.forever:SetTexture(forever)
            row.forever:SetShown(forever ~= nil)
            row.bar:Show()
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", 10 + item.depth * 6, 0)
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.name:SetPoint("RIGHT", row.mats, "LEFT", -4, 0)
            local ev, bags, bank, alts = Craftable(e.id)
            local c = STATUS_COLORS[ev.status]
            -- Not craftable from your own stock, but alts could cover at least one craft.
            if (ev.status == "partial" or ev.status == "missing") and alts > 0 then c = UI.ALT_COLOR end
            row.recipeID = e.id
            row.icon:SetTexture(e.icon)
            row.bar:SetColorTexture(c[1], c[2], c[3], 1)
            local dc = e.learned and (DIFF_COLORS[e.difficulty] or WHITE_RGB) or GREY_RGB
            row.name:SetTextColor(dc[1], dc[2], dc[3])
            row.name:SetText(e.learned and e.name or (e.name .. " *"))
            row.mats:SetText(ChanceText(e, skill) .. FP.Cooldowns:RowText(e.id) .. (#ev.reagents > 0 and CraftableText(ev, bags, bank, alts) or ""))
            row.mats:SetTextColor(1, 1, 1)
            if e.id == FP.selected then row.sel:SetColorTexture(a[1], a[2], a[3], 0.25) else row.sel:SetColorTexture(0, 0, 0, 0) end
            row:Show()
        else
            row.recipeID, row.categoryID = nil, nil
            row:Hide()
        end
    end
end

function UI:Select(recipeID)
    FP.selected, self.selectionStandIn = recipeID, nil
    local lastKey = LastRecipeKey()
    if lastKey then FP.db.lastRecipe[lastKey] = recipeID end
    self:UpdateList()
    self:UpdateDetail()
end

-- Shows a recipe in the main window, opening its profession first when another one is open. The selection waits in
-- pendingRecipe until the profession's recipes have loaded, and lapses if that never happens.
function UI:OpenRecipe(recipeID, skillLine)
    self.pendingRecipe = recipeID
    C_Timer.After(5, function()
        if self.pendingRecipe == recipeID then self.pendingRecipe = nil end
    end)
    self:Show("recipes")
    if not FP.Recipes.byID[recipeID] then FP:OpenProfession(skillLine) end
end
