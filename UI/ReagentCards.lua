local _, FP = ...
local L = FP.L
local HINT_COLOR = { 0.5, 0.8, 1 }
local UI = FP.UI
local Skin = UI.ActiveSkin
local CARD_H, STATUS_COLORS, ItemName = UI.CARD_H, UI.STATUS_COLORS, FP.ItemName

-- The recipe panel's reagent cards: icon, name, owned / needed, and the vendor, shopping list, queue and alt badges.
-- UI:CreateReagentCards builds the grid, UI.UpdateReagentCards fills it for a recipe, and UI.LayoutReagentCards fits
-- it to the panel's height.

local BADGE_QUEUE = "Interface\\Icons\\INV_Misc_Gear_01"
local BADGE_SHOP = "Interface\\Icons\\INV_Misc_Coin_01"
local BADGE_VENDOR = "Interface\\Icons\\INV_Misc_Map_01"
local BADGE_ALTS = "Interface\\Icons\\INV_Letter_15"

-- Hoverable badge (icon + number) in a reagent card's top-right corner; onClick is optional.
local function Badge(row, texture, onEnter, onClick)
    local b = CreateFrame("Frame", nil, row)
    b:SetHeight(14)
    b:EnableMouse(true)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(12, 12)
    b.icon:SetPoint("LEFT")
    b.icon:SetTexture(texture)
    UI.TrimIcon(b.icon)
    b.text = UI:Text(b, -1, "LEFT")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 2, 0)
    UI:Tooltip(b, "ANCHOR_TOP", function() onEnter(row) end)
    if onClick then
        b:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then onClick(row) end end)
    end
    return b
end

-- Lays out the vendor / shopping-list / queue badges right-to-left and keeps the name clear of them.
local function LayoutBadges(row)
    local right = -6
    local leftmost
    for _, b in ipairs(row.badges) do
        local n
        if b == row.vBadge then n = row.hasVendor and 1 or 0
        elseif b == row.aBadge then n = row.altQty or 0
        else n = (b == row.sBadge and row.shopQty or row.queueQty) or 0 end
        b:SetShown(n > 0)
        if n > 0 then
            b.text:SetText(b == row.vBadge and "" or n)
            b:SetWidth(14 + b.text:GetStringWidth())
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, -4)
            right = right - b:GetWidth() - 6
            leftmost = b
        end
    end
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
    if leftmost then row.name:SetPoint("RIGHT", leftmost, "LEFT", -4, 0) else row.name:SetPoint("RIGHT", -6, 0) end
end

-- A card in the reagent cards' style: a skinned button with a status stripe down its left edge, an icon and a name,
-- and the accent border on hover. The reagent cards and Disenchanting Mode's cards are built on it.
function UI:CreateCard(parent, h)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    self:Skin(row, "button")
    row:SetHeight(h)
    row.stripe = row:CreateTexture(nil, "ARTWORK")
    row.stripe:SetWidth(4)
    row.stripe:SetPoint("TOPLEFT", 1, -1)
    row.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(h - 10, h - 10)
    row.icon:SetPoint("LEFT", 10, 0)
    row.name = self:Text(row, 0)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
    row.name:SetPoint("RIGHT", -6, 0)
    row.name:SetWordWrap(false)
    row:HookScript("OnEnter", function(s) s:SetBackdropBorderColor(unpack(UI:GetAccent())) end)
    row:HookScript("OnLeave", function(s) s:SetBackdropBorderColor(unpack(Skin().button.border)) end)
    return row
end

-- The grid of reagent cards; d.AddReagentCard(i) creates card i when a recipe needs it.
function UI:CreateReagentCards(d, c)
    d.rows = {}
    d.AddReagentCard = function(i)
        local row = self:CreateCard(c, CARD_H)
        row.count = self:Text(row, 1)
        row.count:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
        row.bankTag = self:Text(row, -1, "RIGHT")
        row.bankTag:SetPoint("BOTTOMRIGHT", -6, 4)
        row.bankTag:SetTextColor(unpack(STATUS_COLORS.bank))
        row.count:SetPoint("RIGHT", row.bankTag, "LEFT", -4, 0)
        row.count:SetWordWrap(false)
        row.vBadge = Badge(row, BADGE_VENDOR, function(r)
            GameTooltip:AddLine(L["Sold by a vendor"], 1, 0.82, 0)
            GameTooltip:AddLine(FP.Waypoint:VendorSummary(r.itemID), 1, 1, 1, true)
            GameTooltip:AddLine(L["Click: waypoint to the nearest vendor"], 0.5, 0.8, 1)
        end, function(r) FP.Waypoint:NearestVendor(r.itemID) end)
        row.qBadge = Badge(row, BADGE_QUEUE, function(r)
            GameTooltip:AddLine(L["Crafting Queue"], 0.4, 0.8, 1)
            GameTooltip:AddLine(L["%d needed by queued recipes:"]:format(r.queueQty or 0), 1, 1, 1)
            for _, u in ipairs(FP.Queue:UsageList(r.itemID)) do
                GameTooltip:AddDoubleLine(u.name .. " x" .. u.crafts, u.need, 0.8, 0.8, 0.8, 1, 1, 1)
            end
        end)
        row.sBadge = Badge(row, BADGE_SHOP, function(r)
            local want, have = r.shopQty or 0, r.owned or 0
            GameTooltip:AddLine(L["Shopping List"], 1, 0.82, 0)
            GameTooltip:AddDoubleLine(L["On the List"], tostring(want), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["You Have"], tostring(have), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Still to Buy"], tostring(math.max(0, want - have)), 0.8, 0.8, 0.8, 1, 1, 1)
        end)
        row.aBadge = Badge(row, BADGE_ALTS, function(r)
            local it = r.reagent and r.reagent.plan
            if not it then return end
            GameTooltip:AddLine(ItemName(r.itemID), 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Need for Requested Crafts"], it.need, 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Current Bags"], it.bags, 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Current Bank"], it.bank, 0.8, 0.8, 0.8, 1, 1, 1)
            UI:AddAltLines(GameTooltip, it)
        end)
        row.badges = { row.vBadge, row.sBadge, row.qBadge, row.aBadge }
        row:HookScript("OnEnter", function(s)
            if not s.itemID then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            s.ownHints = true -- the key hint goes in this tooltip's own hint line (Tooltips/Tooltips.lua)
            GameTooltip:SetItemByID(s.itemID)
            local hidden = FP.Tooltips.hidden
            -- The normal item tooltip (with its queue block), then the window's own lines; the badges carry the counts.
            FP.Prices:AddUnitLine(GameTooltip, s.itemID)
            local vendor = s.hasVendor and FP.db.tipVendor
            if vendor then
                GameTooltip:AddLine(L["Sold by: %s"]:format(FP.Waypoint:VendorSummary(s.itemID)), 1, 0.82, 0, true)
            end
            local hints = { { L["Click: Add to Shopping List"], L["Click to add this reagent to the shopping list."] } }
            if vendor then hints[#hints + 1] = { L["Right: Vendor Waypoint"], L["Right-click: waypoint to the nearest vendor"] } end
            hints[#hints + 1] = { L["Alt: Recipes"], L["Alt-click: find the recipes that use this reagent"] }
            UI:AddHints(GameTooltip, hints, hidden, HINT_COLOR)
            GameTooltip:Show()
        end)
        row:HookScript("OnLeave", function() GameTooltip:Hide() end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(s, btn)
            if UI.LinkItemToChat(s.itemID) then return end
            if IsAltKeyDown() then
                if s.itemID then FP.ReagentSearch:Open(s.itemID) end
                return
            end
            if btn == "RightButton" then
                if s.hasVendor and s.itemID then FP.Waypoint:NearestVendor(s.itemID) end
            elseif s.itemID and s.need then
                FP.Shop:Add(s.itemID, s.need)
                FP.Shop:Open()
                FP:Print(L["Added %d item(s) to the shopping list."]:format(1))
            end
        end)
        d.rows[i] = row
    end
end

local REAGENT_TOP, REAGENT_GAP, CARD_MIN = 140, 4, 30

-- Cards shrink so the last line stays clear of the cost line, or of the enchant target above it.
local function LayoutReagentCards(d, count, targeted)
    local lines = math.max(1, math.ceil(count / 2))
    local contentH, h = d.content:GetHeight(), CARD_H
    if contentH > 100 then
        local free = contentH - REAGENT_TOP - (targeted and 206 or 134)
        h = math.max(CARD_MIN, math.min(CARD_H, math.floor((free - (lines - 1) * REAGENT_GAP) / lines)))
    end
    local key = h .. ":" .. #d.rows
    if d.cardLayout == key then return end
    d.cardLayout = key
    local c = d.content
    for i, row in ipairs(d.rows) do
        local y = -REAGENT_TOP - math.floor((i - 1) / 2) * (h + REAGENT_GAP)
        row:SetHeight(h)
        row.icon:SetSize(h - 10, h - 10)
        row:ClearAllPoints()
        if i % 2 == 1 then
            row:SetPoint("TOPLEFT", c, "TOPLEFT", 12, y)
            row:SetPoint("TOPRIGHT", c, "TOP", -3, y)
        else
            row:SetPoint("TOPLEFT", c, "TOP", 3, y)
            row:SetPoint("TOPRIGHT", c, "TOPRIGHT", -12, y)
        end
    end
end

-- One card per reagent: icon, name, owned / needed, and the queue, shopping list and vendor badges.
function UI.UpdateReagentCards(d, e, ev)
    for i = #d.rows + 1, #ev.reagents do d.AddReagentCard(i) end
    d.cardCount, d.cardTargeted = #ev.reagents, FP.Recipes:IsEnchant(e.id)
    LayoutReagentCards(d, d.cardCount, d.cardTargeted)
    for i = 1, #d.rows do
        local row, r = d.rows[i], ev.reagents[i]
        if r then
            local col
            if r.total < r.need then
                if r.total + (r.mail or 0) >= r.need then
                    col = UI.MAIL_COLOR -- the rest is waiting in the mailbox
                elseif r.totalWithAlts and r.totalWithAlts + (r.mail or 0) >= r.need then
                    col = UI.ALT_COLOR -- short locally, but enabled alts could cover the whole quantity
                else
                    col = r.total > 0 and STATUS_COLORS.partial or STATUS_COLORS.missing
                end
            else
                col = r.bags < r.need and STATUS_COLORS.bank or STATUS_COLORS.full
            end
            row.itemID, row.need = r.itemID, r.need
            row.icon:SetTexture(C_Item.GetItemIconByID(r.itemID))
            row.name:SetText(ItemName(r.itemID))
            row.name:SetTextColor(0.92, 0.92, 0.92)
            row.stripe:SetColorTexture(col[1], col[2], col[3], 1)
            row.count:SetText(("%d / %d"):format(r.total, r.need))
            row.count:SetTextColor(col[1], col[2], col[3])
            local mailTag = (r.mail or 0) > 0 and (UI.Hex(UI.MAIL_COLOR) .. L["%d in mail"]:format(r.mail) .. "|r") or nil
            local bankTag = r.bank > 0 and L["%d in bank"]:format(r.bank) or nil
            row.bankTag:SetText(bankTag and mailTag and (bankTag .. "  " .. mailTag) or bankTag or mailTag or "")
            row.queueQty = FP.Queue:QueuedAmount(r.itemID)
            row.shopQty = FP.Shop:Quantity(r.itemID)
            row.owned = r.total
            row.altQty = r.alts or 0
            row.reagent = r
            row.hasVendor = FP.Waypoint:VendorNavAvailable(r.itemID)
            LayoutBadges(row)
            row:Show()
        else
            row.itemID = nil
            row:Hide()
        end
    end
end
UI.LayoutReagentCards = LayoutReagentCards
