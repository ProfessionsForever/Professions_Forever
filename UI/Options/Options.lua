local _, FP = ...
local L = FP.L
local UI = FP.UI
local O = FP.Options
local refreshers = O.refreshers

local WIDTH, MIN_HEIGHT = 640, 260
local NAV_W, NAV_ROW_H = 156, 32 -- wide enough for Disenchant Results, indented under Tooltips
local PAGE_LEFT, PAGE_TOP = 184, -44
O.PAGE_W = WIDTH - PAGE_LEFT - 16

local FONTS = {
    { "Friz Quadrata", "Fonts\\FRIZQT__.TTF" }, { "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "Skurri", "Fonts\\skurri.ttf" }, { "Morpheus", "Fonts\\MORPHEUS.ttf" },
}

-- The game's own fonts, then any that LibSharedMedia lists: other addons register theirs there.
local function FontList()
    local list, seen = {}, {}
    for _, font in ipairs(FONTS) do
        list[#list + 1] = font
        seen[font[2]:lower()] = true
    end
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    if media then
        local extra = {}
        for name, path in pairs(media:HashTable("font")) do
            if type(path) == "string" and not seen[path:lower()] then extra[#extra + 1] = { name, path } end
        end
        table.sort(extra, function(a, b) return a[1] < b[1] end)
        for _, font in ipairs(extra) do list[#list + 1] = font end
    end
    return list
end

StaticPopupDialogs["PROFESSIONSFOREVER_RELOAD_SKIN"] = {
    text = L["Reload your UI to fully remove the EllesmereUI skin."],
    button1 = L["Reload UI"],
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function OfferSkinReload() StaticPopup_Show("PROFESSIONSFOREVER_RELOAD_SKIN") end

local function SkinItems()
    local db = FP.db
    local items = {}
    for _, key in ipairs(FP.skinOrder) do
        if UI:SkinAvailable(key) then
            items[#items + 1] = { text = L[FP.skins[key].name], checked = db.skin == key, onSelect = function()
                local was = db.skin
                db.skin = key
                UI:ApplySkin()
                O:Refresh()
                if was == "ellesmere" and key ~= was and UI.euiApplied then OfferSkinReload() end
            end }
        end
    end
    return items
end

local function FontItems()
    local db = FP.db
    local items = {}
    for _, font in ipairs(FontList()) do
        items[#items + 1] = { text = font[1], checked = db.font == font[2], onSelect = function()
            db.font = font[2]
            UI:ApplyFonts()
            O:Refresh()
        end }
    end
    return items
end

local function PickAccent()
    local db = FP.db
    local a = UI:GetAccent()
    -- The picker is DIALOG strata and opens at screen centre like this window, which is above it, so it would be hidden.
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    if not O.pickerHooked then
        O.pickerHooked = true
        ColorPickerFrame:HookScript("OnHide", function(s) s:SetFrameStrata("DIALOG") end)
    end
    local function Apply()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        db.accent = { r, g, b }
        UI:ApplySkin()
        O:Refresh()
    end
    ColorPickerFrame:SetupColorPickerAndShow({ r = a[1], g = a[2], b = a[3], hasOpacity = false,
        swatchFunc = Apply, cancelFunc = function()
            db.accent = { a[1], a[2], a[3] }
            UI:ApplySkin()
            O:Refresh()
        end })
    ColorPickerFrame:Raise()
end

---------------------------------------------------------------------------
-- Appearance
---------------------------------------------------------------------------
local function BuildTheme(page)
    local db = FP.db
    O.Section(page, L["Theme"])
    O.DropList(page, L["Skin"], function() return L[UI.ActiveSkin().name] end, SkinItems)
    local fontDD = O.DropList(page, L["Font"], function()
        for _, font in ipairs(FontList()) do
            if font[2] == db.font then return font[1] end
        end
        return FONTS[1][1]
    end, FontItems)

    O.Label(page, L["Accent Color"])
    local accentBtn = UI:Button(page, L["Choose Color"], O.CTRL_W, 24, PickAccent)
    accentBtn:SetPoint("LEFT", page, "TOPLEFT", O.CTRL_X, page.y - O.ROW_H / 2)
    page.y = page.y - O.ROW_H
    local swatch = accentBtn:CreateTexture(nil, "OVERLAY")
    swatch:SetSize(14, 14)
    swatch:SetPoint("LEFT", 8, 0)
    refreshers[#refreshers + 1] = function() swatch:SetColorTexture(unpack(UI:GetAccent())) end
    refreshers[#refreshers]()

    -- EllesmereUI supplies the font and accent while its skin is active, so these two would have no effect.
    local function SyncEUILocks()
        local locked = UI.EUI() ~= nil
        fontDD:SetActive(not locked)
        accentBtn:SetActive(not locked)
    end
    refreshers[#refreshers + 1] = SyncEUILocks
    SyncEUILocks()
    for _, w in ipairs({ fontDD, accentBtn }) do
        UI:Tooltip(w, "ANCHOR_RIGHT", function(tip)
            if not UI.EUI() then return false end
            tip:AddLine(L["Set by EllesmereUI while its skin is active."], 1, 1, 1, true)
        end)
    end

end

local function ResetTheme()
    local was = FP.db.skin
    O.ResetKeys("skin", "font", "accent")
    UI:ApplySkin()
    if was == "ellesmere" and UI.euiApplied then OfferSkinReload() end
end

local function BuildSize(page)
    local db = FP.db
    O.Section(page, L["Size and Opacity"])
    local scale = O.Slider(page, "ProfessionsForeverOptScale", L["Scale"], UI.SCALE_MIN, UI.SCALE_MAX, 0.05,
        function() return db.scale end, function(v) UI:SetScale(v) end, "%.2f")
    UI:Tooltip(scale, "ANCHOR_RIGHT", L["Ctrl+Mouse wheel on the title bar changes scale."])
    O.Slider(page, "ProfessionsForeverOptFont", L["Font Size"], 9, 18, 1,
        function() return db.fontSize end, function(v) db.fontSize = v UI:ApplyFonts() end, "%d")
    O.Slider(page, "ProfessionsForeverOptOpacity", L["Background Opacity"], 0.3, 1, 0.05,
        function() return db.opacity end, function(v) db.opacity = v UI:ApplySkin() end, "%.2f")

    O.Section(page, L["Window"])
    O.Check(page, L["Lock Window Position and Size"], function() return db.locked end, function(v)
        db.locked = v
        UI:ApplyLock()
    end)
    O.ActionButton(page, L["Reset Window Size and Position"], 240, function() UI:ResetWindow() end)
end

local function ResetSize()
    O.ResetKeys("fontSize", "opacity", "locked")
    UI:ResetWindow()
    UI:ApplyLock()
    UI:ApplySkin()
end

---------------------------------------------------------------------------
-- General
---------------------------------------------------------------------------
local function BuildMainWindow(page)
    local db = FP.db
    O.Section(page, L["Main Window"])
    O.Check(page, L["Replace Default Professions Window"], function() return db.replaceDefault end, function(v)
        db.replaceDefault = v
        if not v then FP:RestoreBlizzard() end
    end)
    local warn = UI:Text(page, -1)
    warn:SetPoint("LEFT", page, "TOPLEFT", 34, page.y - O.ROW_H / 2)
    warn:SetTextColor(1, 0.6, 0.2)
    warn:SetText(L["Changing this needs a UI reload to take full effect."])
    local reload = UI:Button(page, L["Reload UI"], 100, 22, function() ReloadUI() end)
    reload:SetPoint("RIGHT", page, "TOPRIGHT", 0, page.y - O.ROW_H / 2)
    page.y = page.y - O.ROW_H
    O.Check(page, L["Show Skill Up Chance in the Recipe List"], function() return db.showSkillChance end, function(v)
        db.showSkillChance = v
        UI:UpdateList()
    end)
    O.Check(page, L["Mark Recipes New or Changed in Forever"], function() return db.foreverIcon end, function(v)
        db.foreverIcon = v
        UI:UpdateList()
        UI:UpdateDetail()
    end)
    local camp = O.Check(page, L["Show Camp in the Footer"], function() return db.footerCamp end, function(v)
        db.footerCamp = v
        UI:LayoutFooter()
    end)
    UI:Tooltip(camp, "ANCHOR_RIGHT", L["The Camp cell along the bottom of the main window. Off: the window still opens from its quick button or /pf camp."])
    local orders = O.Check(page, L["Show Crates and Writs in the Footer"], function() return db.footerOrders end, function(v)
        db.footerOrders = v
        UI:LayoutFooter()
    end)
    UI:Tooltip(orders, "ANCHOR_RIGHT", L["The Crates and Writs cell along the bottom of the main window. Off: the window still opens from its quick button or /pf crates."])
    O.Check(page, L["Hide Minimap Button"], function() return db.minimap.hide end, function(v)
        db.minimap.hide = v
        FP.Minimap:Update()
    end)
end

local function ResetMainWindow()
    local db = FP.db
    local replaced = db.replaceDefault
    O.ResetKeys("replaceDefault", "showSkillChance", "foreverIcon", "footerCamp", "footerOrders")
    db.minimap.hide = FP.defaults.minimap.hide
    FP.Minimap:Update()
    UI:LayoutFooter()
    UI:UpdateList()
    UI:UpdateDetail()
    if replaced ~= db.replaceDefault then FP:Print(L["Changing this needs a UI reload to take full effect."]) end
end

local function BuildShopping(page)
    local db = FP.db
    O.Section(page, L["Shopping List"])
    local scope = O.Check(page, L["Shopping List Scope"] .. ": " .. L["Account-Wide"], function() return db.shoppingScope == "account" end, function(v)
        db.shoppingScope = v and "account" or "char"
        FP:Changed("shop")
    end)
    UI:Tooltip(scope, "ANCHOR_RIGHT", L["Share one list between all your characters of the same faction, so a different character can do the buying. The other faction has its own, since items can't be mailed across."])
end

local function ResetShopping()
    O.ResetKeys("shoppingScope")
    FP:Changed("shop")
end

local function BuildAlts(page)
    O.BuildAltSection(page)
    page.y = page.y - 32 -- room for the Reset This Page button under the characters list
end

local function ResetAlts() FP.Planner:SetMode(FP.defaults.altMode) end

local function BuildNotifications(page)
    local db = FP.db
    O.Section(page, L["Notifications"])
    O.Check(page, L["Show the Version at Login"], function() return db.versionNotice end, function(v)
        db.versionNotice = v
    end)
    O.Check(page, L["Tell Me When a Newer Version Is Out"], function() return db.updateNotice end, function(v)
        db.updateNotice = v
    end)
    O.Check(page, L["Show Ready Cooldowns at Login"], function() return db.cooldownNotice end, function(v)
        db.cooldownNotice = v
    end)
    O.Check(page, L["Open the Transfer Planner at Your Bank"], function() return db.bankPrompt end, function(v)
        db.bankPrompt = v
    end)
    O.Check(page, L["Open the Transfer Planner at a Mailbox"], function() return db.mailPrompt end, function(v)
        db.mailPrompt = v
    end)
end

local function ResetNotifications() O.ResetKeys("versionNotice", "updateNotice", "cooldownNotice", "bankPrompt", "mailPrompt") end

---------------------------------------------------------------------------
-- Disenchanting
---------------------------------------------------------------------------
local DEPOSIT_HOURS = { 0, 2, 8, 24 }

local function DepositLabel(hours)
    return hours == 0 and L["Not Counted"] or L["%d Hour Listing"]:format(hours)
end

local function BuildDisenchanting(page)
    local db = FP.db
    O.Section(page, L["Disenchanting"])
    local record = O.Check(page, L["Record Your Disenchant Results"], function() return db.deRecord end, function(v)
        db.deRecord = v
    end)
    UI:Tooltip(record, "ANCHOR_RIGHT", L["Each time any of your characters disenchants an item, what it gave is saved, to check the chances against what Forever really drops."])
    local observed = O.Check(page, L["Show Seen Rates"], function() return db.deShowObserved end, function(v)
        db.deShowObserved = v
        UI:UpdateDisenchantMode()
    end)
    UI:Tooltip(observed, "ANCHOR_RIGHT", L["Under each disenchant result's chance, in Disenchanting Mode and on item tooltips with every result shown: how often your characters really got it from that kind of item. Greyed and marked unreliable until 100 disenchants of that kind are recorded."])
    local main = O.DropList(page, L["Main Enchanter"], function() return UI:MainEnchanterLabel() end, function()
        local items = { { text = L["Automatic (Highest Skill)"], checked = db.mainEnchanter == nil,
            onSelect = function() UI:SetMainEnchanter(nil) end } }
        for _, e in ipairs(UI:Enchanters()) do
            items[#items + 1] = { text = ("%s (%d)"):format(FP.Alts:Label(e.rec), e.rank), checked = db.mainEnchanter == e.key,
                onSelect = function() UI:SetMainEnchanter(e.key) end }
        end
        return items
    end)
    UI:Tooltip(main, "ANCHOR_RIGHT", L["The character your other characters send gear to for disenchanting: the quick button, /pf de and the Overview's icon open Disenchanting Mode for them first. Automatic picks the one with the highest Enchanting skill. Characters of the other faction can't be mailed, so they come last whatever is picked here."])
    local deposit = O.DropList(page, L["Auction Deposit"], function() return DepositLabel(db.deDeposit) end, function()
        local items = {}
        for _, hours in ipairs(DEPOSIT_HOURS) do
            items[#items + 1] = { text = DepositLabel(hours), checked = db.deDeposit == hours, onSelect = function()
                db.deDeposit = hours
                UI:UpdateDisenchantMode(true) -- rescanned, for the Best Value sort and Worth Disenchanting Only filter
            end }
        end
        return items
    end)
    UI:Tooltip(deposit, "ANCHOR_RIGHT", L["The best choice, in Disenchanting Mode and on item tooltips, is only Sell It at Auction when that beats the others by more than this listing's deposit: what you lose if it doesn't sell. The deposit is 5%, 20% or 60% of the vendor price for 2, 8 or 24 hours at a faction auction house."])
end

local function ResetDisenchanting()
    O.ResetKeys("deRecord", "deShowObserved", "mainEnchanter", "deDeposit")
    UI:UpdateDisenchantMode(true)
    FP.Launcher:Update() -- the main enchanter is back to Automatic
end

---------------------------------------------------------------------------
-- The page list
---------------------------------------------------------------------------
-- Top-level entries are plain pages, or categories (cat) whose own page links to the pages under them (parent).
-- A category opens in the list when clicked, one at a time. desc is the line under a page's link; an integration's
-- link takes its description and installed status from UI/Options/OptionsIntegrations.lua instead.
local PAGES = {
    { key = "general", label = "General", cat = true, banner = true },
    { key = "main", parent = "general", label = "Main Window", build = BuildMainWindow, reset = ResetMainWindow,
        desc = "Replace Blizzard's professions window, the skill up chance in the recipe list and the minimap button." },
    { key = "shopping", parent = "general", label = "Shopping List", build = BuildShopping, reset = ResetShopping,
        desc = "One shopping list for all your characters of a faction, or one each." },
    { key = "alts", parent = "general", label = "Alt Inventory", build = BuildAlts, reset = ResetAlts,
        desc = "Whether your other characters' bags and banks count toward what you need, and which characters." },
    { key = "notifications", parent = "general", label = "Notifications", build = BuildNotifications, reset = ResetNotifications,
        desc = "Ready cooldowns at login, and opening the Transfer Planner at your bank or a mailbox." },
    { key = "appearance", label = "Appearance", cat = true },
    { key = "theme", parent = "appearance", label = "Theme", build = BuildTheme, reset = ResetTheme,
        desc = "Skin, font and accent color." },
    { key = "size", parent = "appearance", label = "Size and Window", build = BuildSize, reset = ResetSize,
        desc = "Scale, font size, background opacity, and locking or resetting the window." },
    { key = "quickbuttons", label = "Quick Buttons", cat = true },
    { key = "quick", parent = "quickbuttons", label = "Buttons", build = O.BuildQuick, reset = O.ResetQuick,
        desc = "The movable bar of buttons for the queue, shopping list, transfer planner, cooldowns and professions." },
    { key = "quickkeys", parent = "quickbuttons", label = "Key Bindings", build = O.BuildQuickKeys,
        desc = "Key bindings for each quick button and profession, set here or with Mouseover Keybinding." },
    { key = "de", label = "Disenchanting", build = BuildDisenchanting, reset = ResetDisenchanting },
    { key = "tooltips", label = "Tooltips", cat = true },
    { key = "tt_general", parent = "tooltips", label = "General", build = O.BuildTipGeneral, reset = O.ResetTipGeneral,
        desc = "The detail key, spacing, indent and the order of the blocks." },
    { key = "tt_queue", parent = "tooltips", label = "Queues & Shopping", build = O.BuildQueueTooltips, reset = O.ResetQueueTooltips,
        desc = "How many of an item your queues need, how many are still to buy, and which recipes use it." },
    { key = "tt_alts", parent = "tooltips", label = "Alts and Transfers", build = O.BuildTipAlts, reset = O.ResetTipAlts,
        desc = "Who else holds an item, what they should send, and what is still to buy." },
    { key = "tt_hints", parent = "tooltips", label = "Prices and Hints", build = O.BuildTipHints, reset = O.ResetTipHints,
        desc = "The auction price line, click hints and where a vendor sells it." },
    { key = "tt_recipes", parent = "tooltips", label = "Recipes", build = O.BuildTipRecipes, reset = O.ResetTipRecipes,
        desc = "Where a recipe is learned from, even once you know it." },
    { key = "tt_disenchant", parent = "tooltips", label = "Disenchant Results", build = O.BuildDisenchantTooltips,
        reset = O.ResetDisenchantTooltips,
        desc = "What disenchanting gear gives: when it shows, how much, and for which characters." },
    { key = "tt_orders", parent = "tooltips", label = "Crates and Writs", build = O.BuildTipOrders, reset = O.ResetTipOrders,
        desc = "What a Waylaid Crate pays and the cheapest way to fill it; what a Craftsman's Writ's item costs you." },
    { key = "fishing", label = "One-Click Fishing", build = O.BuildFishing, reset = O.ResetFishing },
    { key = "integrations", label = "Integrations", cat = true },
    { key = "int_auctionator", parent = "integrations", label = "Auctionator", build = O.BuildIntAuctionator, reset = O.ResetIntAuctionator },
    { key = "int_waypoints", parent = "integrations", label = "Polestar & TomTom", build = O.BuildIntWaypoints, reset = O.ResetIntWaypoints },
    { key = "int_questie", parent = "integrations", label = "Questie", build = O.BuildIntQuestie, reset = O.ResetIntQuestie },
    { key = "int_syndicator", parent = "integrations", label = "Syndicator", build = O.BuildIntSyndicator, reset = O.ResetIntSyndicator },
    { key = "int_skillup", parent = "integrations", label = "SkillUp Forever", build = O.BuildIntSkillUp, reset = O.ResetIntSkillUp },
    { key = "int_ellesmere", parent = "integrations", label = "EllesmereUI", build = O.BuildIntEllesmere },
    { key = "about", label = "About", build = O.BuildAbout },
}
local BY_KEY = {}
for _, page in ipairs(PAGES) do
    BY_KEY[page.key] = page
    if page.cat then page.children = {} end
    if page.parent then table.insert(BY_KEY[page.parent].children, page) end
end
local SUB_INDENT, SUB_ROW_H = 14, 26 -- pages under a category in the list: indented and a little shorter

-- The General page's banner: an accent-colored glow that fades to the right between two accent lines (Media/fade.tga,
-- white fading to clear, tinted; flat strips showed as steps), the addon icon,
-- its name, a welcome in the character's class color, the version, and a strip of the character's professions with
-- their skill. The accent and professions follow changes each time the window opens.
local BANNER_H, BANNER_ICON, CHIP_GAP, MAX_CHIPS = 84, 60, 12, 5
local function Banner(page)
    local w = O.PAGE_W
    local lines = {}
    local glow = page:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT")
    glow:SetSize(w, BANNER_H)
    glow:SetTexture(UI.FADE)
    for i, y in ipairs({ 0, 1 - BANNER_H }) do
        local line = page:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
        line:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, y)
        lines[i] = line
    end

    local icon = page:CreateTexture(nil, "ARTWORK")
    icon:SetSize(BANNER_ICON, BANNER_ICON)
    icon:SetPoint("LEFT", page, "TOPLEFT", 12, -BANNER_H / 2)
    icon:SetTexture(FP.ICON)
    local title = UI:Text(page, 4)
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 2)
    title:SetText("ProfessionsForever")
    title:SetTextColor(1, 0.82, 0)
    local version = UI:Text(page, -1, "RIGHT")
    version:SetPoint("TOPRIGHT", page, "TOPRIGHT", -10, -8)
    version:SetText("v" .. (C_AddOns.GetAddOnMetadata("ProfessionsForever", "Version") or "?"))
    version:SetTextColor(0.6, 0.6, 0.6)
    local welcome = UI:Text(page, 0)
    welcome:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    local name = FP.Alts:PlayerName()
    local r, g, b = FP.Alts:ClassColor(select(2, UnitClass("player")))
    welcome:SetText(L["Welcome back, %s"]:format(RGBToColorCode(r, g, b) .. name .. "|r"))

    local chips = {}
    for i = 1, MAX_CHIPS do
        local chip = CreateFrame("Frame", nil, page)
        chip:SetHeight(18)
        chip:EnableMouse(true) -- for its tooltip
        chip.icon = chip:CreateTexture(nil, "ARTWORK")
        chip.icon:SetSize(16, 16)
        chip.icon:SetPoint("LEFT")
        chip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        chip.text = UI:Text(chip, -1)
        chip.text:SetPoint("LEFT", chip.icon, "RIGHT", 4, 0)
        chip.text:SetTextColor(0.85, 0.85, 0.85)
        UI:Tooltip(chip, "ANCHOR_BOTTOM", function(tip)
            if not chip.prof then return false end
            tip:AddLine(chip.prof.name)
            tip:AddLine(("%d / %d"):format(chip.prof.rank or 0, chip.prof.maxRank or 0), 0.8, 0.8, 0.8)
        end)
        chips[i] = chip
    end

    refreshers[#refreshers + 1] = function()
        local a = UI:GetAccent()
        glow:SetVertexColor(a[1], a[2], a[3], 0.32)
        for _, line in ipairs(lines) do line:SetColorTexture(a[1], a[2], a[3], 0.8) end
        -- Each chip is as wide as its icon and text; when they don't all fit beside the icon, the skill shows alone.
        local profs = FP:GetProfessions()
        local room = w - (12 + BANNER_ICON + 12) - 10
        local function Place(short)
            local x = 0
            for i, chip in ipairs(chips) do
                local p = profs[i]
                chip.prof = p
                chip:SetShown(p ~= nil)
                if p then
                    chip.icon:SetTexture(p.icon)
                    chip.text:SetText(short and tostring(p.rank or 0) or ("%d/%d"):format(p.rank or 0, p.maxRank or 0))
                    local cw = 20 + math.ceil(chip.text:GetStringWidth())
                    chip:SetWidth(cw)
                    chip:ClearAllPoints()
                    chip:SetPoint("TOPLEFT", welcome, "BOTTOMLEFT", x, -5)
                    x = x + cw + CHIP_GAP
                end
            end
            return x - CHIP_GAP <= room
        end
        if not Place(false) then Place(true) end
    end
    refreshers[#refreshers]()
    page.y = -BANNER_H - 8
end

-- A category's own page: a link to each page under it, with a line on what it holds.
local function BuildLinks(page, cat)
    if cat.banner then Banner(page) end
    O.Section(page, L[cat.label])
    for _, child in ipairs(cat.children) do
        local row = CreateFrame("Button", nil, page)
        row:SetPoint("TOPLEFT", 0, page.y)
        row:SetPoint("RIGHT", page, "RIGHT", 0, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnClick", function()
            UI.TabSound()
            O:Select(child.key)
        end)
        local name = UI:Text(row, 1)
        name:SetPoint("TOPLEFT", 8, -6)
        name:SetText(L[child.label])
        name:SetTextColor(0.4, 0.75, 1)
        local integration = O.Integration(child.key)
        if integration then
            local status = UI:Text(row, -1)
            status:SetPoint("LEFT", name, "RIGHT", 10, 0)
            refreshers[#refreshers + 1] = function() status:SetText(O.StatusText(integration.loaded())) end
            refreshers[#refreshers]()
        end
        local desc = UI:Text(row, -1)
        desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
        desc:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        desc:SetJustifyH("LEFT")
        desc:SetTextColor(0.7, 0.7, 0.7)
        desc:SetText(L[integration and integration.adds or child.desc])
        local h = 6 + math.ceil(name:GetStringHeight()) + 3 + math.ceil(desc:GetStringHeight()) + 6
        row:SetHeight(h)
        page.y = page.y - h - 4
    end
end

-- Resets every page under a category.
local function ResetCategory(cat)
    for _, child in ipairs(cat.children) do
        if child.reset then child.reset() end
    end
end

-- Two clicks, because a reset can't be undone; the second must follow within a few seconds.
local function ResetButton(parent, label, w, onConfirm)
    return UI:Button(parent, label, w, 24, function(s)
        if not s.confirming then
            s.confirming = true
            s.text:SetText(L["Click again to confirm"])
            C_Timer.After(4, function()
                s.confirming = false
                s.text:SetText(label)
            end)
            return
        end
        s.confirming = false
        s.text:SetText(label)
        onConfirm()
        O:Refresh()
    end)
end

-- Places the list's rows: every top-level entry, and the pages of the open category under it.
local function LayoutNav()
    local y = 0
    for _, page in ipairs(PAGES) do
        local shown = not page.parent or page.parent == O.open
        page.nav:SetShown(shown)
        if shown then
            page.nav:ClearAllPoints()
            page.nav:SetPoint("TOPLEFT", 12 + (page.parent and SUB_INDENT or 0), PAGE_TOP - y)
            y = y + (page.parent and SUB_ROW_H or NAV_ROW_H)
        end
        if page.cat then page.nav.sign:SetText(O.open == page.key and "-" or "+") end
    end
end

-- Shows a page, opening the category it is in (or that it is); a plain top-level page closes the open one.
function O:Select(key)
    local page = BY_KEY[key]
    self.tab = key
    self.open = page.parent or (page.cat and key) or nil
    for _, p in ipairs(PAGES) do p.frame:SetShown(p.key == key) end
    LayoutNav()
    self:RefreshNav()
    FP.Tooltips.Preview:Sync(page) -- the tooltip previewer docks beside the Tooltips pages
end

-- The selected page's row is marked, and so is its category's while that is closed.
function O:RefreshNav()
    local accent = UI:GetAccent()
    local tab = BY_KEY[self.tab]
    for _, page in ipairs(PAGES) do
        local sel = page == tab or (tab and tab.parent == page.key and self.open ~= page.key)
        page.nav.bar:SetShown(sel)
        page.nav.bar:SetColorTexture(accent[1], accent[2], accent[3])
        if sel then page.nav.text:SetTextColor(1, 0.82, 0) else page.nav.text:SetTextColor(1, 1, 1) end
    end
end

-- A category's row opens it on its links page; when it is open already, it closes and its links page shows.
local function NavClick(page)
    UI.TabSound()
    local closing = page.cat and O.open == page.key
    O:Select(page.key)
    if closing then
        O.open = nil
        LayoutNav()
        O:RefreshNav()
    end
end

local function BuildNav(p, page)
    local sub = page.parent ~= nil
    local b = UI:Button(p, L[page.label], NAV_W - (sub and SUB_INDENT or 0), sub and 22 or 28, function() NavClick(page) end)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", 12, 0)
    b.text:SetPoint("RIGHT", -18, 0)
    b.text:SetJustifyH("LEFT")
    if page.cat then
        b.sign = UI:Text(b, 0, "RIGHT")
        b.sign:SetPoint("RIGHT", -8, 0)
    end
    b.bar = b:CreateTexture(nil, "OVERLAY")
    b.bar:SetWidth(3)
    b.bar:SetPoint("TOPLEFT", 1, -1)
    b.bar:SetPoint("BOTTOMLEFT", 1, 1)
    page.nav = b
end

function O:Init()
    local p = CreateFrame("Frame", "ProfessionsForeverOptionsFrame", UIParent, "BackdropTemplate")
    self.frame = p
    p:SetSize(WIDTH, MIN_HEIGHT)
    p:SetPoint("CENTER")
    p:SetFrameStrata("FULLSCREEN_DIALOG") -- above the main window and Blizzard's Settings panel
    p:SetMovable(true)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    p.fpOpaque = true
    UI:Skin(p, "window")
    tinsert(UISpecialFrames, "ProfessionsForeverOptionsFrame")

    local titleBar = CreateFrame("Frame", nil, p)
    titleBar:SetPoint("TOPLEFT", 4, -2)
    titleBar:SetPoint("TOPRIGHT", -4, -2)
    titleBar:SetHeight(UI.TITLE_H - 4)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() p:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
    local title = UI:Text(titleBar, 2)
    title:SetPoint("LEFT", 10, 0)
    title:SetText("ProfessionsForever")
    title:SetTextColor(1, 0.82, 0)
    local close = UI:Button(titleBar, "X", 22, 20, function() p:Hide() end)
    close:SetPoint("RIGHT", -2, 0)

    local divider = p:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.12)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", NAV_W + 18, PAGE_TOP)
    divider:SetPoint("BOTTOMLEFT", NAV_W + 18, 12)

    local tallest, topRows, mostChildren = MIN_HEIGHT, 0, 0
    for _, page in ipairs(PAGES) do
        BuildNav(p, page)
        if not page.parent then topRows = topRows + 1 end
        if page.cat then mostChildren = math.max(mostChildren, #page.children) end
        local f = CreateFrame("Frame", nil, p)
        f:SetPoint("TOPLEFT", PAGE_LEFT, PAGE_TOP)
        f:SetPoint("BOTTOMRIGHT", -16, 12)
        f.y = 0
        page.frame = f
        if page.cat then BuildLinks(f, page) else page.build(f) end
        local reset = page.cat and function() ResetCategory(page) end or page.reset
        if reset then
            ResetButton(f, L[page.cat and "Reset This Category" or "Reset This Page"], 150, reset)
                :SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        end
        tallest = math.max(tallest, 56 - f.y) -- top gap, content, bottom gap
    end
    -- Tall enough for the list on the left with its longest category open, and the Reset All Options button under it.
    local navH = topRows * NAV_ROW_H + mostChildren * SUB_ROW_H
    p:SetHeight(math.max(tallest, -PAGE_TOP + navH + 12 + 24 + 12))

    ResetButton(p, L["Reset All Options"], NAV_W, function() FP:ResetOptions() end):SetPoint("BOTTOMLEFT", 12, 12)

    self:Select(self.tab or PAGES[1].key)
    p:Hide()
    -- Set after the first Hide so building the window makes no sound. Refresh because the EllesmereUI
    -- skin can be adopted at login after this window was built.
    p:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
        O:Refresh()
        O:RefreshNav()
        FP.Tooltips.Preview:Sync(BY_KEY[O.tab])
    end)
    p:SetScript("OnHide", function()
        UI.CloseMenu()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    end)
    self:RegisterSettings()
end

function O:Open()
    if not self.frame then self:Init() end
    self.frame:Show()
end

function O:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Open() end
end
