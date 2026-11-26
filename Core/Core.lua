--[[
ProfessionsForever - WoW: Forever (Interface 16001)

NOTES ON API USAGE
  * Recipes: C_TradeSkillUI.GetAllRecipeIDs / GetRecipeInfo / GetRecipeSchematic (modern; the
    Classic Era index-based TradeSkill functions are NOT used).
  * Reagents: only Enum.CraftingReagentType.Basic slots count, by their first item ID.
  * Bank: the client only knows bank contents while the bank is open, so the bank is scanned
    on open/change and cached per character in SavedVariables.
]]
local addonName, FP = ...
_G.ProfessionsForever = FP
FP.ICON = "Interface\\AddOns\\ProfessionsForever\\Media\\icon" -- keep in sync with IconTexture in the .toc
local L = FP.L

function FP:Print(msg)
    print("|cff33bbffProfessionsForever|r: " .. tostring(msg))
end

-- An item's name, or "item:<id>" until the game has loaded it (GET_ITEM_INFO_RECEIVED then triggers a refresh).
-- GET_ITEM_INFO_RECEIVED can come before GetItemNameByID has the name, and asking again for an item the client thinks
-- it already has sends no second event, so a window could keep "item:<id>" until reopened. So the item's own load
-- callback redraws as well, once per item while it is waited for.
local waiting = {}
function FP.ItemName(itemID)
    local name = C_Item.GetItemNameByID(itemID) or C_Item.GetItemInfo(itemID)
    if name then return name end
    if not waiting[itemID] then
        waiting[itemID] = true
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
            waiting[itemID] = nil
            FP:Changed("items")
        end)
    end
    return "item:" .. itemID
end

---------------------------------------------------------------------------
-- Events (handlers run under xpcall so one error never breaks the others)
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {} -- [event] = { { fn, unit }, ... } in the order registered; `unit` on the list is what the frame asked for
frame:SetScript("OnEvent", function(_, event, ...)
    for _, h in ipairs(handlers[event]) do
        if not h.unit or h.unit == ... then xpcall(h.fn, geterrorhandler(), FP, ...) end
    end
end)

-- Any file may add a handler for an event; they are called as fn(FP, ...) in the order they registered, which is
-- the .toc's load order, so a later file can rely on what an earlier one's handler set. `unit` (optional) limits a
-- unit event to that unit.
function FP:RegisterEvent(name, fn, unit)
    local list = handlers[name]
    if not list then
        list = { unit = unit }
        handlers[name] = list
        if unit then frame:RegisterUnitEvent(name, unit) else frame:RegisterEvent(name) end
    elseif list.unit ~= unit then
        -- Handlers that want different units: take the event for every unit; each keeps its own filter.
        list.unit = nil
        frame:RegisterEvent(name)
    end
    list[#list + 1] = { fn = fn, unit = unit }
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
-- Recipe-list filter presets; used for first run and by the filter reset button.
FP.filterDefaults = { showUnlearned = false, unlearnedOnly = false, hasMatsOnly = false, skillUpsOnly = false, hideTrivial = false, favoritesOnly = false, hideCategories = false }
-- Disenchanting Mode's Filters menu (UI/DisenchantMode.lua): other characters' gear, bank items, each quality, equipment
-- set pieces, and only items worth more disenchanted. Its reset button puts these back.
FP.deFilterDefaults = { deShowOthers = true, deShowBank = true, deShowUncommon = true, deShowRare = true, deShowEpic = true,
    deHideSets = false, deWorthOnly = false }

local defaults = {
    scale = 1, width = 920, height = 640, locked = false,
    point = "TOPLEFT", relPoint = "TOPLEFT", x = 16, y = -104, -- where Blizzard's left-side windows open
    skin = "dark", font = "Fonts\\FRIZQT__.TTF", fontSize = 12, opacity = 0.96,
    recipeDensity = "normal",
    sidePanels = {}, -- ["queue" | "transfer" | "shop" | "cooldowns"] = { point, relPoint, x, y } for panels pinned to a screen position
    altMode = "include", -- other characters' materials: never | show | include (in planning)
    characters = {}, -- [name-realm] = cached bags and bank of each character, see AltInventory.lua
    skipImport = {}, -- [name-realm] = true for Syndicator characters removed from that cache
    transfers = {}, -- [crafter name-realm] = what each alt should send it, see Outgoing.lua
    professionData = {}, -- [skill line] = a profession's category tree, see AltProfessions.lua
    sortKey = "name", sortDesc = false,
    lastRecipe = {}, -- [skill line ID] = the recipe last clicked in that profession
    collapsedCategories = {}, -- [categoryID] = true for recipe-list categories the user collapsed
    trackShopping = false, -- show the shopping list tracker on screen
    replaceDefault = true, shoppingScope = "account", -- one shopping list shared by all your characters (or "char")
    confirmVendorBuy = true, -- the Buy List button on a vendor asks first
    trainerRecipes = {}, -- [recipe spell ID] = "npcId,npcId" of the trainers seen teaching it
    trainers = {}, -- [npc id] = { npc, sub, uiMap, x, y, zone, skill, alliance, horde } for trainers you've opened
    bankers = {}, -- same shape, for bankers whose window you've opened
    vendors = {}, -- same shape plus items = ",itemID,itemID," (their stock, recipe items included), for merchants you've opened
    minimap = { hide = false, angle = 215 },
    quickButtons = false, -- show the movable bar of buttons that open the queue, shopping list, transfer planner and cooldowns
    quickButtonsLocked = false,
    quickProfessions = true, -- a quick button for each profession with a crafting window
    quickOverview = true, -- a quick button opening the main window on its Overview
    quickSettings = false, -- a quick button opening the options
    quickCamp = true, -- the Camp quick button
    quickOrders = true, -- the Crates and Writs quick button
    quickDisenchant = true, -- the Disenchanting Mode quick button (where it applies: an enchanter, or one to send to)
    quickHeader = true, -- the addon name above the quick buttons
    quickLayout = "columns", -- columns | rows: which the quick buttons keep fixed while they grow the other way
    quickColumns = 6, -- fixed columns: quick buttons per row; more rows are added as needed
    quickRows = 1, -- fixed rows: quick buttons per column; more columns are added as needed
    quickGrowX = "right", -- right | left: the side the quick buttons grow toward from the handle
    quickGrowY = "down", -- down | up: the way the quick buttons grow from the handle (Grow From sets both)
    quickShowKeys = true, -- each quick button's key binding in its top left corner
    cooldownNotice = true, -- at login, name the characters with a recipe cooldown ready
    versionNotice = true, -- at login, print the addon version (Core/VersionCheck.lua)
    updateNotice = true, -- say so when another player has a newer version
    bankPrompt = true, -- open the transfer planner at the bank when the queue needs something from it
    mailPrompt = true, -- open the transfer planner at a mailbox when this character has something to send or collect
    zoneRecipes = true, -- entering a zone opens the window of recipes to learn there (Core/ZoneRecipes.lua)
    zonePinned = false, -- that window stays open and follows you from zone to zone; its place is db.zonePos
    zoneVendors = true, -- that window lists vendors' recipes,
    zoneLimited = true, -- vendors' recipes in a limited supply,
    zoneTrainers = true, -- trainers' recipes,
    zoneQuests = true, -- quest rewards,
    zoneShowIgnored = false, -- list the recipes ignored in the zone (chardb.zoneIgnored[uiMap][recipe])
    zoneDropScope = "zone", -- the recipes creatures drop and objects hold in the zone: "all", "zone" (not the ones that also drop in other zones) or "none"
    zoneHeld = true, -- and recipes whose item the character already holds
    showIgnoredCooldowns = false, -- list the cooldowns turned off in the Cooldowns window
    showSkillChance = true, -- the skill up chance beside each learned recipe in the list
    foreverIcon = true, -- the infinity on a recipe new or changed in Forever, in the list and the detail panel
    fishEquipPole = true, -- One-Click Fishing equips the best fishing pole in the bags first (Core/Fishing.lua)
    fishApplyLure = true, -- One-Click Fishing puts the best lure in the bags on the pole first
    fishLureSkipKey = "none", -- held with the Fishing Key, the press leaves the lure off: none | shift | ctrl | alt
    fishLoud = true, -- sound effects louder while the line is out
    fishVolume = 100, -- the sound effects volume then, in percent
    fishMuteMusic = false, -- music and ambience off while the line is out
    fishBackground = false, -- sound on while the game is in the background, while the line is out
    fishCVars = {}, -- [CVar] = the player's own value, while fishing has it changed (Core/Fishing.lua)
    fishSwapMount = true, -- swap the gear One-Click Fishing replaced back on when you mount
    fishSwapIdle = true, -- ... when you haven't fished for fishSwapSeconds
    fishSwapSeconds = 120,
    fishSwapCombat = true, -- ... when combat ends
    -- Integrations: each is used only when its addon is loaded and its switch here is on.
    printRoutes = true, -- print Polestar's route to a ProfessionsForever waypoint when it has more than one step
    useAuctionator = true, -- prices for profit, costs and the shopping list
    syncAuctionator = true, -- keep Auctionator's "ProfessionsForever" shopping list the same as what is still to buy
    priceAge = true, -- how old Auctionator's prices are: the last full scan's age, and a note on a price a day or more old
    priceStaleHours = 24, -- hours after which a scan or a price counts as old
    priceCrafted = true, -- a reagent you can craft is priced at its crafting cost when that is cheapest (Core/Prices.lua)
    priceCraftedAlts = false, -- ... counting recipes your other characters know too
    useQuestie = true, -- Questie's NPC database for vendor, trainer and banker waypoints
    useSyndicator = true, -- Syndicator's bank and other characters' inventory (read at login)
    footerSkillUp = true, -- SkillUp Forever's Skill Up Route cell in the footer
    ahSearchButton = true, -- the recipe panel's Search button while the auction house is open, with Auctionator
    footerOrders = true, -- the Crates and Writs cell in the footer
    footerCamp = true, -- the Camp cell in the footer
    quickSkillUp = true, -- SkillUp Forever's Skill Up Route button on the quick buttons
    deSort = "name", -- Disenchanting Mode's list order: name | level | quality | value
    deSortDesc = false, -- Disenchanting Mode's list order reversed
    deDeposit = 24, -- listing hours whose deposit Sell It at Auction must beat the others by: 0 (not counted) | 2 | 8 | 24
    campCollapsed = { unknown = true }, -- [group] = true for Camp window groups collapsed: "ready", "craft", "alts", "unknown"
    deCollapsed = {}, -- [group] = true for Disenchanting Mode groups the user collapsed: "bags", "bank" or a character key
    -- Crates and Writs (Core/Orders.lua, Panels/Orders.lua)
    orderTab = "held", -- the list the window shows: held (what your characters hold) | crates | writs (worth buying)
    orderCollapsed = {}, -- [group] = true for its groups the user collapsed
    orderTooltip = true, -- the cheapest way to fill it, on a crate's or a writ's item tooltip
    cratePay = {}, -- [Sealed crate item ID] = the least Merchant's Favor a hand-in of it has paid
    writCustomers = {}, -- [writ quest ID] = { name, uiMap, x, y } of the customer, where you handed one in
    writQty = {}, -- [writ quest ID] = how many of its item the writ asks for, as the game said
    -- Tooltips (Tooltips/): the lines the addon adds to item tooltips and to its own windows' item tooltips.
    tipDetailKey = "shift", -- the key that shows the detail (queued recipes, every disenchant result): shift | ctrl | alt
    tipKeyHint = true, -- "Hold Shift for details" while there is detail to show
    tipSpacing = true, -- a blank line before each block
    tipIndent = 3, -- spaces each level of detail is indented by
    tipOrder = "queue,disenchant,alts", -- the blocks' order, top to bottom (a string: a reset can't share a table)
    shopTooltip = true, -- "On Shopping List" on item tooltips, for any item on the list
    queueTooltip = true, -- "Needed by Crafting Queues" on item tooltips
    queueTooltipToBuy = true, -- and "Still to Buy" under them, while short
    queueTooltipMade = true, -- "Made by Queues" under the need, when other queues' crafts cover some of it
    queueTooltipCraftsInto = true, -- "Crafts Into" on an item a known recipe turns into something the queues need
    queueTooltipRecipes = "shift", -- each character's queued recipes that use it: shift (with the detail key) | always | never
    queueTooltipGroup = true, -- the recipes under a header per character; off: one list, alts' names after theirs
    queueTooltipCrafts = true, -- "x40" after each recipe
    queueTooltipShopRows = true, -- the recipes on shopping list rows too
    altTipChars = true, -- a line per other character holding it
    altTipBank = true, -- "(26 bank)" on it
    altTipSend = true, -- "Send 42" on it
    altTipTotal = "multi", -- Available on Enabled Characters: never | multi (2 or more characters) | always
    altTipToBuy = true, -- Still to Buy under the alts
    altTipIgnored = true, -- characters left out of planning, grayed
    tipAuctionPrice = "auto", -- "Auction Price: 25c each": auto (unless Auctionator shows one) | always | never
    tipHints = "line", -- click hints: line (one line) | full (a line per action) | none
    tipVendor = true, -- "Sold by" and the right-click waypoint hint
    tipLearnedSource = false, -- where a learned recipe came from, in the recipe list and the detail panel
    tipRecipePlace = "row", -- the recipe list's tooltip: row (right of the row) | beside (outside the window, level with the row) | corner (outside, level with the list's top row)
    tipRecipeSide = "left", -- the side of the window it is docked on, unless "row": left | right
    tipRecipeShow = "always", -- always | shift (only while the detail key is held)
    deTooltip = true, -- disenchant results on item tooltips
    deTooltipShow = "always", -- always | shift (only while Shift is held)
    deTooltipDetail = "shift", -- terse (one line) | full (every result) | shift (one line, every result with Shift)
    deTooltipNeeds = "any", -- who must know Enchanting for it to show: none | any (character) | self
    deTooltipVerdict = true, -- lead with the best choice: disenchant, vendor or auction
    deTooltipBoundSelf = true, -- leave it off soulbound gear unless this character knows Enchanting
    deRecord = true, -- record what each disenchant gives, in deObserved
    deShowObserved = true, -- show your observed disenchant rates next to the expected ones
    deObserved = {}, -- what your disenchants gave, see Core/DisenchantRecord.lua
    deTooltipAuctionator = true, -- leave it out while Auctionator shows its own disenchant prices
    shopping = {}, -- the shared list from before it was per faction, moved into shoppingFaction at login (Core/Shopping.lua)
    shoppingFaction = {}, -- the shared shopping list, one per faction: [faction] = { [itemID] = needed }
}
FP.defaults = defaults

-- Options saved without a default (nil until the user sets one), which a reset clears: the accent color picked over
-- the skin's own, and where the shopping tracker and the quick buttons were dragged to. One more key has no default
-- and is not an option: euiAdopted, set once EllesmereUI's look has been adopted, so a reset leaves it.
local NO_DEFAULT = { "accent", "trackerPos", "launcherPos", "mainEnchanter" } -- mainEnchanter: nil is Automatic

-- Saved data rather than options, so a reset leaves it alone.
local DATA_KEYS = { trainerRecipes = true, trainers = true, bankers = true, vendors = true, shopping = true, shoppingFaction = true, characters = true, skipImport = true, transfers = true, professionData = true, deObserved = true, fishCVars = true, cratePay = true, writCustomers = true, writQty = true }

local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function FP:LoadSettings()
    FP.freshInstall = ProfessionsForeverDB == nil -- no saved settings yet: What's New stays quiet (UI/WhatsNew.lua)
    ProfessionsForeverDB = ProfessionsForeverDB or {}
    ProfessionsForeverCharDB = ProfessionsForeverCharDB or {}
    Merge(ProfessionsForeverDB, FP.filterDefaults)
    Merge(ProfessionsForeverDB, FP.deFilterDefaults)
    Merge(ProfessionsForeverDB, defaults)
    Merge(ProfessionsForeverCharDB, { shopping = {}, makes = {}, fishSaved = {}, fishWeapons = {}, writsDone = {}, zoneIgnored = {} })
    self.db, self.chardb = ProfessionsForeverDB, ProfessionsForeverCharDB
end

-- Puts every option back to its default and applies it. Learned trainers, bankers and the shopping list stay.
function FP:ResetOptions()
    local db = self.db
    local replaced = db.replaceDefault
    for k in pairs(defaults) do
        if not DATA_KEYS[k] then db[k] = nil end
    end
    for k in pairs(FP.filterDefaults) do db[k] = nil end
    for k in pairs(FP.deFilterDefaults) do db[k] = nil end
    for _, k in ipairs(NO_DEFAULT) do db[k] = nil end
    Merge(db, FP.filterDefaults)
    Merge(db, FP.deFilterDefaults)
    Merge(db, defaults)

    local UI = self.UI
    UI:ResetWindow()
    UI:ApplyLock()
    UI:ApplySkin()
    UI:LayoutFooter()
    self.Minimap:Position()
    self.Minimap:Update()
    self.Launcher:Update()
    if self.Launcher.bar then self.Launcher:Place() end
    self:UpdateBindings()
    if replaced ~= db.replaceDefault then self:Print(L["Changing this needs a UI reload to take full effect."]) end

    local shop = self.Shop
    if shop.tracker then shop:PlaceTracker() end
    shop:UpdateTracker()
    if shop.frame and shop.frame:IsShown() then shop:Update() end
    UI:ReflowSidePanels()
    self:RefreshPlanning()
    self.Options:Refresh()
    self:Print(L["Options reset to defaults."])
end

---------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------
local function Refresh(self) self.UI:QueueRefresh() end
local function Reload(self)
    self.Recipes:Reload()
    self.Chain:Record()
    self.AltProfs:RecordOpen()
    self.Cooldowns:Scan()
    self.UI:QueueRefresh()
end

-- Startup
FP:RegisterEvent("ADDON_LOADED", function(self, name)
    if name == addonName then
        self:LoadSettings()
    elseif name == "Blizzard_Professions" and not InCombatLockdown() then -- else the next TRADE_SKILL_SHOW out of combat hides it
        self:SuppressBlizzard()
    end
end)

FP:RegisterEvent("PLAYER_LOGIN", function(self)
    self.Outgoing:MoveOldTransfers()
    self.Waypoint:MoveOldRecordings()
    self.Shop:MoveOldQueueShare()
    self.Shop:MoveToAccountList() -- after it: that one works on the list as it was
    self.Alts:Init()
    self.Queue:OnLogin()
    self.AltProfs:RecordRanks()
    self.Known:Snapshot()
    self.Options:Init()
    self.Minimap:Init()
    self.Launcher:Update()
    self:UpdateBindings()
    self:HookProfessionButtons()
    self.Shop:UpdateTracker()
    C_Timer.After(3, function() self:HookProfessionButtons() end) -- some UI loads after login
    C_Timer.After(4, function() self.Cooldowns:Probe() end)
    C_Timer.After(6, function() self.Outgoing:Announce() end) -- item names need a moment to load
    C_Timer.After(8, function() self.Cooldowns:Announce() end)
end)

FP:RegisterEvent("UPDATE_BINDINGS", function(self) self:UpdateBindings() end)

-- Trade skill
FP:RegisterEvent("TRADE_SKILL_SHOW", function(self)
    -- Disenchanting Mode lives in this window, so opening Enchanting into it shows this window even when it doesn't replace Blizzard's.
    if not (self.db.replaceDefault or self.UI:DisenchantPending()) or InCombatLockdown() then return end
    self:SuppressBlizzard()
    C_Timer.After(0, function() self:SuppressBlizzard() end) -- frame may be created after this event
    self.AltProfs:Stop() -- one of your own professions opened
    self.UI:Show("recipes")
end)

FP:RegisterEvent("TRADE_SKILL_CLOSE", function(self) self.UI:OnTradeSkillClosed() end)
FP:RegisterEvent("TRADE_SKILL_LIST_UPDATE", Reload)
FP:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", function(self)
    self.UI:ResetCraftQty()
    Reload(self)
end)
FP:RegisterEvent("NEW_RECIPE_LEARNED", function(self)
    self.Known:Snapshot()
    Reload(self)
end)
FP:RegisterEvent("TRADE_SKILL_FAVORITES_CHANGED", Reload)
-- The professions the character has, as one string, to tell a learned or dropped profession from a skill up.
local function ProfessionSet(self)
    local lines = {}
    for i, p in ipairs(self:GetProfessions()) do lines[i] = p.skillLine end
    return table.concat(lines, ",")
end
FP:RegisterEvent("SKILL_LINES_CHANGED", function(self) -- a profession learned, unlearned or skilled up
    local before = ProfessionSet(self)
    self:ForgetProfessions()
    -- An unlearned profession takes its recipes with it; a skill up changes none (NEW_RECIPE_LEARNED covers learning).
    if ProfessionSet(self) ~= before then self.Known:Snapshot() end
    self.AltProfs:RecordRanks()
    self.Queue:Update() -- its skill ups follow the new rank
    Reload(self)
end)
FP:RegisterEvent("TRACKED_RECIPE_UPDATE", Refresh)

-- Bags and bank
FP:RegisterEvent("BAG_UPDATE_DELAYED", function(self)
    if self.Inv.bankOpen then self.Inv:ScanBank() end -- also catches bank tab/slot changes
    self.Inv:ScanBagGear()
    self.Alts:Flush()
    self.Planner:Invalidate()
    self:Changed("inventory")
end)
FP:RegisterEvent("BANKFRAME_OPENED", function(self)
    self.Inv.bankOpen = true
    self.Inv:ScanBank()
    self.Planner:Invalidate()
    self:Changed("inventory")
    self.Waypoint:RememberBanker()
    -- The slots may not be readable the instant the window opens, so the check waits a moment for the scan to settle.
    C_Timer.After(0.5, function()
        if not (self.Inv.bankOpen and self.db.bankPrompt) then return end
        self.Planner:Invalidate()
        self:Changed("inventory")
        if #self.Planner.BankNeeds(self.Queue:TransferNeeds()) > 0 then self.UI:OpenSidePanelFor(self.Transfer, "bank") end
    end)
end)
FP:RegisterEvent("BANKFRAME_CLOSED", function(self)
    self.Inv.bankOpen = false
    self.UI:CloseSidePanelsOpenedBy("bank") -- the Transfer Planner, if the bank opened it
    self:Changed("inventory") -- the Transfer Planner's Withdraw button follows the bank
end)
FP:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function(self)
    if self.Inv.bankOpen then self.Inv:ScanBank() self:Changed("inventory") end
end)
FP:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(self) self:Changed("items") end)
FP:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", Refresh) -- worn tools count toward a recipe's requirements

-- Crafting and combat
-- Crafting consumes reagents; bag counts can lag the cast, so refresh again shortly after.
local function LateRefresh() FP.UI:QueueRefresh() end
FP:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(self, _, _, spellID)
    self.Cooldowns:OnCast(spellID)
    self.UI:OnCraftCast(spellID)
    self.UI:QueueRefresh()
    C_Timer.After(0.6, LateRefresh)
end, "player")
FP:RegisterEvent("UPDATE_TRADESKILL_CAST_STOPPED", function(self) self.UI:EndCraftBatch() end)
FP:RegisterEvent("PLAYER_REGEN_DISABLED", function(self)
    self.UI:CloseSidePanels()
    Refresh(self)
end)
FP:RegisterEvent("PLAYER_REGEN_ENABLED", function(self)
    self.UI.RegisterPendingCombatClose()
    if self.bindingsPending then self:UpdateBindings() end
    self.UI:QueueRefresh()
end)
