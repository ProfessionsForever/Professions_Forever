local _, FP = ...
local L = FP.L
local UI = FP.UI
local STATUS_COLORS, Hex = UI.STATUS_COLORS, UI.Hex

-- Where a recipe comes from, and the preview, track and link actions on it. Shared by the recipe list's rows and the
-- recipe panel (UI/RecipeList.lua, UI/Detail.lua, UI/DetailPanel.lua).

local MAX_TRAINERS = 5 -- trainers listed on a tooltip; the rest are counted

-- "Name (Zone)" for a remembered trainer record or a quest's giver, with the holiday a quest is only given in.
local function TrainerWhere(trainer)
    return FP.Waypoint.Label(trainer.npc, trainer.zone, trainer.holiday)
end

-- "Quest: Klaven's Tower (Agent Kearnen)" for a quest that rewards a recipe (an FP.RecipeQuests entry), or
-- "Quest: Small Rockets (Fariel Starsong, Lunar Festival)" for one only given in a holiday.
function UI.QuestSource(q)
    local holiday = FP.Waypoint.HolidayName(q.holiday)
    return ("%s (%s)"):format(L["Quest: %s"]:format(q.quest), holiday and ("%s, %s"):format(q.npc, holiday) or q.npc)
end

-- What the recipe makes, when it can be worn and so previewed.
function UI.PreviewLink(recipeID)
    local output = FP.Recipes:OutputInfo(recipeID)
    local link = output and (output.hyperlink or (output.itemID and select(2, C_Item.GetItemInfo(output.itemID))))
    if link and C_Item.IsDressableItemByID(link) then return link end
end

-- Ctrl-click preview: opens the dressing room on the recipe's result. Returns true when it did.
function UI.PreviewRecipe(recipeID)
    local link = recipeID and UI.PreviewLink(recipeID)
    if not (link and DressUpLink(link)) then return false end
    if DressUpFrame then DressUpFrame:Raise() end -- already-open dressing room stays under our clicked window otherwise
    return true
end

-- A learned recipe is tracked in the game's own objective tracker (shows its reagents as you gather them);
-- an unlearned one gets a waypoint to where it is learned.
local function ToggleTracked(e)
    C_TradeSkillUI.SetRecipeTracked(e.id, not C_TradeSkillUI.IsRecipeTracked(e.id, false), false)
    UI:UpdateDetail()
end

function UI.TrackRecipe(e)
    if FP:IsReadOnly() then return end
    if not e.learned then return FP.Waypoint:ForRecipe(e.id) end
    ToggleTracked(e)
end

-- Chat-link click: link the thing, or, as in Blizzard's window, track the recipe in the objective tracker (learned or
-- not) when no chat box takes it. Not while the auction house is open: there the click is a search. True when the
-- click was spent.
function UI.LinkOrTrack(link, e)
    local held, inChat = UI.LinkToChat(link)
    if inChat or held and AuctionHouseFrame and AuctionHouseFrame:IsShown() then return true end
    if e and IsModifiedClick("RECIPEWATCHTOGGLE") then
        if not FP:IsReadOnly() then ToggleTracked(e) end
        return true
    end
    return held
end

-- Whether to show where a recipe comes from: always while unlearned, and once learned with the Tooltips option on.
function UI.ShowsSource(e)
    return not e.learned or FP.db.tipLearnedSource
end

-- "New in Forever", or "Changed in Forever: Reagents, Trainer Cost" for a recipe 1.12 had differently
-- (Data/RecipeSources.lua); nil for one that is as it was.
local CHANGES = { r = "Reagents", o = "Result", s = "Trainer Skill", c = "Trainer Cost" }
function UI.ForeverTagText(recipeID)
    local tag = FP.RecipeForever[recipeID]
    if not tag then return end
    if tag == "N" then return L["New in Forever"] end
    local what = {}
    for code in tag:sub(2):gmatch(".") do what[#what + 1] = L[CHANGES[code]] end
    return L["Changed in Forever: %s"]:format(table.concat(what, ", "))
end

-- The infinity that marks a recipe new in Forever (gold) or changed in Forever (blue): its texture, or nil for a recipe
-- that is as it was, or with the option off. Drawn by tools/gen_forever_icon.py.
local FOREVER_NEW = "Interface\\AddOns\\ProfessionsForever\\Media\\forever-new"
local FOREVER_CHANGED = "Interface\\AddOns\\ProfessionsForever\\Media\\forever-changed"
function UI.ForeverIcon(recipeID)
    local tag = FP.db.foreverIcon and FP.RecipeForever[recipeID]
    return tag and (tag == "N" and FOREVER_NEW or FOREVER_CHANGED) or nil
end

-- Adds where a recipe comes from (source text, trainers, vendors) to `tip`, GameTooltip unless given. A learned one gets
-- no waypoint hint: Ctrl-click doesn't set one for it. `pv`: the options' previewer's made-up source ({ trainers }), as
-- the game's source text needs the profession open.
function UI.AddSourceLines(recipeID, learned, tip, pv)
    tip = tip or GameTooltip
    local src, trainers, sold, loading
    local quests, dropped, found = {}, nil, nil
    if pv then
        trainers = pv.trainers
    else
        src = C_TradeSkillUI.GetRecipeSourceText(recipeID)
        trainers = FP.Waypoint:TrainersFor(recipeID)
        sold, loading = FP.Waypoint:Summary(recipeID)
        quests = FP.Waypoint:QuestsFor(recipeID)
        -- The game's own source text names a drop where it has one; the built-in drops are for where it has none.
        if not (src and src ~= "") then dropped, found = FP.Waypoint:DropSummary(recipeID) end
    end
    local hasSrc = src and src ~= ""
    local trainer = trainers[1]
    local tag = not pv and UI.ForeverTagText(recipeID)
    if tag then tip:AddLine(tag, 0.5, 0.8, 1, true) end
    if src and hasSrc then tip:AddLine(src, 1, 0.82, 0, true) end
    -- One trainer on one line; more under a "Trained by" line, nearest first.
    if #trainers == 1 then
        tip:AddLine(L["Trained by: %s"]:format(TrainerWhere(trainer)), 1, 0.82, 0, true)
    elseif trainer then
        tip:AddLine(L["Trained by"], 1, 0.82, 0)
        for i = 1, math.min(#trainers, MAX_TRAINERS) do
            tip:AddLine(FP.Tooltips:Indent(1) .. TrainerWhere(trainers[i]), 1, 1, 1)
        end
        if #trainers > MAX_TRAINERS then
            tip:AddLine(FP.Tooltips:Indent(1) .. L["+%d more"]:format(#trainers - MAX_TRAINERS), 0.6, 0.6, 0.6)
        end
    end
    -- What a trainer asks: seen on a Forever build, or 1.12's where no one has seen Forever's.
    local learn = trainer and not pv and FP.RecipeTrainerLearn[recipeID]
    if learn then
        tip:AddLine(L[learn[3] and "Trainer Asks: Skill %d, %s" or "Trainer Asks: Skill %d, %s (Classic Value)"]:format(learn[1], FP.Prices:Format(learn[2])), 0.75, 0.75, 0.75, true)
    end
    if sold then tip:AddLine(L["Sold by: %s"]:format(sold), 1, 0.82, 0, true) end
    if loading then tip:AddLine(L["Looking up vendors..."], 0.6, 0.6, 0.6) end
    -- A quest that rewards it, and who gives the quest where.
    for _, q in ipairs(quests) do
        tip:AddLine(L["Quest: %s"]:format(q.quest), 1, 0.82, 0, true)
        tip:AddLine(FP.Tooltips:Indent(1) .. L["Given by: %s"]:format(TrainerWhere(q)), 1, 1, 1, true)
    end
    if dropped then tip:AddLine(dropped, 1, 0.82, 0, true) end
    if found then tip:AddLine(found, 1, 0.82, 0, true) end
    if not (hasSrc or trainer or sold or loading or quests[1] or dropped or found) then
        tip:AddLine(L["Source not discovered yet"], 1, 0.82, 0)
        tip:AddLine(L["Visit a trainer for this profession and ProfessionsForever will remember what they teach."], 0.75, 0.75, 0.75, true)
        tip:AddLine(L["Recipes a trainer doesn't offer are usually sold by a vendor, dropped, or earned from a quest."], 0.6, 0.6, 0.6, true)
    end
    if not learned and FP.Waypoint:Available(recipeID) and (trainer or sold or quests[1] or dropped or found) and not UI.PreviewLink(recipeID) then
        tip:AddLine(L["Ctrl-click: set a waypoint"], 0.5, 0.8, 1)
    end
end

-- One line on where a recipe is learned from (the nearest trainer, and how many others), and whether a location is
-- known to set a waypoint to.
function UI.SourceSummary(recipeID)
    local trainers = FP.Waypoint:TrainersFor(recipeID)
    if trainers[1] then
        local text = L["Trained by: %s"]:format(TrainerWhere(trainers[1]))
        if #trainers > 1 then text = text .. " (" .. L["+%d more"]:format(#trainers - 1) .. ")" end
        return text, true
    end
    local sold, loading = FP.Waypoint:Summary(recipeID)
    if sold then return L["Sold by: %s"]:format(sold), true end
    local quest = FP.Waypoint:QuestsFor(recipeID)[1]
    if quest then return UI.QuestSource(quest), true end
    local dropped, found = FP.Waypoint:DropSummary(recipeID)
    if dropped or found then return dropped or found, true end
    if loading then return L["Looking up vendors..."], false end
    return L["Location not currently known"], false
end

-- "Requires skill 150" for a recipe that needs more than the starting skill: green once the open profession's skill
-- reaches it, red until then.
function UI.RequiredSkillText(recipeID)
    local need = FP.RecipeMinSkill[recipeID]
    if not need then return end
    local level = select(2, FP.RankInfo()) or 0
    return Hex(level >= need and STATUS_COLORS.full or STATUS_COLORS.missing) .. L["Requires skill %d"]:format(need) .. "|r"
end
