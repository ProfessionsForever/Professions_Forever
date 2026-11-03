local _, FP = ...
local L = FP.L

---------------------------------------------------------------------------
-- Blizzard window replacement
---------------------------------------------------------------------------
-- The default frame must stay "shown" (hiding it closes the trade skill, and we need the
-- profession open for recipe data), so it is made transparent and shrunk to a speck, which
-- keeps its invisible buttons from eating clicks. Its strata is dropped below our windows as a second guard.
-- Its parent and anchors are never touched: re-parenting it left it off screen once restored.
local hiddenFrame, hookedFrame, savedScale, savedStrata
local SPECK = 0.001

local function Squash(pf)
    if hiddenFrame ~= pf then return end
    pf:SetAlpha(0)
    pf:SetScale(SPECK)
    pf:SetFrameStrata("BACKGROUND")
end

function FP:SuppressBlizzard()
    if not FP.db.replaceDefault then return end
    local pf = _G.ProfessionsFrame
    if pf and hiddenFrame ~= pf then
        hiddenFrame = pf
        savedScale, savedStrata = pf:GetScale(), pf:GetFrameStrata()
        pf:EnableMouse(false)
        Squash(pf)
        -- Blizzard resets the scale when the window shows and when its panel layout updates.
        if hookedFrame ~= pf then
            hookedFrame = pf
            pf:HookScript("OnShow", Squash)
            hooksecurefunc(pf, "SetScale", function(s, scale)
                if hiddenFrame == s and scale ~= SPECK then s:SetScale(SPECK) end
            end)
        end
    end
end

function FP:RestoreBlizzard()
    if hiddenFrame then
        local pf = hiddenFrame
        hiddenFrame = nil
        pf:SetScale(savedScale or 1)
        pf:SetFrameStrata(savedStrata or "MEDIUM")
        pf:SetAlpha(1)
        pf:EnableMouse(true)
    end
end

-- Linked, guild and NPC crafting views keep Blizzard's window.
function FP:IsOwnProfession()
    local T = C_TradeSkillUI
    return not (T.IsTradeSkillLinked() or T.IsTradeSkillGuild() or T.IsNPCCrafting())
end

---------------------------------------------------------------------------
-- Professions
---------------------------------------------------------------------------
-- Skill lines to look for when GetProfessions() leaves a profession out, and to offer as learnable.
local SECONDARY_SKILLS = { 129, 185, 356 } -- First Aid, Cooking, Fishing
FP.SECONDARY_SKILLS = SECONDARY_SKILLS
local PRIMARY_SKILLS = { 171, 164, 333, 202, 182, 773, 755, 165, 186, 393, 197 }
local isSecondary = {}
for _, id in ipairs(SECONDARY_SKILLS) do isSecondary[id] = true end

function FP:IsSecondary(skillLine) return isSecondary[skillLine] == true end

function FP:GetProfessions()
    local out, seen = {}, {}
    -- Up to two primary and five secondary profession indices, with gaps.
    local indices = { GetProfessions() }
    for i = 1, 7 do
        local idx = indices[i]
        if idx and idx > 0 then
            local name, icon, rank, maxRank, numSpells, spellOffset, skillLine = GetProfessionInfo(idx)
            if name then
                out[#out + 1] = { name = name, icon = icon, rank = rank, maxRank = maxRank, skillLine = skillLine,
                    numSpells = numSpells, spellOffset = spellOffset }
                seen[name] = true
            end
        end
    end

    -- Add any learned profession (rank > 0) the API above left out.
    local T = C_TradeSkillUI
    local ids = {}
    for _, id in ipairs(PRIMARY_SKILLS) do ids[#ids + 1] = id end
    for _, id in ipairs(SECONDARY_SKILLS) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local ok, info = pcall(T.GetProfessionInfoBySkillLineID, id)
        local name = ok and info and info.professionName
        if name and (info.skillLevel or 0) > 0 and not seen[name] then
            seen[name] = true
            out[#out + 1] = {
                name = name,
                icon = T.GetTradeSkillTexture(id) or "Interface\\Icons\\INV_Misc_QuestionMark",
                rank = info.skillLevel,
                maxRank = info.maxSkillLevel,
                skillLine = id,
            }
        end
    end
    return out
end

-- Professions the player doesn't have yet, for the Overview's "visit a trainer" cards.
function FP:GetLearnableProfessions()
    local T = C_TradeSkillUI
    local known, out = {}, {}
    for _, profession in ipairs(self:GetProfessions()) do known[profession.name] = true end
    local function Add(skillLine, secondary)
        local info = T.GetProfessionInfoBySkillLineID(skillLine)
        local name = info and info.professionName or T.GetTradeSkillDisplayName(skillLine)
        local icon = T.GetTradeSkillTexture(skillLine)
        if name and icon and not known[name] and (info == nil or (info.skillLevel or 0) == 0) then
            known[name] = true
            out[#out + 1] = { name = name, icon = icon, skillLine = skillLine, learnable = true, secondary = secondary }
        end
    end
    for _, skillLine in ipairs(PRIMARY_SKILLS) do Add(skillLine) end
    for _, skillLine in ipairs(SECONDARY_SKILLS) do Add(skillLine, true) end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function FP:OpenProfession(skillLine)
    if InCombatLockdown() then return FP:Print(L["Cannot do that in combat."]) end
    local ok, err = pcall(C_TradeSkillUI.OpenTradeSkill, skillLine)
    if not ok then FP:Print(err) end
end

function FP:Open()
    if C_TradeSkillUI.IsTradeSkillReady() and FP:IsOwnProfession() then
        FP:SuppressBlizzard()
        FP.UI:Show("recipes")
    else
        FP.UI:Show("overview") -- the overview is the starting tab
    end
end

function FP:Toggle()
    if FP.UI.frame and FP.UI.frame:IsShown() then FP.UI.frame:Hide() else FP:Open() end
end

---------------------------------------------------------------------------
-- Opening this window instead of Blizzard's book: the micro button and the keybind
---------------------------------------------------------------------------
-- The micro-menu Professions button and ToggleProfessionsBook open Blizzard's book page, which stays
-- invisible (see SuppressBlizzard); show this window instead. Both fire, so ignore the second.
local lastBookOpen = 0
local function OpenInsteadOfBook()
    if not (FP.db and FP.db.replaceDefault) or GetTime() - lastBookOpen < 0.3 then return end
    lastBookOpen = GetTime()
    FP:Toggle()
end

function FP:HookProfessionButtons()
    if self.buttonsHooked then return end
    if ProfessionMicroButton then ProfessionMicroButton:HookScript("OnClick", OpenInsteadOfBook) self.buttonsHooked = true end
    if type(ToggleProfessionsBook) == "function" then hooksecurefunc("ToggleProfessionsBook", OpenInsteadOfBook) self.buttonsHooked = true end
end

-- Routes the default professions keybind to this addon instead of Blizzard's spellbook tab.
local bindBtn = CreateFrame("Button", "ProfessionsForeverBindButton", UIParent)
bindBtn:SetScript("OnClick", function() FP:Toggle() end)

function FP:UpdateBindings()
    if InCombatLockdown() then self.bindingsPending = true return end
    self.bindingsPending = false
    ClearOverrideBindings(bindBtn)
    if not self.db or not self.db.replaceDefault then return end
    for _, key in ipairs({ GetBindingKey("TOGGLEPROFESSIONBOOK") }) do
        SetOverrideBindingClick(bindBtn, true, key, "ProfessionsForeverBindButton")
    end
end
