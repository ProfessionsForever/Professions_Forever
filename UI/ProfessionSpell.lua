local _, FP = ...
local L = FP.L
local UI = FP.UI

-- Spell buttons beside a profession: Disenchant (then click an item) and the tracking spells.
local SPELLS = {
    [333] = { id = 13262, needsItem = true }, -- Enchanting: Disenchant
    [186] = { id = 2580 },                    -- Mining: Find Minerals
    [182] = { id = 2383 },                    -- Herbalism: Find Herbs
    [356] = { id = 43308 },                   -- Fishing: Find Fish
}

-- The spell's localized name when the character knows it.
function UI:ProfessionSpellName(skillLine)
    local spell = SPELLS[skillLine]
    if not (spell and IsPlayerSpell(spell.id)) then return end
    local info = C_Spell.GetSpellInfo(spell.id)
    return info and info.name
end

function UI:CreateProfessionSpellButton(parent, size)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    button:SetSize(size or 28, size or 28)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("useOnKeyDown", false) -- casting on mouse-down would leave no room to drag
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(s) if s.spell then C_Spell.PickupSpell(s.spell.id) end end)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 3, -3)
    button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self:Tooltip(button, "ANCHOR_RIGHT", function(tip)
        local name = button.spellName
        if not name then return end
        tip:AddLine(name)
        tip:AddLine(button.spell.needsItem and L["Click to cast %s, then click an item."]:format(name)
            or L["Click to cast %s."]:format(name), 0.7, 0.7, 0.7, true)
        tip:AddLine(L["Drag to an action bar for direct access"], 0.5, 0.8, 1)
    end)
    return button
end

-- Points the button at the profession's spell, or hides it when there is none to cast.
function UI:SetProfessionSpellButton(button, skillLine)
    if not button or InCombatLockdown() then return end
    local name = self:ProfessionSpellName(skillLine)
    if not name then button:Hide() return end
    local spell = SPELLS[skillLine]
    button.spell, button.spellName = spell, name
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "/cast " .. name)
    button.icon:SetTexture(C_Spell.GetSpellTexture(spell.id))
    button:Show()
end

function UI:UpdateProfessionSpellButton()
    local f = self.frame
    if not (f and f.detail and f.detail.craftAll) or InCombatLockdown() then return end
    local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    local skillLine = self.page == "recipes" and base and base.professionID
    local button = f.detail.spellButton
    if skillLine and self:ProfessionSpellName(skillLine) and not button then
        button = self:CreateProfessionSpellButton(f.header, 22)
        -- Protected frames can only anchor to frames, not to chains that run through text regions.
        button:SetPoint("RIGHT", f.rank, "LEFT", -6, 0)
        f.detail.spellButton = button
    end
    self:SetProfessionSpellButton(button, skillLine)
end

---------------------------------------------------------------------------
-- Opening a profession. Blizzard's own book casts the profession's spell from a secure button, and
-- OpenTradeSkill is refused for addon code, so cards and tabs are secure buttons that cast it.
---------------------------------------------------------------------------
-- A frame holding a secure button can't be shown, hidden or moved in combat.
function UI.CombatBlocked(w)
    return InCombatLockdown() and w:IsProtected()
end

local function Loaded(skillLine)
    local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    return base and base.professionID == skillLine and C_TradeSkillUI.IsTradeSkillReady()
end

-- Sets what a left click on the button casts: nothing for a profession that isn't learned or is already open.
function UI:SetProfessionOpener(button, p)
    button.skillLine, button.profName, button.learnable = p.skillLine, p.name, p.learnable
    if InCombatLockdown() then return end
    local id = not p.learnable and not Loaded(p.skillLine) and self:ProfessionSpellID(p)
    local info = id and C_Spell.GetSpellInfo(id)
    button.castable = info ~= nil
    button:SetAttribute("macrotext", "")
    button:SetAttribute("macrotext1", info and ("/cast " .. info.name) or "")
end

-- Runs after the secure click: right click and unlearned professions find a trainer, otherwise show the recipe page.
function UI.OnProfessionOpenerClick(button, btn)
    if btn == "RightButton" or button.learnable then
        if FP.Waypoint:NavAvailable() then FP.Waypoint:NearestTrainer(button.profName) end
        return
    end
    UI.TabSound()
    -- A cast opens the profession (and the window's recipe page) through TRADE_SKILL_SHOW.
    if Loaded(button.skillLine) or (not button.castable and FP:OpenProfession(button.skillLine)) then
        if UI.page ~= "recipes" then UI:SetPage("recipes") end
    end
end
