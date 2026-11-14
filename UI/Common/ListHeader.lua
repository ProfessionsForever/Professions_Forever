local _, FP = ...
local L = FP.L
local UI = FP.UI

-- The three rows of controls above a list, shared by the recipe list (UI/RecipePanel.lua) and Disenchanting Mode's
-- gear list (UI/DisenchantMode.lua) so both look and behave the same:
--   [Search..........][Sort: x v][arrow]
--   [Category v.........][-][+][Spacing v]
--   [Filters v...........][extra][X]
-- Row spacing is one setting for every list (FP.db.recipeDensity, read by UI.RecipeRowHeight).

local ROW_STEP = 27 -- from one row's top to the next
local SEARCH_DELAY = 0.12 -- typing waits this long before the list is rebuilt, so fast typing filters once
local DENSITIES = { "compact", "normal", "roomy", "spacious" }
local DENSITY_LABELS = { compact = "Compact", normal = "Normal", roomy = "Roomy", spacious = "Spacious" }

-- The search box. Every text change goes to onSearch(text), after the typing pause (at once when emptied). With
-- matches(text) -> names, it suggests names as you type; a suggestion clicked or picked with Enter fills the box, goes
-- to onSearch at once, then to pick(name).
local function SearchBox(parent, opts)
    local eb = CreateFrame("EditBox", opts.name, parent, "InputBoxTemplate")
    eb:SetHeight(24)
    eb:SetAutoFocus(false)
    eb:SetTextInsets(4, 0, 0, 0)
    local ph = UI:AddPlaceholder(eb, L["Search..."])
    local token, lastText, completion = 0, "", nil
    local function Pick(name)
        eb:SetText(name)
        token = token + 1 -- the text change above already queued a search; this one replaces it
        opts.onSearch(name)
        opts.pick(name)
        eb:ClearFocus()
    end
    if opts.matches then completion = UI:AttachCompletion(eb, opts.matches, false, Pick) end
    eb:SetScript("OnTextChanged", function(s)
        local text = s:GetText()
        if text == lastText then return end
        lastText = text
        ph:SetShown(text == "")
        if completion then completion:Clear() end
        token = token + 1
        local mine = token
        local function Apply()
            opts.onSearch(text)
            if completion then completion:Update() end
        end
        if text == "" then return Apply() end
        C_Timer.After(SEARCH_DELAY, function() if token == mine then Apply() end end)
    end)
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(s)
        local pick = completion and completion:Selected()
        if pick then Pick(pick) else s:ClearFocus() end
    end)
    UI:AddClearButton(eb, L["Clear Search"])
    return eb
end

-- Builds the header in `parent`, its first row `top` pixels down (negative). opts:
--   name: the search box's global name (optional)
--   onSearch(text), matches(text), pick(name): see SearchBox
--   sorts = { { key, label in the menu, short label on the button } }, getSort() -> key, setSort(key),
--   sortShown(key) -> false to leave a sort out of the menu (optional), descKey: the db key of the reverse switch,
--   onSort(): after the sort or its direction changed
--   categoryLabel() -> text, categoryItems() -> menu items (see UI:OpenMenu)
--   onCollapse(collapse): expand (false) or collapse (true) every group; canCollapse() -> false greys out both
--   buttons (optional); hideCollapse() -> true hides them (optional)
--   onDensity(): after the row spacing changed
--   filters() -> { { key (a db key), label, dim (shown, can't be switched) } }, filterDefaults = { [key] = default },
--   onFilter(): after a filter changed or was reset; filterActive() -> true when something besides the filters
--   counts as filtered (optional); onReset(): extra reset work before onFilter (optional)
--   extra(parent) -> a 24x24 button for between the Filters menu and the reset button (optional)
-- Returns the header: its controls (search, sortDD, sortDir, categoryDD, expandAll, collapseAll, density, filtersDD,
-- filterReset, extra), bottom (where the list goes, from the parent's top), and :Sync() to redraw them.
function UI:CreateListHeader(parent, top, opts)
    local h = {}
    local db = FP.db
    local row2, row3 = top - ROW_STEP, top - 2 * ROW_STEP
    h.bottom = top - 3 * ROW_STEP - 1

    -- Row 1: search, sort, direction.
    h.sortDir = self:Button(parent, "", 24, 24, function()
        db[opts.descKey] = not db[opts.descKey]
        opts.onSort()
    end)
    h.sortDir:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, top)
    h.sortDir.arrow = h.sortDir:CreateTexture(nil, "OVERLAY")
    h.sortDir.arrow:SetSize(16, 16)
    h.sortDir.arrow:SetPoint("CENTER", 2, 0)
    self:Tooltip(h.sortDir, "ANCHOR_RIGHT", L["Reverse the Sort Order"])
    h.sortDD = self:Dropdown(parent, 120, 24, function()
        local current = opts.getSort()
        for _, s in ipairs(opts.sorts) do
            if s[1] == current then return L["Sort"] .. ": " .. L[s[3]] end
        end
        return L["Sort"]
    end, function()
        local items, current = {}, opts.getSort()
        for _, s in ipairs(opts.sorts) do
            local key = s[1]
            if not opts.sortShown or opts.sortShown(key) then
                items[#items + 1] = { text = L[s[2]], checked = current == key,
                    onSelect = function() opts.setSort(key) opts.onSort() end }
            end
        end
        return items
    end)
    h.sortDD:SetPoint("TOPRIGHT", h.sortDir, "TOPLEFT", -4, 0)
    h.search = SearchBox(parent, opts)
    h.search:SetPoint("TOPRIGHT", h.sortDD, "TOPLEFT", -4, 0)
    -- InputBoxTemplate draws its left cap about 5px outside the box, so the box starts that much further in to line up
    -- with the dropdowns below; EllesmereUI's square box has no cap.
    h.search.fpEUILayout = function()
        h.search:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.EUI() and 6 or 11, top)
    end
    h.search.fpEUILayout()
    self:EUIWidget(h.search, "editbox")

    -- Row 2: category, collapse / expand, row spacing.
    h.density = self:Dropdown(parent, 96, 24, function()
        return L[DENSITY_LABELS[db.recipeDensity] or "Normal"]
    end, function()
        local items = {}
        for _, key in ipairs(DENSITIES) do
            items[#items + 1] = { text = L[DENSITY_LABELS[key]], checked = db.recipeDensity == key, onSelect = function()
                db.recipeDensity = key
                opts.onDensity()
            end }
        end
        return items
    end)
    h.density:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, row2)
    self:Tooltip(h.density, "ANCHOR_RIGHT", function(tip)
        tip:AddLine(L["Row Spacing"], 1, 1, 1)
        tip:AddLine(L["How tall each row in the list is. Taller rows are easier to read; shorter rows fit more in the list."], 0.8, 0.8, 0.8, true)
    end)
    local function CollapseButton(label, tip, collapse, anchor)
        local b = self:Button(parent, label, 24, 24, function() opts.onCollapse(collapse) end)
        b:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
        self:Tooltip(b, "ANCHOR_RIGHT", L[tip])
        return b
    end
    h.expandAll = CollapseButton("+", "Expand All Categories", false, h.density)
    h.collapseAll = CollapseButton("-", "Collapse All Categories", true, h.expandAll)
    h.categoryDD = self:Dropdown(parent, 10, 24, opts.categoryLabel, opts.categoryItems)

    -- Row 3: filters, the caller's extra button, reset.
    local function Active()
        for k, default in pairs(opts.filterDefaults) do
            if db[k] ~= default then return true end
        end
        return false
    end
    h.filtersDD = self:Dropdown(parent, 10, 24, function() return L["Filters"] end, function()
        local items = {}
        for _, filter in ipairs(opts.filters()) do
            local key = filter[1]
            local item = { text = L[filter[2]], checked = db[key], keepOpen = true, dim = filter[3] }
            if not filter[3] then
                item.onSelect = function()
                    db[key] = not db[key]
                    item.checked = db[key] -- the open menu redraws from this
                    opts.onFilter()
                end
            end
            items[#items + 1] = item
        end
        return items
    end)
    h.filterReset = self:Button(parent, "X", 24, 24, function()
        for k, v in pairs(opts.filterDefaults) do db[k] = v end
        if opts.onReset then opts.onReset() end
        opts.onFilter()
    end)
    h.filterReset.text:SetTextColor(1, 0.2, 0.2)
    h.filterReset:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, row3)
    self:Tooltip(h.filterReset, "ANCHOR_RIGHT", L["Reset All Filters"])
    local right = h.filterReset
    if opts.extra then
        h.extra = opts.extra(parent)
        h.extra:SetPoint("TOPRIGHT", h.filterReset, "TOPLEFT", -4, 0)
        right = h.extra
    end
    h.filtersDD:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, row3)
    h.filtersDD:SetPoint("TOPRIGHT", right, "TOPLEFT", -4, 0)

    function h:Sync()
        self.sortDD:Sync()
        self.sortDir.arrow:SetTexture(db[opts.descKey] and "Interface\\Buttons\\Arrow-Down-Up" or "Interface\\Buttons\\Arrow-Up-Up")
        self.density:Sync()
        self.categoryDD:Sync()
        local hidden = opts.hideCollapse and opts.hideCollapse()
        local can = not opts.canCollapse or opts.canCollapse()
        self.expandAll:SetShown(not hidden)
        self.collapseAll:SetShown(not hidden)
        self.expandAll:SetActive(can)
        self.collapseAll:SetActive(can)
        self.categoryDD:ClearAllPoints()
        self.categoryDD:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, row2)
        self.categoryDD:SetPoint("TOPRIGHT", hidden and self.density or self.collapseAll, "TOPLEFT", -4, 0)
        self.filtersDD:Sync()
        local active = Active()
        UI.SetSelected(self.filtersDD, active) -- an accent that hovering doesn't clear
        self.filterReset:SetActive(active or (opts.filterActive and opts.filterActive()) or false)
    end
    h:Sync()
    return h
end
