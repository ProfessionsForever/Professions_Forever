local _, FP = ...
local L = FP.L
local W = FP.Waypoint
local Questie, Place, Spawns, Friendly = W.Questie, W.Place, W.Spawns, W.Friendly
local indexes = W.indexes

local RECIPE_PREFIXES = W.RECIPE_PREFIXES

local function Label(name, area)
    return area and ("%s (%s)"):format(name, area) or name
end

local function RefreshUI() FP.UI:QueueRefresh() end

---------------------------------------------------------------------------
-- Merchants you open are recorded with their stock and the recipes they sell; shipped data adds the rest.
---------------------------------------------------------------------------
local itemVendors, recipeVendors = {}, nil -- caches, cleared when a merchant is recorded

local function Spot(id, v)
    return { id = id, name = v.npc or "?", uiMap = v.uiMap, x = v.x, y = v.y, area = v.zone }
end

-- Known vendors of your faction selling the recipe, by recipe name.
function W.KnownRecipeVendors(recipeName)
    if not recipeVendors then
        recipeVendors = {}
        for id, v in W.Known("vendors") do
            if v.recipes and W.Usable(v) then
                for _, name in ipairs(v.recipes) do
                    local list = recipeVendors[name]
                    if not list then list = {} recipeVendors[name] = list end
                    list[#list + 1] = Spot(id, v)
                end
            end
        end
    end
    return recipeVendors[recipeName] or {}
end

local function KnownItemVendors(itemID)
    local out, key = {}, "," .. itemID .. ","
    for id, v in W.Known("vendors") do
        if v.items and W.Usable(v) and v.items:find(key, 1, true) then out[#out + 1] = Spot(id, v) end
    end
    return out
end

-- Stock is stored as ",itemID,itemID," to keep the saved file small and searchable.
local function RememberVendor()
    local entry = W.Remember("vendors")
    if not entry then return end
    local ids, recipes = {}, {}
    for i = 1, GetMerchantNumItems() do
        local id = GetMerchantItemID(i)
        if id then
            ids[#ids + 1] = id
            if select(6, C_Item.GetItemInfoInstant(id)) == Enum.ItemClass.Recipe then
                local info = C_MerchantFrame.GetItemInfo(i)
                local recipe = info and info.name and info.name:match("^[^:]+: (.+)")
                if recipe then recipes[#recipes + 1] = recipe end
            end
        end
    end
    entry.items = "," .. table.concat(ids, ",") .. ","
    entry.recipes = #recipes > 0 and recipes or nil
    wipe(itemVendors)
    recipeVendors = nil
end
FP:RegisterEvent("MERCHANT_SHOW", RememberVendor)

---------------------------------------------------------------------------
-- Vendors for a recipe
---------------------------------------------------------------------------
-- Friendly vendor NPC ids selling the recipe item; the item index must be ready.
local function VendorsForRecipe(db, recipeName)
    local items = indexes.item.map
    local out, seen = {}, {}
    for _, prefix in ipairs(RECIPE_PREFIXES) do
        for _, itemId in ipairs(items[prefix .. ": " .. recipeName] or {}) do
            for _, npcId in ipairs(db.QueryItemSingle(itemId, "vendors") or {}) do
                if not seen[npcId] and Friendly(db, npcId) then
                    seen[npcId] = true
                    out[#out + 1] = npcId
                end
            end
        end
    end
    return out
end

local function CleanSource(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "\n"))
end

-- One-line vendor summary for tooltips and the recipe detail. Second return is true while Questie's item index is still building.
function W:Summary(recipeID)
    local e = FP.Recipes.byID[recipeID]
    if not e then return end
    local db, zoneDB = Questie()
    local parts, seen, loading = {}, {}, false
    local function Add(name, area)
        name = name or "?"
        if not seen[name] and #parts < 3 then
            seen[name] = true
            parts[#parts + 1] = Label(name, area)
        end
    end
    if db then
        local st = indexes.item
        if st and st.map then
            for _, npcId in ipairs(VendorsForRecipe(db, e.name)) do
                local spot = Spawns(db, zoneDB, npcId)[1]
                Add(db.QueryNPCSingle(npcId, "name"), spot and spot.area)
            end
        else
            loading = true
            if not (st and st.building) then W.Index("item", db, RefreshUI) end
        end
    end
    for _, s in ipairs(W.KnownRecipeVendors(e.name)) do Add(s.name, s.area) end
    return #parts > 0 and table.concat(parts, ", ") or nil, loading
end

local function SetWaypoint(spot, who, recipeName)
    Place(spot.uiMap, spot.x, spot.y, ("%s (%s)"):format(who or "?", recipeName))
    FP:Print(L["Waypoint set: %s"]:format(who or "?"))
end

local function GoToKnownVendor(e)
    local pick = W.PickNearest(W.KnownRecipeVendors(e.name))
    if pick then SetWaypoint(pick, pick.name, e.name) end
    return pick ~= nil
end

-- Waypoint to whoever teaches or sells the recipe: a trainer first, then a vendor.
function W:ForRecipe(recipeID)
    if not self:CheckNav() then return end
    local e = FP.Recipes.byID[recipeID]
    if not e then return end

    local trainer = self:TrainerFor(recipeID)
    if trainer then return SetWaypoint(trainer, trainer.npc, e.name) end

    local db, zoneDB = Questie()
    if not db then
        if GoToKnownVendor(e) then return end
        return FP:Print(L["No known vendor for %s. Questie can find more."]:format(e.name))
    end

    -- Blizzard's source text, when the client provides it, names the vendor directly.
    local raw = C_TradeSkillUI.GetRecipeSourceText and C_TradeSkillUI.GetRecipeSourceText(recipeID)
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
        local vendors = VendorsForRecipe(db, e.name)
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
    local spots = KnownItemVendors(itemID)
    local db, zoneDB = Questie()
    if db then
        for _, npcId in ipairs(db.QueryItemSingle(itemID, "vendors") or {}) do
            if Friendly(db, npcId) then
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
    W.PlaceNearest(pick, dist, ("%s (%s)"):format(pick.name, item),
        "Nearest vendor for %s: %s (about %d yards)", "Nearest vendor for %s: %s (on another continent)", item, pick.name)
end
