local _, FP = ...
local L = FP.L
local UI = FP.UI

-- Disenchanting Mode: on the Enchanting tab, the recipe list and recipe panel give way to the disenchantable items in
-- your bags and bank (the bank as of your last visit while it is closed). Picking one shows what it may give and what that is worth, and the
-- Disenchant button casts Disenchant on it. Core/Disenchant.lua finds the items and works out their values.
-- With "Show Other Characters" on (the Filters menu), your other characters' unbound gear follows, grouped by
-- character, to show what they could mail you; those rows can't be disenchanted from here. The search, sort, category,
-- row spacing and filter rows are the recipe list's (UI/Common/ListHeader.lua).
-- On another character's Enchanting (Alts/AltProfessions.lua) it lists the gear of yours you could mail them to
-- disenchant instead: unbound items only, and no Disenchant button.

local ENCHANTING = FP.ENCHANTING
local RowHeight = UI.RecipeRowHeight -- the row spacing setting, shared with the recipe list
local MAX_ROWS = 40
local CARD_H, CARD_GAP, RESULT_CARDS = 32, 3, 3 -- no loot table has more than three results
local COL_GAP, COL_PAD = 8, 10
local DASH = "|cff808080-|r"
local BEST_COLOR, OTHER_COLOR = { 0.2, 0.9, 0.2 }, { 0.4, 0.4, 0.4 }
-- The result cards' and value cards' columns: key, width, header. Fixed widths keep every card and its header lined up.
-- Chance is a little wider: your seen rate ("seen 75%") sits under it in small text, as your average amount
-- ("seen 1.7") does under Amount.
local RESULT_COLS = { { "chance", 64, "Chance" }, { "amount", 56, "Amount" }, { "price", 92, "Price Each" }, { "expected", 92, "Expected" } }
local VALUE_COLS = { { "gross", 92, "Value" }, { "cut", 92, "5% Cut" }, { "neutral", 92, "15% Cut" } }
-- Sorts: key, label in the menu, label on the button.
local SORTS = { { "name", "Name", "Name" }, { "level", "Item Level", "Level" }, { "quality", "Quality", "Quality" },
    { "value", "Best Value", "Value" } }
-- The Filters menu, in order: db key, label (defaults in FP.deFilterDefaults). Show Other Characters is left out on
-- another character's Enchanting, and Worth Disenchanting Only needs prices.
local FILTERS = {
    { "deShowOthers", "Show Other Characters" }, { "deShowBank", "Show Bank Items" },
    { "deShowUncommon", "Show Uncommon" }, { "deShowRare", "Show Rare" }, { "deShowEpic", "Show Epic" },
    { "deHideSets", "Hide Equipment Set Pieces" }, { "deWorthOnly", "Worth Disenchanting Only" },
}
local QUALITY_FILTER = { [2] = "deShowUncommon", [3] = "deShowRare", [4] = "deShowEpic" }
local WARN_ICON = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew" -- on the row of an item with a warning
local MODE_ICON = "Interface\\Icons\\INV_Enchant_DustStrange" -- the Overview card's Disenchanting Mode icon
local BANK_COLOR = "|cff4dccff"

UI.deMode = false
local items, display, selectedKey, search = {}, {}, nil, ""
-- The category picked in the header: nil for all, "bags", "bank", or another character's key.
local category

-- What the selection is kept by: the item itself, so it stays on the same item when the bags are sorted or it is
-- moved, and the Disenchant button never ends up aimed at whatever took its slot. Another character's gear from
-- Syndicator has no GUID and is kept by its stand-in id (DE:ScanOthers).
local function Key(it) return it.guid or it.id or (it.bag .. ":" .. it.slot) end

-- The character holding another character's item, and the current one, as labels (full names: two characters can
-- share a first name on Forever).
local function OwnerName(it) return FP.Alts:Label(FP.db.characters[it.owner]) end
local function MyName() return FP.Alts:Label(FP.Alts:Current()) end

-- The character whose Enchanting is being viewed, when the mode lists gear to send them; nil on your own Enchanting.
local function Recipient()
    local viewing = FP.AltProfs.viewing
    return viewing and viewing.skillLine == ENCHANTING and viewing or nil
end

-- Where the window was before OpenDisenchantFor showed an enchanter's gear, for the toggle to go back to:
-- { shown, page, viewing = { key, skillLine } of another character's profession shown then }. Kept while the mode
-- shows an enchanter's gear, so picking another enchanter still goes back to the same place; dropped once it is off.
local returnTo

-- Another character's piece of gear the current character asked it for in the transfer plan (Alts/Outgoing.lua).
-- Only pieces with a GUID can be asked for: Syndicator's rows have none until that character logs in once.
local function InPlan(it)
    return it.owner and it.guid and FP.Outgoing:GearAsked(FP.Alts:GetCharacterKey(), it.owner, it.guid) or false
end

-- True when the recipient is of the other faction, so nothing can be mailed to them.
local function OtherFaction(recipient)
    return FP.Alts:IsOtherFaction(FP.db.characters[recipient.key])
end

local function QualityHex(q)
    local c = ITEM_QUALITY_COLORS[q]
    return c and c.hex or "|cffffffff"
end

---------------------------------------------------------------------------
-- Warnings
---------------------------------------------------------------------------
-- Reasons to think twice before disenchanting an item. Each check returns a warning line for the item, or nil. A
-- warning puts an icon on the item's row and a line in its tooltip, shows in red in the detail panel, and makes the
-- Disenchant button ask first. A new kind of warning is a new check here.
local WARNING_CHECKS = {
    function(it) return it.sets and L["Part of equipment set: %s"]:format(table.concat(it.sets, ", ")) end,
}

local function Warnings(it)
    local out = {}
    for _, check in ipairs(WARNING_CHECKS) do
        local text = check(it)
        if text then out[#out + 1] = text end
    end
    return out
end

local function AddWarningLines(tip, warnings)
    for _, text in ipairs(warnings) do tip:AddLine(text, 1, 0.3, 0.3, true) end
end

---------------------------------------------------------------------------
-- Values
---------------------------------------------------------------------------
local function Values(it) return FP.Disenchant:Values(it.tableID, it.sellPrice, it.itemID, it.bound, it.link) end

---------------------------------------------------------------------------
-- List
---------------------------------------------------------------------------
-- What an item sorts by, besides its name: higher item levels, qualities and values first.
local function SortValue(it, key)
    if key == "level" then return -it.level end
    if key == "quality" then return -it.quality end
    if key == "value" then
        it.values = it.values or Values(it)
        return -it.values.bestValue
    end
    return 0
end

-- Whether the Filters menu lets an item through.
local function Passes(it)
    local db = FP.db
    if it.owner and not db.deShowOthers then return false end
    if it.inBank and not db.deShowBank then return false end
    local q = QUALITY_FILTER[it.quality]
    if q and not db[q] then return false end
    if db.deHideSets and it.sets then return false end
    if db.deWorthOnly and FP.Prices:Available() then
        it.values = it.values or Values(it)
        if it.values.best ~= "disenchant" then return false end
    end
    return true
end

-- The group an item is listed under: "bags", "bank" or its character's key.
local function GroupOf(it) return it.owner or (it.inBank and "bank" or "bags") end

local function GroupTitle(id, it)
    if id == "bags" then return L["In Your Bags"] end
    if id == "bank" then return L["In Your Bank"] end
    return L["On %s"]:format(OwnerName(it))
end

-- Every group the items fall in, bags and bank first, then the other characters in the order DE:ScanOthers gives
-- them: { { id, title } }. For the category menu, so a group stays pickable while filters hide its items.
local function Groups()
    local out, seen = { { "bags", L["In Your Bags"] }, { "bank", L["In Your Bank"] } }, { bags = true, bank = true }
    for _, it in ipairs(items) do
        local id = GroupOf(it)
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = { id, GroupTitle(id, it) }
        end
    end
    return out
end

-- The shown rows: a header per group, then its items unless the group is collapsed (a search shows them all),
-- filtered by the search, the category and the Filters menu.
local function BuildDisplay()
    wipe(display)
    local db = FP.db
    local key, desc, needle = db.deSort, db.deSortDesc, strlower(search)
    local groups, byID = {}, {}
    for _, g in ipairs(Groups()) do
        byID[g[1]] = { id = g[1], title = g[2], list = {} }
        groups[#groups + 1] = byID[g[1]]
    end
    if category and not byID[category] then category = nil end -- that character has nothing listed any more
    for _, it in ipairs(items) do
        local id = GroupOf(it)
        if (not category or category == id) and Passes(it)
            and (needle == "" or strfind(strlower(it.name), needle, 1, true)) then
            table.insert(byID[id].list, it)
        end
    end
    for _, g in ipairs(groups) do
        table.sort(g.list, function(a, b)
            local va, vb = SortValue(a, key), SortValue(b, key)
            if va ~= vb then
                if desc then return va > vb end
                return va < vb
            end
            if a.name ~= b.name then
                if desc and key == "name" then return a.name > b.name end
                return a.name < b.name
            end
            return Key(a) < Key(b)
        end)
        if #g.list > 0 then
            local open = needle ~= "" or not db.deCollapsed[g.id]
            display[#display + 1] = { header = g.title, group = g.id, open = open, count = #g.list }
            if open then
                for _, it in ipairs(g.list) do display[#display + 1] = it end
            end
        end
    end
end

local function Selected()
    for _, it in ipairs(items) do
        if Key(it) == selectedKey then return it end
    end
end

-- Rescans and keeps the selection on the same item when it is still there; after a disenchant empties its slot, the
-- item now in that place in the list is picked instead.
local function Rescan()
    local oldIndex
    for i, row in ipairs(display) do
        if not row.header and Key(row) == selectedKey then oldIndex = i end
    end
    items = FP.Disenchant:Scan()
    local to = Recipient()
    if to then
        -- Only unbound gear can be mailed, and only within a faction.
        local sendable = {}
        if not OtherFaction(to) then
            for _, it in ipairs(items) do
                if not it.bound then sendable[#sendable + 1] = it end
            end
        end
        items = sendable
    else
        -- Always scanned; the Show Other Characters filter hides them.
        for _, it in ipairs(FP.Disenchant:ScanOthers()) do items[#items + 1] = it end
    end
    BuildDisplay()
    if Selected() then return end
    selectedKey = nil
    for i = oldIndex or 1, #display do
        if not display[i].header then selectedKey = Key(display[i]) return end
    end
    for i = #display, 1, -1 do
        if not display[i].header then selectedKey = Key(display[i]) return end
    end
end

---------------------------------------------------------------------------
-- Left panel
---------------------------------------------------------------------------
-- Places the rows for the current row spacing; only does anything after it changed.
local function LayoutRows(p)
    local h = RowHeight()
    if p.rowHeight == h then return end
    p.rowHeight = h
    for i, row in ipairs(p.rows) do
        row:SetHeight(h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", p.list, "TOPLEFT", 0, -(i - 1) * h)
        row:SetPoint("TOPRIGHT", p.list, "TOPRIGHT", -UI.BAR_GUTTER, -(i - 1) * h)
        row.icon:SetSize(h - 4, h - 4)
    end
end

local function UpdateList()
    local f = UI.frame
    local p = f.deLeft
    LayoutRows(p)
    local n, h = #display, RowHeight()
    local visible = math.min(MAX_ROWS, math.max(1, math.floor(p.list:GetHeight() / h)))
    FauxScrollFrame_Update(p.scroll, n, visible, h)
    p.scroll.fpSetRange(math.max(0, n - visible) * h)
    local offset = FauxScrollFrame_GetOffset(p.scroll)
    local a = UI:GetAccent()
    for i, row in ipairs(p.rows) do
        local entry = i <= visible and display[offset + i]
        row.entry = entry or nil
        if not entry then
            row:Hide()
        elseif entry.header then
            -- As the recipe list's category headers: accent colour, - or + for open or collapsed, and the count.
            row.icon:Hide()
            row.warn:Hide()
            row.name:SetText((entry.open and "- " or "+ ") .. entry.header .. " (" .. entry.count .. ")")
            row.name:SetTextColor(a[1], a[2], a[3])
            row.right:SetText("")
            row.sel:SetColorTexture(1, 1, 1, 0.06)
            row:Show()
        else
            row.icon:SetTexture(entry.icon)
            row.icon:Show()
            row.warn:SetShown(#Warnings(entry) > 0)
            row.name:SetText(QualityHex(entry.quality) .. entry.name .. "|r")
            local where = entry.owner and ((InPlan(entry) and ("|cff33ccff" .. L["Asked"] .. "|r  ") or "")
                    .. "|cff808080" .. (entry.inBank and L["Bank"] or L["Bags"]) .. "|r  ")
                or entry.inBank and (BANK_COLOR .. L["Bank"] .. "|r  ") or ""
            row.right:SetText(where .. entry.level)
            if Key(entry) == selectedKey then row.sel:SetColorTexture(a[1], a[2], a[3], 0.25)
            else row.sel:SetColorTexture(0, 0, 0, 0) end
            row:Show()
        end
    end
    p.empty:SetShown(n == 0)
    local to = Recipient()
    p.empty:SetText(search ~= "" and L["No items match the search."]
        or #items > 0 and L["No items match the filters."]
        or to and OtherFaction(to) and L["%s is of the other faction, so nothing can be mailed to them."]:format(to.owner)
        or to and L["Nothing in your bags to send %s. Unbound weapons and armour of uncommon quality or better can be mailed to them to disenchant."]:format(to.owner)
        or L["Nothing to disenchant in your bags. Weapons and armour of uncommon quality or better can be disenchanted."])
end

-- Brings the selected item into view, centred, when it isn't already.
local function ScrollToSelected()
    local p = UI.frame.deLeft
    local h = RowHeight()
    local visible = math.max(1, math.floor(p.list:GetHeight() / h))
    for i, row in ipairs(display) do
        if not row.header and Key(row) == selectedKey then
            local offset = FauxScrollFrame_GetOffset(p.scroll)
            if i > offset and i <= offset + visible then return end
            local top = math.max(0, math.min(i - 1 - math.floor(visible / 2), #display - visible))
            p.scroll.fpScrollTo(top * h)
            return
        end
    end
end

local function CreateRow(p)
    local row = CreateFrame("Button", nil, p.list)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.08)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.right = UI:Text(row, -1, "RIGHT")
    row.right:SetPoint("RIGHT", -4, 0)
    row.warn = row:CreateTexture(nil, "OVERLAY")
    row.warn:SetSize(16, 16)
    row.warn:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
    row.warn:SetTexture(WARN_ICON)
    row.name = UI:Text(row, 0)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.warn, "LEFT", -4, 0)
    row.name:SetWordWrap(false)
    row:SetScript("OnClick", function(s)
        local it = s.entry
        if not it then return end
        if it.header then
            local collapsed = FP.db.deCollapsed
            collapsed[it.group] = (not collapsed[it.group]) or nil
            BuildDisplay()
            UI:UpdateDisenchantMode()
            return
        end
        if UI.LinkToChat(it.link) then return end
        selectedKey = Key(it)
        UI:UpdateDisenchantMode()
    end)
    UI:Tooltip(row, "ANCHOR_RIGHT", function(tip, s)
        local it = s.entry
        if not it or it.header then return false end
        tip:SetHyperlink(it.link)
        AddWarningLines(tip, Warnings(it))
        local to = Recipient()
        if it.owner then
            tip:AddLine(L["Send from %s to %s to disenchant."]:format(OwnerName(it), MyName()), 0.3, 0.8, 1, true)
            if InPlan(it) then tip:AddLine(L["In the transfer plan."], 0.3, 0.8, 1, true) end
        elseif to then
            tip:AddLine(L["Send it to %s to disenchant it."]:format(to.owner), 0.3, 0.8, 1, true)
            if it.inBank then tip:AddLine(L["Withdraw from bank to mail it."], 0.3, 0.8, 1, true) end
        elseif it.inBank then
            tip:AddLine(L["Withdraw from bank to disenchant it."], 0.3, 0.8, 1, true)
        end
    end)
    return row
end

-- Item names in the list that contain the text, those starting with it first, for the search box's suggestions.
local function SearchMatches(text)
    local typed = strlower(text)
    if #typed < 2 then return {} end
    local prefix, within, seen = {}, {}, {}
    for _, it in ipairs(items) do
        local lower = strlower(it.name)
        local at = Passes(it) and not seen[lower] and strfind(lower, typed, 1, true)
        if at then
            seen[lower] = true
            table.insert(at == 1 and prefix or within, it.name)
        end
    end
    table.sort(prefix)
    table.sort(within)
    for _, name in ipairs(within) do prefix[#prefix + 1] = name end
    return prefix
end

local function CreateLeft(f)
    local p = CreateFrame("Frame", "ProfessionsForeverDisenchantList", f, "BackdropTemplate")
    p:SetPoint("TOPLEFT", f.left, "TOPLEFT")
    p:SetPoint("BOTTOMRIGHT", f.left, "BOTTOMRIGHT")
    UI:Skin(p, "panel")
    f.deLeft = p

    -- The way back, at the top in the accent colour so it can't be missed.
    p.back = UI:Button(p, "< " .. L["Back to Recipes"], 10, 24, function() UI:SetDisenchantMode(false) end)
    p.back:SetPoint("TOPLEFT", 6, -7)
    p.back:SetPoint("TOPRIGHT", -6, -7)
    p.back.text:SetTextColor(1, 0.82, 0)
    UI:Tooltip(p.back, "ANCHOR_RIGHT", L["Leave Disenchanting Mode and show the Enchanting recipes again."])

    -- A change that keeps the same items: rebuild the rows and redraw.
    local function Redraw()
        BuildDisplay()
        UI:UpdateDisenchantMode()
    end
    -- A change of what is shown: also back to the top of the list.
    local function Relist()
        BuildDisplay()
        p.scroll.fpScrollTo(0)
        UI:UpdateDisenchantMode()
    end
    p.header = UI:CreateListHeader(p, -34, {
        onSearch = function(text)
            search = text
            Relist()
        end,
        matches = SearchMatches,
        -- A suggestion picked: the first item of that name is selected.
        pick = function(name)
            for _, row in ipairs(display) do
                if not row.header and row.name == name then
                    selectedKey = Key(row)
                    ScrollToSelected()
                    UI:UpdateDisenchantMode()
                    return
                end
            end
        end,
        sorts = SORTS,
        getSort = function() return FP.db.deSort end,
        setSort = function(key) FP.db.deSort = key end,
        descKey = "deSortDesc",
        onSort = Relist,
        categoryLabel = function()
            if not category then return L["All Categories"] end
            for _, g in ipairs(Groups()) do
                if g[1] == category then return g[2] end
            end
            return L["All Categories"]
        end,
        categoryItems = function()
            local function Pick(id) category = id Relist() end
            local out = { { text = L["All Categories"], checked = category == nil, onSelect = function() Pick(nil) end } }
            for _, g in ipairs(Groups()) do
                out[#out + 1] = { text = g[2], checked = category == g[1], onSelect = function() Pick(g[1]) end }
            end
            return out
        end,
        onCollapse = function(collapse)
            local collapsed = wipe(FP.db.deCollapsed)
            if collapse then
                for _, g in ipairs(Groups()) do collapsed[g[1]] = true end
            end
            Redraw()
        end,
        canCollapse = function() return #display > 0 end,
        onDensity = function()
            p.scroll.fpScrollTo(0)
            UI:UpdateDisenchantMode()
            UI:SetNumRows(f:GetHeight()) -- the recipe list, for when you go back to it
        end,
        filters = function()
            local out = {}
            for _, filter in ipairs(FILTERS) do
                local key = filter[1]
                if key == "deWorthOnly" and not FP.Prices:Available() then
                    out[#out + 1] = { key, L[filter[2]] .. " (" .. L["Needs Auctionator for prices"] .. ")", true }
                -- Gear for another character's Enchanting is only ever your own.
                elseif not (key == "deShowOthers" and Recipient()) then
                    out[#out + 1] = filter
                end
            end
            return out
        end,
        filterDefaults = FP.deFilterDefaults,
        onFilter = Relist,
        filterActive = function() return category ~= nil end,
        onReset = function() category = nil end,
    })

    p.list = CreateFrame("Frame", nil, p)
    p.list:SetPoint("TOPLEFT", 6, p.header.bottom)
    p.list:SetPoint("BOTTOMRIGHT", -6, 2)
    p.scroll = CreateFrame("ScrollFrame", "ProfessionsForeverDisenchantScroll", p.list, "FauxScrollFrameTemplate")
    p.scroll:SetPoint("TOPLEFT")
    p.scroll:SetPoint("BOTTOMRIGHT", -UI.BAR_GUTTER, 0)
    p.scroll:SetScript("OnVerticalScroll", function(s, offset)
        FauxScrollFrame_OnVerticalScroll(s, offset, RowHeight(), UpdateList)
    end)
    UI:AttachScrollbar(p.scroll, p.scroll.ScrollBar or _G["ProfessionsForeverDisenchantScrollScrollBar"], p.list)
    p.list:EnableMouseWheel(true)
    p.list:SetScript("OnMouseWheel", function(_, delta)
        p.scroll.fpScrollTo(p.scroll:GetVerticalScroll() - delta * RowHeight() * 3)
    end)
    p.list:SetScript("OnSizeChanged", function() if p:IsShown() then UpdateList() end end)
    p.rows = {}
    for i = 1, MAX_ROWS do p.rows[i] = CreateRow(p) end
    LayoutRows(p)
    p.empty = UI:Text(p.list, 0, "CENTER")
    p.empty:SetPoint("TOPLEFT", 12, -20)
    p.empty:SetPoint("TOPRIGHT", -12, -20)
    p.empty:SetTextColor(0.6, 0.6, 0.6)
    p.empty:SetWordWrap(true)
end

---------------------------------------------------------------------------
-- Right panel
---------------------------------------------------------------------------
local function Money(c) return FP.Prices:Format(c) end

local function MailboxOpen() return MailFrame:IsShown() end

-- Puts the selected bag item on a new mail to the recipient, as dragging it to the first free attachment slot does,
-- and fills in their name and a subject where those boxes are empty. Only while a mailbox is open.
local function MailSelected()
    local it, to = Selected(), Recipient()
    if not (it and to and not it.inBank and MailboxOpen()) then return end
    FP.Outgoing.StartMail(to.owner, L["Gear to Disenchant"])
    FP.Outgoing.AttachSlot(it.bag, it.slot)
end

-- Adds another character's selected piece to the transfer plan, so that character is asked to send it to you, or
-- takes it out again.
local function TogglePlan()
    local it = Selected()
    if not (it and it.owner and it.guid) then return end
    FP.Outgoing:SetGearAsked(FP.Alts:GetCharacterKey(), it.owner, it.guid, not InPlan(it) and it.link or nil)
end

-- Fixed-width, right-aligned columns along a row's right edge, so the cards and their header line up. Returns the
-- leftmost column, for the name to stop at.
local function Columns(row, cols, delta)
    row.cols = {}
    local x, left = -COL_PAD, nil
    for i = #cols, 1, -1 do
        local t = UI:Text(row, delta or 0, "RIGHT")
        t:SetWidth(cols[i][2])
        t:SetPoint("RIGHT", row, "RIGHT", x, 0)
        t:SetWordWrap(false)
        t.fpX = x -- for moving it up when a second line goes under it
        row.cols[cols[i][1]] = t
        x = x - cols[i][2] - COL_GAP
        left = t
    end
    return left
end

-- A section: a gold title, a grey header line with the column names, and `count` cards under it in one column.
-- `seenKeys`: the columns that get a small grey "seen ..." line under their value (see SetSeen).
local function Section(parent, title, cols, count, seenKeys)
    local sec = CreateFrame("Frame", nil, parent)
    sec:SetHeight(1)
    sec.title = UI:Text(sec, 1)
    sec.title:SetPoint("TOPLEFT")
    sec.title:SetText(title)
    sec.title:SetTextColor(1, 0.82, 0)
    local header = CreateFrame("Frame", nil, sec)
    header:SetHeight(16)
    header:SetPoint("TOPLEFT", sec.title, "BOTTOMLEFT", 0, -6)
    header:SetPoint("RIGHT", sec, "RIGHT")
    Columns(header, cols, -1)
    for _, col in ipairs(cols) do
        header.cols[col[1]]:SetText(L[col[3]])
        header.cols[col[1]]:SetTextColor(0.6, 0.6, 0.6)
    end
    sec.header = header
    sec.cards = {}
    for i = 1, count do
        local card = UI:CreateCard(sec, CARD_H)
        card:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2 - (i - 1) * (CARD_H + CARD_GAP))
        card:SetPoint("RIGHT", sec, "RIGHT")
        card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local left = Columns(card, cols)
        card.left = left
        card.seen = {}
        for _, key in ipairs(seenKeys or {}) do
            local col = card.cols[key]
            local t = UI:Text(card, -2, "RIGHT")
            t:SetWidth(col:GetWidth())
            t:SetPoint("TOPRIGHT", col, "BOTTOMRIGHT", 0, -1)
            t:SetWordWrap(false)
            card.seen[key] = t
        end
        card.name:ClearAllPoints()
        card.name:SetPoint("LEFT", card.icon, "RIGHT", 8, 0)
        card.name:SetPoint("RIGHT", left, "LEFT", -COL_GAP, 0)
        card.note = UI:Text(card, -1)
        card.note:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", 8, 0)
        card.note:SetPoint("RIGHT", left, "LEFT", -COL_GAP, 0)
        card.note:SetWordWrap(false)
        card.note:SetTextColor(0.6, 0.6, 0.6)
        card.note:Hide()
        sec.cards[i] = card
    end
    return sec
end

-- The best choice's card: a thin gold outline and a faint gold fill, on layers of their own so the card's hover border
-- (which resets when the mouse leaves) can't clear them.
local BEST_GOLD = { 1, 0.82, 0 }
local function SetBestHighlight(card, on)
    if not card.bestFill then
        if not on then return end
        card.bestFill = card:CreateTexture(nil, "BORDER")
        card.bestFill:SetPoint("TOPLEFT", 1, -1)
        card.bestFill:SetPoint("BOTTOMRIGHT", -1, 1)
        card.bestFill:SetColorTexture(BEST_GOLD[1], BEST_GOLD[2], BEST_GOLD[3], 0.08)
        card.bestEdges = {}
        for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
            { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local e = card:CreateTexture(nil, "OVERLAY")
            e:SetColorTexture(BEST_GOLD[1], BEST_GOLD[2], BEST_GOLD[3], 0.7)
            e:SetPoint(side[1])
            e:SetPoint(side[2])
            if side[1]:sub(1, 3) == side[2]:sub(1, 3) then e:SetHeight(1) else e:SetWidth(1) end
            card.bestEdges[#card.bestEdges + 1] = e
        end
    end
    card.bestFill:SetShown(on)
    for _, e in ipairs(card.bestEdges) do e:SetShown(on) end
end

-- What you've seen, small under a card's value in column `key`: grey while there are too few disenchants to rely on,
-- lighter once there are enough. `text` nil (or the option off) shows nothing, and the value sits in the middle.
local function SetSeen(card, key, text, enough)
    local line, col = card.seen[key], card.cols[key]
    local shown = FP.db.deShowObserved and text ~= nil
    line:SetText(shown and L["seen %s"]:format(text) or "")
    if enough then line:SetTextColor(0.8, 0.8, 0.8) else line:SetTextColor(0.5, 0.5, 0.5) end
    col:ClearAllPoints()
    col:SetPoint("RIGHT", card, "RIGHT", col.fpX, shown and 6 or 0)
end

-- A card's grey second line; without one the name sits in the middle of the card.
local function SetNote(card, text)
    local has = text and text ~= ""
    card.note:SetText(text or "")
    card.note:SetShown(has)
    card.name:ClearAllPoints()
    if has then card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 8, 0)
    else card.name:SetPoint("LEFT", card.icon, "RIGHT", 8, 0) end
    card.name:SetPoint("RIGHT", card.left, "LEFT", -COL_GAP, 0)
end

-- Sets a secure button to cast Disenchant on an item in your bags (nil: to do nothing). Not a "/cast" then "/use"
-- macro: when the cast can't start (another cast running, the global cooldown), the "/use" would run alone and put the
-- gear on. A spell button with a target item only uses the item while the spell is waiting for one.
local function SetCast(b, d, it)
    b:SetAttribute("type", it and "spell" or nil)
    b:SetAttribute("spell", it and d.spellName or nil)
    b:SetAttribute("target-bag", it and it.bag or nil)
    b:SetAttribute("target-slot", it and it.slot or nil)
end

-- The box the Disenchant button opens for an item with warnings: the item, its warnings in red, and a Disenchant
-- button of its own that casts. Only a secure button can cast, so the box has its own and the main one doesn't cast
-- while the item has warnings. Escape is caught here: the game's list of windows closed by Escape would close the main
-- window along with it.
local CONFIRM_W, CONFIRM_PAD = 340, 14
local function CreateConfirm(d)
    local box = CreateFrame("Frame", nil, d, "BackdropTemplate")
    box:SetWidth(CONFIRM_W)
    box:SetPoint("CENTER")
    box:SetFrameLevel(d:GetFrameLevel() + 30)
    box:EnableMouse(true)
    box.fpOpaque = true -- readable over the panel in see-through skins
    UI:Skin(box, "panel")
    box:Hide()
    box.title = UI:Text(box, 1, "CENTER")
    box.title:SetWidth(CONFIRM_W - 2 * CONFIRM_PAD)
    box.title:SetPoint("TOP", 0, -CONFIRM_PAD)
    box.warn = UI:Text(box, 0, "CENTER")
    box.warn:SetWidth(CONFIRM_W - 2 * CONFIRM_PAD)
    box.warn:SetPoint("TOP", box.title, "BOTTOM", 0, -10)
    box.warn:SetTextColor(1, 0.3, 0.3)
    box.accept = UI:Button(box, L["Disenchant"], 120, 24, function()
        box:Hide()
        C_Timer.After(0.5, function() UI:UpdateDisenchantMode(true) end)
    end, "up")
    box.accept:SetPoint("BOTTOMRIGHT", box, "BOTTOM", -4, CONFIRM_PAD)
    box.cancel = UI:Button(box, L["Cancel"], 120, 24, function() box:Hide() end)
    box.cancel:SetPoint("BOTTOMLEFT", box, "BOTTOM", 4, CONFIRM_PAD)
    box:EnableKeyboard(true)
    box:SetScript("OnKeyDown", function(s, key)
        if InCombatLockdown() then return end
        s:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then s:Hide() end
    end)
    d:HookScript("OnHide", function() box:Hide() end) -- the mode turned off or the window closed
    d.confirm = box
end

local function ShowConfirm(it, warnings)
    if InCombatLockdown() then return end -- a secure button can't be set up in combat (the window closes then anyway)
    local d = UI.frame.deRight
    if not d.confirm then CreateConfirm(d) end
    local box = d.confirm
    box.key = Key(it)
    box.title:SetText(L["Disenchant %s?"]:format(QualityHex(it.quality) .. it.name .. "|r"))
    box.warn:SetText(table.concat(warnings, "\n"))
    SetCast(box.accept, d, it)
    box:SetHeight(CONFIRM_PAD + box.title:GetStringHeight() + 10 + box.warn:GetStringHeight() + 16 + 24 + CONFIRM_PAD)
    box:Show()
end

local function UpdateDetail()
    local f = UI.frame
    local d = f.deRight
    local c = d.content
    local it = Selected()
    d.content:SetShown(it ~= nil)
    d.hint:SetShown(it == nil)
    if not it then
        d.hint:SetText(#items == 0 and "" or L["Select an item to disenchant."])
        if not InCombatLockdown() then SetCast(d.cast) end
        if d.confirm then d.confirm:Hide() end
        return
    end
    d.icon:SetTexture(it.icon)
    d.name:SetText(QualityHex(it.quality) .. it.name .. "|r")
    -- Where it is only when that matters: the bank or another character, not a bag slot of yours.
    local where = it.owner and L[it.inBank and "In %s's bank" or "In %s's bags"]:format(OwnerName(it))
        or it.inBank and (BANK_COLOR .. L["In your bank"] .. "|r")
    d.sub:SetText(L["Item level %d"]:format(it.level) .. "  -  " .. (it.bound and L["Soulbound"] or L["Not bound"])
        .. (where and ("  -  " .. where) or ""))
    local warnings = Warnings(it)
    d.warn:SetText(table.concat(warnings, "\n"))
    d.warn:SetShown(#warnings > 0)
    -- The results follow the warning lines, or sit where one line would end without them.
    d.resultsSec:ClearAllPoints()
    if #warnings > 0 then d.resultsSec:SetPoint("TOPLEFT", d.warn, "BOTTOMLEFT", 0, -10)
    else d.resultsSec:SetPoint("TOPLEFT", d.icon, "BOTTOMLEFT", 0, -34) end
    d.resultsSec:SetPoint("RIGHT", c, "RIGHT", -12, 0)

    -- Possible results: one card each, with its chance, amount, price and what it adds to one disenchant.
    local P = FP.Prices
    local priced = P:Available()
    local results = FP.Disenchant:Results(it.tableID)
    local observed = FP.db.deShowObserved
    local last
    for i, card in ipairs(d.results) do
        local res = results[i]
        card.itemID = res and res.itemID
        if res then
            card.icon:SetTexture(C_Item.GetItemIconByID(res.itemID))
            card.name:SetText(C_Item.GetItemNameByID(res.itemID) or ("item " .. res.itemID))
            local q = ITEM_QUALITY_COLORS[C_Item.GetItemQualityByID(res.itemID) or -1]
            card.stripe:SetColorTexture(q and q.r or 0.4, q and q.g or 0.4, q and q.b or 0.4, 1)
            card.cols.chance:SetText(("%g%%"):format(res.chance * 100))
            SetSeen(card, "chance", FP.Disenchant:ObservedChance(it.tableID, res.itemID))
            SetSeen(card, "amount", FP.Disenchant:ObservedAmount(it.tableID, res.itemID))
            card.cols.amount:SetText(res.min == res.max and tostring(res.min) or (res.min .. "-" .. res.max))
            local unit = priced and P:Unit(res.itemID)
            card.cols.price:SetText(unit and Money(unit) or DASH)
            card.cols.expected:SetText(unit and Money(res.chance * (res.min + res.max) / 2 * unit) or DASH)
            card:Show()
            last = card
        else
            card:Hide()
        end
    end
    -- Under the results: how many disenchants your rates come from, and anything else you've had from this table.
    local note, also = FP.Disenchant:ObservedNote(it.tableID, results)
    local _, _, unpricedSeen = FP.Disenchant:ObservedValue(it.tableID)
    if unpricedSeen and unpricedSeen > 0 then note = note .. " " .. L["%d seen results without a price."]:format(unpricedSeen) end
    d.observed:SetText(observed and (also and (note .. "\n" .. also) or note) or "")
    d.observed:SetShown(observed)
    d.observed:ClearAllPoints()
    d.observed:SetPoint("TOPLEFT", last or d.resultsHeader, "BOTTOMLEFT", 0, -6)
    d.observed:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    d.values:ClearAllPoints()
    d.values:SetPoint("TOPLEFT", observed and d.observed or last or d.resultsHeader, "BOTTOMLEFT", 0, observed and -12 or -14)
    d.values:SetPoint("RIGHT", c, "RIGHT", -12, 0)

    -- What it's worth each way, before the auction house cut and after the standard and neutral cuts.
    local v = Values(it)
    it.values = v
    local scan = P:ScanText() -- how old the prices behind it are
    d.values.title:SetText(L["What It's Worth"] .. (scan and ("    " .. scan) or ""))
    local rows = {
        vendor = { v.vendor, v.vendor, v.vendor },
        disenchant = priced and { v.deGross, v.deGross * (1 - P.CUT), v.deGross * (1 - P.NEUTRAL_CUT) },
        auction = v.auctionGross and { v.auctionGross, v.auction, v.auctionGross * (1 - P.NEUTRAL_CUT) },
    }
    local notes = { vendor = "" }
    if not priced then
        notes.disenchant, notes.auction = L["Needs Auctionator for prices"], L["Needs Auctionator for prices"]
    else
        notes.disenchant = v.unpriced > 0 and L["%d results without a price"]:format(v.unpriced) or ""
        notes.auction = it.bound and L["Soulbound, can't be sold"] or (not v.auction and L["No auction price"]) or ""
    end
    for _, card in ipairs(d.valueCards) do
        local k, row = card.key, rows[card.key]
        if k == "auction" then card.icon:SetTexture(it.icon) end
        local best = priced and k == v.best
        local col = best and BEST_COLOR or OTHER_COLOR
        card.stripe:SetColorTexture(col[1], col[2], col[3], 1)
        SetBestHighlight(card, best)
        -- The Disenchant card also shows what your disenchants of this kind were really worth at today's prices
        -- (display only: the verdict above uses the table's chances).
        local realized, enough = nil, nil
        if k == "disenchant" then realized, enough = FP.Disenchant:ObservedValue(it.tableID) end
        local cuts = { 1, 1 - P.CUT, 1 - P.NEUTRAL_CUT }
        for n, vc in ipairs(VALUE_COLS) do
            card.cols[vc[1]]:SetText(row and ((k == "disenchant" and "~" or "") .. Money(row[n])) or DASH)
            SetSeen(card, vc[1], realized and Money(realized * cuts[n]), enough)
        end
        SetNote(card, notes[k])
    end
    if priced then
        local second = 0
        for _, k in ipairs({ "vendor", "disenchant", "auction" }) do
            if k ~= v.best and v[k] and v[k] > second then second = v[k] end
        end
        local to = Recipient()
        local label = ({ vendor = L["Sell to a vendor"], auction = L["Sell it at auction"],
            disenchant = to and L["Send it to %s to disenchant"]:format(to.owner) or L["Disenchant it"] })[v.best]
        d.verdict:SetText("|cff33e633" .. L["Best: %s"]:format(label) .. "|r" .. (v.bestValue > second
            and ("  " .. L["(%s more than the next best)"]:format(Money(v.bestValue - second))) or ""))
    else
        d.verdict:SetText("")
    end

    -- The button casts Disenchant on the item's bag slot; bank items have to come out of the bank first. Gear for
    -- another character gets a Mail button instead, which attaches it to a mail to them while a mailbox is open.
    local to = Recipient()
    local usable = not it.inBank and not to and not it.owner
    -- Another character's piece can't be disenchanted from here: it can be added to the transfer plan instead.
    if it.owner then
        local asked = InPlan(it)
        d.plan.text:SetText(asked and L["Remove from Transfer Plan"] or L["Add to Transfer Plan"])
        d.plan:SetActive(it.guid ~= nil)
        d.castNote:SetText(not it.guid and L["Log in on %s once to add it to the transfer plan."]:format(OwnerName(it))
            or asked and L["%s will be asked to send it to %s."]:format(OwnerName(it), MyName())
            or L["Send from %s to %s to disenchant."]:format(OwnerName(it), MyName()))
    elseif to then
        d.mail.text:SetText(L["Mail to %s"]:format(to.owner:match("^%S+")))
        d.mail:SetActive(not it.inBank and MailboxOpen())
        d.castNote:SetText(it.inBank and L["Withdraw from bank, then mail it to %s to disenchant it."]:format(to.owner)
            or not MailboxOpen() and L["Open a mailbox to send it to %s."]:format(to.owner)
            or L["Attaches it to a mail to %s."]:format(to.owner))
    else
        d.castNote:SetText(usable and "" or L["Withdraw from bank to disenchant it."])
    end
    d.mail:SetShown(to ~= nil)
    d.plan:SetShown(it.owner ~= nil)
    d.castNote:ClearAllPoints()
    d.castNote:SetPoint("LEFT", to and d.mail or it.owner and d.plan or d.cast, "RIGHT", 10, 0)
    d.castNote:SetPoint("RIGHT", d.content, "RIGHT", -12, 0)
    -- With warnings the button opens the confirmation box instead of casting.
    d.cast.confirm = usable and #warnings > 0
    local box = d.confirm
    if box and box:IsShown() and (box.key ~= Key(it) or not d.cast.confirm) then box:Hide() end
    if not InCombatLockdown() then
        d.cast:SetShown(not to and not it.owner)
        d.cast:SetActive(usable)
        SetCast(d.cast, d, usable and #warnings == 0 and it or nil)
        -- The item may have moved to another slot while the box is open.
        if box and box:IsShown() then SetCast(box.accept, d, it) end
    end
end

local function CreateRight(f)
    local p = CreateFrame("Frame", "ProfessionsForeverDisenchantPanel", f, "BackdropTemplate")
    p:SetPoint("TOPLEFT", f.right, "TOPLEFT")
    p:SetPoint("BOTTOMRIGHT", f.right, "BOTTOMRIGHT")
    UI:Skin(p, "panel")
    f.deRight = p
    p.hint = UI:Text(p, 1, "CENTER")
    p.hint:SetPoint("CENTER")
    p.content = CreateFrame("Frame", nil, p)
    p.content:SetAllPoints()
    local c = p.content

    p.icon = c:CreateTexture(nil, "ARTWORK")
    p.icon:SetSize(40, 40)
    p.icon:SetPoint("TOPLEFT", 12, -12)
    p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local iconHit = CreateFrame("Frame", nil, c)
    iconHit:SetAllPoints(p.icon)
    iconHit:EnableMouse(true)
    UI:Tooltip(iconHit, "ANCHOR_RIGHT", function(tip)
        local it = Selected()
        if not it then return false end
        tip:SetHyperlink(it.link)
    end)
    iconHit:SetScript("OnMouseUp", function()
        local it = Selected()
        if it then UI.LinkToChat(it.link) end
    end)
    p.name = UI:Text(c, 4)
    p.name:SetPoint("TOPLEFT", p.icon, "TOPRIGHT", 8, -2)
    p.name:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    p.name:SetWordWrap(false)
    p.sub = UI:Text(c, -1)
    p.sub:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -4)
    p.sub:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    p.sub:SetWordWrap(false)
    p.sub:SetTextColor(0.8, 0.8, 0.8)
    p.warn = UI:Text(c, 0)
    p.warn:SetPoint("TOPLEFT", p.icon, "BOTTOMLEFT", 0, -10)
    p.warn:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    p.warn:SetTextColor(1, 0.3, 0.3)

    local results = Section(c, L["Possible Results"], RESULT_COLS, RESULT_CARDS, { "chance", "amount" }) -- placed on each update, under the warnings
    p.results, p.resultsHeader, p.resultsSec = results.cards, results.header, results
    for _, card in ipairs(p.results) do
        UI:Tooltip(card, "ANCHOR_RIGHT", function(tip, s)
            if not s.itemID then return false end
            tip:SetItemByID(s.itemID)
        end)
        card:SetScript("OnClick", function(s) UI.LinkItemToChat(s.itemID) end)
    end

    p.observed = UI:Text(c, -1) -- placed under the last result card on each update
    p.observed:SetTextColor(0.6, 0.6, 0.6)
    p.observed:SetJustifyH("LEFT")

    -- Placed under the last result card (or the note above) on each update.
    p.values = Section(c, L["What It's Worth"], VALUE_COLS, 3, { "gross", "cut", "neutral" })
    local VALUE_ROWS = {
        { "vendor", L["Vendor"], "Interface\\Icons\\INV_Misc_Coin_01", L["What a vendor pays for it. Vendors take no cut."] },
        { "disenchant", L["Disenchant"], C_Spell.GetSpellTexture(FP.Disenchant.SPELL),
            L["The disenchant value is what its results are expected to sell for, from their chances and Auctionator's prices."] },
        { "auction", L["Auction"], nil, L["What the item itself sells for at auction, from Auctionator's prices. It's only best when it beats the others by more than the deposit picked under Options, Disenchanting."] },
    }
    p.valueCards = p.values.cards
    for i, card in ipairs(p.valueCards) do
        local row = VALUE_ROWS[i]
        card.key = row[1]
        card.name:SetText(row[2])
        card.name:SetTextColor(0.92, 0.92, 0.92)
        if row[3] then card.icon:SetTexture(row[3]) end
        UI:Tooltip(card, "ANCHOR_RIGHT", function(tip)
            tip:AddLine(row[2], 1, 1, 1)
            tip:AddLine(row[4], 0.8, 0.8, 0.8, true)
            tip:AddLine(L["5% is the standard auction house cut, 15% the neutral auction house's."], 0.6, 0.6, 0.6, true)
        end)
    end
    p.verdict = UI:Text(c, 0)
    p.verdict:SetPoint("TOPLEFT", p.valueCards[3], "BOTTOMLEFT", 0, -10)
    p.verdict:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    p.verdict:SetWordWrap(false)

    p.spellName = C_Spell.GetSpellInfo(FP.Disenchant.SPELL).name
    p.cast = UI:Button(c, L["Disenchant"], 140, 24, function(s)
        if s.confirm then
            local it = Selected()
            if it then ShowConfirm(it, Warnings(it)) end
            return
        end
        C_Timer.After(0.5, function() UI:UpdateDisenchantMode(true) end)
    end, "up")
    p.cast:SetPoint("BOTTOMLEFT", 12, 18)
    UI:Tooltip(p.cast, "ANCHOR_TOP", function(tip)
        local it = Selected()
        if not it then return false end
        tip:AddLine(L["Disenchant"], 1, 1, 1)
        tip:AddLine(L["Destroys the item and gives enchanting materials."], 0.8, 0.8, 0.8, true)
        local warnings = Warnings(it)
        AddWarningLines(tip, warnings)
        if #warnings > 0 then tip:AddLine(L["You'll be asked to confirm first."], 0.8, 0.8, 0.8, true) end
    end)
    p.mail = UI:Button(c, "", 140, 24, MailSelected)
    p.mail:SetPoint("BOTTOMLEFT", 12, 18)
    p.mail:Hide()
    UI:Tooltip(p.mail, "ANCHOR_TOP", function(tip)
        local to = Recipient()
        if not to then return false end
        tip:AddLine(L["Mail to %s"]:format(to.owner), 1, 1, 1)
        tip:AddLine(L["Attaches the item to a new mail and fills in their name. Review it and press Send."], 0.8, 0.8, 0.8, true)
    end)
    p.plan = UI:Button(c, "", 180, 24, TogglePlan)
    p.plan:SetPoint("BOTTOMLEFT", 12, 18)
    p.plan:Hide()
    UI:Tooltip(p.plan, "ANCHOR_TOP", function(tip)
        local it = Selected()
        if not (it and it.owner) then return false end
        tip:AddLine(InPlan(it) and L["Remove from Transfer Plan"] or L["Add to Transfer Plan"], 1, 1, 1)
        if not it.guid then
            tip:AddLine(L["Log in on %s once to add it to the transfer plan."]:format(OwnerName(it)), 1, 0.6, 0.2, true)
        else
            tip:AddLine(L["%s is asked to send you this exact piece: it shows in their Transfer Planner, login reminder and mailbox prompt, and their Mail button attaches it. It drops from the plan once they no longer hold it."]
                :format(OwnerName(it)), 0.8, 0.8, 0.8, true)
        end
    end)
    p.castNote = UI:Text(c, -1)
    p.castNote:SetPoint("LEFT", p.cast, "RIGHT", 10, 0)
    p.castNote:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    p.castNote:SetTextColor(0.3, 0.8, 1)
end

---------------------------------------------------------------------------
-- Mode
---------------------------------------------------------------------------
-- While the mode is on, whatever changes its list rescans it, a frame later: by then the game's own mail window has
-- shown or hidden, which the Mail button goes by. Several in one frame (items loading arrive in bursts) rescan once.
local queued
local function Rescanned()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        UI:UpdateDisenchantMode(true)
    end)
end
-- GET_ITEM_INFO_RECEIVED: another character's item the game hadn't loaded yet (DE:ScanOthers asks for it).
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "EQUIPMENT_SETS_CHANGED", "MAIL_SHOW",
    "MAIL_CLOSED", "GET_ITEM_INFO_RECEIVED" }) do
    FP:RegisterEvent(e, Rescanned)
end

-- Redraws both panels; `rescan` re-reads the bags first.
function UI:UpdateDisenchantMode(rescan)
    local f = self.frame
    if not (self.deMode and f and f.deLeft) then return end
    if rescan then Rescan() end
    f.deLeft.header:Sync()
    UpdateList()
    UpdateDetail()
end

-- Shows the mode's panels in place of the recipe ones while it is on and the recipes page is shown.
function UI:ApplyDisenchantMode()
    local f = self.frame
    if not f then return end
    local recipes = self.page == "recipes"
    local on = self.deMode and recipes
    f.left:SetShown(recipes and not on)
    f.right:SetShown(recipes and not on)
    if f.deLeft then
        f.deLeft:SetShown(on)
        f.deRight:SetShown(on)
    end
    if f.deModeBtn then UI.SetSelected(f.deModeBtn, on) end
    if f.footer then UI.SetSelected(f.footer.disenchant, on) end
    FP.Launcher:RefreshSelection()
end

function UI:SetDisenchantMode(on)
    on = on and true or false
    local f = self.frame
    if self.deMode == on or not f then return end
    self.deMode = on
    if not on then returnTo = nil end
    if on then
        if not f.deLeft then
            CreateLeft(f)
            CreateRight(f)
        end
        f.deLeft.scroll.fpScrollTo(0)
    end
    self:ApplyDisenchantMode()
    self:UpdateDisenchantMode(true)
end

-- An icon on the Overview's Enchanting card that opens Enchanting straight into the mode: your own once you know
-- Disenchant (it casts Enchanting, as the card does, since addon code can't open a profession), or another
-- character's (gear to send them). Sits left of `last`, the card's leftmost spell button, or at its top right.
-- Returns the icon when shown.
local pendingAt -- when a card icon started opening your own Enchanting; the mode turns on once it is shown

function UI:SyncDisenchantCardButton(card, p, last)
    local show = p.skillLine == ENCHANTING and not p.learnable and (p.alt ~= nil or IsPlayerSpell(FP.Disenchant.SPELL))
    local b = card.deBtn
    if not b then
        if not show then return end
        b = self:Button(card, "", 24, 24, function(s, btn)
            if btn == "RightButton" then return end
            if s.altKey then
                UI:OpenDisenchantFor(s.altKey)
            else
                pendingAt = GetTime()
                UI.OnProfessionOpenerClick(s, btn)
                UI:QueueRefresh()
            end
        end, "up")
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon:SetTexture(MODE_ICON)
        self:Tooltip(b, "ANCHOR_RIGHT", function(tip, s)
            tip:AddLine(L["Disenchanting Mode"], 1, 1, 1)
            local rec = s.altKey and FP.db.characters[s.altKey]
            tip:AddLine(rec and L["Opens %s's Enchanting with the gear in your bags you could send them to disenchant."]:format(rec.name)
                or L["Opens Enchanting with the gear in your bags that can be disenchanted."], 0.8, 0.8, 0.8, true)
        end)
        card.deBtn = b
    end
    b:SetShown(show)
    if not show then return end
    self:SetProfessionOpener(b, p) -- the same cast as the card, or nothing for another character's
    b:ClearAllPoints()
    if last and last:IsShown() then b:SetPoint("RIGHT", last, "LEFT", -4, 0)
    else b:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8) end
    return b
end

-- True for a few seconds after a card icon or the quick button started opening your own Enchanting.
function UI:DisenchantPending()
    return pendingAt ~= nil and GetTime() - pendingAt < 5
end

-- The quick button: switches the mode while your Enchanting is shown in the window. Otherwise it opens Enchanting with
-- the mode on: its secure cast (set by SetProfessionOpener) opens the window, or, when Enchanting is already open
-- behind another page or with the window closed, the window is shown on it.
-- Every character of yours with Enchanting, by name: { key, rec, rank }. `others`: leave out the current one.
function UI:Enchanters(others)
    local me, out = FP.Alts:GetCharacterKey(), {}
    for key, rec in pairs(FP.db.characters) do
        local p = not (others and key == me) and rec.professions and rec.professions[ENCHANTING]
        if p then out[#out + 1] = { key = key, rec = rec, rank = p.rank or 0 } end
    end
    table.sort(out, function(a, b) return FP.Alts:Label(a.rec) < FP.Alts:Label(b.rec) end)
    return out
end

-- Your main enchanter (FP.db.mainEnchanter, chosen in Options or the enchanter menu) comes first wherever your
-- enchanter is picked for you; nil is Automatic. One who no longer has Enchanting is simply not listed.
function UI:SetMainEnchanter(key)
    FP.db.mainEnchanter = key
    FP.Launcher:Update() -- the quick button's enchanter
    FP.Options:Refresh()
end

-- The main enchanter's name, or Automatic.
function UI:MainEnchanterLabel()
    for _, e in ipairs(self:Enchanters()) do
        if e.key == FP.db.mainEnchanter then return FP.Alts:Label(e.rec) end
    end
    return L["Automatic (Highest Skill)"]
end

-- Your other characters with Enchanting, for a character without it, best first: the ones gear can be mailed to,
-- then your main enchanter, then the highest skill (higher-level gear needs more), then by name.
-- { key, rec, rank, otherFaction }
function UI:DisenchantRecipients()
    local main, out = FP.db.mainEnchanter, self:Enchanters(true)
    for _, e in ipairs(out) do e.otherFaction = FP.Alts:IsOtherFaction(e.rec) end
    table.sort(out, function(a, b)
        if a.otherFaction ~= b.otherFaction then return b.otherFaction end
        if (a.key == main) ~= (b.key == main) then return a.key == main end
        if a.rank ~= b.rank then return a.rank > b.rank end
        return FP.Alts:Label(a.rec) < FP.Alts:Label(b.rec)
    end)
    return out
end

-- Disenchanting Mode for a character without Enchanting: the gear in your bags you could send `key`, by default your
-- best enchanter.
function UI:OpenDisenchantFor(key)
    if InCombatLockdown() then return FP:Print(L["Cannot do that in combat."]) end
    key = key or (self:DisenchantRecipients()[1] or {}).key
    if not key then return FP:Print(L["None of your characters has Enchanting."]) end
    local back = returnTo
    if not (self.deMode and Recipient()) then
        local f, v = self.frame, FP.AltProfs.viewing
        back = { shown = f ~= nil and f:IsShown(), page = self.page,
            viewing = v and { key = v.key, skillLine = v.skillLine } }
    end
    if FP.AltProfs:View(key, ENCHANTING) then -- turns the mode off first, which drops returnTo
        self:SetDisenchantMode(true)
        returnTo = back
    end
end

-- The toggle, leaving an enchanter's gear: back to where OpenDisenchantFor came from (closed, the Overview, your own
-- profession or another character's). Entered from that enchanter's recipes (their header button), back to those.
local function LeaveDisenchantFor()
    local back = returnTo
    if not back then return UI:SetDisenchantMode(false) end
    if not back.shown then return UI.frame:Hide() end -- OnHide leaves the mode and the alt
    if back.viewing then return FP.AltProfs:View(back.viewing.key, back.viewing.skillLine) end
    FP.AltProfs:Stop() -- turns the mode off
    UI:Show(back.page)
end

-- A menu of your enchanters under `anchor`, each opening Disenchanting Mode for them, then the main enchanter choice.
function UI:OpenDisenchantRecipientMenu(anchor)
    local items, to = {}, self.deMode and Recipient()
    local recipients = self:DisenchantRecipients()
    local function Name(r)
        local cr, cg, cb = FP.Alts:ClassColor(r.rec.class)
        return ("|cff%02x%02x%02x%s|r (%d)"):format(cr * 255, cg * 255, cb * 255, FP.Alts:Label(r.rec), r.rank)
    end
    for _, r in ipairs(recipients) do
        items[#items + 1] = { text = Name(r), checked = to and to.key == r.key, dim = r.otherFaction,
            onSelect = function() UI:OpenDisenchantFor(r.key) end }
    end
    -- The main enchanter: picked here, the menu stays open with the tick moved.
    items[#items + 1] = { text = L["Main Enchanter"] .. ":", dim = true, keepOpen = true } -- a heading: clicking it does nothing
    local choices = {}
    local function Choice(text, key)
        local item = { text = text, indent = 1, checked = FP.db.mainEnchanter == key, keepOpen = true }
        item.onSelect = function()
            UI:SetMainEnchanter(key)
            for _, c in ipairs(choices) do c.checked = c == item end
        end
        choices[#choices + 1] = item
        items[#items + 1] = item
    end
    Choice(L["Automatic (Highest Skill)"], nil)
    for _, r in ipairs(self:Enchanters(true)) do Choice(Name(r), r.key) end
    self:OpenMenu(anchor, items, 220)
end

-- Your Enchanting from the profession list, once you know Disenchant; nil otherwise. The footer cell and the quick
-- button cast it to open Enchanting in Disenchanting Mode.
function UI:OwnEnchanting()
    if not IsPlayerSpell(FP.Disenchant.SPELL) then return end
    for _, p in ipairs(FP:GetProfessions()) do
        if p.skillLine == ENCHANTING then return p end
    end
end

-- The quick button and /pf de. Without Enchanting: the gear to send your best enchanter, or back from it. With
-- it: switches the mode while your Enchanting is shown in the window, and otherwise turns it on once Enchanting is
-- shown. `casting`: the quick button's secure cast is opening Enchanting (TRADE_SKILL_SHOW then shows the window).
-- Addon code can't open a profession, so when Enchanting isn't open and nothing casts it, the mode waits a few seconds
-- for it (a macro: /cast Enchanting, then /pf de), then says how to open it.
function UI:ToggleDisenchantMode(casting)
    if InCombatLockdown() then return FP:Print(L["Cannot do that in combat."]) end
    local f = self.frame
    local shown = f and f:IsShown() and self.page == "recipes"
    if not IsPlayerSpell(FP.Disenchant.SPELL) then
        if self.deMode and Recipient() and shown then return LeaveDisenchantFor() end
        return self:OpenDisenchantFor()
    end
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    local onEnchanting = base and base.professionID == ENCHANTING and not FP:IsReadOnly()
    if onEnchanting and shown then return self:SetDisenchantMode(not self.deMode) end
    pendingAt = GetTime()
    if onEnchanting then return self:Show("recipes") end
    if casting then return end
    local started = pendingAt
    C_Timer.After(1, function()
        if pendingAt == started then FP:Print(L["Open Enchanting first, or put /cast Enchanting before /pf de in a macro."]) end
    end)
end

function UI:QuickDisenchantClick(button, btn)
    if btn == "RightButton" then
        if not IsPlayerSpell(FP.Disenchant.SPELL) and not InCombatLockdown() then self:OpenDisenchantRecipientMenu(button) end
        return
    end
    self:ToggleDisenchantMode(button.castable)
end

-- The header button, left of the profession's spell buttons: on your own Enchanting once Disenchant is known, and on
-- another character's Enchanting (to list gear to send them), where there are no spell buttons and it sits by the
-- skill bar. Leaving Enchanting turns the mode off. `leftmost` is the leftmost spell button.
function UI:UpdateDisenchantModeButton(skillLine, leftmost)
    local f = self.frame
    local to = self.page == "recipes" and Recipient() or nil
    local show = (skillLine == ENCHANTING and IsPlayerSpell(FP.Disenchant.SPELL) and leftmost ~= nil) or to ~= nil
    if not show then self:SetDisenchantMode(false) end
    -- A card icon asked for the mode: turn it on once your Enchanting is shown, if that happened within a few seconds.
    if pendingAt and show and not to then
        if GetTime() - pendingAt < 5 then self:SetDisenchantMode(true) end
        pendingAt = nil
    end
    if not f.deModeBtn then
        if not show then return end
        -- The same dust icon as the Overview card's, lit while the mode is on.
        f.deModeBtn = self:Button(f.header, "", 22, 22, function()
            UI:SetDisenchantMode(not UI.deMode)
        end)
        local icon = f.deModeBtn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 3, -3)
        icon:SetPoint("BOTTOMRIGHT", -3, 3)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(MODE_ICON)
        self:Tooltip(f.deModeBtn, "ANCHOR_BOTTOM", function(tip)
            tip:AddLine(L["Disenchanting Mode"], 1, 1, 1)
            local recipient = Recipient()
            tip:AddLine(UI.deMode and L["Click to go back to the Enchanting recipes."]
                or recipient and L["Lists the gear in your bags you could send %s to disenchant, what each may give and what that is worth."]:format(recipient.owner)
                or L["Lists the gear in your bags that can be disenchanted, what each may give and what that is worth."], 0.8, 0.8, 0.8, true)
        end)
    end
    f.deModeBtn:SetShown(show)
    if show then
        f.deModeBtn:ClearAllPoints()
        f.deModeBtn:SetPoint("RIGHT", leftmost or f.rank, "LEFT", leftmost and -4 or -6, 0)
    end
    self:ApplyDisenchantMode()
end
