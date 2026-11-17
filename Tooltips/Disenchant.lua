local _, FP = ...
local L = FP.L

-- Disenchant results on item tooltips: one line naming the three choices (disenchant, vendor, auction) with the best
-- one lit, and what it earns, or the likeliest result when there are no prices; with more detail,
-- each choice's value and every disenchant result with its chance and value. Options, Tooltips decides when it shows and how much.
--
-- Every character can disenchant at skill 1, so nothing here checks Enchanting skill; the "Requires Enchanting"
-- option only asks whether someone on the account can do the disenchanting.

local DE, P = FP.Disenchant, FP.Prices
local ENCHANTING = FP.ENCHANTING
local LABEL = { 1, 0.82, 0 }
local DETAIL = { 0.6, 0.6, 0.6 }
-- The three ways to get rid of an item, in the order the verdict line lists them, each with its colour.
local CHOICE_ORDER = { "disenchant", "vendor", "auction" }
local CHOICES = {
    disenchant = { label = "Disenchant", color = { 0.75, 0.45, 1 } },
    vendor = { label = "Vendor", color = { 1, 0.82, 0 } },
    auction = { label = "Auction", color = { 0.3, 0.8, 1 } },
}

local Hex = FP.UI.Hex

-- "Disenchant / Vendor / Auction" with the best one in its colour and the others grey, so the line says both what
-- is being weighed and which wins.
local function VerdictText(best)
    local parts = {}
    for _, key in ipairs(CHOICE_ORDER) do
        parts[#parts + 1] = Hex(key == best and CHOICES[key].color or DETAIL) .. L[CHOICES[key].label] .. "|r"
    end
    return table.concat(parts, Hex(DETAIL) .. " / |r")
end

local function Money(c) return P:Format(c) end

local function KnowsEnchanting(scope)
    if scope == "none" then return true end
    for _, p in ipairs(FP:GetProfessions()) do
        if p.skillLine == ENCHANTING then return true end
    end
    if scope == "self" then return false end
    for _, rec in pairs(FP.db.characters) do
        if rec.professions and rec.professions[ENCHANTING] then return true end
    end
    return false
end

-- Auctionator adds its own disenchant value line when its "Disenchant prices" tooltip setting is on.
local function AuctionatorShowsDE()
    local A = _G.Auctionator
    return A and A.Config and A.Config.Get(A.Config.Options.ENCHANT_TOOLTIPS) and true or false
end

-- "[icon] Strange Dust x1-2", the name in its quality colour.
local function ResultText(r)
    local name, _, quality = C_Item.GetItemInfo(r.itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(r.itemID)
        name = RETRIEVING_ITEM_INFO
    end
    local c = ITEM_QUALITY_COLORS[quality or 1]
    local amount = r.min == r.max and ("x" .. r.min) or ("x%d-%d"):format(r.min, r.max)
    return ("|T%d:0|t %s%s|r %s"):format(C_Item.GetItemIconByID(r.itemID), c and c.hex or "|cffffffff", name, amount)
end

local function Likeliest(results)
    local best = results[1]
    for _, r in ipairs(results) do
        if r.chance > best.chance then best = r end
    end
    return best
end

-- Soulbound, or bound when picked up or a quest item: such items can't be sold at auction.
local BOUND_LINES = {}
local function Bound(data)
    if not next(BOUND_LINES) then
        for _, text in ipairs({ ITEM_SOULBOUND, ITEM_BIND_ON_PICKUP, ITEM_BIND_QUEST }) do BOUND_LINES[text] = true end
    end
    for _, line in ipairs(data.lines or {}) do
        local text = line.leftText
        if not (issecretvalue(text)) and text and BOUND_LINES[text] then return true end
    end
    return false
end

-- One way to get rid of the item, value after the auction house cut, bright when it is the best one. `extra`: text
-- after the label (the realized value on the Disenchant line).
local function Choice(tip, key, value, best, note, indent, extra)
    local c = key == best and CHOICES[key].color or DETAIL
    tip:AddDoubleLine(indent .. L[CHOICES[key].label] .. (extra or ""), value and Money(value) or note, c[1], c[2], c[3], c[1], c[2], c[3])
end

-- "  (seen 1s 25c)": what your disenchants of this table were really worth at today's prices, times `factor` (1, or
-- after the auction cut), grey while unreliable; "" with Show Seen Rates off or nothing recorded.
local function SeenValue(tableID, factor)
    if not FP.db.deShowObserved then return "" end
    local value, enough = DE:ObservedValue(tableID)
    if not value then return "" end
    return (enough and "  |cffebebeb" or "  |cff8c8c8c") .. L["(seen %s)"]:format(Money(value * factor)) .. "|r"
end

-- Each chance is right-aligned in a column as wide as "100%", so the result icons line up. Tooltip fonts are
-- proportional, so the gap is an invisible texture as wide as the difference, measured in the tooltip's own font.
local BLANK = "Interface\\AddOns\\ProfessionsForever\\Media\\blank"
local measure = UIParent:CreateFontString(nil, "BACKGROUND")
measure:Hide()

local function Chance(tip, chance)
    measure:SetFont(_G[tip:GetName() .. "TextLeft2"]:GetFont())
    measure:SetText("100%")
    local full = measure:GetStringWidth()
    local text = ("%g%%"):format(chance * 100)
    measure:SetText(text)
    local pad = full - measure:GetStringWidth()
    if pad < 1 then return text end
    return ("|T%s:1:%d|t%s"):format(BLANK, math.floor(pad + 0.5), text)
end

-- Each result with its chance and value; with Show Seen Rates on, your own share after it ("(seen 75%)",
-- grey while too few disenchants back it) and, under the results, how many disenchants that is and what else you've
-- had from this table.
local function Results(tip, results, indent, tableID)
    local observed = FP.db.deShowObserved
    for _, r in ipairs(results) do
        local unit = P:Unit(r.itemID)
        local left = ("%s%s  %s"):format(indent, Chance(tip, r.chance), ResultText(r))
        local seen, enough = observed and DE:ObservedChance(tableID, r.itemID)
        if seen then
            local amount = DE:ObservedAmount(tableID, r.itemID)
            seen = amount and L["%s, %s each"]:format(seen, amount) or seen
            left = left .. (enough and "  |cffebebeb" or "  |cff8c8c8c") .. L["(seen %s)"]:format(seen) .. "|r"
        end
        tip:AddDoubleLine(left, unit and Money(r.chance * (r.min + r.max) / 2 * unit) or "",
            DETAIL[1], DETAIL[2], DETAIL[3], unpack(DETAIL))
    end
    if not observed then return end
    local note, also = DE:ObservedNote(tableID, results)
    tip:AddLine(indent .. note, 0.55, 0.55, 0.55, true)
    if also then tip:AddLine(indent .. also, 0.55, 0.55, 0.55, true) end
end

local function Add(tip, data, itemID)
    local db = FP.db
    if not db.deTooltip then return end
    local Tips = FP.Tooltips
    -- "shift" in these settings means the detail key (Options, Tooltips, General), Shift unless changed there.
    local shift = Tips:DetailDown()
    if db.deTooltipShow == "shift" and not shift then return end
    if db.deTooltipAuctionator and AuctionatorShowsDE() then return end

    local _, _, quality, level, _, _, _, _, _, _, sellPrice, classID = C_Item.GetItemInfo(itemID)
    if not quality then return end
    local tableID = DE:TableFor(itemID, classID, quality, level)
    if not tableID or not KnowsEnchanting(db.deTooltipNeeds) then return end
    -- Soulbound gear can't be mailed to an enchanter, so only this character could disenchant it.
    local bound = Bound(data)
    if bound and db.deTooltipBoundSelf and not KnowsEnchanting("self") then return end

    local results = DE:Results(tableID)
    -- The hovered item's own link, as the game's tooltip code finds it.
    local link = data.guid and C_Item.GetItemLinkByGUID(data.guid) or data.hyperlink
    local v = DE:Values(tableID, sellPrice or 0, itemID, bound, link)
    local priced = v.unpriced ~= nil and v.unpriced < #results
    local verdict = priced and db.deTooltipVerdict
    local full = db.deTooltipDetail == "full" or (db.deTooltipDetail == "shift" and shift)
    local one, two = Tips:Indent(1), Tips:Indent(2)

    if verdict then
        -- The decision first: "Disenchant / Vendor / Auction   12s", the winner lit, its value in its colour.
        local c = CHOICES[v.best].color
        tip:AddDoubleLine(VerdictText(v.best), Money(v.bestValue), 1, 1, 1, c[1], c[2], c[3])
        if full then
            Choice(tip, "disenchant", v.disenchant, v.best, nil, one, SeenValue(tableID, 1 - P.CUT))
            Results(tip, results, two, tableID)
            if v.unpriced > 0 then tip:AddLine(two .. L["%d results without a price"]:format(v.unpriced), unpack(DETAIL)) end
            Choice(tip, "vendor", v.vendor > 0 and v.vendor or nil, v.best, L["No vendor price"], one)
            Choice(tip, "auction", v.auction, v.best, bound and L["Soulbound, can't be sold"]
                or L["No auction price"], one)
        end
    elseif priced then
        tip:AddDoubleLine(L["Disenchant"] .. (full and SeenValue(tableID, 1) or ""), Money(v.deGross), LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
        if full then
            Results(tip, results, one, tableID)
            if v.unpriced > 0 then tip:AddLine(one .. L["%d results without a price"]:format(v.unpriced), unpack(DETAIL)) end
        end
    elseif full then
        tip:AddLine(L["Disenchant"], unpack(LABEL))
        Results(tip, results, one, tableID)
    else
        tip:AddDoubleLine(L["Disenchant"], ResultText(Likeliest(results)), LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
    end
    -- Every result waits for the detail key.
    return true, db.deTooltipDetail == "shift" and not full
end

FP.Tooltips:Register("disenchant", Add)

-- Load every result's name and quality at login, so the first tooltip doesn't show "Retrieving item information".
FP:RegisterEvent("PLAYER_LOGIN", function()
    for tableID in pairs(FP.DisenchantTables) do
        for _, r in ipairs(DE:Results(tableID)) do C_Item.RequestLoadItemDataByID(r.itemID) end
    end
end)
