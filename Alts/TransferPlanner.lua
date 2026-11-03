local _, FP = ...
local Planner = {}
FP.Planner = Planner

-- The single allocator of other characters' stock against material requirements. Everything that shows or
-- uses a transfer suggestion (recipe tooltips, reagent cards, the Transfer panel, queue and shopping shortages)
-- reads the result of Plan(), so one requirement set always has one answer.
-- Modes: "never" ignores alts, "show" allocates for display only, "include" also lets the allocation reduce shortages.
Planner.MODES = { "never", "show", "include" }

local max, min, floor, huge = math.max, math.min, math.floor, math.huge

local version, cached, cacheSize = 0, {}, 0
local MAX_CACHED = 48
local sigBuffer = {}

function Planner:Mode()
    local m = FP.db.altMode
    return (m == "never" or m == "show") and m or "include"
end

-- True when allocated alt stock reduces shortages (queue, shopping list); otherwise it is shown only.
function Planner:Applies() return self:Mode() == "include" end

function Planner:Version() return version end

-- Anything that can change a plan's inputs calls this: bags, bank, alt snapshots, enabled characters, the mode.
-- Requirement changes (queue contents, craft quantity) need no call because the requirements are part of the cache key.
function Planner:Invalidate()
    version = version + 1
    if cacheSize > 0 then wipe(cached) cacheSize = 0 end
    if FP.Transfer then FP.Transfer:QueueUpdate() end
end

function Planner:SetMode(mode)
    FP.db.altMode = mode
    FP:RefreshPlanning()
end

-- Settings or alt-cache changes: recalculate and redraw every consumer of the plan.
function FP:RefreshPlanning()
    Planner:Invalidate()
    self.Shop:SyncFromQueue()
    self.UI:QueueRefresh()
    self.Queue:Update()
    self.Shop:Update()
    if self.Options.RefreshCharacters then self.Options:RefreshCharacters() end
end

-- Merges repeated items; entries are { itemID, need }.
local function Normalize(reqs)
    local list, by = {}, {}
    for _, r in ipairs(reqs) do
        local need = r.need or 0
        if need > 0 then
            local n = by[r.itemID]
            if n then
                n.need = n.need + need
            else
                n = { itemID = r.itemID, need = need }
                by[r.itemID] = n
                list[#list + 1] = n
            end
        end
    end
    return list
end

local function Signature(reqs)
    local n = 0
    for _, r in ipairs(reqs) do
        sigBuffer[n + 1], sigBuffer[n + 2] = r.itemID, r.need or 0
        n = n + 2
    end
    for i = #sigBuffer, n + 1, -1 do sigBuffer[i] = nil end
    return table.concat(sigBuffer, ":")
end

local function Allocate(list, mode)
    local Alts, Inv = FP.Alts, FP.Inv
    local chars = FP.db.characters
    local applies = mode == "include"
    local items, byItem = {}, {}
    local result = { mode = mode, applies = applies, items = items, byItem = byItem, characters = {}, byCharacter = {} }
    local sources = mode == "never" and {} or Alts:Eligible()

    local selected = {}
    -- o is an option of item it; it becomes one of the item's sources.
    local function Take(it, o, take)
        o.left = o.left - take
        o.transfer, o.fromBags = take, min(o.bags, take)
        o.fromBank = take - o.fromBags
        selected[o.key] = true
        it.sources[#it.sources + 1] = o
        it.transfer = it.transfer + take
    end

    local short, score = {}, {}
    for i, req in ipairs(list) do
        local id = req.itemID
        local bags, bank, total = Inv:Owned(id)
        local it = { itemID = id, need = req.need, bags = bags, bank = bank, have = total,
            localShort = max(0, req.need - total), altAvailable = 0, transfer = 0, sources = {}, options = {} }
        local open, touched = {}, false
        for _, key in ipairs(sources) do
            local rec = chars[key]
            local bagCount, bankCount = Alts:Counts(key)
            local b, k = bagCount[id] or 0, bankCount[id] or 0
            if b + k > 0 then
                local want = Alts:Taken(key, id)
                if want ~= nil then touched = true end
                if want ~= 0 then it.altAvailable = it.altAvailable + b + k end
                if it.localShort > 0 then
                    -- Every character holding the material is offered, whether or not it ends up supplying any.
                    local o = { key = key, name = rec.name or key, realm = rec.realm, class = rec.class,
                        owns = b + k, bags = b, bank = k, left = b + k, transfer = 0, fromBags = 0, fromBank = 0,
                        manual = want ~= nil, off = want == 0 }
                    it.options[#it.options + 1] = o
                    if want == nil then
                        open[#open + 1] = o
                    elseif want > 0 then
                        Take(it, o, min(want, o.left))
                    end
                end
            end
        end
        items[i], byItem[id] = it, it
        -- Amounts chosen by hand are final for that material: the planner doesn't fill the rest from other characters.
        local remaining = max(0, it.localShort - it.transfer)
        if remaining > 0 and #open > 0 and not touched then
            it.open, it.remaining = open, remaining
            short[#short + 1] = it
            for _, o in ipairs(open) do score[o.key] = (score[o.key] or 0) + min(o.left, remaining) end
        end
    end

    -- Biggest shortages first, so the characters that matter most for them are chosen before the small ones.
    table.sort(short, function(a, b)
        if a.remaining ~= b.remaining then return a.remaining > b.remaining end
        return a.itemID < b.itemID
    end)

    -- Fewest character switches: characters already in the plan, then those useful for most shortages.
    local function Better(a, b)
        if (selected[a.key] or false) ~= (selected[b.key] or false) then return selected[a.key] or false end
        if score[a.key] ~= score[b.key] then return score[a.key] > score[b.key] end
        if a.left ~= b.left then return a.left > b.left end
        return a.key < b.key
    end

    for _, it in ipairs(short) do
        local open, remaining = it.open, it.remaining
        table.sort(open, Better)
        local pool = open
        for _, o in ipairs(open) do
            if o.left >= remaining then pool = { o } break end -- one character covers it all
        end
        for _, o in ipairs(pool) do
            if remaining == 0 then break end
            local take = min(o.left, remaining)
            remaining = remaining - take
            Take(it, o, take)
        end
        it.open, it.remaining = nil, nil
    end

    local totals = { characters = 0, itemTypes = 0, units = 0, shortTypes = 0, shortUnits = 0,
        missingTypes = 0, missingUnits = 0, covered = true }
    result.totals = totals
    for _, it in ipairs(items) do
        it.stillMissing = max(0, it.localShort - it.transfer)
        it.shortage = applies and it.stillMissing or it.localShort
        if it.localShort > 0 then
            totals.shortTypes, totals.shortUnits = totals.shortTypes + 1, totals.shortUnits + it.localShort
        end
        if it.stillMissing > 0 then
            totals.missingTypes, totals.missingUnits = totals.missingTypes + 1, totals.missingUnits + it.stillMissing
            totals.covered = false
        end
        if it.transfer > 0 then
            totals.itemTypes, totals.units = totals.itemTypes + 1, totals.units + it.transfer
        end
        table.sort(it.sources, function(a, b)
            if a.transfer ~= b.transfer then return a.transfer > b.transfer end
            return a.key < b.key
        end)
        for _, s in ipairs(it.sources) do
            local c = result.byCharacter[s.key]
            if not c then
                c = { key = s.key, name = s.name, realm = s.realm, class = s.class, items = {}, units = 0, usesBank = false }
                result.byCharacter[s.key] = c
                result.characters[#result.characters + 1] = c
            end
            c.items[#c.items + 1] = { itemID = it.itemID, need = it.need, transfer = s.transfer, owns = s.owns,
                fromBags = s.fromBags, fromBank = s.fromBank }
            c.units = c.units + s.transfer
            if s.fromBank > 0 then c.usesBank = true end
        end
    end
    totals.characters = #result.characters
    table.sort(result.characters, function(a, b)
        local na, nb = a.name:lower(), b.name:lower()
        if na ~= nb then return na < nb end
        return a.key < b.key
    end)
    return result
end

-- reqs: array of { itemID, need }. Returns the shared, cached result:
--   items[i] / byItem[id] = { itemID, need, bags, bank, have, localShort, altAvailable, transfer, stillMissing,
--                             shortage (what still has to be acquired when alts count),
--                             options = { every enabled character holding it, while it is short: key, name, realm, class,
--                             owns, bags, bank, transfer, fromBags, fromBank, manual (amount chosen by hand), off (set to 0) },
--                             sources = the options that supply something, largest first }
--   characters = { { key, name, realm, class, items = { itemID, transfer, owns, ... }, units, usesBank } }
--   totals, applies
-- Treat the result as read-only. Amounts chosen per character in the Transfer Planner (Alts:SetTake) are final for
-- that material: once any character is set by hand, the planner no longer fills the rest from the others.
function Planner:Plan(reqs)
    local mode = self:Mode()
    local key = mode .. "|" .. Signature(reqs)
    local hit = cached[key]
    if hit then return hit end
    if cacheSize >= MAX_CACHED then wipe(cached) cacheSize = 0 end
    local result = Allocate(Normalize(reqs), mode)
    cached[key], cacheSize = result, cacheSize + 1
    return result
end

-- Crafts possible when everything enabled alts hold is added to what the current character has.
-- reagents: { itemID, qty }. Never lower than the current character alone can do.
function Planner:MaxCrafts(reagents)
    if #reagents == 0 then return 0 end
    local useAlts = self:Mode() ~= "never"
    local best = huge
    for _, r in ipairs(reagents) do
        local _, _, total = FP.Inv:Owned(r.itemID)
        local alts = useAlts and FP.Alts:GetEnabledAltTotal(r.itemID) or 0
        best = min(best, floor((total + alts) / r.qty))
    end
    return best
end
