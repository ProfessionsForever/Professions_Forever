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

---------------------------------------------------------------------------
-- Events (handlers run under xpcall so one error never breaks the others)
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}
frame:SetScript("OnEvent", function(_, event, ...)
    local h = handlers[event]
    if h then xpcall(h, geterrorhandler(), FP, ...) end
end)

-- One handler per event. `unit` (optional) limits a unit event to that unit.
function FP:RegisterEvent(name, fn, unit)
    handlers[name] = fn
    -- pcall: tolerate events missing on this client
    if unit then
        pcall(frame.RegisterUnitEvent, frame, name, unit)
    else
        pcall(frame.RegisterEvent, frame, name)
    end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
-- Recipe-list filter presets; used for first run and by the filter reset button.
FP.filterDefaults = { showUnlearned = false, unlearnedOnly = false, hasMatsOnly = false, skillUpsOnly = false, hideTrivial = false, favoritesOnly = false, hideCategories = false }

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
    sortKey = "name", sortDesc = false,
    lastRecipe = {}, -- [skill line ID] = the recipe last clicked in that profession
    collapsedCategories = {}, -- [categoryID] = true for recipe-list categories the user collapsed
    trackShopping = false, -- show the shopping list tracker on screen
    replaceDefault = true, shoppingScope = "char",
    trainerRecipes = {}, -- [recipe name] = "npcId,npcId" of the trainers seen teaching it
    trainers = {}, -- [npc id] = { npc, sub, uiMap, x, y, zone, skill, alliance, horde } for trainers you've opened
    bankers = {}, -- same shape, for bankers whose window you've opened
    vendors = {}, -- same shape plus items = ",itemID,itemID," (their stock) and recipes = { names }, for merchants you've opened
    minimap = { hide = false, angle = 215 },
    cooldownNotice = true, -- at login, name the characters with a recipe cooldown ready
    bankPrompt = true, -- open the transfer planner at the bank when the queue needs something from it
    showIgnoredCooldowns = false, -- list the cooldowns turned off in the Cooldowns window
    shopping = {}, -- account-wide list: [itemID] = needed
}
FP.defaults = defaults

-- Saved data rather than options, so a reset leaves it alone.
local DATA_KEYS = { trainerRecipes = true, trainers = true, bankers = true, vendors = true, shopping = true, characters = true, skipImport = true, transfers = true }

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
    ProfessionsForeverDB = ProfessionsForeverDB or {}
    ProfessionsForeverCharDB = ProfessionsForeverCharDB or {}
    Merge(ProfessionsForeverDB, FP.filterDefaults)
    Merge(ProfessionsForeverDB, defaults)
    Merge(ProfessionsForeverCharDB, { shopping = {}, queue = {}, queueTakes = {}, shoppingQueue = {}, makes = {} })
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
    db.accent, db.trackerPos = nil, nil
    Merge(db, FP.filterDefaults)
    Merge(db, defaults)

    local UI = self.UI
    UI:ResetWindow()
    UI:ApplyLock()
    UI:ApplySkin()
    self.Minimap:Position()
    self.Minimap:Update()
    self:UpdateBindings()
    if replaced ~= db.replaceDefault then self:Print(L["Changing this needs a UI reload to take full effect."]) end

    local shop = self.Shop
    if shop.tracker then shop:PlaceTracker() end
    shop:UpdateTracker()
    if shop.frame and shop.frame:IsShown() then shop:Update() end
    UI:ReflowSidePanels()
    self.Planner:Invalidate()
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
    self.Cooldowns:Scan()
    self.UI:QueueRefresh()
end
local function RefreshWithTracker(self)
    self.UI:QueueRefresh()
    self.Shop:UpdateTracker()
end

-- Startup
FP:RegisterEvent("ADDON_LOADED", function(self, name)
    if name == addonName then
        self:LoadSettings()
    elseif name == "Blizzard_Professions" then
        self:SuppressBlizzard()
    end
end)

FP:RegisterEvent("PLAYER_LOGIN", function(self)
    self.Alts:Init()
    self.Options:Init()
    self.Minimap:Init()
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
    if not self.db.replaceDefault or InCombatLockdown() then return end
    if not self:IsOwnProfession() then self:RestoreBlizzard() return end
    self:SuppressBlizzard()
    C_Timer.After(0, function() self:SuppressBlizzard() end) -- frame may be created after this event
    self.UI:Show("recipes")
end)

FP:RegisterEvent("TRADE_SKILL_CLOSE", function(self) self.UI:OnTradeSkillClosed() end)
FP:RegisterEvent("TRADE_SKILL_LIST_UPDATE", Reload)
FP:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", function(self)
    self.UI:ResetCraftQty()
    Reload(self)
end)
FP:RegisterEvent("NEW_RECIPE_LEARNED", Reload)
FP:RegisterEvent("TRADE_SKILL_FAVORITES_CHANGED", Reload)
FP:RegisterEvent("SKILL_LINES_CHANGED", Reload)
FP:RegisterEvent("TRACKED_RECIPE_UPDATE", Refresh)

-- Bags and bank
FP:RegisterEvent("BAG_UPDATE_DELAYED", function(self)
    if self.Inv.bankOpen then self.Inv:ScanBank() end -- also catches bank tab/slot changes
    self.Alts:Flush()
    self.Planner:Invalidate()
    RefreshWithTracker(self)
    local queue = self.Queue.frame
    if queue and queue:IsShown() then self.Queue:Update() end
    self.Transfer:QueueUpdate()
end)
FP:RegisterEvent("BANKFRAME_OPENED", function(self)
    self.Inv.bankOpen = true
    self.Inv:ScanBank()
    self.Planner:Invalidate()
    self.UI:QueueRefresh()
    self.Waypoint:RememberBanker()
    -- The slots may not be readable the instant the window opens, so the check waits a moment for the scan to settle.
    C_Timer.After(0.5, function()
        if not (self.Inv.bankOpen and self.db.bankPrompt) then return end
        self.Planner:Invalidate()
        if #self.Transfer.BankNeeds(self.Queue:TransferNeeds()) > 0 then self.Transfer:Open() end
    end)
    self.Transfer:QueueUpdate()
end)
FP:RegisterEvent("BANKFRAME_CLOSED", function(self)
    self.Inv.bankOpen = false
    self.Transfer:QueueUpdate()
end)
for _, e in ipairs({ "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED", "PLAYERREAGENTBANKSLOTS_CHANGED" }) do
    FP:RegisterEvent(e, function(self)
        if self.Inv.bankOpen then self.Inv:ScanBank() self.UI:QueueRefresh() end
    end)
end
FP:RegisterEvent("GET_ITEM_INFO_RECEIVED", RefreshWithTracker)
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
