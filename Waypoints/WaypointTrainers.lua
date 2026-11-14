local _, FP = ...
local L = FP.L
local W = FP.Waypoint
local Questie, Spawns, Friendly, HasWord = W.Questie, W.Spawns, W.Friendly, W.HasWord
local indexes = W.indexes

-- Primary profession trainers are titled by rank and craft ("Expert Engineer"); the rest by "<Profession> Trainer".
local CRAFT_TITLES = {
    engineering = { "engineer" }, alchemy = { "alchemist" }, blacksmithing = { "blacksmith" }, mining = { "miner" },
    herbalism = { "herbalist" }, skinning = { "skinner" }, leatherworking = { "leatherworker" }, tailoring = { "tailor" },
    enchanting = { "enchanter" }, jewelcrafting = { "jewelcrafter" }, inscription = { "scribe" },
}

-- Forever has four ranks, Apprentice to Artisan; each raises a profession's skill cap by 75, up to 300. A rank is
-- named here by the cap it gives: 75, 150, 225 or 300.
local RANK_STEP, MAX_CAP = 75, 300
local RANK_GLOBALS = { "APPRENTICE", "JOURNEYMAN", "EXPERT", "ARTISAN" } -- the game's own (localized) rank names

local function Teaches(sub, profession)
    if not sub then return false end
    local low, prof = sub:lower(), profession:lower()
    if HasWord(low, prof) and HasWord(low, "trainer") then return true end
    for _, title in ipairs(CRAFT_TITLES[prof] or {}) do
        if HasWord(low, title) then return true end
    end
    return false
end

-- The rank worth visiting a trainer for: your current one, the next once you've hit its cap, or Apprentice to learn
-- the profession.
local function WantedCap(profession)
    for _, p in ipairs(FP:GetProfessions()) do
        if p.name == profession and (p.maxRank or 0) > 0 then
            local cap = p.maxRank
            if (p.rank or 0) >= cap then cap = cap + RANK_STEP end
            return math.min(cap, MAX_CAP)
        end
    end
    return RANK_STEP
end

-- Which ranks a trainer teaches can't be read from its title (a "Superior Cook" is not a rank, and some trainers have
-- no title), so it comes from data, each a ",75,150," list of caps:
--   ranks: what the trainer's window has offered (in your own entry, and in the shipped recordings of other players);
--   noRanks: what it was seen not to offer;
--   classicRanks: every rank the classic database lists for it (shipped entries only), the fallback for the rest.
local function Listed(list, cap)
    return list ~= nil and list:find("," .. cap .. ",", 1, true) ~= nil
end

local function AddCap(list, cap)
    if Listed(list, cap) then return list end
    return (list or ",") .. cap .. ","
end

-- True when the trainer teaches the rank, false when it is known not to, nil when nothing says either way. What you
-- have seen in game wins over other players' recordings, and those over the classic database.
function W.TeachesRank(npcId, cap)
    local mine, shipped = FP.db.trainers[npcId], FP.NpcData.trainers[npcId]
    for _, e in ipairs({ mine or false, shipped or false }) do
        if e and Listed(e.ranks, cap) then return true end
        if e and Listed(e.noRanks, cap) then return false end
    end
    if shipped and shipped.classicRanks then return Listed(shipped.classicRanks, cap) end
end

local function Filter(list, pred)
    local out = {}
    for _, c in ipairs(list) do if pred(c) then out[#out + 1] = c end end
    return out
end

-- First Aid, Cooking and Fishing need a skill book from a vendor for Expert, and a quest for Artisan.
-- Keep these ids in step with SKILL_BOOKS and ARTISAN_NPCS in tools/gen_npcs.py, which adds them to the shipped data.
local EXPERT_BOOKS = { [129] = 16084, [185] = 16072, [356] = 16083 }
local JOURNEYMAN_CAP, BOOK_MIN_SKILL = 150, 125
-- Who ends the Artisan quest: First Aid has a doctor for each faction (Gustaf, Gregory), Cooking has Dirge, Fishing has Nat Pagle.
local ARTISAN_NPCS = { [129] = { 12939, 12920 }, [185] = { 8125 }, [356] = { 12919 } }
local EXPERT_CAP, ARTISAN_MIN_SKILL = 225, 225

-- The book to buy for a secondary profession's next rank, once its skill is high enough to read it.
function W.SkillBook(skillLine, rank, maxRank)
    local book = EXPERT_BOOKS[skillLine]
    if book and maxRank == JOURNEYMAN_CAP and (rank or 0) >= BOOK_MIN_SKILL then return book end
end

function W.SkillBookName(book)
    local name = C_Item.GetItemNameByID(book)
    if not name then C_Item.RequestLoadItemDataByID(book) end
    return name or L["a skill book"]
end

local function GoToSkillBook(book, profession)
    local name = W.SkillBookName(book)
    FP:Print(L["%s needs a skill book from a vendor, not a trainer: %s."]:format(profession, name))
    if W:VendorNavAvailable(book) then return W:NearestVendor(book) end
    FP:Print(L["No known location for %s."]:format(name))
end

-- The places of your faction where the Artisan quest ends.
local function ArtisanSpots(skillLine)
    local out = {}
    for _, id in ipairs(ARTISAN_NPCS[skillLine] or {}) do
        local e = FP.NpcData.artisan[id]
        if e and W.Usable(e) then out[#out + 1] = { id = id, name = e.npc, uiMap = e.uiMap, x = e.x, y = e.y, area = e.zone } end
    end
    return out
end

-- The NPC to see for a secondary profession's Artisan rank, once it is capped at Expert and 225 skill.
function W.ArtisanQuest(skillLine, rank, maxRank)
    if maxRank == EXPERT_CAP and (rank or 0) >= ARTISAN_MIN_SKILL then return ArtisanSpots(skillLine)[1] end
end

local function GoToArtisan(skillLine, profession)
    local pick, dist = W.PickNearest(ArtisanSpots(skillLine))
    if not pick then return end
    local where = W.Where(pick.name, pick.area)
    W.PlaceNearest(pick, dist, ("%s (%s)"):format(where, profession),
        "Artisan %s is a quest, not a trainer: %s (about %d yards)", "Artisan %s is a quest, not a trainer: %s (on another continent)",
        profession, where)
end

-- Recorded and shipped trainers for the profession, plus Questie's (by NPC subtitle) for the NPCs those lack.
local function TrainerCandidates(db, zoneDB, profession)
    local cands, have = {}, {}
    for id, t in W.Known("trainers") do
        if W.Usable(t) and (Teaches(t.sub, profession) or (t.skill and t.skill:lower() == profession:lower())) then
            cands[#cands + 1] = { id = id, sub = t.sub or t.skill, uiMap = t.uiMap, x = t.x, y = t.y, name = t.npc, area = t.zone }
            have[id] = true
        end
    end
    if db then
        for sub, ids in pairs(indexes.sub.map) do
            if Teaches(sub, profession) then
                for _, id in ipairs(ids) do
                    if not have[id] and Friendly(db, id) then
                        for _, spot in ipairs(Spawns(db, zoneDB, id)) do
                            spot.id, spot.sub = id, sub
                            cands[#cands + 1] = spot
                        end
                    end
                end
            end
        end
    end
    return cands
end

function W:NearestTrainer(profession)
    if not self:CheckNav() then return end
    for _, p in ipairs(FP:GetProfessions()) do
        if p.name == profession then
            local book = W.SkillBook(p.skillLine, p.rank, p.maxRank)
            if book then return GoToSkillBook(book, profession) end
            if W.ArtisanQuest(p.skillLine, p.rank, p.maxRank) then return GoToArtisan(p.skillLine, profession) end
        end
    end
    local db, zoneDB = Questie()
    W.Search("sub", db, function()
        local cands = TrainerCandidates(db, zoneDB, profession)
        -- Trainers known to teach the rank you need; failing that, the ones nothing is known about.
        local wanted = WantedCap(profession)
        local pool = Filter(cands, function(c) return W.TeachesRank(c.id, wanted) == true end)
        if #pool == 0 then pool = Filter(cands, function(c) return W.TeachesRank(c.id, wanted) == nil end) end

        local pick, dist = W.PickNearest(pool)
        if not pick then return FP:Print(L["No known %s trainer location. Visit one and it will be remembered."]:format(profession)) end
        local label = ("%s (%s)"):format(profession, _G[RANK_GLOBALS[wanted / RANK_STEP]])
        local where = W.Where(pick.name or (db and db.QueryNPCSingle(pick.id, "name")) or "?", pick.area)
        W.PlaceNearest(pick, dist, ("%s (%s)"):format(where, pick.sub),
            "Nearest %s trainer: %s (about %d yards)", "Nearest %s trainer: %s (on another continent)", label, where)
    end)
end

---------------------------------------------------------------------------
-- Every trainer window you open is recorded, so recipes can later say who teaches them.
---------------------------------------------------------------------------
-- Adds npcId to a "1,2,3" list; the second return is false when it was already there.
local function AddId(list, npcId)
    if not list then return tostring(npcId), true end
    for v in list:gmatch("%d+") do
        if tonumber(v) == npcId then return list, false end
    end
    return list .. "," .. npcId, true
end

local function FirstUsableTrainer(ids)
    for v in (ids or ""):gmatch("%d+") do
        local t = W.KnownEntry("trainers", tonumber(v))
        if t and W.Usable(t) then return t end
    end
end

-- The first recorded or shipped trainer of your faction that teaches the recipe.
function W:TrainerFor(recipeID)
    local e = FP.Recipes.byID[recipeID]
    if not e then return end
    return FirstUsableTrainer(FP.db.trainerRecipes[e.name]) or FirstUsableTrainer(FP.NpcData.trainerRecipes[e.name])
end

local function UnitSubtitle()
    local data = C_TooltipInfo.GetUnit("npc")
    local line = data and data.lines and data.lines[2]
    return line and line.leftText
end

-- The next rank a trainer can teach you shows as its own service, apart from the recipes (the game's window puts it in
-- a box under the list), so each visit tells one thing about the trainer: it offers the rank after your current
-- one, or, when you are at your cap and its list hides nothing, it doesn't. `step` is that service's index, or nil.
local function RecordRanks(entry, step)
    local line = step and GetTrainerServiceSkillLine(step) or entry.skill
    local cap, atCap
    for _, p in ipairs(FP:GetProfessions()) do
        if p.name == line then cap, atCap = p.maxRank, p.rank >= p.maxRank end
    end
    local nextCap = (cap or 0) + RANK_STEP
    if nextCap > MAX_CAP then return end
    if step then
        entry.ranks = AddCap(entry.ranks, nextCap)
        entry.skill = entry.skill or line
    elseif atCap and not Listed(entry.ranks, nextCap)
        and GetTrainerServiceTypeFilter("available") and GetTrainerServiceTypeFilter("unavailable") then
        entry.noRanks = AddCap(entry.noRanks, nextCap)
    end
end

local function ScanTrainer()
    if not IsTradeskillTrainer() then return end -- class, riding and weapon trainers are none of our business
    -- The trainer itself is remembered whether or not the client lets us read its recipe list.
    local entry, npcId, isNew = W.Remember("trainers")
    if not entry then return end
    local sub = UnitSubtitle()
    entry.sub = sub and sub:gsub("^<(.*)>$", "%1") or entry.sub
    local npc = entry.npc
    if isNew then FP:Print(L["Remembered trainer: %s (%s)"]:format(npc or "?", entry.sub or "?")) end

    local learned, skills = 0, {}
    local step = GetTrainerServiceStepIndex()
    for i = 1, GetNumTrainerServices() do
        local name, serviceType = GetTrainerServiceInfo(i)
        if name and serviceType ~= "header" and i ~= step then
            local ids, added = AddId(FP.db.trainerRecipes[name], npcId)
            if added then learned = learned + 1 end
            FP.db.trainerRecipes[name] = ids
            -- A profession trainer's recipes name their skill, which doubles as the trainer's profession.
            local skill = GetTrainerServiceSkillReq(i)
            if type(skill) == "string" and skill ~= "" then skills[skill] = (skills[skill] or 0) + 1 end
        end
    end
    local top, topN = nil, 0
    for skill, n in pairs(skills) do if n > topN then top, topN = skill, n end end
    entry.skill = top or entry.skill -- a list with every recipe learned and hidden names no skill
    RecordRanks(entry, step)
    if learned > 0 then FP:Print(L["Learned %d recipes from %s."]:format(learned, npc)) end
end

-- TRAINER_UPDATE can fire in bursts; scan once after it settles.
local scanPending
local function ScanSoon()
    scanPending = false
    if UnitExists("npc") then ScanTrainer() end
end
local function OnTrainerEvent()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.3, ScanSoon)
end
FP:RegisterEvent("TRAINER_SHOW", OnTrainerEvent)
FP:RegisterEvent("TRAINER_UPDATE", OnTrainerEvent)
