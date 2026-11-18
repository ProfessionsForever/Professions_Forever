local _, FP = ...
local L = FP.L
local UI = FP.UI
local Tips = FP.Tooltips

-- The options' tooltip previewer: a real tooltip docked to the right of the Options window while a Tooltips page is
-- open, drawn by the same code as in game, so every setting shows as it changes. It shows a reagent (Linen Cloth),
-- gear (disenchant results: the first piece in your bags that can be disenchanted, or Shadowfang), a shopping list row
-- or a learned recipe's row in the recipe list (Bolt of Linen Cloth). The queue and alts are made up (you and your first
-- other character of this faction), so every block shows even with nothing queued. The Disenchant Results and Recipes
-- pages switch to the sample their settings change.

local Preview = {}
Tips.Preview = Preview

local SAMPLES = { "reagent", "gear", "shop", "recipe" }
local SAMPLE_LABELS = { reagent = "Reagent (Linen Cloth)", gear = "Disenchantable Gear", shop = "Shopping List Row",
    recipe = "Learned Recipe (Bolt of Linen Cloth)" }
-- The sample a page opens on: the one its settings change.
local PAGE_SAMPLES = { tt_disenchant = "gear", tt_recipes = "recipe" }
local REAGENT = 2589 -- Linen Cloth
local GEAR = 1482 -- Shadowfang, when nothing in your bags can be disenchanted
-- Made-up queued recipes that use it: Bolt of Linen Cloth and Heavy Linen Bandage (2 each), Linen Bandage (1 each).
local BOLT, HEAVY_BANDAGE, BANDAGE = 2996, 2581, 1251
local BOLT_RECIPE = 2963 -- the Bolt of Linen Cloth recipe, for the recipe sample
local PANEL_W = 280

local sample, holdKey = "reagent", false
local panel, tip

-- Your first other character of this faction, for the alts' lines.
local function Alt()
    local me = FP.Alts:GetCharacterKey()
    local keys = {}
    for key, rec in pairs(FP.db.characters) do
        if key ~= me and rec.name and not FP.Alts:IsOtherFaction(rec) then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys[1], keys[1] and FP.db.characters[keys[1]]
end

-- What Tips.preview holds while the sample is drawn.
local function Data()
    local meKey = FP.Alts:GetCharacterKey()
    local me = FP.db.characters[meKey]
    local altKey, alt = Alt()
    local groups = { { key = meKey, name = me.name, realm = me.realm, class = me.class, total = 102, list = {
        { name = FP.ItemName(BOLT), crafts = 31, need = 62 },
        { name = FP.ItemName(HEAVY_BANDAGE), crafts = 20, need = 40 },
    } } }
    local alts = { enabled = {}, ignored = {}, enabledTotal = 0 }
    local plan = { itemID = REAGENT, sources = {}, localShort = 0, shortage = 0 }
    if alt then
        groups[2] = { key = altKey, name = alt.name, realm = alt.realm, class = alt.class, total = 75, list = {
            { name = FP.ItemName(BANDAGE), crafts = 75, need = 75 },
        } }
        alts.enabled[1] = { key = altKey, name = alt.name, realm = alt.realm, class = alt.class, count = 66, bank = 26 }
        alts.enabledTotal = 66
        plan.sources[1] = { key = altKey, transfer = 42 }
        plan.localShort, plan.shortage = 69, 27
    end
    -- The alt's queue also makes 40 of it, which comes off the list: Made by Queues. Crafts Into's sample is the bolt.
    local cover = alt and { need = 177, made = 40, by = { [altKey] = { qty = 40, recipes = {
        { name = FP.ItemName(REAGENT), crafts = 40 },
    } } } } or nil
    local craftsInto = { { name = FP.ItemName(BOLT), need = 20, amount = 40, recipes = {
        { name = C_Spell.GetSpellName(BOLT_RECIPE) or FP.ItemName(BOLT), who = FP.Alts:Label(me) },
    } } }
    local queued = alt and 137 or 102
    return { key = holdKey, itemID = REAGENT, unit = 65, alts = alts, plan = plan,
        queue = { row = { needed = queued, queue = queued, toBuy = 27 }, groups = groups, cover = cover, craftsInto = craftsInto } }
end

-- The first item in your bags that can be disenchanted.
local function BagGear()
    for _, bag in ipairs(FP.Inv:CarriedBags()) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local _, _, quality, level, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(info.itemID)
                if quality and FP.Disenchant:TableFor(info.itemID, classID, quality, level) then return bag, slot end
            end
        end
    end
end

function Preview:Update()
    if not (panel and panel:IsShown()) then return end
    local data = Data()
    local shop = sample == "shop"
    -- A shopping list row writes its own queue lines and hint line, as in game.
    panel.ownQueueLines, panel.ownHints = shop, shop
    tip:SetOwner(panel, "ANCHOR_NONE")
    -- A tooltip draws in the TOOLTIP strata, over the options' dropdown menus: keep it with the Options window.
    tip:SetFrameStrata(panel:GetFrameStrata())
    tip:SetFrameLevel(panel:GetFrameLevel() + 1)
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -4)
    Tips.preview = data
    if shop then
        FP.Shop:FillRowTooltip({ itemID = REAGENT, queue = data.queue.row.queue, mine = 0, plan = data.plan, cover = data.queue.cover,
            preview = { unit = data.unit, alts = data.alts, vendor = L["Nearest Trade Goods Vendor"] } }, tip)
    elseif sample == "recipe" then
        -- Made up as well: what needs the profession open. 66 Linen Cloth on the alt makes 33 bolts.
        local e = { id = BOLT_RECIPE, name = FP.ItemName(BOLT), learned = true, difficulty = 1 }
        UI.FillRecipeTooltip(e, tip, { itemID = BOLT, chance = 0.6, reagents = 1, satisfied = 1, bags = 4, bank = 7,
            alts = 33, source = { trainers = { { npc = "Mira Silkweaver" } } } })
    elseif sample == "gear" then
        local bag, slot = BagGear()
        if bag then
            tip:SetBagItem(bag, slot)
        else
            -- Its item info may not be loaded yet: the disenchant lines need it, so draw again once it is.
            local item = Item:CreateFromItemID(GEAR)
            if not item:IsItemDataCached() then item:ContinueOnItemLoad(function() Preview:Update() end) end
            tip:SetItemByID(GEAR)
        end
    else
        tip:SetItemByID(REAGENT)
    end
    Tips.preview = nil
    tip:Show()
end

local function Build(options)
    panel = CreateFrame("Frame", "ProfessionsForeverTooltipPreviewPanel", options, "BackdropTemplate")
    panel:SetSize(PANEL_W, 92)
    panel:SetPoint("TOPLEFT", options, "TOPRIGHT", 4, 0)
    UI:Skin(panel, "window")
    local title = UI:Text(panel, 1)
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(L["Preview"])
    title:SetTextColor(1, 0.82, 0)

    local dd = UI:Dropdown(panel, PANEL_W - 20, 24, function() return L[SAMPLE_LABELS[sample]] end, function()
        local items = {}
        for _, s in ipairs(SAMPLES) do
            items[#items + 1] = { text = L[SAMPLE_LABELS[s]], checked = sample == s, onSelect = function()
                sample = s
                panel.dropdown:Sync()
                Preview:Update()
            end }
        end
        return items
    end)
    dd:SetPoint("TOPLEFT", 10, -30)
    panel.dropdown = dd

    local hold = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    hold:SetSize(24, 24)
    hold:SetPoint("TOPLEFT", 8, -60)
    hold:SetScript("OnClick", function(s)
        holdKey = s:GetChecked() and true or false
        Preview:Update()
    end)
    hold.label = UI:Text(panel, 0)
    hold.label:SetPoint("LEFT", hold, "RIGHT", 4, 0)
    panel.hold = hold

    tip = CreateFrame("GameTooltip", "ProfessionsForeverTooltipPreview", panel, "GameTooltipTemplate")
    panel:SetScript("OnHide", function() tip:Hide() end)
    -- Item names and the detail key arrive or change: draw it again.
    Tips.onRefresh[#Tips.onRefresh + 1] = function() Preview:Update() end
end

-- From the Options window when a page is picked or it opens: shown while a Tooltips page is.
function Preview:Sync(page)
    local show = page and (page.key == "tooltips" or page.parent == "tooltips")
    if not show then
        if panel then panel:Hide() end
        return
    end
    if not panel then Build(FP.Options.frame) end
    sample = PAGE_SAMPLES[page.key] or sample
    panel:Show()
    self:Refresh()
end

-- After any option changes (an options refresher): the Hold box names the detail key, and the sample is drawn again.
function Preview:Refresh()
    if not (panel and panel:IsShown()) then return end
    panel.dropdown:Sync()
    panel.hold:SetChecked(holdKey)
    panel.hold.label:SetText(L["Hold %s"]:format(Tips:KeyName()))
    self:Update()
end
