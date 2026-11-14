local _, FP = ...
local L = FP.L
local UI = FP.UI
local O = FP.Options
local refreshers = O.refreshers

-- The tooltips page: what ProfessionsForever adds to item tooltips.

local function Choices(key, order, labels)
    return function()
        local db = FP.db
        local items = {}
        for _, value in ipairs(order) do
            items[#items + 1] = { text = L[labels[value]], checked = db[key] == value, onSelect = function()
                db[key] = value
                O:Refresh()
            end }
        end
        return items
    end
end

local SHOW = { "always", "shift" }
local SHOW_LABELS = { always = "Always", shift = "While Holding Shift" }
local DETAIL = { "terse", "full", "shift" }
local DETAIL_LABELS = { terse = "One Line", full = "Every Result", shift = "One Line, Every Result With Shift" }
local NEEDS = { "none", "any", "self" }
local NEEDS_LABELS = { none = "Not Required", any = "Any of Your Characters", self = "This Character" }

local function Tip(w, text) UI:Tooltip(w, "ANCHOR_RIGHT", function(t) t:AddLine(text, 1, 1, 1, true) end) end

function O.BuildTooltips(page)
    local db = FP.db
    O.Section(page, L["Disenchanting"])
    local on = O.Check(page, L["Show Disenchant Results on Item Tooltips"], function() return db.deTooltip end, function(v)
        db.deTooltip = v
        O:Refresh()
    end)
    Tip(on, L["Weapons and armour that can be disenchanted show what disenchanting them gives, and with Auctionator what that is worth."])

    local show = O.DropList(page, L["Show"], function() return L[SHOW_LABELS[db.deTooltipShow]] end,
        Choices("deTooltipShow", SHOW, SHOW_LABELS))
    Tip(show, L["Always, or only while you hold Shift."])
    local detail = O.DropList(page, L["Detail"], function() return L[DETAIL_LABELS[db.deTooltipDetail]] end,
        Choices("deTooltipDetail", DETAIL, DETAIL_LABELS))
    Tip(detail, L["One line with the best choice and its value (the likeliest result without prices), or each choice's value and every disenchant result with its chance."])
    local needs = O.DropList(page, L["Requires Enchanting"], function() return L[NEEDS_LABELS[db.deTooltipNeeds]] end,
        Choices("deTooltipNeeds", NEEDS, NEEDS_LABELS))
    Tip(needs, L["Only show it when one of your characters, or this one, knows Enchanting. Not Required shows it everywhere, to decide what to sell and what to send to your enchanter."])
    local boundSelf = O.Check(page, L["Hide on Soulbound Gear Unless This Character Knows Enchanting"],
        function() return db.deTooltipBoundSelf end, function(v) db.deTooltipBoundSelf = v end)
    Tip(boundSelf, L["Soulbound gear can't be mailed to your enchanter, so on a character without Enchanting its disenchant lines only clutter the tooltip."])
    local verdict = O.Check(page, L["Show the Best Choice"], function() return db.deTooltipVerdict end, function(v)
        db.deTooltipVerdict = v
    end)
    Tip(verdict, L["Lead with what to do with the item: disenchant it, sell it to a vendor or sell it at auction, and what that earns after the 5% auction house cut. Every Result also lists each choice's value. Needs Auctionator. Off: just the disenchant value."])

    refreshers[#refreshers + 1] = function()
        local active = db.deTooltip and true or false
        show:SetActive(active)
        detail:SetActive(active)
        needs:SetActive(active)
        for _, check in ipairs({ boundSelf, verdict }) do
            check:SetEnabled(active)
            check.label:SetAlpha(active and 1 or 0.4)
        end
    end
    refreshers[#refreshers]()
end

function O.ResetTooltips()
    O.ResetKeys("deTooltip", "deTooltipShow", "deTooltipDetail", "deTooltipNeeds", "deTooltipVerdict", "deTooltipBoundSelf")
end
