--[[
ThreeLightsLib: the scrolling list with columns (UI:List).
]]
local _, ns = ...
local UI = ns.UI

---------------------------------------------------------------------------
-- Scrolling list with columns.
-- opts.columns: { { title, width (0 = fill), get = function(row) -> text, r, g, b; link = function(row);
--   portrait = function(row) -> texture, dot } }. portrait draws a 16 pixel picture before the cell's text (a class
--   icon, say), with a small status dot on its lower-right corner when dot is a color { r, g, b }.
-- opts.onClick(row, mouseButton), opts.rowHeight, opts.selectable (highlight the clicked row)
-- opts.sortable: clicking a column title sorts by it, again sorts the other way, a third time goes back to the order
--   SetRows was given. Shift-click adds a column as a tie-breaker (again flips it, a third time drops it); each sorted
--   column shows its arrow, and its place in the order when there is more than one. A column sorts by col.sort(row) when it has one (a number or a string; give one for dates,
--   money, ranks), else by its text: a number when the text starts with one, otherwise the text ignoring case and
--   color codes. col.sort = false leaves a column unsortable. Rows with no value ("" or "-") go last either way.
---------------------------------------------------------------------------
-- The icon before an item's name in a list cell: for columns that link an item (col.link), unless col.icon == false.
-- From the game's built-in item data, so it shows before the item itself has loaded.
local function ItemIcon(col, item)
    if not col.link or col.icon == false then return "" end
    local link = col.link(item)
    if type(link) ~= "string" or not link:find("item:", 1, true) then return "" end
    local icon = select(5, C_Item.GetItemInfoInstant(link))
    return icon and ("|T" .. icon .. ":0|t ") or ""
end

-- A cell's text without color codes, pictures or link markup (an item link becomes "[Name]"). For sort values.
function UI.PlainText(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    return strtrim(text)
end

-- The value a row sorts by in a column: a number, a string, or nil for none.
local function SortKey(col, item)
    if col.sort then return col.sort(item) end
    local text = UI.PlainText((col.get(item)))
    if text == "" or text == "-" then return nil end
    return tonumber(text:match("^%-?%d+%.?%d*")) or strlower(text)
end

-- Compares two sort values for direction dir (1 or -1): -1 when x goes first, 1 when y does, 0 when tied. No value
-- goes last and numbers before text, whichever the direction.
local function Compare(x, y, dir)
    if x == nil or y == nil then
        if x == y then return 0 end
        return x == nil and 1 or -1
    end
    local tx, ty = type(x), type(y)
    if tx ~= ty then return tx == "number" and -1 or 1 end
    if x == y then return 0 end
    if (x < y) == (dir > 0) then return -1 end
    return 1
end

-- a before b under sorts ({ { col, dir } }, first decides): ties fall through to the next, then the given order.
local function Before(a, b, sorts)
    for k, sort in ipairs(sorts) do
        local c = Compare(a.keys[k], b.keys[k], sort.dir)
        if c ~= 0 then return c < 0 end
    end
    return a.pos < b.pos
end

function UI:List(parent, opts)
    local rowH = opts.rowHeight or 20
    local list = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    list.libList = true  -- menus opened for its rows open at the mouse (UI:OpenMenu)
    UI:Skin(list, "panel")
    list.rows, list.data, list.source, list.columns = {}, {}, {}, opts.columns
    list.header = CreateFrame("Frame", nil, list)
    list.header:SetPoint("TOPLEFT", 4, -2)
    list.header:SetPoint("TOPRIGHT", -UI.BAR_GUTTER, -2)
    list.header:SetHeight(18)
    -- A faint accent band behind the column titles, so they read as a header.
    list.headerBg = list:CreateTexture(nil, "BORDER")
    list.headerBg:SetPoint("TOPLEFT", 1, -1)
    list.headerBg:SetPoint("TOPRIGHT", -1, -1)
    list.headerBg:SetHeight(20)
    -- Scrolled a row at a time: list.offset is the first row shown, moved by the wheel or the bar's thumb.
    list.offset = 0
    list.bar = UI:RowScrollbar(list, function(offset)
        list.offset = offset
        list:Refresh()
    end, { top = 24, bottom = 4 })
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(s, delta)
        s.offset = s.offset - delta * 2
        s:Refresh()
    end)
    -- The message for an empty list, wrapped to stay inside it.
    local empty = UI:Text(list, "normal", "CENTER")
    empty:SetPoint("LEFT", 12, 0)
    empty:SetPoint("RIGHT", -12, 0)
    empty:SetWordWrap(true)
    empty:SetTextColor(unpack(UI.colors.dim))
    list.empty = empty

    local PORTRAIT_W = 20  -- the picture and the gap after it

    local function Layout(cells, container)
        local x, total = 4, container:GetWidth()
        local fixed = 0
        for _, col in ipairs(list.columns) do fixed = fixed + (col.width or 0) end
        for i, col in ipairs(list.columns) do
            local width = (col.width and col.width > 0) and col.width or math.max(40, total - fixed - 8)
            -- In a row, a portrait column's text starts after the picture; its title stays over the picture.
            local pic = container.pics and container.pics[i]
            local pad = pic and PORTRAIT_W or 0
            local shown = x + width <= total + 1  -- a column past the right edge is hidden, not drawn outside the list
            cells[i]:ClearAllPoints()
            cells[i]:SetPoint("LEFT", container, "LEFT", x + pad, 0)
            cells[i]:SetWidth(width - 4 - pad)
            cells[i]:SetShown(shown)
            if pic then
                pic.icon:SetPoint("LEFT", container, "LEFT", x, 0)
                pic.shown = shown
            end
            x = x + width
        end
    end

    -- A portrait column's picture and status dot (a black edge under a colored centre).
    local function MakePortrait(row)
        local pic = {}
        pic.icon = row:CreateTexture(nil, "ARTWORK")
        pic.icon:SetSize(16, 16)
        pic.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        pic.edge = row:CreateTexture(nil, "OVERLAY", nil, 1)
        pic.edge:SetSize(8, 8)
        pic.edge:SetPoint("CENTER", pic.icon, "BOTTOMRIGHT", -1, 1)
        pic.edge:SetColorTexture(0, 0, 0, 1)
        pic.dot = row:CreateTexture(nil, "OVERLAY", nil, 2)
        pic.dot:SetSize(6, 6)
        pic.dot:SetPoint("CENTER", pic.edge)
        return pic
    end

    local function SetPortrait(pic, texture, dot)
        local on = pic.shown and texture ~= nil
        pic.icon:SetShown(on)
        if on then pic.icon:SetTexture(texture) end
        pic.edge:SetShown(on and dot ~= nil)
        pic.dot:SetShown(on and dot ~= nil)
        if on and dot then pic.dot:SetColorTexture(dot[1], dot[2], dot[3], 1) end
    end

    list.sorts = {}
    list.headerCells, list.sortArrows, list.sortButtons, list.sortRanks = {}, {}, {}, {}
    for i, col in ipairs(list.columns) do
        local fs = UI:Text(list.header, "small")
        fs:SetWordWrap(false)
        fs:SetText(col.title or "")
        list.headerCells[i] = fs
        if opts.sortable and col.sort ~= false and (col.title or "") ~= "" then
            -- The client's own sort arrow, cut the way its sort buttons cut it (9 of 16 wide).
            -- The art points down, so ascending (A first) draws it flipped to point up.
            local arrow = list.header:CreateTexture(nil, "ARTWORK")
            arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
            arrow:SetSize(9, 8)
            arrow:Hide()
            list.sortArrows[i] = arrow
            local rank = UI:Text(list.header, "small")
            rank:SetPoint("LEFT", arrow, "RIGHT", 1, 0)
            rank:Hide()
            list.sortRanks[i] = rank
            local btn = CreateFrame("Button", nil, list.header)
            btn:SetPoint("TOPLEFT", fs, "LEFT", -4, 9)
            btn:SetPoint("BOTTOMRIGHT", fs, "RIGHT", 0, -9)
            btn:SetScript("OnClick", function() list:SortBy(i, IsShiftKeyDown()) end)
            btn:SetScript("OnEnter", function() fs:SetTextColor(1, 1, 1) end)
            btn:SetScript("OnLeave", function()
                local a = UI:GetAccent()
                fs:SetTextColor(a[1], a[2], a[3])
            end)
            list.sortButtons[i] = btn
        end
    end

    -- Row tooltips. What the mouse is over decides the tooltip: an item link cell shows the item, anywhere else the
    -- list's own tooltip. It is checked every frame while the mouse is in the row, so moving between cells switches
    -- it, and redrawn when the row's data changes. It opens to the right of the mouse and follows it.
    local function CellUnderMouse(row)
        for i, cell in ipairs(row.cells) do
            if cell:IsShown() and cell:IsMouseOver() then return i end
        end
    end

    local function LinkCell(row, i)
        local col = i and list.columns[i]
        return col and col.link and col.link(row.item) or nil
    end

    -- What the tooltip should show for the mouse's spot in a row: an item link cell shows the item; a cell whose text
    -- is cut off shows its full text (above the list's own tooltip, if any); anywhere else the list's tooltip.
    -- Returns a key that changes when the tooltip should, the cell index, and the link.
    local function Target(row)
        if not row.item then return "none" end
        local i = CellUnderMouse(row)
        local link = LinkCell(row, i)
        if link then return "link" .. i, i, link end
        if i and row.cells[i]:IsTruncated() then return "cut" .. i, i end
        return "row", i
    end

    local function ShowTip(row)
        local key, i, link = Target(row)
        row.tipItem, row.tipKey = row.item, key
        local cut = key:sub(1, 3) == "cut"
        if key == "none" or (key == "row" and not opts.tooltip) then
            GameTooltip:Hide()
            return
        end
        GameTooltip:SetOwner(row, "ANCHOR_NONE")
        UI.TooltipAtCursor()
        if link then
            GameTooltip:SetHyperlink(link)
        else
            if cut then
                -- The full text, in the cell's color.
                local cell = row.cells[i]
                local r, g, b = cell:GetTextColor()
                GameTooltip:AddLine(cell:GetText(), r, g, b, true)
            end
            if opts.tooltip then
                if cut then GameTooltip:AddLine(" ") end
                if opts.tooltip(GameTooltip, row.item) == false and not cut then
                    GameTooltip:Hide()
                    return
                end
            end
        end
        GameTooltip:Show()
    end

    local function RowUpdate(row)
        if GameTooltip:IsOwned(row) then UI.TooltipAtCursor() end
        if row.item ~= row.tipItem or Target(row) ~= row.tipKey then ShowTip(row) end
    end

    local function RowEnter(row)
        ShowTip(row)
        row:SetScript("OnUpdate", RowUpdate)
    end

    local function RowLeave(row)
        row:SetScript("OnUpdate", nil)
        row.tipItem, row.tipKey = nil, nil
        GameTooltip:Hide()
    end

    local function MakeRow(i)
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(rowH)
        row:SetPoint("TOPLEFT", 2, -22 - (i - 1) * rowH)
        row:SetPoint("TOPRIGHT", -UI.BAR_GUTTER, -22 - (i - 1) * rowH)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.07)
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:Hide()
        row.cells, row.pics = {}, {}
        for c = 1, #list.columns do
            if list.columns[c].portrait then row.pics[c] = MakePortrait(row) end
            local cell = UI:Text(row, "normal")
            -- Rows taller than one line (rowHeight 30 and up) show as many lines as fit, for "title\ndetail" cells.
            if rowH >= 30 then
                cell:SetHeight(rowH - 4)
                cell:SetWordWrap(true)
                cell:SetMaxLines(math.floor((rowH - 4) / 14))
                cell:SetJustifyV("MIDDLE")
            else
                cell:SetWordWrap(false)
            end
            row.cells[c] = cell
        end
        Layout(row.cells, row)
        row:SetScript("OnClick", function(s, button)
            if not s.item then return end
            if opts.selectable then
                list.selected = s.item
                list:Refresh()
            end
            if opts.onClick then opts.onClick(s.item, button) end
        end)
        row:SetScript("OnEnter", RowEnter)
        row:SetScript("OnLeave", RowLeave)
        list.rows[i] = row
        return row
    end

    function list:Refresh()
        local shown = math.max(1, math.floor((self:GetHeight() - 24) / rowH))
        self.offset = math.max(0, math.min(self.offset, #self.data - shown))
        local offset = self.offset
        self.bar:Update(offset, #self.data, shown)
        Layout(self.headerCells, self.header)
        local a = UI:GetAccent()  -- read each time, so a skin change shows on the next refresh
        for i, fs in ipairs(self.headerCells) do
            local btn, arrow = self.sortButtons[i], self.sortArrows[i]
            if not (btn and btn:IsMouseOver()) then fs:SetTextColor(a[1], a[2], a[3]) end
            if btn then btn:SetShown(fs:IsShown()) end
            if arrow then
                local place, sort
                for k, s in ipairs(self.sorts) do
                    if s.col == i then place, sort = k, s end
                end
                local on = fs:IsShown() and sort ~= nil
                arrow:SetShown(on)
                self.sortRanks[i]:SetShown(on and #self.sorts > 1)
                if on then
                    arrow:ClearAllPoints()
                    arrow:SetPoint("LEFT", fs, "LEFT", math.min(fs:GetStringWidth(), fs:GetWidth() - 9) + 3, 0)
                    if sort.dir > 0 then arrow:SetTexCoord(0, 0.5625, 1, 0) else arrow:SetTexCoord(0, 0.5625, 0, 1) end
                    self.sortRanks[i]:SetText(place)
                    self.sortRanks[i]:SetTextColor(a[1], a[2], a[3])
                end
            end
        end
        self.headerBg:SetColorTexture(a[1], a[2], a[3], 0.10)
        for i = 1, math.max(shown, #self.rows) do
            local row = self.rows[i] or (i <= shown and MakeRow(i))
            if row then
                local item = i <= shown and self.data[offset + i]
                row.item = item or nil
                if item then
                    Layout(row.cells, row)
                    for c, col in ipairs(self.columns) do
                        local text, r, g, b = col.get(item)
                        row.cells[c]:SetText(ItemIcon(col, item) .. (text or ""))
                        row.cells[c]:SetTextColor(r or 1, g or 1, b or 1)
                        if row.pics[c] then SetPortrait(row.pics[c], col.portrait(item)) end
                    end
                    row.sel:SetColorTexture(a[1], a[2], a[3], 0.18)
                    row.sel:SetShown(opts.selectable and self.selected == item)
                    row:Show()
                    if row:GetScript("OnUpdate") then ShowTip(row) end  -- hovered: show the new data
                else
                    row:Hide()
                end
            end
        end
        empty:SetShown(#self.data == 0)
    end

    -- Sorts self.source into self.data by the chosen columns, or keeps the given order when none is chosen.
    local function ApplySort(self)
        local src, sorts = self.source, self.sorts
        if #sorts == 0 then
            self.data = src
            return
        end
        local keyed = {}
        for pos, item in ipairs(src) do
            local keys = {}
            for k, sort in ipairs(sorts) do keys[k] = SortKey(self.columns[sort.col], item) end
            keyed[pos] = { item = item, pos = pos, keys = keys }
        end
        table.sort(keyed, function(a, b) return Before(a, b, sorts) end)
        local out = {}
        for i, k in ipairs(keyed) do out[i] = k.item end
        self.data = out
    end

    -- Clicking column i's title: ascending, then descending, then the given order. add (Shift-click): the column joins
    -- the sorts as the last tie-breaker, or flips, or leaves; the other sorted columns stay.
    function list:SortBy(i, add)
        local sorts, at = self.sorts, nil
        for k, s in ipairs(sorts) do
            if s.col == i then at = k end
        end
        if not add and not (at and #sorts == 1) then
            self.sorts = { { col = i, dir = 1 } }
        elseif not at then
            sorts[#sorts + 1] = { col = i, dir = 1 }
        elseif sorts[at].dir > 0 then
            sorts[at].dir = -1
        else
            table.remove(sorts, at)
        end
        ApplySort(self)
        self:Refresh()
    end

    function list:SetRows(data)
        self.source = data or {}
        ApplySort(self)
        self:Refresh()
    end

    list:SetScript("OnSizeChanged", function() list:Refresh() end)
    return list
end
