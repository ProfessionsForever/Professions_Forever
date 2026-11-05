local _, FP = ...
local L = FP.L
local UI = FP.UI

local WHITE = "Interface\\Buttons\\WHITE8x8"
local CARD_H, GAP = 136, 12
local PAD = 14 -- panel padding on the sides and below the cards
local TOP = 64 -- space above the cards (title, hint)
local FOOTER = UI.FOOTER_RESERVE
local SECONDARY_ORDER = { [185] = 1, [356] = 2, [129] = 3 } -- Cooking, Fishing, First Aid

-- The game's own (localized) rank names; the tier is the profession's current cap in steps of 75.
local TIER_GLOBALS = { "APPRENTICE", "JOURNEYMAN", "EXPERT", "ARTISAN", "MASTER", "GRAND_MASTER", "ILLUSTRIOUS", "ZEN_MASTER" }

function UI:SetPage(page)
    local f = self.frame
    if not f then return end
    if UI.CombatBlocked(f.overview) then return FP:Print(L["Cannot do that in combat."]) end
    self:ResetCraftQty()
    self.page = page
    f.left:SetShown(page == "recipes")
    f.right:SetShown(page == "recipes")
    f.overview:SetShown(page == "overview")
    self:RefreshProfessions()
    self:UpdateExtraSpellButtons()
    if page == "overview" then self:RefreshOverview() end
end

---------------------------------------------------------------------------
-- Profession cards
---------------------------------------------------------------------------
local function CardDrag(s)
    local id = s.prof and UI:DragSpellID(s.prof)
    if id then C_Spell.PickupSpell(id) end
end

local function CardTooltip(s)
    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
    GameTooltip:AddLine(s.profName, 1, 1, 1)
    local nav = FP.Waypoint:NavAvailable()
    if s.learnable then
        GameTooltip:AddLine(L["Visit a trainer to learn this profession."], 0.8, 0.8, 0.8, true)
        if nav then
            GameTooltip:AddLine(L["Click: waypoint to the nearest trainer"], 0.5, 0.8, 1)
        else
            GameTooltip:AddLine(L["Polestar or TomTom is needed for waypoints."], 0.6, 0.6, 0.6, true)
        end
    else
        if s.maxRank and s.maxRank > 0 then
            GameTooltip:AddLine(("%s: %d / %d"):format(L["Skill"], s.rank or 0, s.maxRank), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(L["Click: open this profession"], 0.5, 0.8, 1)
        if s.prof and UI:DragSpellID(s.prof) then
            GameTooltip:AddLine(L["Drag to an action bar for direct access"], 0.5, 0.8, 1)
        end
        if nav then GameTooltip:AddLine(L["Right-click: waypoint to the nearest trainer"], 0.5, 0.8, 1) end
    end
    GameTooltip:Show()
end

-- The card is one mouse target, so the icon's highlight follows the cursor while a card is hovered.
local hoverCard
local iconWatcher = CreateFrame("Frame")
iconWatcher:Hide()
iconWatcher:SetScript("OnUpdate", function(s)
    if not hoverCard:IsMouseOver() then
        s:Hide()
        hoverCard.glow:Hide()
        return
    end
    local icon = hoverCard.icon
    local scale = icon:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale
    hoverCard.glow:SetShown(x >= icon:GetLeft() and x <= icon:GetRight() and y >= icon:GetBottom() and y <= icon:GetTop())
end)

-- `tall` cards are the narrow, vertical ones used for secondary professions; their height is set by LayoutOverview.
local function MakeCard(o, tall)
    local card = UI:Button(o, "", 100, tall and 100 or CARD_H, UI.OnProfessionOpenerClick, "up")
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnDragStart", CardDrag)
    card.text:SetText("")

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.name = UI:Text(card, 3, tall and "CENTER" or "LEFT")
    card.name:SetWordWrap(false)
    card.tier = UI:Text(card, -1, tall and "CENTER" or "LEFT")
    card.tier:SetTextColor(0.65, 0.65, 0.65)
    card.maxed = UI:Text(card, -1, tall and "CENTER" or "RIGHT")
    if tall then
        card.icon:SetSize(48, 48)
        card.icon:SetPoint("TOP", 0, -14)
        card.name:SetPoint("TOPLEFT", 8, -70)
        card.name:SetPoint("RIGHT", -8, 0)
        card.tier:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
        card.tier:SetPoint("RIGHT", -8, 0)
        card.maxed:SetPoint("TOPLEFT", card.tier, "BOTTOMLEFT", 0, -6)
        card.maxed:SetPoint("RIGHT", -8, 0)
    else
        card.icon:SetSize(44, 44)
        card.icon:SetPoint("TOPLEFT", 10, -10)
        card.maxed:SetPoint("TOPRIGHT", -10, -12)
        card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -2)
        card.name:SetPoint("RIGHT", card.maxed, "LEFT", -6, 0)
        card.tier:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
        card.tier:SetPoint("RIGHT", -10, 0)
    end

    card.glow = card:CreateTexture(nil, "OVERLAY")
    card.glow:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    card.glow:SetBlendMode("ADD")
    card.glow:SetAllPoints(card.icon)
    card.glow:Hide()

    card.bar = CreateFrame("StatusBar", nil, card)
    card.bar:SetPoint("BOTTOMLEFT", 10, 10)
    card.bar:SetPoint("BOTTOMRIGHT", -10, 10)
    card.bar:SetHeight(14)
    card.bar:SetStatusBarTexture(WHITE)
    card.bar.bg = card.bar:CreateTexture(nil, "BACKGROUND")
    card.bar.bg:SetAllPoints()
    card.bar.bg:SetColorTexture(0, 0, 0, 0.55)
    card.bar.text = UI:Text(card.bar, -1, "CENTER")
    card.bar.text:SetPoint("CENTER")

    card:HookScript("OnEnter", function(s)
        hoverCard = s
        iconWatcher:Show()
        CardTooltip(s)
    end)
    card:HookScript("OnLeave", function(s)
        iconWatcher:Hide()
        s.glow:Hide()
        GameTooltip:Hide()
    end)

    -- Primary professions only; the game's own confirmation popup asks you to type a word before it abandons the skill.
    if not tall then
        card.unlearn = UI:Button(card, "", 18, 18, function()
            StaticPopup_Show("UNLEARN_SKILL", card.profName, nil, card.skillLine)
        end)
        local icon = card.unlearn:CreateTexture(nil, "OVERLAY")
        icon:SetPoint("CENTER")
        icon:SetSize(14, 14)
        icon:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Opaque")
        UI:Tooltip(card.unlearn, "ANCHOR_RIGHT", L["Unlearn This Profession"])
    end
    return card
end

-- A primary profession slot with nothing learned: a droplist of the professions to find a trainer for.
local function MakeEmptySlot(o)
    local slot = CreateFrame("Frame", nil, o, "BackdropTemplate")
    UI:Skin(slot, "button")
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetSize(44, 44)
    slot.icon:SetPoint("TOPLEFT", 10, -10)
    slot.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    slot.icon:SetDesaturated(true)
    slot.icon:SetAlpha(0.5)
    slot.name = UI:Text(slot, 3)
    slot.name:SetPoint("TOPLEFT", slot.icon, "TOPRIGHT", 10, -2)
    slot.name:SetPoint("RIGHT", -10, 0)
    slot.name:SetWordWrap(false)
    slot.name:SetTextColor(0.6, 0.6, 0.6)
    slot.name:SetText(L["Profession slot available"])
    slot.find = UI:Dropdown(slot, 100, 24, function() return L["Find a Trainer..."] end, function()
        local items = {}
        for _, p in ipairs(o.trainerChoices) do
            items[#items + 1] = { text = p.name, icon = p.icon, onSelect = function() FP.Waypoint:NearestTrainer(p.name) end }
        end
        return items
    end)
    slot.find:SetPoint("BOTTOMLEFT", 64, 10)
    slot.find:SetPoint("BOTTOMRIGHT", -10, 10)
    slot.find:Sync()
    UI:Tooltip(slot.find, "ANCHOR_RIGHT", function(tip)
        if FP.Waypoint:NavAvailable() then return false end
        tip:AddLine(L["Polestar or TomTom is needed for waypoints."], 0.6, 0.6, 0.6, true)
    end)
    return slot
end

-- A card holding a secure button is protected, so it can't be shown, hidden or moved in combat.
local CombatBlocked = UI.CombatBlocked

local function Place(w, x, y, width, height)
    if CombatBlocked(w) then return end
    w:ClearAllPoints()
    w:SetPoint("TOPLEFT", w:GetParent(), "TOPLEFT", x, -y)
    w:SetSize(width, height)
end

-- Only sizes and positions; the secondary row fills the height down to the padding.
function UI:LayoutOverview()
    local f = self.frame
    local o = f and f.overview
    if not o then return end
    -- The panel is the window less its margins; its own size can lag behind while the window is being resized.
    local width, height = f:GetWidth() - 16, f:GetHeight() - 101 - FOOTER
    local inner = width - PAD * 2
    local half = (inner - GAP) / 2
    for i = 1, 2 do
        local x = PAD + (i - 1) * (half + GAP)
        Place(o.cards[i], x, TOP, half, CARD_H)
        Place(o.empties[i], x, TOP, half, CARD_H)
    end
    local y = TOP + CARD_H + GAP
    local tallH = height - y - PAD
    local tallW = (inner - GAP * 2) / 3
    for i = 1, 3 do Place(o.tall[i], PAD + (i - 1) * (tallW + GAP), y, tallW, tallH) end
end

---------------------------------------------------------------------------
-- Construction and refresh
---------------------------------------------------------------------------
function UI:CreateOverview()
    local f = self.frame
    local o = CreateFrame("Frame", "ProfessionsForeverOverview", f, "BackdropTemplate")
    o:SetPoint("TOPLEFT", 8, -93)
    o:SetPoint("BOTTOMRIGHT", -8, 8 + FOOTER)
    self:Skin(o, "panel")
    f.overview = o
    o.primary, o.secondary, o.trainerChoices = {}, {}, {}

    -- Two primary slots (a card, or the empty-slot picker) and the three secondary cards.
    o.cards, o.empties, o.tall = {}, {}, {}
    for i = 1, 2 do
        o.cards[i] = MakeCard(o)
        o.empties[i] = MakeEmptySlot(o)
    end
    for i = 1, 3 do o.tall[i] = MakeCard(o, true) end

    o.title = self:Text(o, 5)
    o.title:SetPoint("TOPLEFT", 14, -14)
    o.title:SetText(L["Professions"])
    o.title:SetTextColor(1, 0.82, 0)
    o.hint = self:Text(o, -1)
    o.hint:SetPoint("TOPLEFT", o.title, "BOTTOMLEFT", 0, -4)
    o.hint:SetTextColor(0.65, 0.65, 0.65)

    o:Hide()
end

local function FillCard(card, p, accent, nav)
    UI:SetProfessionOpener(card, p)
    card.rank, card.maxRank, card.prof = p.rank, p.maxRank, p
    card.icon:SetTexture(p.icon)
    card.icon:SetDesaturated(p.learnable == true)
    card.name:SetText(p.name)
    if card.unlearn then
        card.unlearn:SetShown(not p.learnable)
        card.unlearn:ClearAllPoints()
        card.unlearn:SetPoint("LEFT", card.name, "LEFT", card.name:GetStringWidth() + 6, 0)
    end
    if p.learnable then
        card.name:SetTextColor(0.6, 0.6, 0.6)
        card.tier:SetText(L["Not Learned"])
        card.maxed:SetTextColor(0.5, 0.8, 1)
        card.maxed:SetText(nav and L["Find a Trainer"] or "")
        card.bar:Hide()
        return
    end
    card.name:SetTextColor(1, 1, 1)
    local rank, max = p.rank or 0, p.maxRank or 0
    local tier = max % 75 == 0 and TIER_GLOBALS[max / 75]
    card.tier:SetText(tier and _G[tier] or "")
    card.bar:SetMinMaxValues(0, math.max(max, 1))
    card.bar:SetValue(rank)
    local capped = max > 0 and rank >= max
    if capped then
        card.bar:SetStatusBarColor(0.2, 0.75, 0.2)
    else
        card.bar:SetStatusBarColor(accent[1] * 0.8, accent[2] * 0.8, accent[3] * 0.8)
    end
    card.bar.text:SetText(max > 0 and ("%d / %d"):format(rank, max) or tostring(rank))
    card.maxed:SetTextColor(0.2, 0.9, 0.2)
    card.maxed:SetText(capped and L["Visit a Trainer"] or "")
    card.bar:Show()
end

-- Cards of professions with spells (Disenchant, tracking, the pole) carry a button for each.
local function UpdateSpellButtons(card, p)
    if InCombatLockdown() then return end
    local last = UI:SyncExtraSpellButtons(card, card, p.skillLine, 24, function(b)
        b:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
    end)
    -- Only the wide primary cards put the label beside the buttons; the tall ones keep it below the tier.
    if card.unlearn then
        card.maxed:ClearAllPoints()
        if last and last:IsShown() then
            card.maxed:SetPoint("RIGHT", last, "LEFT", -4, 0)
        else
            card.maxed:SetPoint("TOPRIGHT", -10, -12)
        end
    end
end

function UI:RefreshOverview()
    local f = self.frame
    local o = f and f.overview
    if not (o and o:IsShown()) then return end

    local nav = FP.Waypoint:NavAvailable()
    local primary, secondary, choices = wipe(o.primary), wipe(o.secondary), wipe(o.trainerChoices)
    for _, p in ipairs(FP:GetProfessions()) do
        if FP:IsSecondary(p.skillLine) then
            secondary[#secondary + 1] = p
        elseif #primary < 2 then
            primary[#primary + 1] = p
        end
    end
    for _, p in ipairs(FP:GetLearnableProfessions()) do
        if p.secondary then secondary[#secondary + 1] = p else choices[#choices + 1] = p end
    end
    table.sort(secondary, function(x, y) return SECONDARY_ORDER[x.skillLine] < SECONDARY_ORDER[y.skillLine] end)

    local accent = self:GetAccent()
    for i = 1, 2 do
        local card, empty, p = o.cards[i], o.empties[i], primary[i]
        if not CombatBlocked(card) then card:SetShown(p ~= nil) end
        empty:SetShown(p == nil)
        if p then
            FillCard(card, p, accent, nav)
            UpdateSpellButtons(card, p)
        else
            empty.find:SetActive(nav)
        end
    end
    for i = 1, 3 do
        local card, p = o.tall[i], secondary[i]
        if not CombatBlocked(card) then card:SetShown(p ~= nil) end
        if p then
            FillCard(card, p, accent, nav)
            UpdateSpellButtons(card, p)
        end
    end
    o.hint:SetText(FP.Waypoint:NavAvailable() and L["Click a profession to open it. Right-click for the nearest trainer."]
        or L["Click a profession to open it."])
    self:LayoutOverview()
end
