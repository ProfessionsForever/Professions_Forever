local _, FP = ...

-- Forever's camp items (Data/Camp.lua): crafted objects you place at a camp, used up when placed. Placing one needs
-- its profession (the one whose recipe makes it), not the recipe. The camp objects share one cooldown and the campfire
-- kits another (each item's category in Data/Camp.lua).
local Camp = {}
FP.Camp = Camp

Camp.OBJECTS, Camp.CAMPFIRES = 97, 2511
Camp.GROUPS = { "extras", "ready", "craft", "alts", "unknown" } -- in list order

-- Hand-picked items listed in their own group at the top (Essentials) while this character has them; add more here.
-- Not crafted, so not in Data/Camp.lua, and never used up, each with its own cooldown: the Cozy Sleeping Bag (an item
-- in the bags) and the Pouch of Violet Dust (a toy, for a limited time). [item ID] = "item" | "toy"
Camp.EXTRAS = { [211527] = "item", [289439] = "toy" }

-- One item of each category to read the shared cooldown from: the game reports it on every item of the category.
local probe = {}
for itemID, d in pairs(FP.CampItems) do
    if not probe[d[3]] or itemID < probe[d[3]] then probe[d[3]] = itemID end
end

-- Seconds until `itemID` can be used again; 0 when ready. The global cooldown is not counted.
local function Left(itemID)
    local start, duration = C_Container.GetItemCooldown(itemID)
    if not start or start == 0 or duration <= 2 then return 0 end
    return math.max(0, start + duration - GetTime())
end

-- Seconds until a camp item of `category` can be placed again; 0 when ready.
function Camp:Remaining(category) return Left(probe[category]) end

-- The same for an entry of Camp:List: its category's shared cooldown, or the item's own for the extras.
function Camp:EntryRemaining(e) return Left(e.extra and e.id or probe[e.category]) end

-- The item's name, or nil while the game hasn't loaded it (it is asked for, and "items" redraws once it arrives).
function Camp.Name(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if not name then C_Item.RequestLoadItemDataByID(itemID) end
    return name
end

local ORDER = {}
for i, g in ipairs(Camp.GROUPS) do ORDER[g] = i end

-- The camp items this character's faction can use, each { id, recipe, skillLine, category, bags, bank, group,
-- canPlace (this character knows its profession), crafters (other characters who know the recipe), holders
-- (Alts:GetAltBreakdown's characters that could mail some, largest holding first) }, in group order, then by profession
-- and name. group:
--   extras: Camp.EXTRAS you have; ready: in your bags or bank; craft: you know the recipe; alts: another character holds it or knows the recipe;
--   unknown: nobody does.
-- The extras have `extra` set ("item" or "toy") and no recipe, category or crafters.
function Camp:List()
    local me, faction = FP.Alts:GetCharacterKey(), UnitFactionGroup("player")
    local out, learned = {}, {}
    for _, p in ipairs(FP:GetProfessions()) do learned[p.skillLine] = true end
    for itemID, d in pairs(FP.CampItems) do
        if not d[5] or d[5] == faction then
            local bags = C_Item.GetItemCount(itemID)
            local e = { id = itemID, recipe = d[1], skillLine = d[2], category = d[3], bags = bags,
                bank = C_Item.GetItemCount(itemID, true) - bags, crafters = {},
                holders = FP.Alts:GetAltBreakdown(itemID).enabled, canPlace = learned[d[2]] or false }
            for _, key in ipairs(FP.Known:Who(d[1])) do
                if key ~= me then e.crafters[#e.crafters + 1] = key end
            end
            e.group = (bags + e.bank > 0) and "ready" or IsPlayerSpell(d[1]) and "craft"
                or (#e.holders > 0 or #e.crafters > 0) and "alts" or "unknown"
            e.prof = C_TradeSkillUI.GetTradeSkillDisplayName(d[2]) or ""
            e.name = Camp.Name(itemID) or ("item:" .. itemID)
            out[#out + 1] = e
        end
    end
    for itemID, kind in pairs(self.EXTRAS) do
        local bags = kind == "item" and C_Item.GetItemCount(itemID) or (PlayerHasToy(itemID) and 1 or 0)
        local bank = kind == "item" and C_Item.GetItemCount(itemID, true) - bags or 0
        if bags + bank > 0 then
            out[#out + 1] = { id = itemID, extra = kind, bags = bags, bank = bank, crafters = {}, holders = {}, canPlace = true,
                group = "extras", prof = kind == "toy" and FP.L["Toy"] or "", name = Camp.Name(itemID) or ("item:" .. itemID) }
        end
    end
    table.sort(out, function(a, b)
        if a.group ~= b.group then return ORDER[a.group] < ORDER[b.group] end
        if a.prof ~= b.prof then return a.prof < b.prof end
        return a.name < b.name
    end)
    return out
end

-- Placing one starts the shared cooldown; the window, footer and quick button show it.
FP:RegisterEvent("BAG_UPDATE_COOLDOWN", function() FP:Changed("camp") end)
