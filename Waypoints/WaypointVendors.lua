local _, FP = ...
local L = FP.L
local W = FP.Waypoint
local Questie, Place, Spawns, Friendly = W.Questie, W.Place, W.Spawns, W.Friendly
local indexes = W.indexes

-- Vendors: who sells a recipe or an item, from the vendors you have opened, the shipped data and Questie; the
-- Sold By summaries, and waypoints to the nearest one.

local RECIPE_PREFIXES = W.RECIPE_PREFIXES

-- "Name (Area)", with the holiday the source is only there for: "Name (Area, Lunar Festival)". The Darkmoon Faire
-- isn't named again: its area already says so. A doubtful vendor (W.Doubtful) is marked and grayed:
-- "Name (Area, Not Seen in Stock)".
function W.Label(name, area, holiday, doubtful)
    local notes = {}
    notes[#notes + 1] = area
    notes[#notes + 1] = W.HolidayName(holiday)
    notes[#notes + 1] = doubtful and L["Not Seen in Stock"] or nil
    local text = notes[1] and ("%s (%s)"):format(name, table.concat(notes, ", ")) or name
    return doubtful and FP.UI.Hex(FP.UI.STATUS_COLORS.none) .. text .. "|r" or text
end
local Label = W.Label

local function RefreshUI() FP.UI:QueueRefresh() end

---------------------------------------------------------------------------
-- Merchants you open are recorded with their stock; shipped data adds the rest.
---------------------------------------------------------------------------
local itemVendors, recipeVendors = {}, nil -- caches, cleared when a merchant is recorded

-- The Darkmoon Faire's merchants stand wherever the faire is, Mulgore or Elwynn Forest in turn, so the one position
-- an entry holds is right half the time. Both sites are offered instead, to either faction. The game's calendar lists
-- each site's faire as its own holiday (event).
local DARKMOON_NPCS = { [14828] = true, [14844] = true, [14845] = true, [14846] = true, [14847] = true, [14860] = true }
local DARKMOON_SITES = {
    { event = 264, uiMap = 1412, x = 0.374, y = 0.449 }, -- Mulgore
    { event = 263, uiMap = 1429, x = 0.412, y = 0.699 }, -- Elwynn Forest
}

-- [npc id] = the calendar holiday (event) the vendor is only there for. Smokywood Pastures' city vendors come for
-- the Feast of Winter Veil (141, as Forever's calendar lists it) with the Gingerbread Cookie and Egg Nog recipes.
local HOLIDAY_NPCS = { [13420] = 141, [13429] = 141, [13432] = 141, [13433] = 141, [13435] = 141 }

-- [quest id] = the calendar holiday the quest is only given in. Fariel Starsong's firework recipe quests in Moonglade
-- come with the Lunar Festival (327 in Forever's Holidays table).
local HOLIDAY_QUESTS = { [8876] = 327, [8877] = 327, [8878] = 327, [8879] = 327, [8880] = 327, [8881] = 327, [8882] = 327 }

-- [recipe spell] = { [vendor npc id] = true }: vendors the built-in data and Questie list for the recipe that players
-- have confirmed don't sell it in Forever. Never listed, unless your own visit records it in their stock.
local NOT_SOLD = {
    [15906] = { [4897] = true }, -- Dragonbreath Chili: Helenia Olden (Wowhead comments, 2026-11)
}

local function NotSold(recipeID, npcId)
    return NOT_SOLD[recipeID] ~= nil and NOT_SOLD[recipeID][npcId] == true
end

-- The holidays a source's label names (locale keys), by calendar event ID.
local HOLIDAY_NAMES = { [141] = "Feast of Winter Veil", [327] = "Lunar Festival" }

function W.HolidayName(event)
    return HOLIDAY_NAMES[event] and L[HOLIDAY_NAMES[event]]
end

local function Serves(id, v)
    return DARKMOON_NPCS[id] or W.Usable(v, "vendors", id)
end

-- A calendar time as minutes, to compare two of them.
local function Minutes(t)
    return (((t.year * 12 + t.month) * 31 + t.monthDay) * 24 + t.hour) * 60 + t.minute
end

-- Whether the calendar's holiday (by its event ID) is running right now; false until the calendar's data arrives
-- after login. The calendar counts months from the one its window shows, which the player may have paged away from
-- today's.
function W.HolidayOn(event)
    local now, shown = C_DateAndTime.GetCurrentCalendarTime(), C_Calendar.GetMonthInfo(0)
    local offset = (now.year - shown.year) * 12 + now.month - shown.month
    for i = 1, C_Calendar.GetNumDayEvents(offset, now.monthDay) do
        local e = C_Calendar.GetDayEvent(offset, now.monthDay, i)
        if e.eventID == event and Minutes(e.startTime) <= Minutes(now) and Minutes(now) < Minutes(e.endTime) then
            return true
        end
    end
    return false
end
FP:RegisterEvent("PLAYER_LOGIN", function() C_Calendar.OpenCalendar() end) -- asks the server for the calendar's data

-- Adds the vendor's spot to list: one, or one per faire site. `holiday` on a spot is the calendar holiday the vendor
-- is only there for: the faire at that site, or a seasonal vendor's.
local function AddSpots(list, id, v)
    if DARKMOON_NPCS[id] then
        for _, site in ipairs(DARKMOON_SITES) do
            list[#list + 1] = { id = id, name = v.npc or "?", uiMap = site.uiMap, x = site.x, y = site.y,
                area = L["Darkmoon Faire"], holiday = site.event }
        end
    else
        list[#list + 1] = { id = id, name = v.npc or "?", uiMap = v.uiMap, x = v.x, y = v.y, area = v.zone,
            holiday = HOLIDAY_NPCS[id] }
    end
end

-- Known vendors of your faction selling the recipe, by its ID: the ones recorded with its recipe item in their stock
-- (yours and other players' shipped ones), and the built-in sources.
function W.KnownRecipeVendors(recipeID)
    if not recipeVendors then
        recipeVendors = {}
        for id, v in W.Known("vendors") do
            if v.items and Serves(id, v) then
                for item in v.items:gmatch("%d+") do
                    local recipe = FP.RecipeItems[tonumber(item)]
                    if recipe then
                        local list = recipeVendors[recipe]
                        if not list then list = {} recipeVendors[recipe] = list end
                        AddSpots(list, id, v)
                    end
                end
            end
        end
    end
    local out, seen, doubtful = {}, {}, {}
    for _, spot in ipairs(recipeVendors[recipeID] or {}) do
        seen[spot.id] = true
        out[#out + 1] = spot
    end
    for v in (W.SourceIds(recipeID, "VL") or ""):gmatch("%d+") do
        local id = tonumber(v)
        local vendor = not seen[id] and not NotSold(recipeID, id) and W.KnownEntry("vendors", id)
        if vendor and Serves(id, vendor) then
            if W.Doubtful(recipeID, id) then
                local first = #doubtful + 1
                AddSpots(doubtful, id, vendor)
                for i = first, #doubtful do doubtful[i].doubtful = true end
            else
                AddSpots(out, id, vendor)
            end
        end
    end
    for _, spot in ipairs(doubtful) do out[#out + 1] = spot end
    return out
end

local function KnownItemVendors(itemID)
    local out, key = {}, "," .. itemID .. ","
    for id, v in W.Known("vendors") do
        if v.items and Serves(id, v) and v.items:find(key, 1, true) then AddSpots(out, id, v) end
    end
    return out
end

-- ",id,id," as a set, and back (nil for an empty one).
local function SupplySet(list)
    local set = {}
    for v in (list or ""):gmatch("%d+") do set[tonumber(v)] = true end
    return set
end

local function SupplyList(set)
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids[1] and ("," .. table.concat(ids, ",") .. ",") or nil
end

-- The items that teach a recipe, by its ID (FP.RecipeItems turned around, built on first use).
local itemsOf
local function RecipeItemsOf(recipeID)
    if not itemsOf then
        itemsOf = {}
        for item, recipe in pairs(FP.RecipeItems) do
            itemsOf[recipe] = itemsOf[recipe] or {}
            tinsert(itemsOf[recipe], item)
        end
    end
    return itemsOf[recipeID] or {}
end

-- Whether the vendor's supply of the recipe is limited: as seen at the vendor (your recording or a shipped one), else
-- as 1.12's data has it.
function W.LimitedSupply(recipeID, npcId)
    local entry = W.KnownEntry("vendors", npcId)
    local seenLimited, seenNoLimit = SupplySet(entry.limited), SupplySet(entry.noLimit)
    local seen
    for _, item in ipairs(RecipeItemsOf(recipeID)) do
        if seenLimited[item] then return true end
        seen = seen or seenNoLimit[item]
    end
    if seen then return false end
    return ("," .. (W.SourceIds(recipeID, "L") or "") .. ","):find("," .. npcId .. ",", 1, true) ~= nil
end

-- Whether a vendor the built-in data or Questie lists for the recipe may no longer sell it: it was recorded in
-- Forever (by you or in the shipped data) without the recipe item in its stock, and the item isn't a limited supply
-- there, which a visit can find sold out. Still listed, as the recording may have missed it (an item shown only to
-- some players), but marked, after the others, and not picked for a waypoint while another vendor is known.
function W.Doubtful(recipeID, npcId)
    local entry = W.KnownEntry("vendors", npcId)
    if not (entry and entry.ver and entry.items) then return false end
    for _, item in ipairs(RecipeItemsOf(recipeID)) do
        if entry.items:find("," .. item .. ",", 1, true) then return false end
    end
    return not W.LimitedSupply(recipeID, npcId)
end

-- Stock is stored as ",itemID,itemID," to keep the saved file small and searchable. The recipes a vendor sells are
-- read from it: a recipe item is in the stock like any other.
local function RememberVendor()
    local entry = W.Remember("vendors")
    if not entry then return end
    -- The recipe items seen with a limited supply and with none: Forever's vendors don't always follow 1.12's.
    local limited, noLimit = SupplySet(entry.limited), SupplySet(entry.noLimit)
    local ids = {}
    for i = 1, GetMerchantNumItems() do
        local id = GetMerchantItemID(i)
        if id then ids[#ids + 1] = id end
        if id and FP.RecipeItems[id] then
            local scarce = C_MerchantFrame.GetItemInfo(i).numAvailable >= 0
            limited[id], noLimit[id] = scarce or nil, not scarce or nil
        end
    end
    entry.limited, entry.noLimit = SupplyList(limited), SupplyList(noLimit)
    -- Combined with what earlier visits saw: sold-out limited-supply items drop off the list, and are far more
    -- common than items a patch removes.
    for v in (entry.items or ""):gmatch("%d+") do
        if not tContains(ids, tonumber(v)) then ids[#ids + 1] = tonumber(v) end
    end
    entry.items = "," .. table.concat(ids, ",") .. ","
    wipe(itemVendors)
    recipeVendors = nil
end
FP:RegisterEvent("MERCHANT_SHOW", RememberVendor)

---------------------------------------------------------------------------
-- Vendors for a recipe
---------------------------------------------------------------------------
-- Friendly vendor NPC ids Questie lists as selling the recipe item, the doubtful ones (W.Doubtful) last and the ones
-- confirmed not to sell it left out; the item index must be ready.
local function VendorsForRecipe(db, recipeName, recipeID)
    local items = indexes.item.map
    local out, doubtful, seen = {}, {}, {}
    for _, prefix in ipairs(RECIPE_PREFIXES) do
        for _, itemId in ipairs(items[prefix .. ": " .. recipeName] or {}) do
            for _, npcId in ipairs(db.QueryItemSingle(itemId, "vendors") or {}) do
                if not seen[npcId] and Friendly(db, npcId) and not NotSold(recipeID, npcId) then
                    seen[npcId] = true
                    local list = W.Doubtful(recipeID, npcId) and doubtful or out
                    list[#list + 1] = npcId
                end
            end
        end
    end
    for _, npcId in ipairs(doubtful) do out[#out + 1] = npcId end
    return out
end

local function CleanSource(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "\n"))
end

-- One-line vendor summary for tooltips and the recipe detail. Second return is true while Questie's item index is still building.
function W:Summary(recipeID)
    local e = FP.Recipes.byID[recipeID]
    local recipeName = e and e.name or C_Spell.GetSpellName(recipeID) -- a recipe of a profession that isn't open
    local db, zoneDB = Questie()
    local sure, doubtful, seen, loading = {}, {}, {}, false
    local function Add(name, area, holiday, doubt)
        name = name or "?"
        if not seen[name] then
            seen[name] = true
            local list = doubt and doubtful or sure
            list[#list + 1] = Label(name, area, holiday, doubt)
        end
    end
    if db then
        local st = indexes.item
        if st and st.map then
            for _, npcId in ipairs(VendorsForRecipe(db, recipeName, recipeID)) do
                local spot = Spawns(db, zoneDB, npcId)[1]
                Add(db.QueryNPCSingle(npcId, "name"), spot and spot.area, HOLIDAY_NPCS[npcId], W.Doubtful(recipeID, npcId))
            end
        else
            loading = true
            if not (st and st.building) then W.Index("item", db, RefreshUI) end
        end
    end
    for _, s in ipairs(W.KnownRecipeVendors(recipeID)) do Add(s.name, s.area, s.holiday, s.doubtful) end
    -- Three at most, the doubtful ones last.
    local parts = {}
    for _, list in ipairs({ sure, doubtful }) do
        for _, label in ipairs(list) do
            if #parts < 3 then parts[#parts + 1] = label end
        end
    end
    return #parts > 0 and table.concat(parts, ", ") or nil, loading
end

-- spot is a vendor spot (area) or a trainer entry (zone).
local function SetWaypoint(spot, who, recipeName)
    local where = W.Where(who or "?", spot.area or spot.zone)
    Place(spot.uiMap, spot.x, spot.y, ("%s (%s)"):format(where, recipeName))
    FP:Print(L["Waypoint set: %s"]:format(where))
end

-- Waypoint to one given source of a recipe: a vendor spot or a trainer entry.
function W:ForSpot(spot, who, recipeName)
    if self:CheckNav() then SetWaypoint(spot, who, recipeName) end
end

-- The quests that reward the recipe and that your faction can take, with a giver placed in the built-in data
-- (FP.RecipeQuests entries, each with its quest id, and the calendar holiday it is only given in):
-- { id, quest, level, npc, zone, uiMap, x, y, holiday }.
function W:QuestsFor(recipeID)
    local out = {}
    for v in (W.SourceIds(recipeID, "Q") or ""):gmatch("%d+") do
        local id = tonumber(v)
        local q = FP.RecipeQuests[id] -- none for a quest an item starts: it has no place
        if q and W.Usable(q) then
            q.id, q.holiday = id, HOLIDAY_QUESTS[id]
            out[#out + 1] = q
        end
    end
    return out
end

-- Where the recipe's item drops, from the built-in data (FP.DropCreatures, FP.DropObjects): a spot per zone for each
-- creature that drops it (kind "D") and each object that holds it ("O"): { id, kind, name, uiMap, x, y, area }.
-- A creature on your side is left out: it can't be killed for it (a Dun Garok Priest, for the Alliance). The list's
-- `unplaced` are the ones with no spot on a zone map: { kind, name }, and for each dungeon one stands in (FP.Dungeons)
-- dungeon (its instance map ID), area (its name) and uiMap, x, y (its entrance; none for a battleground).
local drops = {} -- [recipe] = spots
function W:DropsFor(recipeID)
    if drops[recipeID] then return drops[recipeID] end
    local out, mine = { unplaced = {} }, UnitFactionGroup("player") == "Alliance" and "A" or "H"
    for _, kind in ipairs({ "D", "O" }) do
        local data = kind == "D" and FP.DropCreatures or FP.DropObjects
        for v in (W.SourceIds(recipeID, kind) or ""):gmatch("%d+") do
            local id = tonumber(v)
            local name, side, spots = strsplit("^", data[id])
            if not side:find(mine) then
                for map in spots:gmatch("d(%d+)") do
                    map = tonumber(map)
                    local d = FP.Dungeons[map]
                    out.unplaced[#out.unplaced + 1] = { id = id, kind = kind, name = name, dungeon = map, area = d.name,
                        uiMap = d.uiMap, x = d.x, y = d.y }
                end
                if spots == "" then out.unplaced[#out.unplaced + 1] = { id = id, kind = kind, name = name } end
                for uiMap, x, y in spots:gmatch("(%d+):(%d+):(%d+)") do
                    uiMap = tonumber(uiMap)
                    out[#out + 1] = { id = id, kind = kind, name = name, uiMap = uiMap, x = x / 1000, y = y / 1000,
                        area = C_Map.GetMapInfo(uiMap).name }
                end
            end
        end
    end
    drops[recipeID] = out
    return out
end

-- "Dropped by: Name (Zone), Name (Zone)" and "Found in: ..." for the recipe, nearest first and then the ones in
-- dungeons, three each at most; nil for the one it has none of.
function W:DropSummary(recipeID)
    local parts, all = { D = {}, O = {} }, self:DropsFor(recipeID)
    local function Add(s)
        local list = parts[s.kind]
        if #list < 3 then list[#list + 1] = Label(s.name, s.area) end
    end
    for _, s in ipairs(W.SortNearest({ unpack(all) })) do Add(s) end
    for _, s in ipairs(all.unplaced) do Add(s) end
    return parts.D[1] and L["Dropped by: %s"]:format(table.concat(parts.D, ", ")) or nil,
        parts.O[1] and L["Found in: %s"]:format(table.concat(parts.O, ", ")) or nil
end

-- Where a waypoint can lead for the recipe's drops: the creatures and objects on a zone map, and the entrance of
-- each dungeon one of them stands in.
function W:DropTargets(recipeID)
    local all = self:DropsFor(recipeID)
    local out = { unpack(all) }
    for _, s in ipairs(all.unplaced) do
        if s.uiMap then out[#out + 1] = s end
    end
    return out
end

-- The nearest known vendor of the recipe (a doubtful one only when no other is known), else the nearest giver of a
-- quest that rewards it, else the nearest creature or object that drops it (for one in a dungeon, the dungeon's
-- entrance).
local function GoToKnownVendor(e)
    local vendors, sure = W.KnownRecipeVendors(e.id), {}
    for _, s in ipairs(vendors) do
        if not s.doubtful then sure[#sure + 1] = s end
    end
    local pick = W.PickNearest(sure) or W.PickNearest(vendors)
    if pick then
        SetWaypoint(pick, pick.name, e.name)
        return true
    end
    pick = W.PickNearest(W:QuestsFor(e.id))
    if pick then
        SetWaypoint(pick, pick.npc, e.name)
        return true
    end
    pick = W.PickNearest(W:DropTargets(e.id))
    if pick then SetWaypoint(pick, pick.name, e.name) end
    return pick ~= nil
end

-- Waypoint to whoever teaches or sells the recipe: a trainer first, then a vendor.
function W:ForRecipe(recipeID)
    if not self:CheckNav() then return end
    local e = FP.Recipes.byID[recipeID]
    if not e then return end

    local trainer = self:TrainersFor(recipeID)[1]
    if trainer then return SetWaypoint(trainer, trainer.npc, e.name) end

    local db, zoneDB = Questie()
    if not db then
        if GoToKnownVendor(e) then return end
        return FP:Print(L["No known vendor for %s. Questie can find more."]:format(e.name))
    end

    -- Blizzard's source text, when the client provides it, names the vendor directly.
    local raw = C_TradeSkillUI.GetRecipeSourceText(recipeID)
    local vendorName = raw and raw ~= "" and CleanSource(raw):match("[Vv]endor:%s*([^\n]+)")
    if vendorName then
        vendorName = strtrim(vendorName)
        return W.SearchNpc(db, vendorName, function(ids)
            local spot = ids[1] and Spawns(db, zoneDB, ids[1])[1]
            if spot then return SetWaypoint(spot, vendorName, e.name) end
            if not GoToKnownVendor(e) then FP:Print(L["No known location for %s."]:format(vendorName)) end
        end)
    end

    W.Search("item", db, function()
        local vendors = VendorsForRecipe(db, e.name, recipeID)
        for _, npcId in ipairs(vendors) do
            local spot = Spawns(db, zoneDB, npcId)[1]
            if spot then
                if #vendors > 1 then FP:Print(L["%d vendors sell this; showing the first."]:format(#vendors)) end
                return SetWaypoint(spot, db.QueryNPCSingle(npcId, "name"), e.name)
            end
        end
        if not GoToKnownVendor(e) then FP:Print(L["Questie knows no vendor for %s."]:format(e.name)) end
    end)
end

---------------------------------------------------------------------------
-- Vendors for a reagent: known vendors plus whoever Questie lists as selling the item.
---------------------------------------------------------------------------
local function VendorSpots(itemID)
    if itemVendors[itemID] then return itemVendors[itemID] end
    local spots, have = KnownItemVendors(itemID), {}
    for _, s in ipairs(spots) do have[s.id] = true end
    local db, zoneDB = Questie()
    if db then
        -- Recorded and shipped vendors win over Questie's spawn for the same NPC.
        for _, npcId in ipairs(db.QueryItemSingle(itemID, "vendors") or {}) do
            if not have[npcId] and Friendly(db, npcId) then
                local name = db.QueryNPCSingle(npcId, "name")
                for _, spot in ipairs(Spawns(db, zoneDB, npcId)) do
                    spot.id, spot.name = npcId, name
                    spots[#spots + 1] = spot
                end
            end
        end
    end
    if db or not _G.QuestieLoader then itemVendors[itemID] = spots end -- Questie may still be starting up
    return spots
end

-- Only offered when a navigator is usable and a vendor with a location is known.
function W:VendorNavAvailable(itemID)
    return self:NavAvailable() and #VendorSpots(itemID) > 0
end

function W:VendorSummary(itemID)
    local parts, seen = {}, {}
    for _, s in ipairs(VendorSpots(itemID)) do
        if not seen[s.id] and #parts < 3 then
            seen[s.id] = true
            parts[#parts + 1] = Label(s.name, s.area)
        end
    end
    return table.concat(parts, ", ")
end

function W:NearestVendor(itemID)
    if not self:VendorNavAvailable(itemID) then return end
    local pick, dist = W.PickNearest(VendorSpots(itemID))
    if not pick then return end
    local item = C_Item.GetItemNameByID(itemID) or "?"
    local where = W.Where(pick.name, pick.area)
    W.PlaceNearest(pick, dist, ("%s (%s)"):format(where, item),
        "Nearest vendor for %s: %s (about %d yards)", "Nearest vendor for %s: %s (on another continent)", item, where)
end
