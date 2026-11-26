local _, FP = ...
local W = FP.Waypoint

-- Recipe Scout: on entering a zone, the recipes this character hasn't learned that a vendor, a trainer or a
-- quest there offers, shown once per zone each session (Panels/ZoneRecipes.lua).
local Zone = {}
FP.ZoneRecipes = Zone

-- Where you are: { key, uiMap, dungeon, name }. In a dungeon, a raid or a battleground: its instance map ID as
-- dungeon, its name, and the key "d" and that ID (the game may give no map there). Else the zone map you are on, by
-- its ID. nil with neither (a loading screen).
function Zone:Here()
    local uiMap = C_Map.GetBestMapForUnit("player")
    if IsInInstance() then
        local name, _, _, _, _, _, _, dungeon = GetInstanceInfo()
        return { key = "d" .. dungeon, uiMap = uiMap, dungeon = dungeon, name = name }
    end
    if uiMap then return { key = uiMap, uiMap = uiMap, name = C_Map.GetMapInfo(uiMap).name } end
end

-- A quest that rewards the recipe and is given on the map, which this character may take (side, level) and has not
-- done: its entry in FP.RecipeQuests. A holiday's quest (the Lunar Festival's) only counts while the holiday is on.
local function Quest(recipeID, uiMap)
    for _, q in ipairs(W:QuestsFor(recipeID)) do
        if q.uiMap == uiMap and UnitLevel("player") >= q.level and not C_QuestLog.IsQuestFlaggedCompleted(q.id)
            and (not q.holiday or W.HolidayOn(q.holiday)) then
            return q
        end
    end
end

-- Where the recipe is offered on the map: its first vendor there, else its nearest trainer there when the skill is
-- enough to learn it, else a quest given there, else a creature that drops it or an object that holds
-- it there. Returns the kind ("V" vendor, "L" vendor with a limited supply, "T" trainer, "Q" quest, "D" creature,
-- "O" object), the NPC's or object's name, its spot or entry (with dungeon for one inside a dungeon), and the skill
-- needed (a trainer's asked skill for "T"; nil when any skill will do). A holiday's vendor or quest (the Darkmoon
-- Faire at this site, Winter Veil, the Lunar Festival) only counts while the calendar says the holiday is on.
local function Source(recipeID, here, rank)
    local db, need, uiMap = FP.db, FP.RecipeMinSkill[recipeID], here.uiMap
    for _, s in ipairs((db.zoneVendors or db.zoneLimited) and W.KnownRecipeVendors(recipeID) or {}) do
        if s.uiMap == uiMap and (not s.holiday or W.HolidayOn(s.holiday)) then
            local kind = W.LimitedSupply(recipeID, s.id) and "L" or "V"
            if db[kind == "L" and "zoneLimited" or "zoneVendors"] then return kind, s.name, s, need end
        end
    end
    local learn = FP.RecipeTrainerLearn[recipeID]
    local asked = learn and learn[1] or need
    if db.zoneTrainers and rank >= (asked or 0) then
        for _, t in ipairs(W:TrainersFor(recipeID)) do
            if t.uiMap == uiMap then return "T", t.npc, t, asked end
        end
    end
    local q = db.zoneQuests and Quest(recipeID, uiMap)
    if q then return "Q", q.npc, q, need end
    -- Drops: "all", only the recipes that drop nowhere but here ("zone", which leaves the world drops out), or
    -- "none". Here is the map, or inside a dungeon that dungeon.
    local scope, pick, elsewhere = db.zoneDropScope, nil, false
    local spots = scope ~= "none" and W:DropsFor(recipeID) or { unplaced = {} }
    for _, s in ipairs(spots) do
        if here.dungeon or s.uiMap ~= uiMap then elsewhere = true else pick = pick or s end
    end
    for _, s in ipairs(spots.unplaced) do
        if here.dungeon and s.dungeon == here.dungeon then pick = pick or s else elsewhere = true end
    end
    if scope == "zone" and elsewhere then return end
    if pick then return pick.kind, pick.name, pick, need end
end

-- The choices of which drops are listed, for the window's and the options' dropdown.
local SCOPES = { { "all", "All Drops" }, { "zone", "Zone Drops Only" }, { "none", "No Drops" } }

function Zone:DropScopeLabel()
    for _, s in ipairs(SCOPES) do
        if s[1] == FP.db.zoneDropScope then return FP.L[s[2]] end
    end
end

function Zone:DropScopeItems()
    local items = {}
    for i, s in ipairs(SCOPES) do
        items[i] = { text = FP.L[s[2]], checked = FP.db.zoneDropScope == s[1], onSelect = function()
            FP.db.zoneDropScope = s[1]
            self:Refresh()
            FP.Options:Refresh()
        end }
    end
    return items
end

-- The item that teaches the recipe (the one this character already holds, else its first), and where it is held:
-- "In Your Bags", "In Your Bank" or "In the Mailbox" (a locale key), or nil. No item for a recipe only trainers teach.
local itemsOf -- [recipe] = { recipe item, ... }, lowest ID first
local function RecipeItem(recipeID)
    if not itemsOf then
        itemsOf = {}
        for item, recipe in pairs(FP.RecipeItems) do
            itemsOf[recipe] = itemsOf[recipe] or {}
            tinsert(itemsOf[recipe], item)
        end
        for _, items in pairs(itemsOf) do table.sort(items) end
    end
    local items = itemsOf[recipeID]
    if not items then return end
    local found, where
    for _, item in ipairs(items) do
        local bags, bank, _, mail = FP.Inv:Owned(item)
        if bags > 0 then return item, "In Your Bags" end
        if not where and bank + mail > 0 then found, where = item, bank > 0 and "In Your Bank" or "In the Mailbox" end
    end
    return found or items[1], where
end

-- The unlearned recipes of this character's professions offered here (Zone:Here), by profession and then by name:
-- { recipe, name, skillLine, profession, icon, rank (the character's skill), kind, npc, spot, need, item, held,
-- ignored }. For a quest, spot is its FP.RecipeQuests entry. item, held: the recipe's item and where the character
-- already has it (RecipeItem). A recipe this character ignored on the map is only listed with Show Ignored on; the
-- second result counts the ones left out.
function Zone:Find(here)
    local out, hidden = {}, 0
    local ignoredHere = FP.chardb.zoneIgnored[here.key] or {}
    for _, p in ipairs(FP:GetProfessions()) do
        local first = #out + 1
        for v in (FP.RecipeLines[p.skillLine] or ""):gmatch("%d+") do -- gathering professions have no recipes
            local id = tonumber(v)
            local spec = FP.RecipeSpecialization[id] -- a Goblin Engineer's recipe is no use to a Gnomish Engineer
            if not IsPlayerSpell(id) and (not spec or IsPlayerSpell(spec)) then
                local kind, npc, spot, need = Source(id, here, p.rank)
                local item, held
                if kind then item, held = RecipeItem(id) end
                local ignored = ignoredHere[id]
                if kind and ignored and not FP.db.zoneShowIgnored then
                    hidden = hidden + 1
                elseif kind and (FP.db.zoneHeld or not held) then
                    out[#out + 1] = { ignored = ignored, recipe = id, name = C_Spell.GetSpellName(id), skillLine = p.skillLine,
                        profession = p.name, icon = p.icon, rank = p.rank, kind = kind, npc = npc, spot = spot,
                        need = need, item = item, held = held }
                end
            end
        end
        -- Each profession's recipes are one run of the list, sorted on its own.
        local run = {}
        for i = first, #out do run[#run + 1] = out[i] end
        table.sort(run, function(a, b) return a.name < b.name end)
        for i, e in ipairs(run) do out[first + i - 1] = e end
    end
    return out, hidden
end

-- Ignores the recipe in the zone or dungeon you are in for this character, or stops ignoring it.
function Zone:SetIgnored(recipeID, on)
    local all, key = FP.chardb.zoneIgnored, self:Here().key
    all[key] = all[key] or {}
    all[key][recipeID] = on or nil
    self:Refresh()
end

local function Open(here, found)
    FP.UI:ShowZoneRecipes(here.name, found)
end

-- /pf scout: the popup for the zone you are in, whether or not it was shown already.
function Zone:Show()
    local here = self:Here()
    local found, hidden = self:Find(here)
    -- Ignored recipes still open it, or there would be no way back to them.
    if #found == 0 and hidden == 0 and not FP.db.zonePinned then return FP:Print(FP.L["No recipes to learn in this zone."]) end
    Open(here, found)
end

-- The open window's list again: a recipe was learned or bought, or an option changed.
function Zone:Refresh()
    local here = FP.UI:ZoneRecipesShown() and self:Here()
    if here then Open(here, self:Find(here)) end
end

-- The pin was switched (its button on the window, or the options): a pinned window opens for the zone you are in.
function Zone:PinChanged()
    FP.UI:RefreshZonePin()
    if FP.db.zonePinned then self:Show() end
    FP.Options:Refresh()
end

local checked = {} -- [Here's key] = true once the zone or dungeon was looked at this session
local waiting -- a zone entered in combat is looked at when the fight ends

local function Check()
    if InCombatLockdown() then
        waiting = true
        return
    end
    local here = Zone:Here()
    if not here then return end -- no map during a loading screen
    -- A pinned window follows you: every zone, with or without recipes. With opening by itself off, only once it
    -- is open.
    if FP.db.zonePinned then
        if FP.db.zoneRecipes or FP.UI:ZoneRecipesShown() then Open(here, Zone:Find(here)) end
        return
    end
    if not FP.db.zoneRecipes or checked[here.key] then return end
    checked[here.key] = true
    local found = Zone:Find(here)
    -- Recipes already bought and waiting to be learned, and ignored ones, are listed, but don't open the window on
    -- their own.
    for _, e in ipairs(found) do
        if not e.held and not e.ignored then return Open(here, found) end
    end
end

FP:RegisterEvent("ZONE_CHANGED_NEW_AREA", Check)
FP:RegisterEvent("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, Check) end) -- the map needs a moment
FP:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if waiting then
        waiting = nil
        Check()
    end
end)
-- An open window drops what was just learned, and marks what was just bought.
FP:RegisterEvent("NEW_RECIPE_LEARNED", function() Zone:Refresh() end)
FP:RegisterEvent("BAG_UPDATE_DELAYED", function() Zone:Refresh() end)
