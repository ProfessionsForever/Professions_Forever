local _, FP = ...
local L = FP.L
local UI = FP.UI
local STATUS_COLORS, Hex = UI.STATUS_COLORS, UI.Hex

-- Where a recipe comes from, and the preview, track and link actions on it. Shared by the recipe list's rows and the
-- recipe panel (UI/RecipeList.lua, UI/Detail.lua, UI/DetailPanel.lua).

-- "Trained by" text for a remembered trainer record.
local function TrainerText(trainer)
    return L["Trained by: %s"]:format(trainer.zone and ("%s (%s)"):format(trainer.npc, trainer.zone) or trainer.npc)
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
function UI.TrackRecipe(e)
    if FP:IsReadOnly() then return end
    if not e.learned then return FP.Waypoint:ForRecipe(e.id) end
    C_TradeSkillUI.SetRecipeTracked(e.id, not C_TradeSkillUI.IsRecipeTracked(e.id, false), false)
    UI:UpdateDetail()
end

-- Chat-link click: link the thing, or track the recipe when no chat box takes it. True when the click was spent.
function UI.LinkOrTrack(link, e)
    if UI.LinkToChat(link) then return true end
    if e and IsModifiedClick("RECIPEWATCHTOGGLE") then UI.TrackRecipe(e) return true end
    return false
end

-- Adds where an unlearned recipe comes from (source text, trainer, vendors) to the shared GameTooltip.
function UI.AddSourceLines(recipeID)
    local src = C_TradeSkillUI.GetRecipeSourceText(recipeID)
    local hasSrc = src and src ~= ""
    if src and hasSrc then GameTooltip:AddLine(src, 1, 0.82, 0, true) end
    local trainer = FP.Waypoint:TrainerFor(recipeID)
    if trainer then GameTooltip:AddLine(TrainerText(trainer), 1, 0.82, 0, true) end
    local sold, loading = FP.Waypoint:Summary(recipeID)
    if sold then GameTooltip:AddLine(L["Sold by: %s"]:format(sold), 1, 0.82, 0, true) end
    if loading then GameTooltip:AddLine(L["Looking up vendors..."], 0.6, 0.6, 0.6) end
    if not (hasSrc or trainer or sold or loading) then
        GameTooltip:AddLine(L["Source not discovered yet"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Visit a trainer for this profession and ProfessionsForever will remember what they teach."], 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine(L["Recipes a trainer doesn't offer are usually sold by a vendor, dropped, or earned from a quest."], 0.6, 0.6, 0.6, true)
    end
    if FP.Waypoint:Available(recipeID) and (trainer or sold) and not UI.PreviewLink(recipeID) then
        GameTooltip:AddLine(L["Ctrl-click: set a waypoint"], 0.5, 0.8, 1)
    end
end

-- One line on where an unlearned recipe is learned from, and whether a location is known to set a waypoint to.
function UI.SourceSummary(recipeID)
    local trainer = FP.Waypoint:TrainerFor(recipeID)
    if trainer then return TrainerText(trainer), true end
    local sold, loading = FP.Waypoint:Summary(recipeID)
    if sold then return L["Sold by: %s"]:format(sold), true end
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
