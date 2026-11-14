local _, FP = ...

-- What another character needs to browse a profession read-only, beyond the recipes each character knows (Known, in
-- Core/KnownRecipes.lua) and every recipe of each profession (FP.RecipeLines in the game data).
--
-- FP.db.characters[key].professions[skillLine] = { name, icon, rank, maxRank, modifier, bonus }
--   Every profession the character has, recorded at login and on each skill change. modifier (skill from gear and
--   buffs) is only read while that profession is open; bonus is the character's skill-up chance bonus from talents.
-- FP.db.professionData[skillLine] = { recipeCategory = "recipeID,categoryID;...", categories = { [id] = { name, parent, order } } }
--   The profession's category tree, the same for every character. The game only fills in a recipe's category while
--   its profession is open, so it is kept from the last time any character opened that profession.
local AltProfs = {}
FP.AltProfs = AltProfs

-- Name, icon and rank of every profession the current character has; ones it no longer has are dropped.
function AltProfs:RecordRanks()
    local rec = FP.Alts:Current()
    if not rec then return end
    local old, out = rec.professions or {}, {}
    local bonus = FP.Recipes:SkillUpBonus()
    for _, p in ipairs(FP:GetProfessions()) do
        local e = old[p.skillLine] or {}
        e.name, e.icon, e.rank, e.maxRank, e.bonus = p.name, p.icon, p.rank, p.maxRank, bonus
        out[p.skillLine] = e
    end
    rec.professions = out
end

-- The open profession's skill modifier and category tree, when it is the current character's own.
function AltProfs:RecordOpen()
    local T = C_TradeSkillUI
    if FP:IsReadOnly() or not T.IsTradeSkillReady() then return end
    local base = T.GetBaseProfessionInfo()
    local skillLine = base and base.professionID
    local list = FP.Recipes.list
    if not skillLine or #list == 0 then return end

    local rec = FP.Alts:Current()
    local e = rec and rec.professions and rec.professions[skillLine]
    if e then e.modifier = base.skillModifier or 0 end

    local recipeCategory, categories = {}, {}
    for _, r in ipairs(list) do
        if r.categoryID and r.categoryID ~= 0 then recipeCategory[#recipeCategory + 1] = r.id .. "," .. r.categoryID end
    end
    for id, c in pairs(FP.Recipes.categories) do
        categories[id] = { name = c.name, parent = c.parent, order = c.order }
    end
    FP.db.professionData[skillLine] = { recipeCategory = table.concat(recipeCategory, ";"), categories = categories }
end

---------------------------------------------------------------------------
-- Viewing another character's profession
---------------------------------------------------------------------------
-- While set, the main window shows that character's recipes instead of the open profession's, read-only:
-- FP:IsReadOnly() reports it as a linked profession owned by that character, so every chat-link restriction applies.
-- { key, skillLine, owner (the character's name), name, icon, rank, maxRank, modifier, bonus }
AltProfs.viewing = nil

-- Opens a character's saved profession in the main window. False when nothing is saved for it.
function AltProfs:View(key, skillLine)
    local rec = FP.db.characters[key]
    local p = rec and rec.professions and rec.professions[skillLine]
    if not p then return false end
    FP.UI:SetDisenchantMode(false) -- its list depends on whose Enchanting is shown
    self.viewing = { key = key, skillLine = skillLine, owner = rec.name, name = p.name, icon = p.icon, rank = p.rank or 0,
        maxRank = p.maxRank or 0, modifier = p.modifier or 0, bonus = p.bonus or 0 }
    FP.Recipes:Reload()
    FP.UI:Show("recipes")
    return true
end

-- Back to the current character's own professions.
function AltProfs:Stop()
    if not self.viewing then return end
    FP.UI:SetDisenchantMode(false)
    self.viewing = nil
    FP.Recipes:Reload()
end

-- The viewed character was removed under Options: back to your own Overview.
FP.Alts:OnRemove(function(key)
    if AltProfs.viewing and AltProfs.viewing.key == key then
        AltProfs:Stop()
        FP.UI:SetPage("overview")
    end
end)

-- Characters with saved professions, for the Overview's character picker: { key, rec, me }, the current one first.
-- The current character is always listed, even with no professions (a bank character), so the picker can go back to it.
function AltProfs:Characters()
    local me, out = FP.Alts:GetCharacterKey(), {}
    for key, rec in pairs(FP.db.characters) do
        if key == me or (rec.professions and next(rec.professions)) then out[#out + 1] = { key = key, rec = rec, me = key == me } end
    end
    table.sort(out, function(a, b)
        if a.me ~= b.me then return a.me end
        return (a.rec.name or a.key) < (b.rec.name or b.key)
    end)
    return out
end

-- A character's saved professions in the shape FP:GetProfessions() gives, with `alt` set to its key.
function AltProfs:Professions(key)
    local out = {}
    for skillLine, p in pairs(FP.db.characters[key].professions or {}) do
        out[#out + 1] = { name = p.name, icon = p.icon, rank = p.rank, maxRank = p.maxRank, skillLine = skillLine, alt = key }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end
