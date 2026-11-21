local _, FP = ...
local L = FP.L
local Tips = FP.Tooltips

-- On a Waylaid Crate's item tooltip: what handing it in pays, and each bundle that fills it with what it would cost
-- you, the cheapest first. On a Craftsman's Writ's: its reputation, what getting its item costs you, and the customer.
-- The Crates and Writs window's rows show the same lines (Panels/Orders.lua), whatever the option says.
local OT = {}
FP.OrderTips = OT

local GREEN, WHITE, GREY, RED, LABEL = { 0.2, 0.9, 0.2 }, { 1, 1, 1 }, { 0.6, 0.6, 0.6 }, { 0.9, 0.2, 0.2 }, { 1, 0.82, 0 }

-- A number without a trailing ".0": 11.5 Favor, 10 Favor.
local function Num(n) return (("%.1f"):format(n):gsub("%.0$", "")) end
OT.Num = Num

-- What an Orders:Get result is worth and how it is come by, and its colour: "3s 20c (In Hand)", or
-- "3s 20c (Alts Send 12, Buy 8)". The price is for the whole amount, in hand or not.
function OT.Describe(g)
    local parts, color = {}, WHITE
    if g.missing == 0 and g.alts == 0 then parts[1], color = L["In Hand"], GREEN end
    if g.alts > 0 then parts[#parts + 1] = L["Alts Send %d"]:format(g.alts) end
    if g.missing > 0 then parts[#parts + 1] = L[g.via == "craft" and "Craft %d" or "Buy %d"]:format(g.missing) end
    if g.alts > 0 and g.missing == 0 then color = FP.UI.ALT_COLOR end
    local how = " (" .. table.concat(parts, ", ") .. ")"
    if not g.cost then return L["No Price"] .. how, g.missing > 0 and GREY or color end
    -- An auction price Auctionator last saw too long ago: "(3 Days Old)".
    local old = g.source == "auction" and FP.Prices:AgeNote(g.itemID) or ""
    return FP.Prices:Format(g.cost) .. old .. how, color
end

-- "20 Copper Bar"
local function Amount(g) return ("%d %s"):format(g.need, FP.ItemName(g.itemID)) end
OT.Amount = Amount

-- e: an Orders:Crate entry.
function OT.AddCrate(tip, e)
    local one = Tips:Indent(1)
    if e.pay then
        local pay = L["%s Favor"]:format(Num(e.pay))
        if e.expected ~= e.pay then pay = L["%s (%s With Performance Bonus)"]:format(pay, Num(e.expected)) end
        tip:AddDoubleLine(L["Hand-In Pays"], pay, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
    else
        tip:AddDoubleLine(L["Hand-In Pays"], L["Not Known Yet"], LABEL[1], LABEL[2], LABEL[3], GREY[1], GREY[2], GREY[3])
    end
    if e.copies > 1 and e.pay then
        local pay = L["%s Favor"]:format(Num(e.pay * e.copies))
        if e.expected ~= e.pay then pay = L["%s (%s With Performance Bonus)"]:format(pay, Num(e.expected * e.copies)) end
        tip:AddDoubleLine(L["%d Crates Pay"]:format(e.copies), pay, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
    end
    tip:AddLine(L[e.copies > 1 and "Fill Them With Any One Of:" or "Fill It With Any One Of:"], LABEL[1], LABEL[2], LABEL[3])
    for _, g in ipairs(e.bundles) do
        local text, c = OT.Describe(g)
        local n = g == e.best and WHITE or GREY
        tip:AddDoubleLine(one .. Amount(g), text, n[1], n[2], n[3], c[1], c[2], c[3])
    end
    if e.fillPerFavor and e.fillPerFavor > 0 then
        tip:AddDoubleLine(L["Cheapest Fill"], L["%s per Favor"]:format(FP.Prices:Format(e.fillPerFavor)), LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
    end
    if not e.pay then
        tip:AddLine(L["Hand one in and ProfessionsForever will remember what it pays."], GREY[1], GREY[2], GREY[3], true)
    end
end

-- "Kixxle, Wetlands"; just the zone when the customer has no name on record.
function OT.CustomerText(customer)
    local map = C_Map.GetMapInfo(customer.uiMap)
    local zone = map and map.name
    if customer.name and zone then return ("%s, %s"):format(customer.name, zone) end
    return customer.name or zone
end

-- e: an Orders:Writ entry.
function OT.AddWrit(tip, e)
    tip:AddDoubleLine(L["Delivery Pays"], L["%d Reputation"]:format(e.rep), LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
    local text, c = OT.Describe(e.get)
    tip:AddDoubleLine(Amount(e.get), text, 1, 1, 1, c[1], c[2], c[3])
    if not e.qtyKnown then
        tip:AddLine(L["Quantity not confirmed yet: the cost is for one."], GREY[1], GREY[2], GREY[3], true)
    end
    if e.perRep and e.perRep > 0 then
        tip:AddDoubleLine(L["Cost"], L["%s per Reputation"]:format(FP.Prices:Format(e.perRep)), LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
    end
    if #e.crafters > 0 then
        local names = {}
        for _, key in ipairs(e.crafters) do names[#names + 1] = FP.Alts:Label(FP.db.characters[key]) end
        tip:AddLine(L["Can craft it: %s"]:format(table.concat(names, ", ")), 1, 1, 1, true)
    end
    if e.customer then
        tip:AddDoubleLine(L["Customer"], OT.CustomerText(e.customer), LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
    else
        tip:AddDoubleLine(L["Customer"], L["Not Known Yet"], LABEL[1], LABEL[2], LABEL[3], GREY[1], GREY[2], GREY[3])
    end
    if e.done then
        local left = FP.Cooldowns.Format(C_DateAndTime.GetSecondsUntilDailyReset())
        tip:AddLine(L["Delivered today. It can be delivered again in %s."]:format(left), RED[1], RED[2], RED[3], true)
    end
end

local function Add(tip, _, itemID)
    if Tips.preview or not FP.db.orderTooltip then return end
    local owner = tip:GetOwner()
    if owner and owner.orderRow then return end -- the window's rows add these lines themselves, among their own
    if FP.Crates[itemID] then
        Tips:Space(tip)
        OT.AddCrate(tip, FP.Orders:Crate(itemID))
        return true
    elseif FP.Writs[itemID] then
        Tips:Space(tip)
        OT.AddWrit(tip, FP.Orders:Writ(itemID))
        return true
    end
end

Tips:Register("orders", Add)
