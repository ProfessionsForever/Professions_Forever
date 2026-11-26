local _, FP = ...
local L = FP.L
local UI = FP.UI
local O = FP.Options

-- The options window's pages that the other Options files don't build, and the list of every page. The window itself,
-- its controls and the Appearance pages are the shared library's (Libs/ThreeLightsLib/Options.lua).

-- Puts the named options back to their defaults; each page's reset names its own.
function O.ResetKeys(...)
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        FP.db[key] = FP.defaults[key]
    end
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
    O.Check(page, L["Show Skill Up Chance in the Recipe List and Queue"], function() return db.showSkillChance end, function(v)
        db.showSkillChance = v
        UI:UpdateList()
        FP.Queue:Update()
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
    UI:Tooltip(camp, L["The Camp cell along the bottom of the main window. Off: the window still opens from its quick button or /pf camp."])
    local orders = O.Check(page, L["Show Crates and Writs in the Footer"], function() return db.footerOrders end, function(v)
        db.footerOrders = v
        UI:LayoutFooter()
    end)
    UI:Tooltip(orders, L["The Crates and Writs cell along the bottom of the main window. Off: the window still opens from its quick button or /pf crates."])
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
    UI:Tooltip(scope, L["Share one list between all your characters of the same faction, so a different character can do the buying. The other faction has its own, since items can't be mailed across."])
    local confirm = O.Check(page, L["Confirm Before Buy List Buys"], function() return db.confirmVendorBuy end, function(v)
        db.confirmVendorBuy = v
    end)
    UI:Tooltip(confirm, L["The Buy List button on a vendor's window asks first, listing what it will buy and the total."])
end

local function ResetShopping()
    O.ResetKeys("shoppingScope", "confirmVendorBuy")
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
-- Recipe Scout (Core/ZoneRecipes.lua)
---------------------------------------------------------------------------
-- { setting, label, what it does }: the window opening by itself, then one switch per kind of recipe it lists.
local ZONE_CHECKS = {
    { "zoneRecipes", "Open When You Enter a Zone", "Opens the window once per zone each session, when the zone has a recipe you have not learned. Off: only /pf scout opens it." },
    { "zonePinned", "Pin the Window", "A pinned window stays open, lists each zone you enter, and does not close when you press Escape. The pin on the window does the same." },
    { "zoneVendors", "Recipes Sold by Vendors", "Lists the recipes a vendor in the zone sells." },
    { "zoneLimited", "Recipes in Limited Supply", "Lists the recipes a vendor in the zone sells in a limited supply, which may be sold out." },
    { "zoneTrainers", "Recipes Taught by Trainers", "Lists the recipes a trainer in the zone teaches, once your skill is high enough to learn them." },
    { "zoneQuests", "Recipes from Quests", "Lists the recipes a quest given in the zone rewards, when you can take the quest and have not done it." },
    { "zoneHeld", "Recipes You Already Have", "Lists the recipes whose item is in your bags, your bank or your mailbox, waiting to be learned." },
}

local function BuildZone(page)
    local db = FP.db
    O.Section(page, L["Recipe Scout"])
    for i, c in ipairs(ZONE_CHECKS) do
        if i == 3 then O.Section(page, L["What It Lists"]) end
        local key = c[1]
        local cb = O.Check(page, L[c[2]], function() return db[key] end, function(v)
            db[key] = v
            if key == "zonePinned" then FP.ZoneRecipes:PinChanged() else FP.ZoneRecipes:Refresh() end
        end)
        UI:Tooltip(cb, L[c[3]])
    end
    local scope = O.DropList(page, L["Drops"], function() return FP.ZoneRecipes:DropScopeLabel() end,
        function() return FP.ZoneRecipes:DropScopeItems() end)
    UI:Tooltip(scope, L["Which of the recipes that creatures drop and that chests and other objects hold are listed. Zone Drops Only leaves out the recipes that also drop in other zones or in a dungeon."])
end

local function ResetZone()
    for _, c in ipairs(ZONE_CHECKS) do O.ResetKeys(c[1]) end
    O.ResetKeys("zoneDropScope", "zoneShowIgnored", "zonePos") -- the window goes back above the middle of the screen
    wipe(FP.chardb.zoneIgnored) -- this character's ignored recipes are listed again
    FP.UI:RefreshZonePin()
    FP.ZoneRecipes:Refresh()
end

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
    UI:Tooltip(record, L["Each time any of your characters disenchants an item, what it gave is saved, to check the chances against what Forever really drops."])
    local observed = O.Check(page, L["Show Seen Rates"], function() return db.deShowObserved end, function(v)
        db.deShowObserved = v
        UI:UpdateDisenchantMode()
    end)
    UI:Tooltip(observed, L["Under each disenchant result's chance, in Disenchanting Mode and on item tooltips with every result shown: how often your characters really got it from that kind of item. Grayed and marked unreliable until 100 disenchants of that kind are recorded."])
    local main = O.DropList(page, L["Main Enchanter"], function() return FP.Disenchant:MainEnchanterLabel() end, function()
        local items = { { text = L["Automatic (Highest Skill)"], checked = db.mainEnchanter == nil,
            onSelect = function() FP.Disenchant:SetMainEnchanter(nil) end } }
        for _, e in ipairs(FP.Disenchant:Enchanters()) do
            items[#items + 1] = { text = ("%s (%d)"):format(FP.Alts:Label(e.rec), e.rank), checked = db.mainEnchanter == e.key,
                onSelect = function() FP.Disenchant:SetMainEnchanter(e.key) end }
        end
        return items
    end)
    UI:Tooltip(main, L["The character your other characters send gear to for disenchanting: the quick button, /pf de and the Overview's icon open Disenchanting Mode for them first. Automatic picks the one with the highest Enchanting skill. Characters of the other faction can't be mailed, so they come last whatever is picked here."])
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
    UI:Tooltip(deposit, L["The best choice, in Disenchanting Mode and on item tooltips, is only Sell It at Auction when that beats the others by more than this listing's deposit: what you lose if it doesn't sell. The deposit is 5%, 20% or 60% of the vendor price for 2, 8 or 24 hours at a faction auction house."])
end

local function ResetDisenchanting()
    O.ResetKeys("deRecord", "deShowObserved", "mainEnchanter", "deDeposit")
    UI:UpdateDisenchantMode(true)
    FP.Launcher:Update() -- the main enchanter is back to Automatic
end

-- The General page's banner: an accent-colored glow that fades to the right between two accent lines (UI.FADE,
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
        UI.TrimIcon(chip.icon)
        chip.text = UI:Text(chip, -1)
        chip.text:SetPoint("LEFT", chip.icon, "RIGHT", 4, 0)
        chip.text:SetTextColor(0.85, 0.85, 0.85)
        UI:Tooltip(chip, function(tip)
            if not chip.prof then return false end
            tip:AddLine(chip.prof.name)
            tip:AddLine(("%d / %d"):format(chip.prof.rank or 0, chip.prof.maxRank or 0), 0.8, 0.8, 0.8)
        end, "ANCHOR_BOTTOM")
        chips[i] = chip
    end

    O.AddRefresher(function()
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
    end)
    page.y = -BANNER_H - 8
end

---------------------------------------------------------------------------
-- The page list
---------------------------------------------------------------------------
-- Top-level entries are plain pages, or categories (cat) whose own page links to the pages under them (parent).
-- A category opens in the list when clicked, one at a time. desc is the line under a page's link; an integration's
-- link takes its description and installed status from UI/Options/OptionsIntegrations.lua instead.
local BY_KEY = {}
local function Page(page)
    BY_KEY[page.key] = page
    page.label = L[page.label]
    local integration = O.Integration(page.key)
    if integration then
        page.desc = L[integration.adds]
        page.status = function() return O.StatusText(integration.loaded()) end
    elseif page.desc then
        page.desc = L[page.desc]
    end
    O:AddPage(page)
end

Page({ key = "general", label = "General", cat = true, banner = Banner })
Page({ key = "main", parent = "general", label = "Main Window", build = BuildMainWindow, reset = ResetMainWindow,
    desc = "Replace Blizzard's professions window, the skill up chance in the recipe list and the minimap button." })
Page({ key = "shopping", parent = "general", label = "Shopping List", build = BuildShopping, reset = ResetShopping,
    desc = "One shopping list for all your characters of a faction, or one each, and whether Buy List asks first." })
Page({ key = "alts", parent = "general", label = "Alt Inventory", build = BuildAlts, reset = ResetAlts,
    desc = "Whether your other characters' bags and banks count toward what you need, and which characters." })
Page({ key = "notifications", parent = "general", label = "Notifications", build = BuildNotifications,
    reset = ResetNotifications,
    desc = "Ready cooldowns at login, and opening the Transfer Planner at your bank or a mailbox." })
Page({ key = "zone", parent = "general", label = "Recipe Scout", build = BuildZone, reset = ResetZone,
    desc = "The window that lists the recipes you can learn in the zone you enter, and which kinds it lists." })
O:AddAppearancePages()
Page({ key = "quickbuttons", label = "Quick Buttons", cat = true })
Page({ key = "quick", parent = "quickbuttons", label = "Buttons", build = O.BuildQuick, reset = O.ResetQuick,
    desc = "The movable bar of buttons for the queue, shopping list, transfer planner, cooldowns and professions." })
Page({ key = "quickkeys", parent = "quickbuttons", label = "Key Bindings", build = O.BuildQuickKeys,
    desc = "Key bindings for each quick button and profession, set here or with Mouseover Keybinding." })
Page({ key = "de", label = "Disenchanting", build = BuildDisenchanting, reset = ResetDisenchanting })
Page({ key = "tooltips", label = "Tooltips", cat = true })
Page({ key = "tt_general", parent = "tooltips", label = "General", build = O.BuildTipGeneral, reset = O.ResetTipGeneral,
    desc = "The detail key, spacing, indent and the order of the blocks." })
Page({ key = "tt_queue", parent = "tooltips", label = "Queues & Shopping", build = O.BuildQueueTooltips,
    reset = O.ResetQueueTooltips,
    desc = "How many of an item your queues need, how many are still to buy, and which recipes use it." })
Page({ key = "tt_alts", parent = "tooltips", label = "Alts and Transfers", build = O.BuildTipAlts, reset = O.ResetTipAlts,
    desc = "Who else holds an item, what they should send, and what is still to buy." })
Page({ key = "tt_hints", parent = "tooltips", label = "Prices and Hints", build = O.BuildTipHints, reset = O.ResetTipHints,
    desc = "The auction price line, click hints and where a vendor sells it." })
Page({ key = "tt_recipes", parent = "tooltips", label = "Recipes", build = O.BuildTipRecipes, reset = O.ResetTipRecipes,
    desc = "Where a recipe is learned from, even once you know it." })
Page({ key = "tt_disenchant", parent = "tooltips", label = "Disenchant Results", build = O.BuildDisenchantTooltips,
    reset = O.ResetDisenchantTooltips,
    desc = "What disenchanting gear gives: when it shows, how much, and for which characters." })
Page({ key = "tt_orders", parent = "tooltips", label = "Crates and Writs", build = O.BuildTipOrders, reset = O.ResetTipOrders,
    desc = "What a Waylaid Crate pays and the cheapest way to fill it; what a Craftsman's Writ's item costs you." })
Page({ key = "fishing", label = "One-Click Fishing", build = O.BuildFishing, reset = O.ResetFishing })
Page({ key = "integrations", label = "Integrations", cat = true })
Page({ key = "int_auctionator", parent = "integrations", label = "Auctionator", build = O.BuildIntAuctionator,
    reset = O.ResetIntAuctionator })
Page({ key = "int_waypoints", parent = "integrations", label = "Polestar & TomTom", build = O.BuildIntWaypoints,
    reset = O.ResetIntWaypoints })
Page({ key = "int_questie", parent = "integrations", label = "Questie", build = O.BuildIntQuestie, reset = O.ResetIntQuestie })
Page({ key = "int_syndicator", parent = "integrations", label = "Syndicator", build = O.BuildIntSyndicator,
    reset = O.ResetIntSyndicator })
Page({ key = "int_skillup", parent = "integrations", label = "SkillUp Forever", build = O.BuildIntSkillUp,
    reset = O.ResetIntSkillUp })
Page({ key = "int_ellesmere", parent = "integrations", label = "EllesmereUI", build = O.BuildIntEllesmere })
Page({ key = "about", label = "About", build = O.BuildAbout })

-- The tooltip previewer docks beside the Tooltips pages, so it follows the page shown (the window shows its page
-- through O:Select when it opens, too).
local Select = O.Select
function O:Select(key)
    Select(self, key)
    FP.Tooltips.Preview:Sync(BY_KEY[self.tab])
end

-- The window is also listed in Blizzard's Settings panel, once built.
local Init = O.Init
function O:Init()
    Init(self)
    self:RegisterSettings()
end
