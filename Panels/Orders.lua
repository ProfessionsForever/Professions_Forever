local _, FP = ...
local L = FP.L
local Panel = {}
FP.OrdersPanel = Panel

-- The Crates and Writs window (Core/Orders.lua): which Waylaid Crates and Craftsman's Writs are worth doing.
--   Held: the crates and writs this character and the others hold, each with the cheapest way to fill it and a button
--     that queues the crafts or puts what is missing on the shopping list.
--   Buy Crates, Buy Writs: what buying one at the auction house and filling it would cost, per Favor or per
--     reputation.
local ROWS, ROW_H = 18, 22
local LIST_TOP = 86
local GREY, WHITE, GREEN, GOLD, BLUE = { 0.6, 0.6, 0.6 }, { 0.92, 0.92, 0.92 }, { 0.2, 0.9, 0.2 }, { 1, 0.82, 0 }, { 0.5, 0.8, 1 }
local GROUP_NAMES = { handin = "Ready to Hand In", crates = "Crates", writs = "Writs", unopened = "Not Opened Yet",
    alts = "On Other Characters", market = "Crates to Buy and Fill", sealedwrits = "Sealed Writs (Average)",
    writmarket = "Writs to Buy and Deliver", receipt = "Reputation From a Crate" }
-- The views (db.orderTab) in button order, and the groups of each in list order.
local TABS = { "held", "crates", "writs" }
local GROUPS = {
    held = { "handin", "crates", "writs", "unopened", "alts" },
    crates = { "market" },
    writs = { "receipt", "sealedwrits", "writmarket" },
}
local BUTTONS = { queue = "Queue", shop = "Shop", queued = "Queued", listed = "On List", go = "Waypoint", buy = "Shop", fill = "Fill" }

-- The bag slot of the smallest stack of the item that holds `need` of it: a crate takes its fill from one stack, and
-- by name the game picks the first stack, which may be too small. Nil when no single stack holds enough.
local function FillStack(itemID, need)
    local bag, slot, least
    for _, b in ipairs(FP.Inv:CarriedBags()) do
        for s = 1, C_Container.GetContainerNumSlots(b) do
            local info = C_Container.GetContainerItemInfo(b, s)
            if info and info.itemID == itemID and info.stackCount >= need and (not least or info.stackCount < least) then
                bag, slot, least = b, s, info.stackCount
            end
        end
    end
    return bag, slot
end

-- Puts the item's second largest stack onto its largest: a step toward one stack that fills a crate, when the bags
-- hold enough only between several stacks. The bags change and the row is drawn again, as Fill once a stack holds enough.
local function MergeStacks(itemID)
    local stacks = {}
    for _, b in ipairs(FP.Inv:CarriedBags()) do
        for s = 1, C_Container.GetContainerNumSlots(b) do
            local info = C_Container.GetContainerItemInfo(b, s)
            if info and info.itemID == itemID and not info.isLocked then stacks[#stacks + 1] = { bag = b, slot = s, count = info.stackCount } end
        end
    end
    if #stacks < 2 then return end -- still moving from the click before
    table.sort(stacks, function(a, b) return a.count > b.count end)
    ClearCursor()
    C_Container.PickupContainerItem(stacks[2].bag, stacks[2].slot)
    C_Container.PickupContainerItem(stacks[1].bag, stacks[1].slot)
end

local BOUGHT = { crate = true, writ = true, sealedWrit = true } -- the rows of the Buy views bought at the auction house

-- How many of a crate held several times over the row fills: [crate item ID] = number, all of them until picked.
-- Kept while the game runs.
local picked = {}

-- What the player chose to fill a crate with instead of its cheapest fill: [crate item ID] = item ID. For one fill:
-- the Fill button takes it back.
local fills = {}

local function Collapsed(group) return FP.db.orderCollapsed[group] end

function Panel:Open() FP.UI:ShowSidePanel(self) end
Panel.Toggle = FP.UI.ToggleSidePanel

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
-- What each group holds, by group key.
local function HeldGroups()
    local held = FP.Orders:Held(picked, fills)
    local g = { handin = {}, crates = {}, writs = {}, unopened = {}, alts = {} }
    for _, s in ipairs(held.sealed) do g.handin[#g.handin + 1] = { kind = "sealed", id = s.id, s = s } end
    if held.containers > 0 then
        g.handin[#g.handin + 1] = { kind = "container", id = FP.OrderItems.container, count = held.containers }
    end
    for _, e in ipairs(held.crates) do
        local list = e.count > 0 and g.crates or g.alts
        list[#list + 1] = e
    end
    for _, e in ipairs(held.writs) do
        local list = e.count > 0 and g.writs or g.alts
        list[#list + 1] = e
    end
    for _, u in ipairs(held.unopened) do g.unopened[#g.unopened + 1] = { kind = "unopened", id = u.id, count = u.count } end
    return g, held.standing, held.repHeld
end

local function BuyGroups(tab)
    local Orders = FP.Orders
    local standing = Orders:Standing()
    if tab == "crates" then return { market = Orders:CrateMarket() }, standing end
    local writs = Orders:WritMarket()
    local receipt = Orders:ReceiptMarket(Orders:CrateMarket(), writs, standing)
    return { receipt = { receipt }, sealedwrits = writs.sealed, writmarket = writs.writs }, standing
end

-- Flat list for the scroll area: a header per group with entries, then its entries unless collapsed.
local function BuildRows(groups, order)
    local rows = {}
    for _, key in ipairs(order) do
        local list = groups[key]
        if list and #list > 0 then
            rows[#rows + 1] = { kind = "group", group = key, count = #list }
            if not Collapsed(key) then
                for _, e in ipairs(list) do rows[#rows + 1] = e end
            end
        end
    end
    return rows
end

---------------------------------------------------------------------------
-- Waypoints
---------------------------------------------------------------------------
local function Go(name, uiMap, x, y)
    local W = FP.Waypoint
    if not W:CheckNav() then return end
    local map = C_Map.GetMapInfo(uiMap)
    local where = W.Where(name, map and map.name)
    W.Place(uiMap, x, y, where)
    FP:Print(L["Waypoint set: %s"]:format(where))
end

-- Where an entry is handed in: a writ's customer, else the camp. False when a writ's customer isn't known.
local function Waypoint(e)
    if e.kind == "writ" then
        local c = e.customer
        if not c then FP:Print(L["This writ's customer isn't known yet. Accept the writ and the game marks them on your map."]) return end
        return Go(c.name or L["Customer"], c.uiMap, c.x, c.y)
    end
    local camp = FP.Orders:Camp()[e.kind == "receipt" and "scribe" or "intake"]
    Go(camp[2], camp[3], camp[4], camp[5])
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function Money(copper) return FP.Prices:Format(copper) end

-- A cost per Favor or per reputation as the status column shows it; g: the Orders:Get result behind it, green when
-- all of it is in hand.
local function Rate(per, g, format)
    if not per then return L["No Price"], GREY end
    return L[format]:format(Money(per)), g and g.missing == 0 and g.alts == 0 and GREEN or WHITE
end

-- The other characters holding it: "Incinderella Pureflame Has 2".
local function HolderText(e)
    local h = e.holders[1]
    return L["%s Has %d"]:format(FP.Alts:Label(h), h.count)
end

-- What a row shows: detail (the middle column), status and its colour (the right one), action (a key of BUTTONS, or
-- nil for no button). buy: in a Buy view, where the cost counts the auction price too.
local function Describe(e, buy)
    local Orders, OT = FP.Orders, FP.OrderTips
    if e.kind == "crate" then
        local detail = OT.Amount(e.best)
        if buy then
            if not e.price then return detail, L["No Auction Price"], GREY end
            if not e.expected then return detail, Money(e.total or e.price), WHITE end
            return detail, Rate(e.perFavor, nil, "%s per Favor")
        end
        local action = Orders:FetchState(e.best)
        -- Nothing left to fetch and one crate's worth is in the bags: the button fills it.
        if not action and e.count > 0 and C_Item.GetItemCount(e.best.itemID) >= e.best.need / e.copies then action = "fill" end
        if e.count == 0 then return detail, HolderText(e), FP.UI.ALT_COLOR, action end
        local inHand = e.best.missing == 0 and e.best.alts == 0
        if not e.expected and e.cost then return detail, Money(e.cost), inHand and GREEN or WHITE, action end
        local text, c = Rate(e.perFavor, e.best, "%s per Favor")
        return detail, text, c, action
    elseif e.kind == "writ" then
        local detail = e.customer and OT.CustomerText(e.customer) or L[Orders.TIERS[e.tier]]
        -- Handed in today by this character: "Delivered (Resets in 5h)", in either view.
        local delivered = L["Delivered (Resets in %s)"]:format(FP.Cooldowns.Format(C_DateAndTime.GetSecondsUntilDailyReset()))
        if buy and e.done then return detail, delivered, GREY end
        if buy and not e.qtyKnown then return detail, L["Checking Quantity"], GREY end
        if buy then return detail, Rate(e.perRep, nil, "%s per Rep") end
        if e.count == 0 then return detail, HolderText(e), FP.UI.ALT_COLOR end
        if e.done then return detail, delivered, GREY end
        if not e.qtyKnown then return detail, L["Checking Quantity"], GREY end -- the game answers within a moment
        local action = Orders:FetchState(e.get) or (e.customer and "go")
        local text, c = Rate(e.perRep, e.get, "%s per Rep")
        return detail, text, c, action
    elseif e.kind == "sealed" then
        local s = e.s
        local pay = s.expected and L["%s Favor"]:format(OT.Num(s.expected * s.count)) or L["Favor Not Known Yet"]
        return L["Hand In at the Camp"], pay, s.expected and GREEN or GREY, "go"
    elseif e.kind == "container" then
        return L["Hand In at the Camp"], L["%d Reputation"]:format(Orders.RECEIPT_REP * e.count), GREEN, "go"
    elseif e.kind == "unopened" then
        return L["Open It to See What It Asks For"], "", GREY
    elseif e.kind == "sealedWrit" then
        local detail = L["%d of %d Orders Priced"]:format(e.priced, e.orders)
        if not e.price then return detail, L["No Auction Price"], GREY end
        return detail, Rate(e.perRep, nil, "%s per Rep")
    end
    -- The cheapest crate at auction, for a Forged Delivery Receipt.
    return L["With a Forged Delivery Receipt"], L["%s per Rep"]:format(Money(e.perRep)), WHITE, "go"
end

-- "5x " before the name when holding several: a long name is cut short at its end, so the count leads. A crate's
-- row has the number box and "of 5" for it instead.
local function Count(e)
    local n = e.kind ~= "crate" and (e.count or (e.s and e.s.count)) or 0
    return n > 1 and ("|cffffffff%dx|r "):format(n) or ""
end

-- The name as a row shows it: without what comes before the colon ("Waylaid Crate: ", "Craftsman's Writ: "), which
-- the group's heading and the icon already say. A name with no colon, in any language, is shown whole.
local function ShortName(itemID)
    local name = FP.ItemName(itemID)
    return name:match("^.-:%s*(.+)$") or name:match("^.-：%s*(.+)$") or name
end

-- What it pays, for the column before the cost: a crate's Favor for the copies being filled ("?" while not known),
-- a writ's reputation.
local function Pays(e)
    local Orders, OT = FP.Orders, FP.OrderTips
    if e.kind == "crate" then
        if not e.pay then return "?", GREY end
        return L["%s Favor"]:format(OT.Num(e.pay * e.copies)), WHITE
    elseif e.kind == "writ" or e.kind == "sealedWrit" then
        return L["%d Rep"]:format(e.rep), WHITE
    elseif e.kind == "receipt" then
        return L["%d Rep"]:format(Orders.RECEIPT_REP), WHITE
    end
    return "", WHITE
end

local HINT_LINK = { "Shift-click: Link", "Shift-click: link it in chat" }
local HINT_AH = { "Ctrl: Auction House", "Ctrl-click: search the auction house" }
local HINT_WAY = { "Right-click: Waypoint", "Right-click: set a waypoint to where it is handed in" }

-- On a held crate or writ: the sale it gives up, which its cost counts, and the cost with it.
local function AddSale(tip, e, per, format, missing)
    if e.sale then
        tip:AddDoubleLine(L["Sold Instead, After the Cut"], Money(e.sale), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
        if per then tip:AddDoubleLine(L["Kept and Handed In"], L[format]:format(Money(per)), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1) end
    elseif FP.Prices:Available() then
        tip:AddLine(L[missing], GREY[1], GREY[2], GREY[3], true)
    end
end

-- Why a marked crate is better handed in with a Forged Delivery Receipt, with the numbers behind it.
local function AddReceipt(tip, r)
    local Orders = FP.Orders
    local function Line(label, value) tip:AddDoubleLine(FP.Tooltips:Indent(1) .. label, value, 1, 1, 1, 1, 1, 1) end
    tip:AddLine(" ")
    tip:AddLine(("|T%s:0|t %s"):format(C_Item.GetItemIconByID(FP.OrderItems.receipt), FP.ItemName(FP.OrderItems.receipt)), BLUE[1], BLUE[2], BLUE[3])
    tip:AddLine(L["Reputation is cheaper from this crate with a receipt than from filling it. The crate is handed in empty."], 1, 1, 1, true)
    Line(L["Receipt Costs"], r.owned > 0 and L["%d in Your Bags"]:format(r.owned)
        or L["%d Favor (You Have %d)"]:format(Orders.RECEIPT_FAVOR, r.favor))
    Line(L["Pays"], L["%d Reputation"]:format(Orders.RECEIPT_REP))
    Line(L["A Favor Is Worth"], Money(r.perFavor))
    if r.sale then Line(L["Sold Instead, After the Cut"], Money(r.sale)) end
    Line(L["This Way"], L["%s per Reputation"]:format(Money(r.perRep)))
    Line(L["Your Cheapest Writ"], r.writ and L["%s per Reputation"]:format(Money(r.writ)) or L["None to Deliver"])
    tip:AddLine(L["A Favor is valued at what your cheapest crate costs to fill. %s at the camp sells the receipt."]
        :format(Orders:Camp().scribe[2]), GREY[1], GREY[2], GREY[3], true)
end

local function RowTooltip(row)
    local e = row.entry
    if not e or e.kind == "group" then return false end
    local tip, OT, Orders = GameTooltip, FP.OrderTips, FP.Orders
    tip:SetItemByID(e.id)
    tip:AddLine(" ")
    local hints = { HINT_LINK, HINT_AH }
    if e.kind == "crate" then
        OT.AddCrate(tip, e)
        if e.price then
            tip:AddDoubleLine(L["Crate at Auction"], Money(e.price), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
            if e.perFavor then
                tip:AddDoubleLine(L["Bought and Filled"], L["%s per Favor"]:format(Money(e.perFavor)), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
            end
        end
        if e.count then AddSale(tip, e, e.perFavor, "%s per Favor", "This crate has no auction price: only its fill is counted.") end
        if e.receipt then AddReceipt(tip, e.receipt) end
        hints[#hints + 1] = HINT_WAY
    elseif e.kind == "writ" then
        OT.AddWrit(tip, e)
        if e.price then tip:AddDoubleLine(L["Writ at Auction"], Money(e.price), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1) end
        if e.count then AddSale(tip, e, nil, nil, "This writ has no auction price: only its item is counted.") end
        if e.customer then hints[#hints + 1] = HINT_WAY end
    elseif e.kind == "sealed" then
        local s = e.s
        if s.pay then
            tip:AddDoubleLine(L["Hand-In Pays"], L["%s Favor"]:format(OT.Num(s.pay)) .. " " .. L["Each"], GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
        else
            tip:AddLine(L["Hand one in and ProfessionsForever will remember what it pays."], GREY[1], GREY[2], GREY[3], true)
        end
        hints[#hints + 1] = HINT_WAY
    elseif e.kind == "container" then
        hints[#hints + 1] = HINT_WAY
    elseif e.kind == "sealedWrit" then
        tip:AddLine(L["Opens into a random %s writ: %d reputation."]:format(L[Orders.TIERS[e.tier]], e.rep), 1, 1, 1, true)
        if e.average then
            tip:AddDoubleLine(L["Average Cost of Its Item"], Money(e.average), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
        end
        if e.price then tip:AddDoubleLine(L["Sealed Writ at Auction"], Money(e.price), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1) end
        tip:AddLine(L["An average over the %d of its %d orders whose item has a price. What you get is luck."]:format(e.priced, e.orders),
            GREY[1], GREY[2], GREY[3], true)
    elseif e.kind == "receipt" then
        tip:AddDoubleLine(L["Crate at Auction"], Money(e.crate.price), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1)
        tip:AddLine(L["The cheapest crate at auction, with a Forged Delivery Receipt (%d Favor from the Uncertified Scribe), is handed in empty for %d reputation: less per reputation than any writ with a price."]
            :format(Orders.RECEIPT_FAVOR, Orders.RECEIPT_REP), 1, 1, 1, true)
        hints[#hints + 1] = HINT_WAY
    end
    for _, h in ipairs(e.holders or {}) do
        tip:AddLine(L["%s has %d"]:format(FP.Alts:Label(h), h.count), FP.UI.ALT_COLOR[1], FP.UI.ALT_COLOR[2], FP.UI.ALT_COLOR[3])
    end
    for i, h in ipairs(hints) do hints[i] = { L[h[1]], L[h[2]] } end
    FP.UI:AddHints(tip, hints, false, BLUE)
end

local function RowClick(row, button)
    local e = row.entry
    if not e then return end
    if e.kind == "group" then
        FP.db.orderCollapsed[e.group] = not Collapsed(e.group) or nil
        return Panel:Update()
    end
    if button == "RightButton" then
        if e.kind ~= "unopened" and e.kind ~= "sealedWrit" then Waypoint(e) end
    elseif IsModifiedClick("CHATLINK") then
        FP.UI.LinkItemToChat(e.id)
    elseif IsControlKeyDown() then
        FP.Shop:SearchAuctionHouse(e.id)
    end
end

-- The row's button: queue or shop for what is missing, or a waypoint to where it is handed in.
local function ActionClick(b)
    local e, action = b:GetParent().entry, b.action
    if action == "go" then return Waypoint(e) end
    if action == "buy" then return FP.Shop:Add(e.id, 1) end
    FP.Orders:Fetch(e.kind == "writ" and e.get or e.best)
end

local ACTION_TIPS = {
    queue = "Queues the crafts that make what is missing, the crafts of their own reagents first.",
    shop = "Puts what you don't have in hand on the shopping list. What your other characters hold is asked for in the Transfer Planner.",
    queued = "The crafts that make it are in the crafting queue.",
    listed = "It is on the shopping list.",
    go = "Sets a waypoint to where it is handed in.",
    buy = "Puts one on the shopping list, to buy at the auction house.",
    stack = "Your bags hold enough for this crate, but not in one stack, and a crate is filled from one stack. Puts two stacks together; the button reads Fill once a stack holds enough.",
    fill = "Fills one crate with what the row names, from your bags. If the game still asks which item to use, your bags open: click it there.",
}

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function SummaryText(standing, repHeld)
    local Orders, parts = FP.Orders, {}
    local name = _G["FACTION_STANDING_LABEL" .. standing.reaction]
    parts[#parts + 1] = standing.need > 0 and ("%s %d / %d"):format(name, standing.have, standing.need) or name
    parts[#parts + 1] = L["Favor: %d"]:format(standing.favor)
    local bonus = Orders:BonusChance()
    if bonus > 0 then parts[#parts + 1] = L["Performance Bonus: %d%%"]:format(math.floor(bonus * 100 + 0.5)) end
    if repHeld and repHeld > 0 then parts[#parts + 1] = L["Writs Held: +%d Reputation"]:format(repHeld) end
    parts[#parts + 1] = FP.Prices:ScanText()
    return table.concat(parts, "    ")
end

function Panel:Update()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local db = FP.db
    local view = db.orderTab
    for _, key in ipairs(TABS) do FP.UI.SetSelected(f.tabs[key], view == key) end

    local groups, standing, repHeld
    if view == "held" then groups, standing, repHeld = HeldGroups() else groups, standing = BuyGroups(view) end
    f.summary:SetText(SummaryText(standing, repHeld))
    local list = BuildRows(groups, GROUPS[view])
    local empty = #list == 0
    f.empty:SetShown(empty)
    if empty then
        f.empty:SetText(view == "held" and L["None of your characters holds a Waylaid Crate or a Craftsman's Writ."]
            or not FP.Prices:Available() and L["Auction prices need Auctionator (Options, Integrations)."]
            or L["Nothing here has an auction price yet. Scan the auction house with Auctionator."])
    end

    local shown = FP.UI.PanelRows(f)
    FauxScrollFrame_Update(f.scroll, #list, shown, ROW_H)
    f.scroll.fpSetRange(math.max(0, #list - shown) * ROW_H)
    local offset = FauxScrollFrame_GetOffset(f.scroll)

    for i, row in ipairs(f.rows) do
        local e = i <= shown and list[offset + i] or nil
        row.entry = e
        row.action:Hide()
        if not InCombatLockdown() then f.fills[i]:Hide() end -- a secure button: it can't be touched in combat
        if not e then
            row:Hide()
        else
            local isGroup = e.kind == "group"
            row.bg:SetShown(isGroup)
            row.icon:SetShown(not isGroup)
            row.name:ClearAllPoints()
            row.detail:SetText("")
            row.mark:SetShown(e.receipt ~= nil)
            row.pay:SetText("")
            -- The number box, on a crate this character holds several of.
            local several = e.kind == "crate" and view == "held" and e.count > 1
            row.qty:SetShown(several)
            row.qty.minus:SetShown(several)
            row.qty.plus:SetShown(several)
            row.of:SetShown(several)
            row.pick:SetShown(e.kind == "crate" and view == "held" and #e.bundles > 1)
            if isGroup then
                row.name:SetPoint("LEFT", 8, 0)
                row.name:SetPoint("RIGHT", row.status, "LEFT", -4, 0)
                row.name:SetText((Collapsed(e.group) and "+ " or "- ") .. L[GROUP_NAMES[e.group]])
                row.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
                row.status:SetText(e.count)
                row.status:SetTextColor(0.8, 0.8, 0.8)
                row.status:SetPoint("RIGHT", -6, 0)
            else
                local detail, status, color, action = Describe(e, view ~= "held")
                -- In the Buy views the button puts the crate or writ itself on the shopping list.
                if view ~= "held" and BOUGHT[e.kind] then action = FP.Shop:Quantity(e.id) > 0 and "listed" or "buy" end
                row.icon:SetTexture(C_Item.GetItemIconByID(e.id))
                -- A Forged Delivery Receipt's icon before the name: this crate is better used with one.
                row.name:SetPoint("LEFT", e.receipt and row.mark or row.icon, "RIGHT", 4, 0)
                row.name:SetPoint("RIGHT", row.detail, "LEFT", -4, 0)
                if several then
                    if not row.qty:HasFocus() then row.qty:SetText(e.copies) end
                    row.of:SetText(L["of %d"]:format(e.count))
                end
                local pays, payColor = Pays(e)
                row.pay:SetText(pays)
                row.pay:SetTextColor(payColor[1], payColor[2], payColor[3])
                row.name:SetText(Count(e) .. ShortName(e.id))
                -- The item's own quality colour (a green crate pays double), greyed once a writ is delivered today.
                local q = ITEM_QUALITY_COLORS[C_Item.GetItemQualityByID(e.id) or 1]
                if e.kind == "writ" and e.done then
                    row.name:SetTextColor(0.55, 0.55, 0.55)
                else
                    row.name:SetTextColor(q.r, q.g, q.b)
                end
                row.detail:SetText(detail)
                -- A fill the player chose over the cheapest one is gold.
                local chose = e.kind == "crate" and e.best ~= e.bundles[1] and GOLD or GREY
                row.detail:SetTextColor(chose[1], chose[2], chose[3])
                row.status:SetText(status)
                row.status:SetTextColor(color[1], color[2], color[3])
                row.status:SetPoint("RIGHT", -192, 0) -- left of the number box and the button, there or not: the columns line up
                if action == "fill" and not InCombatLockdown() then
                    -- Uses the crate, then hands the game's item picker the fill.
                    local fill = f.fills[i]
                    local bag, slot = FillStack(e.best.itemID, e.best.need / e.copies)
                    -- Enough only between several stacks: the button puts them together instead, and uses nothing.
                    fill.crate = e.id
                    fill.merge = not slot and e.best.itemID or nil
                    fill.text:SetText(L[slot and "Fill" or "Stack"])
                    fill:SetAttribute("item", slot and "item:" .. e.id or nil)
                    fill:SetAttribute("target-bag", bag)
                    fill:SetAttribute("target-slot", slot)
                    fill.action = action
                    fill:Show()
                elseif action then
                    row.action.action = action
                    row.action.text:SetText(L[BUTTONS[action]])
                    row.action:SetActive(action ~= "queued" and action ~= "listed" and action ~= "fill") -- Fill in combat: off
                    row.action:Show()
                end
            end
            row:Show()
        end
    end
end

function Panel:Create()
    local UI, db = FP.UI, FP.db
    local f = UI:CreateSidePanel({ name = "ProfessionsForeverOrdersFrame", key = "orders", title = L["Crates and Writs"],
        width = 790, height = 480, onShow = function() Panel:Update() end })
    self.frame = f

    local labels = {
        held = { L["Held"], L["The crates and writs your characters hold, with the cheapest way to fill each."] },
        crates = { L["Buy Crates"], L["What buying a crate at the auction house and filling it would cost you per Merchant's Favor. Needs Auctionator's prices."] },
        writs = { L["Buy Writs"], L["What buying a writ at the auction house and getting its item would cost you per reputation. Needs Auctionator's prices."] },
    }
    f.tabs = {}
    for i, key in ipairs(TABS) do
        local b = UI:Button(f, labels[key][1], 110, 22, function()
            db.orderTab = key
            f.scroll.fpScrollTo(0)
            Panel:Update()
        end)
        UI:Tooltip(b, "ANCHOR_RIGHT", labels[key][2])
        if i == 1 then b:SetPoint("TOPLEFT", 12, -34) else b:SetPoint("LEFT", f.tabs[TABS[i - 1]], "RIGHT", 6, 0) end
        f.tabs[key] = b
    end

    f.summary = UI:Text(f, 0)
    f.summary:SetPoint("TOPLEFT", 14, -64)
    f.summary:SetPoint("RIGHT", -14, 0)
    f.summary:SetWordWrap(false)
    f.summary:SetTextColor(0.8, 0.8, 0.8)

    UI:AddPanelList(f, { name = "ProfessionsForeverOrdersScroll", top = LIST_TOP, bottom = 14, rows = ROWS, rowH = ROW_H,
        update = function() Panel:Update() end, rowBg = true, tooltip = RowTooltip, onClick = RowClick, rightClick = true,
        build = function(row)
            row.orderRow, row.ownHints = true, true -- Tooltips/Orders.lua leaves its lines to RowTooltip
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ROW_H - 4, ROW_H - 4)
            row.icon:SetPoint("LEFT", 14, 0)
            UI.TrimIcon(row.icon)
            row.mark = row:CreateTexture(nil, "ARTWORK")
            row.mark:SetSize(ROW_H - 8, ROW_H - 8)
            row.mark:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            UI.TrimIcon(row.mark)
            row.mark:SetTexture(C_Item.GetItemIconByID(FP.OrderItems.receipt))
            row.action = UI:Button(row, "", 66, ROW_H - 2, ActionClick)
            row.action:SetPoint("RIGHT", -2, 0)
            UI:Tooltip(row.action, "ANCHOR_RIGHT", function(tip, b) tip:AddLine(L[ACTION_TIPS[b.action]], 1, 1, 1, true) end)
            row.status = UI:Text(row, 0, "RIGHT")
            row.status:SetPoint("RIGHT", -6, 0)
            row.status:SetWidth(126)
            row.status:SetWordWrap(false)
            row.pay = UI:Text(row, 0, "RIGHT")
            row.pay:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
            row.pay:SetWidth(66)
            row.pay:SetWordWrap(false)
            row.detail = UI:Text(row, -1, "RIGHT")
            row.detail:SetPoint("RIGHT", row.pay, "LEFT", -6, 0)
            row.detail:SetWidth(170)
            row.detail:SetWordWrap(false)
            row.detail:SetTextColor(GREY[1], GREY[2], GREY[3])
            -- Over a crate's fill: a click lists the crate's fills to choose from, cheapest first.
            -- A box around it shows it opens a list; brighter under the mouse.
            row.pick = CreateFrame("Button", nil, row, "BackdropTemplate")
            row.pick:SetPoint("TOPLEFT", row.detail, "TOPLEFT", -4, 3)
            row.pick:SetPoint("BOTTOMRIGHT", row.detail, "BOTTOMRIGHT", 3, -3)
            row.pick:SetBackdrop({ edgeFile = UI.WHITE, edgeSize = 1 })
            row.pick:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            row.pick:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(0.8, 0.8, 0.8, 1) end)
            row.pick:SetScript("OnLeave", function(s) s:SetBackdropBorderColor(0.4, 0.4, 0.4, 1) end)
            row.pick:SetScript("OnClick", function(s)
                local e, OT, items = row.entry, FP.OrderTips, {}
                for i, g in ipairs(e.bundles) do
                    items[i] = { text = ("%s: %s"):format(OT.Amount(g), (OT.Describe(g))), checked = g == e.best, onSelect = function()
                        fills[e.id] = i > 1 and g.itemID or nil
                        Panel:Update()
                    end }
                end
                UI:OpenMenu(s, items, 340)
            end)
            UI:Tooltip(row.pick, "ANCHOR_RIGHT", L["Click to choose what to fill this crate with, for one fill. The cheapest is first."])
            -- How many of a crate held several times over to fill, beside the button that acts on it: "- [3] + of 5".
            row.of = UI:Text(row, -1)
            row.of:SetPoint("RIGHT", row.action, "LEFT", -6, 0)
            row.of:SetWidth(30)
            row.of:SetTextColor(GREY[1], GREY[2], GREY[3])
            local function Pick(v)
                local e = row.entry
                picked[e.id] = math.max(1, math.min(e.count, v))
                Panel:Update()
            end
            row.qty = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            row.qty:SetSize(30, 20)
            row.qty:SetPoint("RIGHT", row.of, "LEFT", -25, 0)
            UI:EUIWidget(row.qty, "numbox")
            row.qty:SetAutoFocus(false)
            row.qty:SetNumeric(true)
            row.qty:SetMaxLetters(3)
            row.qty:SetScript("OnTextChanged", function(s, user) if user then Pick(tonumber(s:GetText()) or 1) end end)
            row.qty:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
            row.qty:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
            row.qty:SetScript("OnEditFocusLost", function() Panel:Update() end)
            UI:Stepper(row.qty, 1, 999, Pick)
            row.name = UI:Text(row, 0)
            row.name:SetWordWrap(false)
        end })

    -- The Fill buttons, one over each row's button. They use an item, so they are secure buttons; as children of the
    -- window and anchored to it, not to the rows, they leave the rows free to change in combat.
    f.fills = {}
    for i, row in ipairs(f.rows) do
        local b
        b = UI:Button(f, L["Fill"], 66, ROW_H - 2, function()
            if b.merge then return MergeStacks(b.merge) end
            fills[b.crate] = nil -- a chosen fill is for this one fill
            -- One crate filled: the number box counts down, so the next click fills the rest.
            if picked[b.crate] then picked[b.crate] = math.max(1, picked[b.crate] - 1) end
            if SpellIsTargeting() then OpenAllBags() end -- the game still asks which item: it is picked in the bags
        end, true)
        b:SetAttribute("type", "item")
        b:SetPoint("RIGHT", f, "TOPRIGHT", -UI.BAR_GUTTER - 2, -LIST_TOP - (i - 1) * ROW_H - ROW_H / 2)
        b:SetFrameLevel(row:GetFrameLevel() + 2)
        UI:Tooltip(b, "ANCHOR_RIGHT", function(tip) tip:AddLine(L[ACTION_TIPS[b.merge and "stack" or "fill"]], 1, 1, 1, true) end)
        b:Hide()
        f.fills[i] = b
    end
    FP:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        for _, b in ipairs(f.fills) do b:Hide() end
        Panel:Update()
    end)
    FP:RegisterEvent("PLAYER_REGEN_ENABLED", function() Panel:Update() end)

    f.empty = UI:Text(f, 0, "CENTER")
    f.empty:SetPoint("TOPLEFT", 30, -LIST_TOP - 40)
    f.empty:SetPoint("RIGHT", -30, 0)
    f.empty:SetTextColor(GREY[1], GREY[2], GREY[3])
end
