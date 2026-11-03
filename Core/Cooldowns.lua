local _, FP = ...
local L = FP.L
local Cooldowns = {}
FP.Cooldowns = Cooldowns

-- FP.db.characters[key].cooldowns[recipeID] = { name, icon, prof, readyAt }, kept for every character.
-- A recipe is tracked once it is seen on cooldown, or learned and listed in FP.CooldownData (Data/Cooldowns.lua: its
-- cooldown length and shared category). readyAt is a server timestamp, 0 once seen ready, so nothing is read from
-- the game again for it until the profession is next opened or the recipe is cast. `ignored` entries are the ones the
-- user turned off.

local Data = FP.CooldownData
local floor, max = math.floor, math.max
local DAY, HOUR, MINUTE = 86400, 3600, 60
local MIN_SPELL_COOLDOWN = 60 -- the spell-cooldown fallback ignores the global cooldown and other short ones
local SCAN_INTERVAL = 5 -- seconds before the same profession is scanned again
local CLOCK = "|TInterface\\Icons\\INV_Misc_PocketWatch_01:12|t"
local lastScan = {}

-- Seconds left on a recipe's cooldown, or nil when it has none. The recipe call needs the profession open; the spell
-- cooldown is the fallback for a recipe cast from a macro with the window closed.
local function ReadRemaining(recipeID)
    local ok, cooldown, _, charges = pcall(C_TradeSkillUI.GetRecipeCooldown, recipeID)
    if ok and cooldown then
        if (charges or 0) > 0 then return nil end -- a charge is available
        return cooldown
    end
    local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(recipeID)
    if info and (info.duration or 0) > MIN_SPELL_COOLDOWN then
        local left = info.startTime + info.duration - GetTime()
        if left > 0 then return left end
    end
end

local function OpenProfession()
    local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    if base then return base.professionName, base.professionID end
end

-- The current character's tracked cooldowns, created on first use.
local function Mine()
    local rec = FP.Alts:Current()
    if not rec then return end
    rec.cooldowns = rec.cooldowns or {}
    return rec.cooldowns
end

local function Entry(recipeID)
    local rec = FP.db.characters[FP.Alts:GetCharacterKey()]
    return rec and rec.cooldowns and rec.cooldowns[recipeID]
end

-- The entry of a recipe that is tracked: one the user ignored still exists, but counts as untracked.
local function Active(recipeID)
    local c = Entry(recipeID)
    if c and not c.ignored then return c end
end

-- Stores what was read for a recipe: a cooldown starts tracking it, no cooldown marks a tracked one ready, and a
-- recipe with a known cooldown length is tracked as ready. `src` supplies name and icon. Returns whether anything changed.
local function Observe(mine, recipeID, src, remaining, prof)
    local c = mine[recipeID]
    if remaining then
        c = c or {}
        mine[recipeID] = c
        c.name, c.icon, c.prof = src.name, src.icon, prof or c.prof
        c.readyAt = GetServerTime() + math.ceil(remaining)
        return true
    end
    if not c then
        if not Data[recipeID] then return end
        mine[recipeID] = { name = src.name, icon = src.icon, prof = prof, readyAt = 0 }
        return true
    end
    if c.readyAt ~= 0 then
        c.readyAt = 0
        return true
    end
end

-- "1d 23h", "3h", "12m": zero parts are left out.
function Cooldowns.Format(seconds)
    seconds = math.ceil(seconds)
    local d, h, m = floor(seconds / DAY), floor(seconds % DAY / HOUR), floor(seconds % HOUR / MINUTE)
    if d > 0 then return h > 0 and L["%dd %dh"]:format(d, h) or L["%dd"]:format(d) end
    if h > 0 then return m > 0 and L["%dh %dm"]:format(h, m) or L["%dh"]:format(h) end
    if m > 0 then return L["%dm"]:format(m) end
    return L["<1m"]
end

-- The recipe's cooldown in seconds, nil when the data doesn't know it.
function Cooldowns.Length(recipeID)
    local d = Data[recipeID]
    return d and d[1]
end

function Cooldowns:IsTracked(recipeID) return Active(recipeID) ~= nil end

-- The skill line a list entry's recipe belongs to: from the data, else the profession it was seen in.
function Cooldowns.SkillLine(entry)
    local d = Data[entry.id]
    if d then return d[2] end
    for _, p in ipairs(FP:GetProfessions()) do
        if p.name == entry.prof then return p.skillLine end
    end
end

-- Seconds until the current character can use the recipe again: 0 when ready, nil when it has no known cooldown.
function Cooldowns:Remaining(recipeID)
    local c = Active(recipeID)
    return c and max(0, c.readyAt - GetServerTime())
end

function Cooldowns:IsOnCooldown(recipeID)
    local left = self:Remaining(recipeID)
    return left ~= nil and left > 0
end

-- The detail pane line, coloured: the cooldown's length, then ready or the time left. Empty for a recipe without one.
function Cooldowns:DetailText(recipeID)
    local c = Entry(recipeID)
    if c and c.ignored then return "" end
    local length, left = self.Length(recipeID), self:Remaining(recipeID)
    if not (length or left) then return "" end
    local e = FP.Recipes.byID[recipeID]
    if left == nil and e and not e.learned then
        return "|cff999999" .. L["Cooldown: %s"]:format(self.Format(length)) .. "|r"
    end
    left = left or 0
    if left == 0 then
        return "|cff33e633" .. (length and L["Cooldown: %s - ready"]:format(self.Format(length)) or L["Cooldown ready"]) .. "|r"
    end
    local text = length and L["Cooldown: %s - %s left"]:format(self.Format(length), self.Format(left))
        or L["Cooldown: %s left"]:format(self.Format(left))
    return "|cffe63333" .. text .. "|r"
end

-- Clock and time for a recipe-list row; only while the recipe is on cooldown.
function Cooldowns:RowText(recipeID)
    local left = self:Remaining(recipeID)
    if not left or left == 0 then return "" end
    return CLOCK .. " |cffe63333" .. self.Format(left) .. "|r  "
end

---------------------------------------------------------------------------
-- Reading the game
---------------------------------------------------------------------------
-- Reads the cooldown of every learned recipe in the open profession.
function Cooldowns:Scan()
    local T = C_TradeSkillUI
    if not (T.IsTradeSkillReady() and FP:IsOwnProfession()) then return end
    local prof, line = OpenProfession()
    local now = GetTime()
    if lastScan[line or 0] and now - lastScan[line or 0] < SCAN_INTERVAL then return end
    lastScan[line or 0] = now
    local mine = Mine()
    if not mine then return end
    local changed
    for _, e in ipairs(FP.Recipes.list) do
        if e.learned and Observe(mine, e.id, e, ReadRemaining(e.id), prof) then changed = true end
    end
    if changed then self:Changed() end
end

-- A craft of a recipe from the open profession, or one already tracked, starts or restarts its cooldown, and the
-- cooldown of every recipe sharing its category. The cooldown may not be set the moment the cast succeeds, so it is
-- read again shortly after.
function Cooldowns:OnCast(spellID)
    if not (FP.Recipes.byID[spellID] or Entry(spellID)) then return end
    local ids, category = { spellID }, Data[spellID] and Data[spellID][3]
    if category then
        wipe(ids)
        for id, d in pairs(Data) do
            if d[3] == category then ids[#ids + 1] = id end
        end
    end
    local function Read()
        local mine = Mine()
        if not mine then return end
        local changed
        for _, id in ipairs(ids) do
            local e = FP.Recipes.byID[id]
            local src = e and e.learned and e or mine[id]
            local remaining = src and ReadRemaining(id)
            if remaining and Observe(mine, id, src, remaining, e and (OpenProfession()) or nil) then changed = true end
        end
        if changed then self:Changed() end
    end
    Read()
    C_Timer.After(0.3, Read)
end

-- Tracks the cooldown recipes this character knows without opening their professions, so alts show up from the first
-- login. Only adds or extends: with the profession closed, "no cooldown" can't be trusted.
function Cooldowns:Probe()
    local mine = Mine()
    if not (mine and IsPlayerSpell) then return end
    local changed
    for id, d in pairs(Data) do
        local info = IsPlayerSpell(id) and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        if info and info.name then
            local src = { name = info.name, icon = info.iconID }
            local remaining = ReadRemaining(id)
            if (remaining or not mine[id]) and Observe(mine, id, src, remaining, C_TradeSkillUI.GetTradeSkillDisplayName(d[2])) then
                changed = true
            end
        end
    end
    if changed then self:Changed() end
end

function Cooldowns:Changed()
    local panel = FP.CooldownPanel
    if panel then panel:Update() end
    FP.UI:RefreshFooter()
end

---------------------------------------------------------------------------
-- Every character
---------------------------------------------------------------------------
-- Several recipes ready in one shared category are named by what precedes the colon in the first such name:
-- "Transmute" for "Transmute: Arcanite".
local function GroupLabel(members)
    for _, name in ipairs(members) do
        local prefix = name:match("^(.-):")
        if prefix then return prefix end
    end
    return members[1]
end

-- Characters with tracked cooldowns, the current one first: { key, rec, ready, readyNames, entries }. Entries are
-- { id, name, icon, prof, readyAt, remaining }, ready ones first, then soonest. `ready` counts recipes sharing a
-- cooldown category once, and `readyNames` names those groups ("Transmute (9)"). The current character also lists every other recipe of its own professions in the data, last,
-- flagged `unknown` (not seen yet), so no cooldown of theirs is ever missing from the tracker.
function Cooldowns:List()
    local now, me = GetServerTime(), FP.Alts:GetCharacterKey()
    local out = {}
    for key, rec in pairs(FP.db.characters) do
        if (rec.cooldowns and next(rec.cooldowns)) or key == me then
            local entries, readyGroups, ready = {}, {}, 0
            for id, c in pairs(rec.cooldowns or {}) do
                if not c.ignored or FP.db.showIgnoredCooldowns then
                    local remaining = max(0, c.readyAt - now)
                    if remaining == 0 and not c.ignored then
                        local group = Data[id] and Data[id][3] or id
                        local members = readyGroups[group]
                        if not members then
                            members = {}
                            readyGroups[group] = members
                            ready = ready + 1
                        end
                        members[#members + 1] = c.name
                    end
                    entries[#entries + 1] = { id = id, name = c.name, icon = c.icon, prof = c.prof, readyAt = c.readyAt,
                        remaining = remaining, ignored = c.ignored }
                end
            end
            if key == me then
                local mine = {}
                for _, p in ipairs(FP:GetProfessions()) do mine[p.skillLine] = true end
                for id, d in pairs(Data) do
                    if mine[d[2]] and not (rec.cooldowns and rec.cooldowns[id]) then
                        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
                        if info and info.name then
                            entries[#entries + 1] = { id = id, name = info.name, icon = info.iconID, unknown = true,
                                prof = C_TradeSkillUI.GetTradeSkillDisplayName(d[2]), remaining = 0 }
                        end
                    end
                end
            end
            table.sort(entries, function(a, b)
                if a.ignored ~= b.ignored then return b.ignored == true end
                if a.unknown ~= b.unknown then return b.unknown == true end
                if a.remaining ~= b.remaining then return a.remaining < b.remaining end
                return a.name < b.name
            end)
            local readyNames = {}
            for _, members in pairs(readyGroups) do
                table.sort(members)
                readyNames[#readyNames + 1] = #members == 1 and members[1] or L["%s (%d)"]:format(GroupLabel(members), #members)
            end
            table.sort(readyNames)
            if #entries > 0 or key == me then
                out[#out + 1] = { key = key, rec = rec, ready = ready, readyNames = readyNames, entries = entries }
            end
        end
    end
    table.sort(out, function(a, b)
        if (a.key == me) ~= (b.key == me) then return a.key == me end
        local na, nb = strlower(a.rec.name or a.key), strlower(b.rec.name or b.key)
        if na ~= nb then return na < nb end
        return a.key < b.key
    end)
    return out
end

function Cooldowns:ReadyTotal()
    local total = 0
    for _, g in ipairs(self:List()) do total = total + g.ready end
    return total
end

-- Ignoring keeps the entry, so scans don't add the recipe back; it is still kept up to date but shows nowhere.
-- `src` ({ name, icon, prof }) is for a recipe that has no entry yet.
function Cooldowns:SetIgnored(key, recipeID, on, src)
    local rec = FP.db.characters[key]
    if not rec then return end
    rec.cooldowns = rec.cooldowns or {}
    local c = rec.cooldowns[recipeID]
    if not c and on and src then
        c = { name = src.name, icon = src.icon, prof = src.prof, readyAt = 0 }
        rec.cooldowns[recipeID] = c
    end
    if c then c.ignored = on and true or nil end
    self:Changed()
    FP.UI:QueueRefresh()
end

-- One chat line per character at login naming its ready cooldowns.
function Cooldowns:Announce()
    if not FP.db.cooldownNotice then return end
    for _, g in ipairs(self:List()) do
        if g.ready > 0 then
            local r, gr, b = FP.Alts:ClassColor(g.rec.class)
            local who = ("|cff%02x%02x%02x%s|r"):format(floor(r * 255 + 0.5), floor(gr * 255 + 0.5), floor(b * 255 + 0.5),
                FP.Alts:Label(g.rec))
            FP:Print(L["Cooldowns ready on %s: %s"]:format(who, table.concat(g.readyNames, ", ")))
        end
    end
end

-- Checks this client against the cooldown data: whether each listed recipe is known without its profession open, and
-- what the game returns for the open profession's learned recipes.
function Cooldowns:Debug()
    local T = C_TradeSkillUI
    local mine = Mine() or {}
    for id, d in pairs(Data) do
        local e = FP.Recipes.byID[id]
        local known = IsPlayerSpell and IsPlayerSpell(id)
        if known or (e and e.learned) or mine[id] then
            FP:Print(("data %d %s: IsPlayerSpell=%s, learned in open profession=%s, tracked=%s, readyAt=%s"):format(id,
                (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or "?", tostring(known),
                tostring(e and e.learned), tostring(mine[id] ~= nil), tostring(mine[id] and mine[id].readyAt)))
        end
    end
    if not T.IsTradeSkillReady() then return FP:Print(L["Open a profession to also check its recipes."]) end
    local scanned, viaRecipe, viaSpell = 0, 0, 0
    for _, e in ipairs(FP.Recipes.list) do
        if e.learned then
            scanned = scanned + 1
            local ok, cooldown, isDay, charges, maxCharges = pcall(T.GetRecipeCooldown, e.id)
            local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(e.id)
            local spellLeft = info and info.duration and info.duration > MIN_SPELL_COOLDOWN
            if ok and cooldown then viaRecipe = viaRecipe + 1 end
            if spellLeft then viaSpell = viaSpell + 1 end
            if ((ok and cooldown) or spellLeft) and not Data[e.id] then
                FP:Print(("not in the data: %s (%d): recipe cooldown=%s day=%s charges=%s/%s, spell duration=%s"):format(e.name, e.id,
                    tostring(cooldown), tostring(isDay), tostring(charges), tostring(maxCharges), tostring(info and info.duration)))
            end
        end
    end
    FP:Print(("cooldowns: %d learned recipes, %d with a recipe cooldown, %d with a spell cooldown"):format(scanned, viaRecipe, viaSpell))
end
