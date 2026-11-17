local _, FP = ...
local L = FP.L
local UI = FP.UI
local O = FP.Options
local refreshers = O.refreshers
local Tips = FP.Tooltips

-- The Tooltips category's pages: what ProfessionsForever adds to item tooltips and to its own windows' item tooltips.
-- Every change redraws the previewer docked beside the window (Tooltips/Preview.lua), through O:Refresh.

-- A choice's label: a locale key, or a function for labels that name the detail key.
local function LabelOf(labels, value)
    local label = labels[value]
    return type(label) == "function" and label() or L[label]
end

local function Choices(key, order, labels)
    return function()
        local db = FP.db
        local items = {}
        for _, value in ipairs(order) do
            items[#items + 1] = { text = LabelOf(labels, value), checked = db[key] == value, onSelect = function()
                db[key] = value
                O:Refresh()
            end }
        end
        return items
    end
end

local function Tip(w, text) UI:Tooltip(w, "ANCHOR_RIGHT", function(t) t:AddLine(text, 1, 1, 1, true) end) end

-- A checkbox for one saved setting; any change redraws the previewer.
local function Check(page, label, key, text)
    local cb = O.Check(page, label, function() return FP.db[key] end, function(v)
        FP.db[key] = v
        O:Refresh()
    end)
    Tip(cb, text)
    return cb
end

-- A drop list for one saved setting.
local function Drop(page, label, key, order, labels, text)
    local dd = O.DropList(page, label, function() return LabelOf(labels, FP.db[key]) end, Choices(key, order, labels))
    Tip(dd, text)
    return dd
end

-- Greys out the controls that only matter while their feature's switch is on.
local function Follow(active, drops, checks)
    active = active and true or false
    for _, drop in ipairs(drops) do drop:SetActive(active) end
    for _, check in ipairs(checks) do
        check:SetEnabled(active)
        check.label:SetAlpha(active and 1 or 0.4)
    end
end

local function WithKey(format) return function() return L[format]:format(Tips:KeyName()) end end

---------------------------------------------------------------------------
-- General
---------------------------------------------------------------------------
local KEY_LABELS = { shift = "Shift", ctrl = "Ctrl", alt = "Alt" }
local BLOCK_LABELS = { queue = "Crafting Queues", disenchant = "Disenchant Results", alts = "Alts and Transfers" }
local ORDER_ROW, ORDER_W = 24, 260

-- The blocks' order, top to bottom: drag a row up or down. A line shows where it will land.
local function OrderList(page)
    local box = CreateFrame("Frame", nil, page)
    box:SetPoint("TOPLEFT", 8, page.y)
    local count = #Tips:Order()
    box:SetSize(ORDER_W, ORDER_ROW * count)
    local mark = box:CreateTexture(nil, "OVERLAY")
    mark:SetHeight(2)
    mark:SetWidth(ORDER_W)
    mark:Hide()
    local rows, dragging = {}, nil

    -- The gap the cursor is nearest: 0 above the first row, count below the last.
    local function Gap()
        local _, y = GetCursorPosition()
        y = y / box:GetEffectiveScale()
        local gap = math.floor((box:GetTop() - y) / ORDER_ROW + 0.5)
        return math.max(0, math.min(count, gap))
    end

    local function Track()
        mark:ClearAllPoints()
        mark:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -Gap() * ORDER_ROW + 1)
    end

    local function Sync()
        for i, key in ipairs(Tips:Order()) do
            rows[i].key = key
            rows[i].text:SetText(("%d.  %s"):format(i, L[BLOCK_LABELS[key]]))
        end
    end

    local function Release()
        if not dragging then return end
        local from, gap = dragging.index, Gap()
        dragging:SetAlpha(1)
        dragging = nil
        mark:Hide()
        box:SetScript("OnUpdate", nil)
        local order = Tips:Order()
        local key = table.remove(order, from)
        if gap >= from then gap = gap - 1 end
        table.insert(order, gap + 1, key)
        Tips:SetOrder(order)
        O:Refresh()
    end

    for i = 1, count do
        local r = CreateFrame("Button", nil, box, "BackdropTemplate")
        r.index = i
        r:SetSize(ORDER_W, ORDER_ROW - 2)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ORDER_ROW)
        UI:Skin(r, "button")
        local grip = UI:Text(r, 0)
        grip:SetPoint("LEFT", 8, 0)
        grip:SetText("::")
        grip:SetTextColor(0.6, 0.6, 0.6)
        r.text = UI:Text(r, 0)
        r.text:SetPoint("LEFT", 26, 0)
        r:RegisterForDrag("LeftButton")
        r:SetScript("OnDragStart", function(s)
            dragging = s
            s:SetAlpha(0.5)
            local accent = UI:GetAccent()
            mark:SetColorTexture(accent[1], accent[2], accent[3])
            mark:Show()
            box:SetScript("OnUpdate", Track)
        end)
        r:SetScript("OnDragStop", Release)
        Tip(r, L["Drag up or down to move this block."])
        rows[i] = r
    end
    refreshers[#refreshers + 1] = Sync
    Sync()
    page.y = page.y - ORDER_ROW * count - 8
end

function O.BuildTipGeneral(page)
    O.Section(page, L["General"])
    Drop(page, L["Detail Key"], "tipDetailKey", Tips.KEY_ORDER, KEY_LABELS,
        L["Hold it over an item for the detail: each character's queued recipes, and every disenchant result."])
    Check(page, L["Show the Detail Key Hint"], "tipKeyHint",
        L["A grey \"Hold Shift for details\" line while there is detail to show; in the addon's windows it joins the click hints."])
    Check(page, L["Blank Line Before Each Block"], "tipSpacing",
        L["Space between the addon's blocks and the rest of the tooltip. Off: tighter tooltips."])
    O.Slider(page, "ProfessionsForeverTipIndent", L["Indent"], 0, 8, 1, function() return FP.db.tipIndent end, function(v)
        FP.db.tipIndent = v
        O:Refresh()
    end, "%d")

    O.Section(page, L["Block Order"])
    OrderList(page)
end

function O.ResetTipGeneral()
    O.ResetKeys("tipDetailKey", "tipKeyHint", "tipSpacing", "tipIndent", "tipOrder")
end

---------------------------------------------------------------------------
-- Crafting Queues
---------------------------------------------------------------------------
local RECIPES = { "shift", "always", "never" }
-- "shift" is the detail key, Shift unless changed under General.
local RECIPES_LABELS = { shift = WithKey("While Holding %s"), always = "Always", never = "Never" }

function O.BuildQueueTooltips(page)
    local db = FP.db
    O.Section(page, L["Crafting Queues"])
    Check(page, L["Show Queue Needs on Item Tooltips"], "queueTooltip",
        L["Items your crafting queues need say how many on their tooltip, in your bags, bank, loot window and chat links: the same number as the shopping list. With a faction-wide shopping list, your other characters' queues count too."])
    local toBuy = Check(page, L["Show Still to Buy"], "queueTooltipToBuy",
        L["Under it, how many you still have to buy while you're short, the shopping list's Buy column."])
    local recipes = Drop(page, L["Show the Recipes"], "queueTooltipRecipes", RECIPES, RECIPES_LABELS,
        L["Each character whose queue uses the item, with how many, and under each one the queued recipes and how many each takes."])
    local group = Check(page, L["Group by Character"], "queueTooltipGroup",
        L["A line per character with their total, their recipes under it. Off: one list, your alts' recipes with their name after."])
    local crafts = Check(page, L["Show Craft Counts"], "queueTooltipCrafts",
        L["\"x40\" after each recipe: how many crafts are queued."])
    local shopRows = Check(page, L["Show the Recipes on Shopping List Rows"], "queueTooltipShopRows",
        L["The shopping list's rows have their own Needed by Crafting Queues line; this adds the recipes under it too."])

    refreshers[#refreshers + 1] = function()
        local recipesShown = db.queueTooltipRecipes ~= "never"
        Follow(db.queueTooltip, { recipes }, { toBuy })
        Follow(recipesShown, {}, { group, crafts, shopRows })
    end
    refreshers[#refreshers]()
end

function O.ResetQueueTooltips()
    O.ResetKeys("queueTooltip", "queueTooltipToBuy", "queueTooltipRecipes", "queueTooltipGroup", "queueTooltipCrafts",
        "queueTooltipShopRows")
end

---------------------------------------------------------------------------
-- Alts and Transfers
---------------------------------------------------------------------------
local TOTAL = { "never", "multi", "always" }
local TOTAL_LABELS = { never = "Never", multi = "With Two or More Characters", always = "Always" }

function O.BuildTipAlts(page)
    local db = FP.db
    O.Section(page, L["Alts and Transfers"])
    local intro = O.Label(page, L["Shopping list rows, Transfer Planner rows and the alt badge."])
    intro:SetTextColor(0.7, 0.7, 0.7)
    page.y = page.y - O.ROW_H
    Check(page, L["Show Each Character"], "altTipChars",
        L["A line per other character holding it: \"Has 66 (26 bank), Send 42\"."])
    local bank = Check(page, L["Show How Many Are in the Bank"], "altTipBank", L["\"(26 bank)\" after what they have."])
    local send = Check(page, L["Show What to Send"], "altTipSend",
        L["\"Send 42\": what the plan takes from them. \"Could Send\" while your alts don't count toward planning."])
    Drop(page, L["Total on Your Alts"], "altTipTotal", TOTAL, TOTAL_LABELS,
        L["Available on Enabled Characters: everything your alts hold. With one character it's the same as their line."])
    Check(page, L["Show Still to Buy"], "altTipToBuy",
        L["What you still have to buy after what your alts can send: the shopping list's Buy column."])
    Check(page, L["Show Ignored Characters"], "altTipIgnored",
        L["Characters left out of planning (Options, General, Alt Inventory) who hold it, greyed."])

    refreshers[#refreshers + 1] = function() Follow(db.altTipChars, {}, { bank, send }) end
    refreshers[#refreshers]()
end

function O.ResetTipAlts()
    O.ResetKeys("altTipChars", "altTipBank", "altTipSend", "altTipTotal", "altTipToBuy", "altTipIgnored")
end

---------------------------------------------------------------------------
-- Prices and Hints
---------------------------------------------------------------------------
local PRICE = { "auto", "always", "never" }
local PRICE_LABELS = { auto = "Unless Auctionator Shows One", always = "Always", never = "Never" }
local HINTS = { "line", "full", "none" }
local HINTS_LABELS = { line = "One Line", full = "A Line per Action", none = "Hidden" }

function O.BuildTipHints(page)
    O.Section(page, L["Prices and Hints"])
    local intro = O.Label(page, L["Shopping list rows and the recipe's reagent cards."])
    intro:SetTextColor(0.7, 0.7, 0.7)
    page.y = page.y - O.ROW_H
    Drop(page, L["Auction Price"], "tipAuctionPrice", PRICE, PRICE_LABELS,
        L["\"Auction Price: 25c each\" under the item. Auctionator adds its own Auction line when its auction price tooltip setting is on, so by default this one is left off then."])
    Drop(page, L["Click Hints"], "tipHints", HINTS, HINTS_LABELS,
        L["What a click does: \"Click: Quantity, Ctrl: Auction House, Alt: Recipes\" on one line, each action on its own line, or none."])
    Check(page, L["Show Where a Vendor Sells It"], "tipVendor",
        L["\"Sold by\" with the vendor, and Right-click for a waypoint to the nearest one."])
end

function O.ResetTipHints()
    O.ResetKeys("tipAuctionPrice", "tipHints", "tipVendor")
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------
function O.BuildTipRecipes(page)
    O.Section(page, L["Recipes"])
    local intro = O.Label(page, L["The recipe list's tooltips and the recipe's detail panel."])
    intro:SetTextColor(0.7, 0.7, 0.7)
    page.y = page.y - O.ROW_H
    Check(page, L["Show Where Learned Recipes Came From"], "tipLearnedSource",
        L["Keep the trainer, vendor or other source after you learn a recipe, not only while it is unlearned."])
end

function O.ResetTipRecipes()
    O.ResetKeys("tipLearnedSource")
end

---------------------------------------------------------------------------
-- Disenchant Results
---------------------------------------------------------------------------
local SHOW = { "always", "shift" }
-- "shift" in these settings is the detail key, Shift unless changed under General.
local SHOW_LABELS = { always = "Always", shift = WithKey("While Holding %s") }
local DETAIL = { "terse", "full", "shift" }
local DETAIL_LABELS = { terse = "One Line", full = "Every Result", shift = WithKey("One Line, Every Result With %s") }
local NEEDS = { "none", "any", "self" }
local NEEDS_LABELS = { none = "Not Required", any = "Any of Your Characters", self = "This Character" }

function O.BuildDisenchantTooltips(page)
    local db = FP.db
    O.Section(page, L["Disenchant Results"])
    Check(page, L["Show Disenchant Results on Item Tooltips"], "deTooltip",
        L["Weapons and armour that can be disenchanted show what disenchanting them gives, and with Auctionator what that is worth."])
    local show = Drop(page, L["Show"], "deTooltipShow", SHOW, SHOW_LABELS,
        L["Always, or only while you hold the detail key (Options, Tooltips, General)."])
    local detail = Drop(page, L["Detail"], "deTooltipDetail", DETAIL, DETAIL_LABELS,
        L["One line with the best choice and its value (the likeliest result without prices), or each choice's value and every disenchant result with its chance."])
    local needs = Drop(page, L["Requires Enchanting"], "deTooltipNeeds", NEEDS, NEEDS_LABELS,
        L["Only show it when one of your characters, or this one, knows Enchanting. Not Required shows it everywhere, to decide what to sell and what to send to your enchanter."])
    local boundSelf = Check(page, L["Hide on Soulbound Gear Unless This Character Knows Enchanting"], "deTooltipBoundSelf",
        L["Soulbound gear can't be mailed to your enchanter, so on a character without Enchanting its disenchant lines only clutter the tooltip."])
    local verdict = Check(page, L["Show the Best Choice"], "deTooltipVerdict",
        L["Lead with what to do with the item: disenchant it, sell it to a vendor or sell it at auction, and what that earns after the 5% auction house cut. Every Result also lists each choice's value. Needs Auctionator. Off: just the disenchant value."])

    refreshers[#refreshers + 1] = function()
        Follow(db.deTooltip, { show, detail, needs }, { boundSelf, verdict })
    end
    refreshers[#refreshers]()
end

function O.ResetDisenchantTooltips()
    O.ResetKeys("deTooltip", "deTooltipShow", "deTooltipDetail", "deTooltipNeeds", "deTooltipVerdict", "deTooltipBoundSelf")
end

-- Any option changing redraws the previewer (it is hidden off the Tooltips pages, so this costs nothing there).
refreshers[#refreshers + 1] = function() Tips.Preview:Refresh() end
