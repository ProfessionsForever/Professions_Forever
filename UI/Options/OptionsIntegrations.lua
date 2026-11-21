local _, FP = ...
local L = FP.L
local UI = FP.UI
local O = FP.Options
local refreshers = O.refreshers

-- Settings that depend on other addons: a page for each addon under the Integrations category of the options list,
-- whose own page links to them with what each adds and whether it is installed (UI/Options/Options.lua). A switch is
-- greyed out while its addon isn't loaded. New features that use another addon put their options on that addon's page.

local function Loaded(...)
    for i = 1, select("#", ...) do
        if C_AddOns.IsAddOnLoaded((select(i, ...))) then return true end
    end
    return false
end

-- The supported addons: key (its page), name, whether it is loaded, and what it adds.
local ADDONS = {
    { key = "int_auctionator", name = "Auctionator", loaded = function() return Loaded("Auctionator") end,
        adds = "Prices for recipe profit, crafting costs, the shopping list and disenchant values. Your shopping list as an Auctionator list, kept in sync." },
    { key = "int_waypoints", name = "Polestar & TomTom", loaded = function() return _G.Polestar ~= nil or _G.TomTom ~= nil end,
        adds = "Waypoints and the arrow to vendors, trainers and bankers." },
    { key = "int_questie", name = "Questie", loaded = function() return Loaded("Questie", "QuestieDB") end,
        adds = "More vendor, trainer and banker locations for waypoints." },
    { key = "int_syndicator", name = "Syndicator", loaded = function() return Loaded("Syndicator") end,
        adds = "Your bank and your other characters' bags, bank and mail, as Syndicator records them." },
    { key = "int_skillup", name = "SkillUp Forever", loaded = function() return FP.SkillUpPanel:Available() end,
        adds = "The Skill Up Route window, footer cell and quick button." },
    { key = "int_ellesmere", name = "EllesmereUI", loaded = function() return _G.EllesmereUI ~= nil end,
        adds = "The EllesmereUI skin, and docking beside its bank window." },
}

local function ByKey(key)
    for _, a in ipairs(ADDONS) do
        if a.key == key then return a end
    end
end
-- The supported addon whose page has this key ({ name, loaded, adds }), for its link on the Integrations page.
O.Integration = ByKey

-- "Installed" in green or "Not installed" in grey.
local function StatusText(loaded)
    return loaded and ("|cff33e633" .. L["Installed"] .. "|r") or ("|cff808080" .. L["Not installed"] .. "|r")
end
O.StatusText = StatusText

-- A sub-page's top: the addon's name, whether it is installed, and what it adds.
local function Header(page, a)
    local title = UI:Text(page, 3)
    title:SetPoint("TOPLEFT", page, "TOPLEFT", 0, page.y)
    title:SetText(a.name)
    title:SetTextColor(1, 0.82, 0)
    local status = UI:Text(page, 0)
    status:SetPoint("LEFT", title, "RIGHT", 10, 0)
    status:SetText(StatusText(a.loaded()))
    local adds = UI:Text(page, -1)
    adds:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    adds:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    adds:SetJustifyH("LEFT")
    adds:SetTextColor(0.75, 0.75, 0.75)
    adds:SetText(L[a.adds])
    page.y = page.y - math.ceil(title:GetStringHeight()) - 6 - math.ceil(adds:GetStringHeight()) - 12
end

-- A checkbox for one of the addon's settings, with a tooltip saying what it does.
local function AddonCheck(page, label, loaded, get, set, tip)
    local cb = O.Check(page, label, get, set)
    if not loaded then
        cb:Disable()
        cb.label:SetTextColor(0.5, 0.5, 0.5)
    end
    UI:Tooltip(cb, "ANCHOR_RIGHT", function(t)
        t:AddLine(label, 1, 1, 1)
        t:AddLine(tip, 0.8, 0.8, 0.8, true)
    end)
    return cb
end

-- Prices feed the recipe list, the recipe panel, the shopping list and the footer. "prices" redraws the main window
-- in full, which re-sorts the list (the Profit sort) and keeps its scroll position.
local function PricesChanged()
    FP.Prices:WatchScans() -- the Use Auctionator switch may just have been turned on
    FP:Changed("plan")
    FP:Changed("prices")
end

---------------------------------------------------------------------------
-- One page per addon
---------------------------------------------------------------------------
function O.BuildIntAuctionator(page)
    local db, a = FP.db, ByKey("int_auctionator")
    Header(page, a)
    AddonCheck(page, L["Use Auctionator's Prices"], a.loaded(),
        function() return db.useAuctionator end, function(v) db.useAuctionator = v PricesChanged() end,
        L["Auction and vendor prices for recipe profit, crafting costs and the shopping list total. Off: no prices are shown."])
    AddonCheck(page, L["Price Crafted Reagents by Crafting Cost"], a.loaded(),
        function() return db.priceCrafted end, function(v) db.priceCrafted = v PricesChanged() O:Refresh() end,
        L["A reagent one of your recipes makes, like Bolt of Silk Cloth, is priced at what its own reagents cost when that is cheaper than buying it. Off: vendor and auction prices only."])
    -- Does nothing while crafting costs are off, so it is shown unticked and greyed then; its own setting is kept.
    local alts = AddonCheck(page, L["Include Recipes Your Other Characters Know"], a.loaded(),
        function() return db.priceCrafted and db.priceCraftedAlts end, function(v) db.priceCraftedAlts = v PricesChanged() end,
        L["A reagent is also priced at its crafting cost when one of your other characters knows the recipe, not just this character, for example a Bolt of Silk Cloth your tailor alt could make from cloth you buy. A character counts once you've logged in on them with ProfessionsForever, unless it is switched off under Alt Inventory or is of the other faction. Needs Price Crafted Reagents by Crafting Cost."])
    refreshers[#refreshers + 1] = function()
        local active = a.loaded() and db.priceCrafted and true or false
        alts:SetEnabled(active)
        alts.label:SetAlpha(active and 1 or 0.4)
    end
    refreshers[#refreshers]()
    AddonCheck(page, L["Show How Old Auction Prices Are"], a.loaded(),
        function() return db.priceAge end, function(v) db.priceAge = v FP:Changed("prices") O:Refresh() end,
        L["\"Auction Scan: 2h Ago\" in the shopping list, Crates and Writs, Disenchanting Mode and the recipe panel's cost and profit tooltips, from Auctionator's last full scan. A single price Auctionator last saw too long ago is marked \"(3 Days Old)\"."])
    local stale = O.Slider(page, "ProfessionsForeverOptPriceStale", L["Prices Are Old After"], 1, 168, 1,
        function() return db.priceStaleHours end, function(v)
            db.priceStaleHours = v
            FP:Changed("prices")
        end, function(v) return FP.Cooldowns.Format(v * 3600) end)
    UI:Tooltip(stale, "ANCHOR_RIGHT", L["The scan's age turns red once it is older than this, and single prices older than this are marked. A single price's age is known in whole days."])
    refreshers[#refreshers + 1] = function()
        local active = a.loaded() and db.priceAge and true or false
        stale:SetEnabled(active)
        stale.label:SetAlpha(active and 1 or 0.4)
    end
    refreshers[#refreshers]()
    AddonCheck(page, L["Keep Auctionator's Shopping List in Sync"], a.loaded(),
        function() return db.syncAuctionator end, function(v) db.syncAuctionator = v FP:Changed("shop") end,
        L["Auctionator's shopping list named ProfessionsForever always holds what is still to buy, with the amounts, and updates as you queue, craft and buy. Off: the list in Auctionator is left as it is."])
    AddonCheck(page, L["Skip Disenchant Tooltips When Auctionator Shows Its Own"], a.loaded(),
        function() return db.deTooltipAuctionator end, function(v) db.deTooltipAuctionator = v end,
        L["While Auctionator's \"Disenchant prices\" tooltip setting is on, ProfessionsForever leaves its disenchant lines off item tooltips, so they aren't shown twice. Off: both are shown."])
end

function O.ResetIntAuctionator()
    O.ResetKeys("useAuctionator", "priceAge", "priceStaleHours", "priceCrafted", "priceCraftedAlts", "syncAuctionator", "deTooltipAuctionator")
    PricesChanged()
end

function O.BuildIntWaypoints(page)
    local db, a = FP.db, ByKey("int_waypoints")
    Header(page, a)
    local status = UI:Text(page, -1)
    status:SetPoint("TOPLEFT", page, "TOPLEFT", 8, page.y - 4)
    status:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    status:SetJustifyH("LEFT")
    refreshers[#refreshers + 1] = function()
        local text, ok = FP.Waypoint:NavigatorStatus()
        status:SetText(text)
        if ok then status:SetTextColor(0.8, 0.8, 0.8) else status:SetTextColor(1, 0.6, 0.2) end
    end
    refreshers[#refreshers]()
    page.y = page.y - 36
    AddonCheck(page, L["Print Multi-Step Polestar Routes to Chat"], _G.Polestar ~= nil,
        function() return db.printRoutes end, function(v) db.printRoutes = v end,
        L["When ProfessionsForever sets a waypoint and Polestar's route there has more than one step (a flight, a boat, the Hearthstone), the steps are printed to chat."])
end

function O.ResetIntWaypoints() O.ResetKeys("printRoutes") end

function O.BuildIntQuestie(page)
    local db, a = FP.db, ByKey("int_questie")
    Header(page, a)
    AddonCheck(page, L["Use Questie's NPC Database"], a.loaded(),
        function() return db.useQuestie end, function(v) db.useQuestie = v end,
        L["Questie's NPC database for vendor, trainer and banker waypoints. Off: only the NPCs that ship with ProfessionsForever and the ones you have opened are used."])
end

function O.ResetIntQuestie() O.ResetKeys("useQuestie") end

function O.BuildIntSyndicator(page)
    local db, a = FP.db, ByKey("int_syndicator")
    Header(page, a)
    AddonCheck(page, L["Use Syndicator's Inventory Data"], a.loaded(),
        function() return db.useSyndicator end, function(v) db.useSyndicator = v O:Refresh() end,
        L["Your bank and your other characters' bags and bank, as Syndicator records them. Off: ProfessionsForever records each character itself when you log in on it. Takes a UI reload."])
    local reload = UI:Button(page, L["Reload UI"], 100, 22, function() ReloadUI() end)
    reload:SetPoint("RIGHT", page, "TOPRIGHT", 0, page.y + O.ROW_H / 2)
    refreshers[#refreshers + 1] = function()
        -- Shown while the switch differs from what this session read at login.
        reload:SetShown(a.loaded() and (db.useSyndicator and true or false) ~= FP.Alts:UsesSyndicator())
    end
    refreshers[#refreshers]()
end

function O.ResetIntSyndicator() O.ResetKeys("useSyndicator") end

function O.BuildIntSkillUp(page)
    local db, a = FP.db, ByKey("int_skillup")
    Header(page, a)
    AddonCheck(page, L["Skill Up Route in the Footer"], a.loaded(),
        function() return db.footerSkillUp end, function(v) db.footerSkillUp = v UI:LayoutFooter() end,
        L["The footer cell with SkillUp Forever's next levelling step. The route window still opens with /pf route."])
    AddonCheck(page, L["Skill Up Route Quick Button"], a.loaded(),
        function() return db.quickSkillUp end, function(v) db.quickSkillUp = v FP.Launcher:Update() end,
        L["A button on the quick buttons that opens SkillUp Forever's levelling route."])
end

function O.ResetIntSkillUp()
    O.ResetKeys("footerSkillUp", "quickSkillUp")
    FP.Launcher:Update()
    UI:LayoutFooter()
end

-- Nothing to switch: the skin is picked on the Appearance page, and docking beside its bank window just happens.
function O.BuildIntEllesmere(page)
    local a = ByKey("int_ellesmere")
    Header(page, a)
    local note = UI:Text(page, 0)
    note:SetPoint("TOPLEFT", page, "TOPLEFT", 8, page.y)
    note:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    note:SetJustifyH("LEFT")
    note:SetTextColor(0.8, 0.8, 0.8)
    note:SetText(L["Pick the EllesmereUI skin on the Appearance page. With EllesmereUI's bags, the side windows dock beside its bank window while the main window is closed. There is nothing to set here."])
    page.y = page.y - math.ceil(note:GetStringHeight()) - 8
end
