local _, FP = ...
local L = FP.L
local Shop = FP.Shop -- created in Core/Shopping.lua

local ROWS, ROW_H = 11, 24
local ACTION_BUTTON_H = 20
local ICON_SLOT = 20 -- the icon of the item typed in the add box, as tall as the box
Shop.ACTION_BUTTON_H = ACTION_BUTTON_H

-- Columns run right to left; "Alts" only shows while alts count toward planning.
local COLS = { { "cost", "Cost", 100 }, { "buy", "Buy" }, { "alts", "Alts" }, { "have", "Own" }, { "need", "Need" } }
local COL_W, COL_GAP = 36, 4
local LIST_RIGHT = FP.UI.BAR_GUTTER -- inset of the rows and the scroll bar from the window's right edge
local COLS_RIGHT = LIST_RIGHT + 26 -- the rightmost column's distance from the window's right edge

-- Opens the list, or refreshes it when it is already open.
function Shop:Open()
    if self.frame and self.frame:IsShown() then return self:Update() end
    FP.UI:ShowSidePanel(self) -- OnShow refreshes the list
end

-- Loads a listed item and its quantity into the add box, to retype the number.
function Shop:EditItem(itemID)
    if self.frame and self.frame.loadItem then self.frame.loadItem(itemID) end
end

function Shop:LayoutColumns(f, showAlts)
    -- Columns stay put under their headers.
    if f.altsShown == showAlts then return end
    f.altsShown = showAlts
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
            fs:SetPoint("RIGHT", row, "RIGHT", LIST_RIGHT - x, 0)
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
        row.name:SetPoint("RIGHT", row, "RIGHT", LIST_RIGHT - nameEdge, 0)
    end
end

-- Redraws the list, the on-screen tracker and the merchant's Buy List button; a change to the list redraws the other
-- windows through FP:Changed("shop").
function Shop:Update()
    local f = self.frame
    local listShown = f and f:IsShown()
    local data = listShown and self:Aggregate()
    self:UpdateTracker(data)
    self:QueueVendorUpdate()
    if not listShown then return end
    self:LayoutColumns(f, FP.Planner:Applies())
    if f.track then f.track:SetChecked(FP.db.trackShopping) end
    local shown = FP.UI.PanelRows(f) -- fewer than ROWS while the panel is docked shorter
    FauxScrollFrame_Update(f.scroll, #data, shown, ROW_H)
    f.scroll.fpSetRange(math.max(0, #data - shown) * ROW_H)
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
        local e = i <= shown and data[offset + i] or nil
        if e then
            row.itemID = e.itemID
            row.icon:SetTexture(C_Item.GetItemIconByID(e.itemID))
            row.name:SetText(e.name)
            row.need:SetText(e.needed)
            row.have:SetText(e.owned)
            row.alts:SetText(e.alts > 0 and e.alts or "")
            row.plan, row.queue, row.mine, row.cover = e.plan, e.queue, e.mine, e.cover
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
    f.coverHint:SetShown(not FP.Planner:Applies() and self:CoveredByOthers())
end

-- Whether another character's queued crafts cover something on the list (Shop.cover, set by the Aggregate above).
function Shop:CoveredByOthers()
    local me = FP.Alts:GetCharacterKey()
    for _, c in pairs(self.cover) do
        for key in pairs(c.by) do
            if key ~= me then return true end
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local GREY = { 0.6, 0.6, 0.6 }

-- A row's tooltip, on GameTooltip or on `tip` (the options' previewer: row.preview holds its made-up price, alts and
-- vendor). The queue and alts blocks come in Options, Tooltips, General's order; each part as its options say.
-- The owner says it writes its own queue lines and hint line, so Tooltips/ leaves those off (ownQueueLines, ownHints).
function Shop:FillRowTooltip(row, tip)
    tip = tip or GameTooltip
    local db, Tips, pv, id = FP.db, FP.Tooltips, row.preview, row.itemID
    tip:SetItemByID(id)
    local hidden = Tips.hidden -- detail a provider held back (every disenchant result)
    FP.Prices:AddUnitLine(tip, id, pv and pv.unit)
    local blocks = {
        queue = function()
            if row.queue <= 0 then return end
            local c = row.cover
            Tips:Space(tip)
            tip:AddDoubleLine(L["Needed by Crafting Queues"], c and c.need or row.queue, 0.8, 0.8, 0.8, 1, 1, 1)
            if db.queueTooltipShopRows and Tips:AddQueueRecipes(tip, id) then hidden = true end
            if Tips:AddMadeBy(tip, c) then hidden = true end
            if row.mine ~= 0 then
                tip:AddDoubleLine(L["Your Change"], ("%+d"):format(row.mine), 0.8, 0.8, 0.8, 1, 1, 1)
            end
        end,
        alts = function()
            if row.plan then FP.UI:AddAltLines(tip, row.plan, nil, pv and pv.alts) end
        end,
    }
    for _, key in ipairs(Tips:Order()) do
        if blocks[key] then blocks[key]() end
    end
    local vendor
    if db.tipVendor then
        if pv then vendor = pv.vendor
        elseif FP.Waypoint:VendorNavAvailable(id) then vendor = FP.Waypoint:VendorSummary(id) end
    end
    if vendor then tip:AddLine(L["Sold by: %s"]:format(vendor), 1, 0.82, 0, true) end
    local hints = { { L["Click: Quantity"], L["Click: change the quantity"] } }
    if vendor then hints[#hints + 1] = { L["Right: Vendor Waypoint"], L["Right-click: waypoint to the nearest vendor"] } end
    hints[#hints + 1] = { L["Ctrl: Auction House"], L["Ctrl-click: search the auction house"] }
    hints[#hints + 1] = { L["Alt: Recipes"], L["Alt-click: find the recipes that use this reagent"] }
    FP.UI:AddHints(tip, hints, hidden, GREY)
end

local function RowTooltip(row)
    if not row.itemID then return false end
    row.ownQueueLines, row.ownHints = true, true
    Shop:FillRowTooltip(row)
end

local function RowClick(row, button)
    if not row.itemID or FP.UI.LinkItemToChat(row.itemID) then return end
    if button == "RightButton" then return FP.Waypoint:NearestVendor(row.itemID) end
    if IsControlKeyDown() then return Shop:SearchAuctionHouse(row.itemID) end
    if IsAltKeyDown() then return FP.ReagentSearch:Open(row.itemID) end
    Shop:EditItem(row.itemID)
end

local function RowRemove(button)
    local id = button:GetParent().itemID
    if id then Shop:Remove(id) end
end

-- Tracking: the shopping list on screen, as a small movable tracker with owned/needed counts.
local function BuildTracking(f)
    local UI = FP.UI
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

    UI:AddPanelList(f, { name = "ProfessionsForeverShopScroll", top = 56, bottom = 140, rows = ROWS, rowH = ROW_H,
        update = function() Shop:Update() end, tooltip = RowTooltip, onClick = RowClick, rightClick = true,
        build = function(row)
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
        end })
    Shop:LayoutColumns(f, false)

    -- While Planning isn't Include in Planning, items another character's queue makes come back as they are crafted, in
    -- that character's bags, until mailed. Said where the item names start, left of the column headers.
    local hint = CreateFrame("Frame", nil, f)
    hint:SetPoint("TOPLEFT", 14, -34)
    hint:SetSize(150, 16)
    hint:EnableMouse(true)
    hint.text = UI:Text(hint, -2)
    hint.text:SetPoint("LEFT")
    hint.text:SetText(L["Made by Queues (?)"])
    hint.text:SetTextColor(0.6, 0.6, 0.6)
    UI:Tooltip(hint, "ANCHOR_TOP", function(tip)
        tip:AddLine(L["Made by Queues"], 1, 1, 1)
        tip:AddLine(L["Some items are off the list because another character's queue makes them. They come back as that character crafts them, until mailed. Set Alt Inventory to Include in Planning to count them in that character's bags instead."], 0.8, 0.8, 0.8, true)
    end)
    hint:Hide()
    f.coverHint = hint

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
    item:SetSize(200 - ICON_SLOT - 4, 20)
    -- Above the window buttons, after the icon. InputBoxTemplate draws its left cap about 5px outside the box;
    -- EllesmereUI's square box has no cap.
    item.fpEUILayout = function() item:SetPoint("BOTTOMLEFT", 13 + ICON_SLOT + 4 + (UI.EUI() and 0 or 5), 112) end
    item.fpEUILayout()
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
    local ph = UI:AddPlaceholder(item, L["Item ID / link / name"])
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
    local suggest = FP.UI:AttachItemAutocomplete(item, function(name)
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
    suggest:IconSlot(ICON_SLOT):SetPoint("BOTTOMLEFT", 13, 112) -- where the box's left cap started
    UI:Stepper(qty, 1, 9999)
    add = UI:Button(f, L["Add"], 60, ACTION_BUTTON_H, AddManual)
    add:SetPoint("LEFT", qty.plus, "RIGHT", 8, 0)
    local find = FP.ReagentSearch:CreateButton(f, ACTION_BUTTON_H, function()
        local text = strtrim(item:GetText())
        FP.ReagentSearch:Open(text ~= "" and suggest:Resolve(text) or nil)
    end)
    find:SetPoint("LEFT", add, "RIGHT", 6, 0)
    -- A list row loads its item and quantity here, with the quantity ready to retype.
    f.loadItem = function(itemID)
        local name = C_Item.GetItemNameByID(itemID)
        if not name then return end
        editName = name
        item:SetText(name)
        SetEditing(itemID)
        qty:SetText(math.max(1, Shop:Quantity(itemID)))
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
    f.reset = UI:Button(f, L["Reset to Queue"], 130, ACTION_BUTTON_H, function()
        Shop:ResetToQueue()
        FP:Print(L["Shopping list reset to what the queues need."])
    end)
    f.reset:SetPoint("BOTTOMLEFT", 14, 46)
    UI:Tooltip(f.reset, "ANCHOR_TOP", function(tip)
        tip:AddLine(L["Reset to Queue"], 1, 1, 1)
        tip:AddLine(L["Undoes your changes to the items the queues need, including ones you removed. Anything you added yourself stays on the list."], 0.8, 0.8, 0.8, true)
    end)
    f.ah = UI:Button(f, L["Send to Auctionator"], 150, ACTION_BUTTON_H, function() Shop:SendToAuctionator() end)
    f.ah:SetPoint("LEFT", f.reset, "RIGHT", 6, 0)
    UI:AddWindowButtons(f, 80) -- between the item search and Reset to Queue
end

function Shop:Create()
    local f = FP.UI:CreateSidePanel({ name = "ProfessionsForeverShoppingFrame", key = "shop", title = L["Shopping List"],
        width = 460, height = 460, onShow = function() Shop:Update() end,
        openSound = SOUNDKIT.IG_BACKPACK_OPEN, closeSound = SOUNDKIT.IG_BACKPACK_CLOSE })
    self.frame = f
    BuildTracking(f)
    BuildList(f)
    BuildManualAdd(f)
    BuildButtons(f)
end
Shop.Toggle = FP.UI.ToggleSidePanel
