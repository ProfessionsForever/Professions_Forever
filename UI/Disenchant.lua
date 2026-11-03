local _, FP = ...
local L = FP.L
local UI = FP.UI

local DISENCHANT_SPELL_ID = 13262

function UI:DisenchantSpellName()
    local info = C_Spell.GetSpellInfo(DISENCHANT_SPELL_ID)
    if info and IsPlayerSpell(DISENCHANT_SPELL_ID) then return info.name end
end

local function DisenchantSpellTexture()
    return C_Spell.GetSpellTexture(DISENCHANT_SPELL_ID)
end

function UI:CreateDisenchantButton(parent, size)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    button:SetSize(size or 28, size or 28)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function() C_Spell.PickupSpell(DISENCHANT_SPELL_ID) end)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 3, -3)
    button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self:Tooltip(button, "ANCHOR_RIGHT", function(tip)
        tip:AddLine(L["Disenchant"])
        tip:AddLine(L["Click to cast Disenchant, then click an item."], 0.7, 0.7, 0.7, true)
        tip:AddLine(L["Drag to an action bar for direct access"], 0.5, 0.8, 1)
    end)
    return button
end

function UI:SetDisenchantButton(button, enabled)
    if not button or InCombatLockdown() then return end
    local name = enabled and self:DisenchantSpellName()
    if not name then button:Hide() return end
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "/cast " .. name)
    button.icon:SetTexture(DisenchantSpellTexture())
    button:Show()
end

function UI:UpdateDisenchantButton()
    local f = self.frame
    if not (f and f.detail and f.detail.craftAll) or InCombatLockdown() then return end
    local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    local enchanting = self.page == "recipes" and base and base.professionID == 333
    local button = f.detail.disenchant
    if enchanting and self:DisenchantSpellName() and not button then
        button = self:CreateDisenchantButton(f.header, 22)
        -- Protected frames can only anchor to frames, not to chains that run through text regions.
        button:SetPoint("RIGHT", f.rank, "LEFT", -6, 0)
        f.detail.disenchant = button
    end
    self:SetDisenchantButton(button, enchanting)
end
