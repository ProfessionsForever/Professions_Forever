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

-- Forever tops out at 300: one tier per 75 skill points.
local TIERS = { "apprentice", "journeyman", "expert", "artisan" }
local TIER_WORDS = { apprentice = "apprentice", junior = "apprentice", journeyman = "journeyman", expert = "expert",
    artisan = "artisan" }

local function RankOf(sub)
    if not sub then return nil end
    local low = sub:lower()
    for word, tier in pairs(TIER_WORDS) do
        if HasWord(low, word) then return tier end
    end
end

local function Teaches(sub, profession)
    if not sub then return false end
    local low, prof = sub:lower(), profession:lower()
    if HasWord(low, prof) and HasWord(low, "trainer") then return true end
    for _, title in ipairs(CRAFT_TITLES[prof] or {}) do
        if HasWord(low, title) and RankOf(sub) then return true end
    end
    return false
end

-- The tier worth visiting: your current one, or the next once you've hit its cap.
local function WantedTier(profession)
    for _, p in ipairs(FP:GetProfessions()) do
        if p.name == profession and (p.maxRank or 0) > 0 then
            local i = p.maxRank / 75
            if (p.rank or 0) >= p.maxRank then i = i + 1 end
            return TIERS[math.min(i, #TIERS)]
        end
    end
end

local function Filter(list, pred)
    local out = {}
    for _, c in ipairs(list) do if pred(c) then out[#out + 1] = c end end
    return out
end

-- Questie's trainers for the profession (by NPC subtitle), plus any you've opened.
local function TrainerCandidates(db, zoneDB, profession)
    local cands = {}
    if db then
        for sub, ids in pairs(indexes.sub.map) do
            if Teaches(sub, profession) then
                for _, id in ipairs(ids) do
                    if Friendly(db, id) then
                        for _, spot in ipairs(Spawns(db, zoneDB, id)) do
                            spot.id, spot.sub, spot.tier = id, sub, RankOf(sub)
                            cands[#cands + 1] = spot
                        end
                    end
                end
            end
        end
    end
    -- Opened trainers cover NPCs Questie lacks or has no spawn for.
    for id, t in W.Known("trainers") do
        if W.Usable(t) and (Teaches(t.sub, profession) or (t.skill and t.skill:lower() == profession:lower())) then
            cands[#cands + 1] = { id = id, sub = t.sub or t.skill, tier = RankOf(t.sub), uiMap = t.uiMap, x = t.x, y = t.y, name = t.npc }
        end
    end
    return cands
end

function W:NearestTrainer(profession)
    if not self:CheckNav() then return end
    local db, zoneDB = Questie()
    W.Search("sub", db, function()
        local cands = TrainerCandidates(db, zoneDB, profession)
        -- Prefer trainers of the tier you need, then unranked ones, then anything that teaches the profession.
        local wanted = WantedTier(profession)
        local pool = wanted and Filter(cands, function(c) return c.tier == wanted end) or {}
        local exact = #pool > 0
        if not exact then pool = Filter(cands, function(c) return c.tier == nil end) end
        if #pool == 0 then pool = cands end

        local pick, dist = W.PickNearest(pool)
        if not pick then return FP:Print(L["No known %s trainer location. Visit one and it will be remembered."]:format(profession)) end
        local label = exact and ("%s (%s)"):format(profession, (wanted:gsub("^%l", string.upper))) or profession
        local name = pick.name or (db and db.QueryNPCSingle(pick.id, "name")) or "?"
        W.PlaceNearest(pick, dist, ("%s (%s)"):format(name, pick.sub),
            "Nearest %s trainer: %s (about %d yards)", "Nearest %s trainer: %s (on another continent)", label, name)
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

local function ScanTrainer()
    -- The trainer itself is remembered whether or not the client lets us read its recipe list.
    local entry, npcId, isNew = W.Remember("trainers")
    if not entry then return end
    local sub = UnitSubtitle()
    entry.sub = sub and sub:gsub("^<(.*)>$", "%1") or entry.sub
    local npc = entry.npc
    if isNew then FP:Print(L["Remembered trainer: %s (%s)"]:format(npc or "?", entry.sub or "?")) end
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return end

    local learned, skills = 0, {}
    for i = 1, GetNumTrainerServices() do
        local name, _, category = GetTrainerServiceInfo(i)
        if name and category ~= "header" then
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
    entry.skill = top
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
