local _, FP = ...
local L = FP.L
local Shop = {}
FP.Shop = Shop

local ROWS, ROW_H = 12, 24
local ACTION_BUTTON_H = 20
Shop.ACTION_BUTTON_H = ACTION_BUTTON_H

-- Columns run right to left; "Alts" only shows while alts count toward planning.
local COLS = { { "cost", "Cost", 114 }, { "buy", "Buy" }, { "alts", "Alts" }, { "have", "Own" }, { "need", "Need" } }
local COL_W, COL_GAP = 36, 4
local LIST_RIGHT = 30 -- inset of the rows and the scroll bar from the window's right edge
local COLS_RIGHT = LIST_RIGHT + 26 -- the rightmost column's distance from the window's right edge

-- Flat model: list[itemID] = total quantity needed. Owned counts are compared live, so
-- the "to buy" column shrinks as the player acquires items.
function Shop:Data()
    if FP.db.shoppingScope == "account" then return FP.db.shopping end
    return FP.chardb.shopping
end

-- Opens the list, or refreshes it when it is already open.
function Shop:Open()
    if not self.frame then self:Create() end
    if self.frame:IsShown() then return self:Update() end
    FP.UI:PlaceSidePanel(self.frame)
    self.frame:Show() -- OnShow refreshes the list
end

function Shop:Add(itemID, qty)
    local d = self:Data()
    d[itemID] = (d[itemID] or 0) + math.max(1, qty or 1)
    self:Open()
end

function Shop:Remove(itemID)
    self:Data()[itemID] = nil
    self:Update()
end

-- Replaces the quantity; zero removes the item.
function Shop:SetQuantity(itemID, count)
    self:Data()[itemID] = count > 0 and count or nil
    self:Update()
end

-- Loads a listed item and its quantity into the add box, to retype the number.
function Shop:EditItem(itemID)
    if self.frame and self.frame.loadItem then self.frame.loadItem(itemID) end
end

-- This character's queue remembers how much of each item it put on the list, so asking again or asking for less
-- adjusts that share instead of stacking, and quantities you added yourself are left alone.
function Shop:SetFromQueue(itemID, need)
    local d, from = self:Data(), FP.chardb.shoppingQueue
    local before = d[itemID]
    -- An item you removed from the list no longer carries the queue's share.
    local prev = d[itemID] and from[itemID] or 0
    local left = (d[itemID] or 0) + need - prev
    d[itemID] = left > 0 and left or nil
    from[itemID] = need > 0 and need or nil
    return d[itemID] ~= before -- whether the list changed
end

-- A queued craft used up `reagents` ({ itemID, qty }), so the queue no longer needs them. Takes that much off the
-- queue's share of the list, which keeps finished items from reappearing as still to buy.
function Shop:CreditCraft(reagents)
    local d, from = self:Data(), FP.chardb.shoppingQueue
    local changed = false
    for _, r in ipairs(reagents) do
        local share = from[r.itemID]
        if share then
            local used = math.min(r.qty, share)
            from[r.itemID] = share > used and share - used or nil
            local left = (d[r.itemID] or 0) - used
            d[r.itemID] = left > 0 and left or nil
            changed = true
        end
    end
    if changed then self:Update() end
end

-- Re-reads the queue's needs for everything it put on the list, for when the queue shrank or was cleared. With
-- addNew, materials that have become short are added too, except ones you removed from the list yourself.
-- Callers refresh the list afterwards.
function Shop:RecalculateFromQueue(addNew)
    local needs = {}
    for _, it in ipairs(FP.Queue:TrueShortages()) do needs[it.itemID] = it.need end
    local d, from = self:Data(), FP.chardb.shoppingQueue
    for itemID in pairs(from) do
        local need = needs[itemID] or 0
        if d[itemID] then
            self:SetFromQueue(itemID, need)
        elseif need == 0 then
            from[itemID] = nil -- removed by you, and no longer needed by the queue
        end
    end
    if addNew then
        -- Anything still in `from` was handled above or removed by you.
        for itemID, need in pairs(needs) do
            if not from[itemID] then self:SetFromQueue(itemID, need) end
        end
    end
end

-- Once the queue has put anything on the list, changes to what alts can supply carry through to it.
function Shop:SyncFromQueue()
    if next(FP.chardb.shoppingQueue) then self:RecalculateFromQueue(true) end
end

-- Adds the full needed quantity of every reagent that is still short (evaluation from Recipes:Evaluate); when alts
-- count toward planning, reagents they can cover are left off.
function Shop:AddRecipeMissing(ev)
    local n = 0
    local d = self:Data()
    for _, r in ipairs(ev.reagents) do
        if (r.shortage or r.short) > 0 then
            d[r.itemID] = (d[r.itemID] or 0) + r.need
            n = n + 1
        end
    end
    self:Open()
    return n
end

-- The list is one requirement set for the transfer planner; toBuy is its shortage, so stock that alts can send
-- is not bought when they count toward planning.
function Shop:Aggregate()
    local reqs = {}
    for itemID, needed in pairs(self:Data()) do reqs[#reqs + 1] = { itemID = itemID, need = needed } end
    table.sort(reqs, function(a, b) return a.itemID < b.itemID end) -- a stable order keeps the plan cache key stable
    local plan = FP.Planner:Plan(reqs)
    local out = {}
    for _, r in ipairs(reqs) do
        local it = plan.byItem[r.itemID]
        local owned, toBuy, alts = 0, 0, 0
        if it then owned, toBuy, alts = it.have, it.shortage, plan.applies and it.transfer or 0 end
        local unit = FP.Prices:Unit(r.itemID)
        out[#out + 1] = { itemID = r.itemID, name = FP.UI.ItemName(r.itemID), needed = r.need, owned = owned,
            alts = alts, plan = it, toBuy = toBuy, unit = unit, cost = unit and unit * toBuy or nil }
    end
    table.sort(out, function(a, b)
        if (a.toBuy > 0) ~= (b.toBuy > 0) then return a.toBuy > 0 end
        return a.name < b.name
    end)
    return out
end

-- Items still to buy, their estimated total cost, and how many have no auction price. data: an Aggregate result.
function Shop:Summary(data)
    local items, cost, unpriced = 0, 0, 0
    for _, e in ipairs(data or self:Aggregate()) do
        if e.toBuy > 0 then
            items = items + 1
            if e.cost then cost = cost + e.cost else unpriced = unpriced + 1 end
        end
    end
    return items, cost, unpriced
end

function Shop:Clear()
    wipe(self:Data())
    self:Update()
end

function Shop:RemoveDone()
    local d = self:Data()
    for _, e in ipairs(self:Aggregate()) do
        if e.toBuy == 0 then d[e.itemID] = nil end
    end
    self:Update()
end

function Shop:LayoutColumns(f, showAlts)
    -- Columns stay put under their headers, so they are placed from wherever the rows' right edge currently is.
    local right = f.rowEdge.inset
    if f.altsShown == showAlts and f.laidRight == right then return end
    f.altsShown, f.laidRight = showAlts, right
    local x, nameEdge = COLS_RIGHT, 0
    for _, col in ipairs(COLS) do
        local key, width = col[1], col[3] or COL_W
        local isAlts = key == "alts"
        local h = f.headers[key]
        h:ClearAllPoints()
        h:SetPoint("TOPRIGHT", -x, -38)
        if isAlts then h:SetShown(showAlts) end
        for _, row in ipairs(f.rows) do
            local fs = row[key]
            fs:ClearAllPoints()
            fs:SetPoint("RIGHT", row, "RIGHT", right - x, 0)
            if isAlts then fs:SetShown(showAlts) end
        end
        if not isAlts or showAlts then
            nameEdge = x + width + 2
            x = x + width + COL_GAP
        end
    end
    for _, row in ipairs(f.rows) do
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", right - nameEdge, 0)
    end
end

function Shop:Update()
    local f = self.frame
    local listShown = f and f:IsShown()
    local data = listShown and self:Aggregate()
    self:UpdateTracker(data)
    self:QueueVendorUpdate()
    if FP.UI.frame and FP.UI.frame:IsShown() then
        FP.UI:UpdateDetail()
        FP.UI:RefreshFooter()
    end
    if not listShown then return end
    f.rowEdge:SetBar(#data > ROWS)
    self:LayoutColumns(f, FP.Planner:Applies())
    if f.track then f.track:SetChecked(FP.db.trackShopping) end
    FauxScrollFrame_Update(f.scroll, #data, ROWS, ROW_H)
    if f.scroll.fpEUISetRange then f.scroll:fpEUISetRange(math.max(0, #data - ROWS) * ROW_H) end
    local offset = FauxScrollFrame_GetOffset(f.scroll)
    f.empty:SetShown(#data == 0)
    local hasPrices = FP.Prices:Available()
    f.costHeader:SetShown(hasPrices)
    local _, total, unpriced = self:Summary(data)
    f.totalLabel:SetShown(hasPrices)
    f.total:SetShown(hasPrices)
    f.total:SetText(total > 0 and FP.Prices:Format(total) or "-")
    f.unpriced:SetText(hasPrices and unpriced > 0 and L["%d without an auction price"]:format(unpriced) or "")
    local colors = FP.UI.STATUS_COLORS
    for i, row in ipairs(f.rows) do
        local e = data[offset + i]
        if e then
            row.itemID = e.itemID
            row.icon:SetTexture(C_Item.GetItemIconByID(e.itemID))
            row.name:SetText(e.name)
            row.need:SetText(e.needed)
            row.have:SetText(e.owned)
            row.alts:SetText(e.alts > 0 and e.alts or "")
            row.plan = e.plan
            row.buy:SetText(e.toBuy)
            row.cost:SetShown(hasPrices)
            row.cost:SetText(e.toBuy == 0 and "" or (e.cost and FP.Prices:Format(e.cost) or "-"))
            local c = e.toBuy == 0 and colors.full or (e.owned > 0 and colors.partial or colors.missing)
            row.name:SetTextColor(c[1], c[2], c[3])
            row.buy:SetTextColor(c[1], c[2], c[3])
            row:Show()
        else
            row.itemID = nil
            row:Hide()
        end
    end
    f.ah:SetShown(FP.Prices:Available())
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function RowEnter(row)
    if not row.itemID then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(row.itemID)
    local unit = FP.Prices:Unit(row.itemID)
    if unit then GameTooltip:AddLine(L["Auction Price: %s each"]:format(FP.Prices:Format(unit)), 1, 0.82, 0) end
    if row.plan then FP.UI:AddAltLines(GameTooltip, row.plan) end
    GameTooltip:AddLine(L["Click: change the quantity"], 0.6, 0.6, 0.6)
    GameTooltip:AddLine(L["Ctrl-click: search the auction house"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function RowLeave() GameTooltip:Hide() end

local function RowClick(row)
    if not row.itemID or FP.UI.LinkItemToChat(row.itemID) then return end
    if IsControlKeyDown() then return Shop:SearchAuctionHouse(row.itemID) end
    Shop:EditItem(row.itemID)
end

local function RowRemove(button)
    local id = button:GetParent().itemID
    if id then Shop:Remove(id) end
end

local function BuildTitleBar(f)
    local UI = FP.UI
    local title = UI:Text(f, 2)
    title:SetPoint("LEFT", f, "TOPLEFT", 12, -UI.TITLE_H / 2)
    title:SetText(L["Shopping List"])
    title:SetTextColor(1, 0.82, 0)
    local close = UI:Button(f, "X", 22, ACTION_BUTTON_H, function() f:Hide() end)
    close:SetPoint("RIGHT", f, "TOPRIGHT", -6, -UI.TITLE_H / 2)
    UI:AddPinButton(f, close)

    -- Tracking: the shopping list on screen, as a small movable tracker with owned/needed counts.
    local track = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    track:SetSize(24, 24)
    track:SetPoint("RIGHT", f, "TOPRIGHT", -198, -UI.TITLE_H / 2)
    track:SetChecked(FP.db.trackShopping)
    track:SetScript("OnClick", function(s)
        FP.db.trackShopping = s:GetChecked() and true or false
        Shop:UpdateTracker()
    end)
    f.track = track
    local trackLabel = UI:Text(f, 0)
    trackLabel:SetPoint("LEFT", track, "RIGHT", 2, 0)
    trackLabel:SetText(L["Track on Screen"])
end

local function BuildList(f)
    local UI = FP.UI
    f.headers = {}
    for _, col in ipairs(COLS) do
        local h = UI:Text(f, -1, "RIGHT")
        h:SetWidth(col[3] or COL_W)
        h:SetText(L[col[2]])
        h:SetTextColor(0.7, 0.7, 0.7)
        f.headers[col[1]] = h
    end
    f.costHeader = f.headers.cost

    local scroll = CreateFrame("ScrollFrame", "ProfessionsForeverShopScroll", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -56)
    scroll:SetPoint("BOTTOMRIGHT", -LIST_RIGHT, 112)
    scroll:SetScript("OnVerticalScroll", function(s, offset)
        FauxScrollFrame_OnVerticalScroll(s, offset, ROW_H, function() Shop:Update() end)
    end)
    f.scroll = scroll
    local scrollBar = scroll.ScrollBar or _G["ProfessionsForeverShopScrollScrollBar"]
    if not UI:AttachEUIThinScrollbar(scroll, scrollBar, f, { top = 56, bottom = 112 }) then
        UI:EUIWidget(scrollBar, "scrollbar")
    end

    f.rowEdge = UI:RowEdge(f, LIST_RIGHT, 8)
    f.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -56 - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", f.rowEdge, "TOPRIGHT", 0, -56 - (i - 1) * ROW_H)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 1, 1, 0.08)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ROW_H - 4, ROW_H - 4)
        row.icon:SetPoint("LEFT", 2, 0)
        local rm = UI:Button(row, "x", 18, 18, RowRemove)
        rm:SetPoint("RIGHT", -2, 0)
        for _, col in ipairs(COLS) do
            local fs = UI:Text(row, 0, "RIGHT")
            fs:SetWidth(col[3] or COL_W)
            row[col[1]] = fs
        end
        row.alts:SetTextColor(unpack(UI.STATUS_COLORS.bank))
        row.name = UI:Text(row, 0)
        row.name:SetWordWrap(false)
        row:SetScript("OnEnter", RowEnter)
        row:SetScript("OnLeave", RowLeave)
        row:SetScript("OnClick", RowClick)
        f.rows[i] = row
    end
    Shop:LayoutColumns(f, false)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        if scroll.fpEUIScrollTo then
            scroll.fpEUIScrollTo(scroll:GetVerticalScroll() - delta * ROW_H * 3)
        elseif scrollBar then
            scrollBar:SetValue(scrollBar:GetValue() - delta * ROW_H * 3)
        end
    end)

    f.empty = UI:Text(f, 0, "CENTER")
    f.empty:SetPoint("CENTER", 0, 20)
    f.empty:SetText(L["Shopping list is empty"])

    -- Estimated total of everything still to buy, priced from Auctionator's last scan.
    f.unpriced = UI:Text(f, -2, "RIGHT")
    f.unpriced:SetPoint("BOTTOMRIGHT", -16, 14)
    f.unpriced:SetTextColor(0.6, 0.6, 0.6)
    f.total = UI:Text(f, 2, "RIGHT")
    f.total:SetPoint("BOTTOMRIGHT", -16, 30)
    f.totalLabel = UI:Text(f, -1, "RIGHT")
    f.totalLabel:SetPoint("BOTTOMRIGHT", -16, 52)
    f.totalLabel:SetText(L["Estimated Cost to Buy"])
    f.totalLabel:SetTextColor(0.7, 0.7, 0.7)
end

-- Manual add: accepts an item ID, pasted item link, or a (cached) item name.
local function BuildManualAdd(f)
    local UI = FP.UI
    local item = CreateFrame("EditBox", "ProfessionsForeverShopItem", f, "InputBoxTemplate")
    item:SetSize(240, 20)
    item:SetPoint("BOTTOMLEFT", 18, 80)
    item:SetAutoFocus(false)
    UI:EUIWidget(item, "editbox")
    local qty = CreateFrame("EditBox", "ProfessionsForeverShopQty", f, "InputBoxTemplate")
    qty:SetSize(40, 20)
    qty:SetPoint("LEFT", item, "RIGHT", 32, 0)
    UI:EUIWidget(qty, "numbox")
    qty:SetAutoFocus(false)
    qty:SetNumeric(true)
    qty:SetMaxLetters(4)
    qty:SetText("1")
    local ph = UI:Text(item, -1)
    ph:SetPoint("LEFT", 2, 0)
    ph:SetText(L["Item ID / link / name"])
    ph:SetTextColor(0.5, 0.5, 0.5)
    local add
    -- Set when a list row was loaded into the box: Add then replaces that item's quantity instead of adding to it.
    local editing, editName
    local function SetEditing(id)
        editing = id
        add.text:SetText(id and L["Set"] or L["Add"])
    end
    item:SetScript("OnTextChanged", function(s)
        ph:SetShown(s:GetText() == "")
        if editing and s:GetText() ~= editName then SetEditing(nil) end
    end)
    local AddManual
    local suggest = Shop:AttachSuggest(item, function(name)
        item:SetText(name)
        AddManual()
    end)
    AddManual = function()
        local text = suggest:Selected() or strtrim(item:GetText())
        local id = editing or (text ~= "" and suggest:Resolve(text))
        if not id then return end
        local count = tonumber(qty:GetText()) or 1
        if editing then
            Shop:SetQuantity(id, count)
            qty:SetText("1")
        else
            Shop:Add(id, count)
        end
        item:SetText("")
        item:ClearFocus()
        qty:ClearFocus()
    end
    item:SetScript("OnEnterPressed", AddManual)
    item:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    qty:SetScript("OnEnterPressed", AddManual)
    qty:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    UI:AddClearButton(item, L["Clear Search"])
    UI:Stepper(qty, 1, 9999)
    add = UI:Button(f, L["Add"], 60, ACTION_BUTTON_H, AddManual)
    add:SetPoint("LEFT", qty.plus, "RIGHT", 8, 0)
    -- A list row loads its item and quantity here, with the quantity ready to retype.
    f.loadItem = function(itemID)
        local name = C_Item.GetItemNameByID(itemID)
        if not name then return end
        editName = name
        item:SetText(name)
        SetEditing(itemID)
        qty:SetText(Shop:Data()[itemID] or 1)
        qty:SetFocus()
        qty:HighlightText()
    end
end

local function BuildButtons(f)
    local UI = FP.UI
    local clear = UI:Button(f, L["Clear"], 90, ACTION_BUTTON_H, function() Shop:Clear() end)
    clear:SetPoint("BOTTOMLEFT", 14, 14)
    local done = UI:Button(f, L["Remove Done"], 110, ACTION_BUTTON_H, function() Shop:RemoveDone() end)
    done:SetPoint("LEFT", clear, "RIGHT", 6, 0)
    local export = UI:Button(f, L["Export"], 90, ACTION_BUTTON_H, function() Shop:ShowExport() end)
    export:SetPoint("LEFT", done, "RIGHT", 6, 0)
    f.recalc = UI:Button(f, L["Recalculate"], 130, ACTION_BUTTON_H, function()
        Shop:RecalculateFromQueue()
        Shop:Update()
        FP:Print(L["Shopping list recalculated from the crafting queue."])
    end)
    f.recalc:SetPoint("BOTTOMLEFT", 14, 46)
    UI:Tooltip(f.recalc, "ANCHOR_TOP", L["Updates what the crafting queue added to this list to match what the queue needs now."])
    f.ah = UI:Button(f, L["Send to Auctionator"], 150, ACTION_BUTTON_H, function() Shop:SendToAuctionator() end)
    f.ah:SetPoint("LEFT", f.recalc, "RIGHT", 6, 0)
end

function Shop:Create()
    local UI = FP.UI
    local f = CreateFrame("Frame", "ProfessionsForeverShoppingFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:Hide() -- frames start shown, which would skip OnShow and leave unpopulated rows visible
    f:SetSize(520, 460)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    UI:Skin(f, "window")
    tinsert(UISpecialFrames, "ProfessionsForeverShoppingFrame")
    f:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
        Shop:Update()
    end)
    f:SetScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
    end)
    UI:MakeSidePanelDraggable(f, "shop")
    BuildTitleBar(f)
    BuildList(f)
    BuildManualAdd(f)
    BuildButtons(f)
end

function Shop:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Open() end
end
