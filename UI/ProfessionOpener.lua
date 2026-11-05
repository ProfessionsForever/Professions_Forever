local _, FP = ...
local UI = FP.UI

-- Cards and tabs open a profession the way Blizzard's profession book does: a secure button casts its spell.
-- OpenTradeSkill is refused for addon code.

local function Loaded(skillLine)
    local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    return base and base.professionID == skillLine and C_TradeSkillUI.IsTradeSkillReady()
end

-- The profession's spell that opens its crafting window; Fishing also has one that casts the pole.
function UI:ProfessionSpellID(p)
    local first = (p.spellOffset or 0) + 1
    local last = first + (p.numSpells or 0) - 1
    local fallback
    for i = first, last do
        local item = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
        local id = item and item.spellID
        if id then
            local ok, opensWindow = pcall(C_TradeSkillUI.CanTradeSkillShowCraftingUI, id)
            if ok and opensWindow then return id end
            if not fallback and not C_Spell.IsSpellPassive(id) then fallback = id end
        end
    end
    return fallback
end

-- Dragging a card to an action bar puts this spell there instead of the one that opens the window.
local DRAG_SPELLS = { [356] = 7620 } -- Fishing: the pole

function UI:DragSpellID(p)
    return DRAG_SPELLS[p.skillLine] or self:ProfessionSpellID(p)
end

-- A left click casts the profession's spell, unless it isn't learned or is already open.
function UI:SetProfessionOpener(button, p)
    button.skillLine, button.profName, button.learnable = p.skillLine, p.name, p.learnable
    if InCombatLockdown() then return end
    local id = not p.learnable and not Loaded(p.skillLine) and self:ProfessionSpellID(p)
    local info = id and C_Spell.GetSpellInfo(id)
    button.castable = info ~= nil
    button:SetAttribute("macrotext", "")
    button:SetAttribute("macrotext1", info and ("/cast " .. info.name) or "")
end

-- Runs after the secure click. Right click and unlearned professions find a trainer; otherwise show the recipe page.
function UI.OnProfessionOpenerClick(button, btn)
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
