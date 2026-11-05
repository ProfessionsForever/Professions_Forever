local _, FP = ...
local L = FP.L
local UI = FP.UI
local RecipeRowHeight = UI.RecipeRowHeight

local DENSITY_OPTIONS = { "compact", "normal", "roomy", "spacious" }
local SORTS = { "name", "difficulty", "craftable", "profit" }
local SORT_LABELS = { name = "Name", difficulty = "Skill Up Difficulty", craftable = "Craftable Amount", profit = "Profit" }
local SORT_DISPLAY_LABELS = { name = "Name", difficulty = "Skill Up", craftable = "Craftable", profit = "Profit" }
local DENSITY_LABELS = { compact = "Compact", normal = "Normal", roomy = "Roomy", spacious = "Spacious" }

-- The saved sort, except that profit counts as name without Auctionator.
local function SortKey()
    local key = FP.db.sortKey
    return key == "profit" and not FP.Prices:Available() and "name" or key
end

-- Left panel: the search box, filter bar and recipe list.
function UI:CreateRecipePanel(f)
    -- Left: search + list
    local left = CreateFrame("Frame", "ProfessionsForeverRecipePanel", f, "BackdropTemplate")
    left:SetPoint("TOPLEFT", 8, -93)
    left:SetPoint("BOTTOMLEFT", 8, 8 + UI.FOOTER_RESERVE)
    left:SetWidth(325)
    f.left = left
    self:Skin(left, "panel")

    local search = CreateFrame("EditBox", "ProfessionsForeverSearch", left, "InputBoxTemplate")
    search:SetPoint("TOPLEFT", left, "TOPLEFT", 11, -7)
    search:SetHeight(24)
    search:SetAutoFocus(false)
    self:EUIWidget(search, "editbox")
    search:SetTextInsets(4, 0, 0, 0)
    f.search = search
    local ph = self:Text(search, -1)
    ph:SetPoint("LEFT", 4, 0)
    ph:SetText(L["Search..."])
    ph:SetTextColor(0.5, 0.5, 0.5)
    -- Typing waits this long before the list is rebuilt, so fast typing filters once rather than per letter.
    local SEARCH_DELAY, token, lastText = 0.12, 0, ""
    -- Recipe names in the list that contain the text, those starting with it first.
    local function SearchMatches(text)
        local typed = strlower(text)
        if #typed < 2 then return {} end
        local prefix, within, seen = {}, {}, {}
        for _, e in ipairs(UI.filtered) do
            e.nameLower = e.nameLower or strlower(e.name)
            local at = strfind(e.nameLower, typed, 1, true)
            if at and not seen[e.nameLower] then
                seen[e.nameLower] = true
                local group = at == 1 and prefix or within
                group[#group + 1] = e
            end
        end
        local function ByName(a, b) return a.nameLower < b.nameLower end
        table.sort(prefix, ByName)
        table.sort(within, ByName)
        local out = {}
        for _, e in ipairs(prefix) do out[#out + 1] = e.name end
        for _, e in ipairs(within) do out[#out + 1] = e.name end
        return out
    end
    -- Fills the box, lists the recipe and selects it, rather than waiting out the typing pause.
    local function PickRecipe(name)
        local pick
        for _, e in ipairs(UI.filtered) do
            if e.name == name then pick = e break end
        end
        search:SetText(name)
        token = token + 1
        UI:Relist()
        if pick then
            UI:Select(pick.id)
            UI:ScrollToSelected()
        end
        search:ClearFocus()
    end
    local completion = self:AttachCompletion(search, SearchMatches, false, PickRecipe)
    search:SetScript("OnTextChanged", function(s)
        local text = s:GetText()
        if text == lastText then return end
        lastText = text
        ph:SetShown(text == "")
        UI.search = text
        completion:Clear()
        token = token + 1
        local mine = token
        local function Apply()
            UI:Relist()
            completion:Update()
        end
        if text == "" then return Apply() end
        C_Timer.After(SEARCH_DELAY, function() if token == mine then Apply() end end)
    end)
    search:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(s)
        local pick = completion:Selected()
        if pick then PickRecipe(pick) else s:ClearFocus() end
    end)

    self:AddClearButton(search, L["Clear Search"])
    self:CreateFilterBar(f)
    self:CreateRecipeList(f)
end

-- Puts the category and filter presets back to their defaults; the search text is left alone.
function UI:ResetFilters()
    for k, v in pairs(FP.filterDefaults) do FP.db[k] = v end
    self.categoryName = nil
    self:SyncFilters()
    self:Refresh()
end

-- Sort, category and density dropdowns, expand / collapse buttons and the filter menu.
function UI:CreateFilterBar(f)
    local left, search = f.left, f.search

    -- Sort and category dropdowns; the arrow button flips the sort direction.
    f.sortDir = self:Button(left, "", 24, 24, function()
        FP.db.sortDesc = not FP.db.sortDesc
        UI:Relist()
    end)
    f.sortDir:SetPoint("TOPRIGHT", left, "TOPRIGHT", -6, -7)
    f.sortDir.arrow = f.sortDir:CreateTexture(nil, "OVERLAY")
    f.sortDir.arrow:SetSize(16, 16)
    f.sortDir.arrow:SetPoint("CENTER",2,0)
    self:Tooltip(f.sortDir, "ANCHOR_RIGHT", L["Reverse the Sort Order"])

    f.sortDD = self:Dropdown(left, 120, 24, function()
        return L["Sort"] .. ": " .. L[SORT_DISPLAY_LABELS[SortKey()] or "Name"]
    end, function()
        local items = {}
        for _, key in ipairs(SORTS) do
            if key ~= "profit" or FP.Prices:Available() then
                items[#items + 1] = { text = L[SORT_LABELS[key]], checked = SortKey() == key,
                    onSelect = function() FP.db.sortKey = key UI:Relist() end }
            end
        end
        return items
    end)
    f.sortDD:SetPoint("TOPRIGHT", f.sortDir, "TOPLEFT", -4, 0)
    search:SetPoint("TOPRIGHT", f.sortDD, "TOPLEFT", -4, 0)
    f.sortDD:SetPoint("RIGHT", f.sortDir, "LEFT", -4, 0)

    f.categoryDD = self:Dropdown(left, 10, 24, function()
        if UI.categoryName == FP.Recipes.FAVORITES then return L["Favorites"] end
        return UI.categoryName or L["All Categories"]
    end, function()
        local function Pick(name) UI.categoryName = name UI:Relist() end
        local items = {
            { text = L["All Categories"], checked = UI.categoryName == nil, onSelect = function() Pick(nil) end },
            { text = L["Favorites"], checked = UI.categoryName == FP.Recipes.FAVORITES, onSelect = function() Pick(FP.Recipes.FAVORITES) end },
        }
        for _, c in ipairs(FP.Recipes:CategoryNames()) do
            items[#items + 1] = { text = c.name, indent = c.depth, checked = UI.categoryName == c.name,
                onSelect = function() Pick(c.name) end }
        end
        return items
    end)
    f.rowDensity = self:Dropdown(left, 96, 24, function()
        return L[DENSITY_LABELS[FP.db.recipeDensity] or "Normal"]
    end, function()
        local items = {}
        for _, key in ipairs(DENSITY_OPTIONS) do
            local density = key
            local label = DENSITY_LABELS[density]
            items[#items + 1] = { text = L[label], checked = FP.db.recipeDensity == density,
                onSelect = function()
                    FP.db.recipeDensity = density
                    UI:SetNumRows(f:GetHeight())
                    if f.scroll.ScrollBar then f.scroll.ScrollBar:SetValue(0) end
                    UI:SyncFilters()
                    UI:UpdateList()
                    UI:UpdateDetail()
                end }
        end
        return items
    end)
    f.rowDensity:SetPoint("TOPRIGHT", left, "TOPRIGHT", -6, -34)
    self:Tooltip(f.rowDensity, "ANCHOR_RIGHT", function(tip)
        tip:AddLine(L["Row Spacing"], 1, 1, 1)
        tip:AddLine(L["How tall each recipe in the list is. Taller rows are easier to read; shorter rows fit more recipes."], 0.8, 0.8, 0.8, true)
    end)

    -- Expand / collapse every category header in the list.
    local function SetAllCollapsed(collapse)
        local collapsed = FP.db.collapsedCategories
        wipe(collapsed)
        if collapse then
            for id in pairs(FP.Recipes.categories) do collapsed[id] = true end
        end
        UI:RefreshFilter()
        UI:UpdateList()
    end
    local function HeaderButton(label, tip, collapse, anchor)
        local b = self:Button(left, label, 24, 24, function() SetAllCollapsed(collapse) end)
        b:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
        self:Tooltip(b, "ANCHOR_RIGHT", L[tip])
        return b
    end
    f.expandAll = HeaderButton("+", "Expand All Categories", false, f.rowDensity)
    f.collapseAll = HeaderButton("-", "Collapse All Categories", true, f.expandAll)
    f.categoryDD:SetPoint("TOPLEFT", left, "TOPLEFT", 6, -34)
    f.categoryDD:SetPoint("TOPRIGHT", f.collapseAll, "TOPLEFT", -4, 0)

    f.filtersDD = self:Dropdown(left, 10, 24, function() return L["Filters"] end, function()
        local options = {
            { "showUnlearned", "Show Unlearned" },
            { "unlearnedOnly", "Unlearned Only" },
            { "hasMatsOnly", "Has Materials" },
            { "skillUpsOnly", "Orange and Yellow Only" },
            { "hideTrivial", "Hide Grey Recipes" },
            { "favoritesOnly", "Favorites Only" },
            { "hideCategories", "Do Not Show Category Headers" },
        }
        local items = {}
        for _, option in ipairs(options) do
            local key, label = option[1], option[2]
            local item = { text = L[label], checked = FP.db[key], keepOpen = true }
            item.onSelect = function()
                FP.db[key] = not FP.db[key]
                item.checked = FP.db[key]
                UI:Relist()
            end
            items[#items + 1] = item
        end
        return items
    end)
    f.filterReset = self:Button(left, "X", 24, 24, function() UI:ResetFilters() end)
    f.filterReset.text:SetTextColor(1, 0.2, 0.2)
    f.filterReset:SetPoint("TOPRIGHT", left, "TOPRIGHT", -6, -61)
    self:Tooltip(f.filterReset, "ANCHOR_RIGHT", L["Reset All Filters"])
    f.filtersDD:SetPoint("TOPLEFT", left, "TOPLEFT", 6, -61)
    f.filtersDD:SetPoint("TOPRIGHT", f.filterReset, "TOPLEFT", -4, 0)
    self:SyncFilters()
end

-- The scrolling recipe list.
function UI:CreateRecipeList(f)
    local left = f.left
    local list = CreateFrame("Frame", "ProfessionsForeverRecipeList", left)
    list:SetPoint("TOPLEFT", 6, -89)
    list:SetPoint("BOTTOMRIGHT", -6, 2)
    f.list = list
    f.rowEdge = self:RowEdge(list, 26, 0)
    local scroll = CreateFrame("ScrollFrame", "ProfessionsForeverRecipeScroll", list, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    scroll:SetScript("OnVerticalScroll", function(s, offset)
        FauxScrollFrame_OnVerticalScroll(s, offset, RecipeRowHeight(), function() UI:UpdateList() end)
    end)
    f.scroll = scroll
    local scrollBar = scroll.ScrollBar or _G["ProfessionsForeverRecipeScrollScrollBar"]
    f.scrollBar = scrollBar
    if not self:AttachEUIThinScrollbar(scroll, scrollBar, list) then self:EUIWidget(scrollBar, "scrollbar") end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        if scroll.fpEUIScrollTo then
            scroll.fpEUIScrollTo(scroll:GetVerticalScroll() - delta * RecipeRowHeight() * 3)
        elseif scrollBar then
            scrollBar:SetValue(scrollBar:GetValue() - delta * RecipeRowHeight() * 3)
        end
    end)
end
