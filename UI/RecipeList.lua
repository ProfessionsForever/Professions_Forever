local _, FP = ...
local L = FP.L
local UI = FP.UI
local Skin = UI.ActiveSkin
local STATUS_COLORS, DIFF_COLORS, DIFF_LABELS, WHITE_RGB = UI.STATUS_COLORS, UI.DIFF_COLORS, UI.DIFF_LABELS, UI.WHITE_RGB
local RecipeRowHeight, RankInfo = UI.RecipeRowHeight, UI.RankInfo
local MAX_ROWS = 60
local GREY_RGB = { 0.5, 0.5, 0.5 }

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
    self.filtered = FP.Recipes:GetFiltered(o)
    self.display = FP.Recipes:BuildDisplay(self.filtered, db.collapsedCategories, (self.search or "") ~= "", not db.hideCategories, db.favoritesOnly)
    if self.pendingRecipe and FP.Recipes.byID[self.pendingRecipe] then
        FP.selected, self.pendingRecipe, self.scrollToSelected = self.pendingRecipe, nil, true
    end
    if not FP.selected or not FP.Recipes.byID[FP.selected] then
        -- Back on a profession: the recipe last clicked in it, if the current filters still show it.
        local _, _, _, _, skillLine = RankInfo()
        local last = skillLine and db.lastRecipe[skillLine]
        FP.selected = nil
        for _, e in ipairs(self.filtered) do
            if e.id == last then FP.selected = last break end
        end
        FP.selected = FP.selected or (self.filtered[1] and self.filtered[1].id or nil)
        self.scrollToSelected = true
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
            if f.scroll.fpEUIScrollTo then f.scroll.fpEUIScrollTo(y)
            elseif f.scroll.ScrollBar then f.scroll.ScrollBar:SetValue(y) end
            return
        end
    end
end

-- Rebuilds the recipe list at the top after a search, filter or sort change.
function UI:Relist()
    self:RefreshFilter()
    self.scrollToSelected = false -- a search or filter change starts at the top
    local scrollBar = self.frame.scroll.ScrollBar
    if scrollBar then scrollBar:SetValue(0) end
    self:UpdateList()
    self:UpdateDetail()
end

-- True when any filter preset differs from its default.
local function PresetsActive(db)
    for k, default in pairs(FP.filterDefaults) do
        if db[k] ~= default then return true end
    end
    return false
end

-- Refreshes the sort, category, density and filter dropdowns.
function UI:SyncFilters()
    local f = self.frame
    if not (f and f.filtersDD and f.sortDD and f.filterReset) then return end
    f.sortDD:Sync()
    if f.rowDensity then f.rowDensity:Sync() end
    f.filtersDD:Sync()
    local db = FP.db
    local presetsActive = PresetsActive(db)
    f.filtersDD:SetBackdropBorderColor(unpack(presetsActive and self:GetAccent() or Skin().button.border))
    f.sortDir.arrow:SetTexture(FP.db.sortDesc and "Interface\\Buttons\\Arrow-Down-Up" or "Interface\\Buttons\\Arrow-Up-Up")
    f.categoryDD:Sync()
    f.categoryDD:SetActive(true) -- the favorites group is always available
    f.expandAll:SetShown(not db.hideCategories)
    f.collapseAll:SetShown(not db.hideCategories)
    f.categoryDD:ClearAllPoints()
    f.categoryDD:SetPoint("TOPLEFT", f.left, "TOPLEFT", 6, -34)
    f.categoryDD:SetPoint("TOPRIGHT", db.hideCategories and f.rowDensity or f.collapseAll, "TOPLEFT", -4, 0)
    f.filterReset:SetActive(self.categoryName ~= nil or presetsActive)
    f.expandAll:SetActive(next(FP.Recipes.categories) ~= nil)
    f.collapseAll:SetActive(next(FP.Recipes.categories) ~= nil)
end

-- "Trained by" text for a remembered trainer record.
local function TrainerText(trainer)
    return L["Trained by: %s"]:format(trainer.zone and ("%s (%s)"):format(trainer.npc, trainer.zone) or trainer.npc)
end

-- What the recipe makes, when it can be worn and so previewed.
local function PreviewLink(recipeID)
    local output = FP.Recipes:OutputInfo(recipeID)
    local link = output and (output.hyperlink or (output.itemID and select(2, C_Item.GetItemInfo(output.itemID))))
    if link and C_Item.IsDressableItemByID(link) then return link end
end

-- Ctrl-click preview: opens the dressing room on the recipe's result. Returns true when it did.
function UI.PreviewRecipe(recipeID)
    local link = recipeID and PreviewLink(recipeID)
    if not (link and DressUpLink(link)) then return false end
    if DressUpFrame then DressUpFrame:Raise() end -- already-open dressing room stays under our clicked window otherwise
    return true
end

-- A learned recipe is tracked in the game's own objective tracker (shows its reagents as you gather them);
-- an unlearned one gets a waypoint to where it is learned.
function UI.TrackRecipe(e)
    if not e.learned then return FP.Waypoint:ForRecipe(e.id) end
    C_TradeSkillUI.SetRecipeTracked(e.id, not C_TradeSkillUI.IsRecipeTracked(e.id, false), false)
    UI:UpdateDetail()
end

-- Chat-link click: link the thing, or track the recipe when no chat box takes it. True when the click was spent.
function UI.LinkOrTrack(link, e)
    if UI.LinkToChat(link) then return true end
    if e and IsModifiedClick("RECIPEWATCHTOGGLE") then UI.TrackRecipe(e) return true end
    return false
end

-- Adds where an unlearned recipe comes from (source text, trainer, vendors) to the shared GameTooltip.
function UI.AddSourceLines(recipeID)
    local src = C_TradeSkillUI.GetRecipeSourceText and C_TradeSkillUI.GetRecipeSourceText(recipeID)
    local hasSrc = src and src ~= ""
    if src and hasSrc then GameTooltip:AddLine(src, 1, 0.82, 0, true) end
    local trainer = FP.Waypoint:TrainerFor(recipeID)
    if trainer then GameTooltip:AddLine(TrainerText(trainer), 1, 0.82, 0, true) end
    local sold, loading = FP.Waypoint:Summary(recipeID)
    if sold then GameTooltip:AddLine(L["Sold by: %s"]:format(sold), 1, 0.82, 0, true) end
    if loading then GameTooltip:AddLine(L["Looking up vendors..."], 0.6, 0.6, 0.6) end
    if not (hasSrc or trainer or sold or loading) then
        GameTooltip:AddLine(L["Source not discovered yet"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Visit a trainer for this profession and ProfessionsForever will remember what they teach."], 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine(L["Recipes a trainer doesn't offer are usually sold by a vendor, dropped, or earned from a quest."], 0.6, 0.6, 0.6, true)
    end
    if FP.Waypoint:Available(recipeID) and (trainer or sold) and not PreviewLink(recipeID) then
        GameTooltip:AddLine(L["Ctrl-click: set a TomTom waypoint"], 0.5, 0.8, 1)
    end
end

-- One line on where an unlearned recipe is learned from, and whether a location is known to set a waypoint to.
local function SourceSummary(recipeID)
    local trainer = FP.Waypoint:TrainerFor(recipeID)
    if trainer then return TrainerText(trainer), true end
    local sold, loading = FP.Waypoint:Summary(recipeID)
    if sold then return L["Sold by: %s"]:format(sold), true end
    if loading then return L["Looking up vendors..."], false end
    return L["Location not currently known"], false
end

-- Crafts from bags, the extra the bank adds, and the extra enabled alts add: the same split as the detail tiles.
local function Craftable(recipeID)
    local ev = FP.Recipes:Evaluate(recipeID)
    local withAlts = ev.craftTotal
    if #ev.reagents > 0 and FP.Planner:Mode() ~= "never" then
        withAlts = math.max(ev.craftTotal, FP.Planner:MaxCrafts(ev.reagents))
    end
    return ev, ev.craftBags, ev.craftTotal - ev.craftBags, withAlts - ev.craftTotal
end

local function Hex(c)
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
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

function UI:EnsureRows(n)
    local f = self.frame
    n = math.min(n, MAX_ROWS)
    local rowHeight = RecipeRowHeight()
    for i = #self.rows + 1, n do
        local row = CreateFrame("Button", nil, f.list)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", f.list, "TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetPoint("TOPRIGHT", f.rowEdge, "TOPRIGHT", 0, -(i - 1) * rowHeight)
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
            local e = s.recipeID and FP.Recipes.byID[s.recipeID]
            if not e then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            local output = FP.Recipes:OutputInfo(e.id)
            if output and output.hyperlink then GameTooltip:SetHyperlink(output.hyperlink)
            elseif output and output.itemID then GameTooltip:SetItemByID(output.itemID)
            else GameTooltip:AddLine(e.name, 1, 1, 1) end
            GameTooltip:AddLine(e.name, 1, 0.82, 0)
            GameTooltip:AddLine(e.learned and L["Learned"] or L["Not Learned"], 0.6, 0.6, 0.6)
            local difficulty = DIFF_LABELS[e.difficulty]
            if difficulty then GameTooltip:AddLine(L[difficulty], 1, 0.82, 0) end
            local cooldown = FP.Cooldowns:DetailText(e.id)
            if cooldown ~= "" then GameTooltip:AddLine(cooldown) end
            local description = UI.RecipeDescription(e.id)
            if description then GameTooltip:AddLine(description, 0.9, 0.9, 0.9, true) end
            if not e.learned then UI.AddSourceLines(e.id) end
            local ev, bags, bank, alts = Craftable(e.id)
            if #ev.reagents > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine(L["From Bags"], bags, 0.8, 0.8, 0.8, unpack(STATUS_COLORS.full))
                GameTooltip:AddDoubleLine(L["From Bank"], "+" .. bank, 0.8, 0.8, 0.8, unpack(STATUS_COLORS.bank))
                if FP.Planner:Mode() ~= "never" then
                    GameTooltip:AddDoubleLine(L["From Alts"], "+" .. alts, 0.8, 0.8, 0.8, unpack(UI.ALT_COLOR))
                end
                GameTooltip:AddDoubleLine(L["Total Craftable"], bags + bank + alts, 1, 1, 1, 1, 1, 1)
                GameTooltip:AddDoubleLine(L["Reagents in Stock"], ev.satisfied .. " / " .. #ev.reagents, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
            end
            if PreviewLink(e.id) then GameTooltip:AddLine(L["Ctrl-click: preview"], 0.5, 0.8, 1) end
            GameTooltip:Show()
            UI:ShowTooltipIcon(e.icon)
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.rows[i] = row
    end
    for i, row in ipairs(self.rows) do
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.list, "TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetPoint("TOPRIGHT", f.rowEdge, "TOPRIGHT", 0, -(i - 1) * rowHeight)
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
    f.rowEdge:SetBar(n > self.numRows)
    if f.scroll.fpEUISetRange then f.scroll:fpEUISetRange(math.max(0, n - self.numRows) * rowHeight) end
    local offset = FauxScrollFrame_GetOffset(f.scroll)
    local a = self:GetAccent()
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
            row.mats:SetText(FP.Cooldowns:RowText(e.id) .. (#ev.reagents > 0 and CraftableText(ev, bags, bank, alts) or ""))
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
    FP.selected = recipeID
    local _, _, _, _, skillLine = RankInfo()
    if skillLine then FP.db.lastRecipe[skillLine] = recipeID end
    self:UpdateList()
    self:UpdateDetail()
end
UI.PreviewLink, UI.SourceSummary = PreviewLink, SourceSummary

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
