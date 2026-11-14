local _, FP = ...
local UI = FP.UI

-- Cards and tabs open a profession the way Blizzard's profession book does: a secure button casts its spell, which
-- works where C_TradeSkillUI.OpenTradeSkill doesn't (it needs a click of its own and is refused in some states).

local function Loaded(skillLine)
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    return base and base.professionID == skillLine and C_TradeSkillUI.IsTradeSkillReady() and not FP:IsReadOnly()
end

-- The profession's spellbook entries as { slot, id }.
local function SpellEntries(p)
    local out = {}
    local first = (p.spellOffset or 0) + 1
    for slot = first, first + (p.numSpells or 0) - 1 do
        local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
        if item and item.spellID then out[#out + 1] = { slot = slot, id = item.spellID } end
    end
    return out
end

-- The profession's spell that opens its crafting window; Fishing also has one that casts the pole.
function UI:ProfessionSpellID(p)
    local fallback
    for _, spell in ipairs(SpellEntries(p)) do
        local ok, opensWindow = pcall(C_TradeSkillUI.CanTradeSkillShowCraftingUI, spell.id)
        if ok and opensWindow then return spell.id end
        if not fallback and not C_Spell.IsSpellPassive(spell.id) then fallback = spell.id end
    end
    return fallback
end

-- Whether the profession has a crafting window to open (not Herbalism, Skinning or Fishing, whose spell would cast).
function UI:HasCraftingWindow(p)
    for _, spell in ipairs(SpellEntries(p)) do
        local ok, opensWindow = pcall(C_TradeSkillUI.CanTradeSkillShowCraftingUI, spell.id)
        if ok and opensWindow then return true end
    end
    return false
end

-- Dragging a card to an action bar picks up the spell that opens the window, except Fishing, which picks up the pole.
local DRAGS_OTHER_SPELL = { [356] = true }

-- The spellbook slot a card drags, as Blizzard's book picks spells up.
function UI:DragSlot(p)
    local opener, other
    local extra = {}
    for _, spell in ipairs(self:ExtraSpells(p.skillLine)) do extra[spell.id] = true end -- they have their own buttons
    for _, spell in ipairs(SpellEntries(p)) do
        if not C_Spell.IsSpellPassive(spell.id) then
            local ok, opensWindow = pcall(C_TradeSkillUI.CanTradeSkillShowCraftingUI, spell.id)
            if ok and opensWindow then opener = opener or spell.slot
            elseif not extra[spell.id] then other = other or spell.slot end
        end
    end
    if DRAGS_OTHER_SPELL[p.skillLine] then return other or opener end
    return opener or other
end

function UI:PickupProfession(p)
    local slot = self:DragSlot(p)
    if slot then C_SpellBook.PickupSpellBookItem(slot, Enum.SpellBookSpellBank.Player) end
end

-- A left click casts the profession's spell, unless it isn't learned or is already open. Another character's
-- profession (p.alt, its key) casts nothing; the click opens its saved recipes.
function UI:SetProfessionOpener(button, p)
    button.skillLine, button.profName, button.learnable, button.altKey = p.skillLine, p.name, p.learnable, p.alt
    if InCombatLockdown() then return end
    local id = not p.alt and not p.learnable and not Loaded(p.skillLine) and self:ProfessionSpellID(p)
    local info = id and C_Spell.GetSpellInfo(id)
    button.castable = info ~= nil
    button:SetAttribute("macrotext", "")
    button:SetAttribute("macrotext1", info and ("/cast " .. info.name) or "")
end

-- Runs after the secure click. Right click and unlearned professions find a trainer; otherwise show the recipe page.
function UI.OnProfessionOpenerClick(button, btn)
    if button.altKey then
        if btn ~= "RightButton" then
            UI.TabSound()
            FP.AltProfs:View(button.altKey, button.skillLine)
        end
        return
    end
    if btn == "RightButton" or button.learnable then
        if FP.Waypoint:NavAvailable() then FP.Waypoint:NearestTrainer(button.profName) end
        return
    end
    UI.TabSound()
    -- A cast opens the window's recipe page itself, through TRADE_SKILL_SHOW.
    if Loaded(button.skillLine) or (not button.castable and FP:OpenProfession(button.skillLine)) then
        if UI.page ~= "recipes" then UI:SetPage("recipes") end
    end
end
