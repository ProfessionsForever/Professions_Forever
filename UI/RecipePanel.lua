local _, FP = ...
local L = FP.L
local UI = FP.UI
local RecipeRowHeight = UI.RecipeRowHeight

-- Sorts: key, label in the menu, label on the button.
local SORTS = {
    { "name", "Name", "Name" }, { "difficulty", "Skill Up Difficulty", "Skill Up" }, { "chance", "Skill Up Chance", "Chance" },
    { "craftable", "Craftable Amount", "Craftable" }, { "profit", "Profit", "Profit" },
}
local FILTERS = {
    { "showUnlearned", "Show Unlearned" }, { "unlearnedOnly", "Unlearned Only" }, { "hasMatsOnly", "Has Materials" },
    { "skillUpsOnly", "Orange and Yellow Only" }, { "hideTrivial", "Hide Grey Recipes" }, { "favoritesOnly", "Favorites Only" },
    { "hideCategories", "Do Not Show Category Headers" },
}

-- The saved sort, except that profit counts as name without Auctionator.
local function SortKey()
    local key = FP.db.sortKey
    return key == "profit" and not FP.Prices:Available() and "name" or key
end

-- Left panel: the search, sort and filter rows (UI/Common/ListHeader.lua) and the recipe list.
function UI:CreateRecipePanel(f)
    local left = CreateFrame("Frame", "ProfessionsForeverRecipePanel", f, "BackdropTemplate")
    left:SetPoint("TOPLEFT", 8, -93)
    left:SetPoint("BOTTOMLEFT", 8, 8 + UI.FOOTER_RESERVE)
    left:SetWidth(325)
    f.left = left
    self:Skin(left, "panel")

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
    local function Relist() UI:Relist() end

    local header = self:CreateListHeader(left, -7, {
        name = "ProfessionsForeverSearch",
        onSearch = function(text)
            UI.search = text
            UI:Relist()
        end,
        matches = SearchMatches,
        -- A suggestion picked: the recipe is selected, rather than waiting out the typing pause.
        pick = function(name)
            for _, e in ipairs(UI.filtered) do
                if e.name == name then
                    UI:Select(e.id)
                    UI:ScrollToSelected()
                    return
                end
            end
        end,
        sorts = SORTS,
        getSort = SortKey,
        setSort = function(key) FP.db.sortKey = key end,
        sortShown = function(key) return key ~= "profit" or FP.Prices:Available() end,
        descKey = "sortDesc",
        onSort = Relist,
        categoryLabel = function()
            if UI.categoryName == FP.Recipes.FAVORITES then return L["Favorites"] end
            return UI.categoryName or L["All Categories"]
        end,
        categoryItems = function()
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
        end,
        onCollapse = SetAllCollapsed,
        canCollapse = function() return next(FP.Recipes.categories) ~= nil end,
        hideCollapse = function() return FP.db.hideCategories end,
        onDensity = function()
            UI:SetNumRows(f:GetHeight())
            f.scroll.fpScrollTo(0)
            UI:SyncFilters()
            UI:UpdateList()
            UI:UpdateDetail()
        end,
        filters = function() return FILTERS end,
        filterDefaults = FP.filterDefaults,
        onFilter = Relist,
        filterActive = function() return UI.categoryName ~= nil end,
        onReset = function() UI.categoryName = nil end,
        extra = function(parent) return FP.ReagentSearch:CreateButton(parent, 24) end,
    })
    f.listHeader, f.search = header, header.search
    self:CreateRecipeList(f)
end

-- The scrolling recipe list.
function UI:CreateRecipeList(f)
    local left = f.left
    local list = CreateFrame("Frame", "ProfessionsForeverRecipeList", left)
    list:SetPoint("TOPLEFT", 6, f.listHeader.bottom)
    list:SetPoint("BOTTOMRIGHT", -6, 2)
    f.list = list
    local scroll = CreateFrame("ScrollFrame", "ProfessionsForeverRecipeScroll", list, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -UI.BAR_GUTTER, 0)
    scroll:SetScript("OnVerticalScroll", function(s, offset)
        FauxScrollFrame_OnVerticalScroll(s, offset, RecipeRowHeight(), function() UI:UpdateList() end)
    end)
    f.scroll = scroll
    local scrollBar = scroll.ScrollBar or _G["ProfessionsForeverRecipeScrollScrollBar"]
    self:AttachScrollbar(scroll, scrollBar, list)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        scroll.fpScrollTo(scroll:GetVerticalScroll() - delta * RecipeRowHeight() * 3)
    end)
end
