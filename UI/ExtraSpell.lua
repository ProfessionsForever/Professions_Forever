local _, FP = ...
local L = FP.L
local UI = FP.UI

-- Spell buttons beside a profession: Disenchant (then click an item), the tracking spells and Bait and Tackle,
-- which opens Fishing's crafting window (`opens`).
local SPELLS = {
    [FP.ENCHANTING] = { { id = FP.Disenchant.SPELL, needsItem = true } }, -- Enchanting: Disenchant
    [186] = { { id = 2580 } },                    -- Mining: Find Minerals
    [182] = { { id = 2383 } },                    -- Herbalism: Find Herbs
    [356] = { { id = 1278067, opens = true }, { id = 43308 } }, -- Fishing: Bait and Tackle, Find Fish
}

-- The spell's localized name when the character knows it.
local function SpellName(spell)
    if not IsPlayerSpell(spell.id) then return end
    local info = C_Spell.GetSpellInfo(spell.id)
    return info and info.name
end

-- The profession's known spells, in button order.
function UI:ExtraSpells(skillLine)
    local out = {}
    for _, spell in ipairs(SPELLS[skillLine] or {}) do
        if SpellName(spell) then out[#out + 1] = spell end
    end
    return out
end

local function CreateButton(parent, size)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate, BackdropTemplate")
    button:SetSize(size, size)
    UI:Skin(button, "button")
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("useOnKeyDown", false) -- casting on mouse-down would leave no room to drag
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(s) if s.spell then C_Spell.PickupSpell(s.spell.id) end end)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 3, -3)
    button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    UI.TrimIcon(button.icon)
    UI:Tooltip(button, function(tip)
        local name = button.spellName
        if not name then return end
        tip:AddLine(name)
        tip:AddLine(button.spell.needsItem and L["Click to cast %s, then click an item."]:format(name)
            or L["Click to cast %s."]:format(name), 0.7, 0.7, 0.7, true)
        tip:AddLine(L["Drag to an action bar for direct access"], 0.5, 0.8, 1)
    end)
    -- A spell that opens the profession's window clicks like the profession's card (UI/ProfessionOpener.lua).
    button:SetScript("PostClick", function(s, btn, down)
        if down or not s.spell.opens then return end
        UI.OnProfessionOpenerClick(s, btn)
    end)
    return button
end

local function SetButton(button, spell, skillLine)
    local name = SpellName(spell)
    button.spell, button.spellName = spell, name
    button:SetAttribute("type", "macro")
    if spell.opens then
        for _, p in ipairs(FP:GetProfessions()) do
            if p.skillLine == skillLine then UI:SetProfessionOpener(button, p) end
        end
    else
        button:SetAttribute("macrotext1", nil) -- the button may have held an opener before
        button:SetAttribute("macrotext", "/cast " .. name)
    end
    button.icon:SetTexture(C_Spell.GetSpellTexture(spell.id))
    button:Show()
end

-- Shows one button per known spell of the profession on `parent`, the first placed by placeFirst(button) and the
-- rest to its left; the buttons are kept in store.spellButtons. Returns the leftmost shown button.
function UI:SyncExtraSpellButtons(store, parent, skillLine, size, placeFirst)
    if InCombatLockdown() then return end
    local spells = self:ExtraSpells(skillLine)
    local buttons = store.spellButtons or {}
    store.spellButtons = buttons
    for i, spell in ipairs(spells) do
        if not buttons[i] then
            buttons[i] = CreateButton(parent, size)
            if i == 1 then placeFirst(buttons[i]) else buttons[i]:SetPoint("RIGHT", buttons[i - 1], "LEFT", -4, 0) end
        end
        SetButton(buttons[i], spell, skillLine)
    end
    for i = #spells + 1, #buttons do buttons[i]:Hide() end
    return buttons[#spells]
end

function UI:UpdateExtraSpellButtons()
    local f = self.frame
    if not (f and f.detail and f.detail.craftAll) then return end
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    local skillLine = self.page == "recipes" and not FP:IsReadOnly() and base and base.professionID
    -- Protected frames can only anchor to frames, not to chains that run through text regions.
    local leftmost = self:SyncExtraSpellButtons(f.detail, f.header, skillLine, 22, function(b)
        b:SetPoint("RIGHT", f.rank, "LEFT", -6, 0)
    end)
    self:UpdateDisenchantModeButton(skillLine, leftmost)
end
