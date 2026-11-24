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
-- It only drops the cached plans; the caller says what changed with FP:Changed, which redraws the windows.
-- Requirement changes (queue contents, craft quantity) need no call because the requirements are part of the cache key.
function Planner:Invalidate()
    version = version + 1
    if cacheSize > 0 then wipe(cached) cacheSize = 0 end
end

function Planner:SetMode(mode)
    FP.db.altMode = mode
    FP:RefreshPlanning()
end

-- Settings or alt-cache changes: recalculate and redraw every consumer of the plan.
function FP:RefreshPlanning()
    Planner:Invalidate()
    self:Changed("plan")
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

-- Plans are made for a crafter: the current character (nil), or another one whose profession is viewed in the main
-- window (its key, see Alts/AltProfessions.lua). Bags, bank, their total, and mail of an item that `key`
-- (nil = current) holds; mail is apart from the total, as in Inv:Owned.
function Planner:Holding(key, id)
    if key == nil or key == FP.Alts:GetCharacterKey() then return FP.Inv:Owned(id) end
    local bags, bank, mail = FP.Alts:Counts(key)
    local b, k = bags[id] or 0, bank[id] or 0
    return b, k, b + k, mail[id] or 0
end

-- Everything `key` (nil = current) holds of an item: bags, bank and mail together.
function Planner:HeldInAll(key, id)
    local _, _, total, mail = self:Holding(key, id)
    return total + mail
end

-- The characters that can supply the crafter: Alts:Eligible() for the current one; for another, every enabled
-- character of its faction (mail can't cross factions), the current one included.
local function Sources(crafter)
    if not crafter then return FP.Alts:Eligible() end
    local chars, me, out = FP.db.characters, FP.Alts:GetCharacterKey(), {}
    local faction = chars[crafter].faction
    for _, key in ipairs({ me, unpack(FP.Alts:Eligible()) }) do
        local rec = chars[key]
        if key ~= crafter and (faction == nil or rec.faction == nil or rec.faction == faction) then out[#out + 1] = key end
    end
    return out
end

local function Allocate(list, mode, crafter)
    local Alts = FP.Alts
    local chars = FP.db.characters
    local applies = mode == "include"
    local items, byItem = {}, {}
    local result = { mode = mode, applies = applies, items = items, byItem = byItem, characters = {}, byCharacter = {} }
    local sources = mode == "never" and {} or Sources(crafter)

    local selected = {}
    -- o is an option of item it; it becomes one of the item's sources.
    local function Take(it, o, take)
        o.left = o.left - take
        o.transfer, o.fromBags = take, min(o.bags, take)
        o.fromBank = min(o.bank, take - o.fromBags)
        o.fromMail = take - o.fromBags - o.fromBank
        selected[o.key] = true
        it.sources[#it.sources + 1] = o
        it.transfer = it.transfer + take
    end

    local short, score = {}, {}
    for i, req in ipairs(list) do
        local id = req.itemID
        -- What waits in the crafter's mailbox is its own: it counts as had, after the bags and the bank.
        local bags, bank, total, mail = Planner:Holding(crafter, id)
        local it = { itemID = id, need = req.need, bags = bags, bank = bank, mail = mail, have = total + mail,
            fromMail = max(0, min(mail, req.need - total)),
            localShort = max(0, req.need - total - mail), altAvailable = 0, transfer = 0, sources = {}, options = {} }
        local open, touched = {}, false
        for _, key in ipairs(sources) do
            local rec = chars[key]
            local b, k, held, m = Planner:Holding(key, id)
            held = held + m
            if held > 0 then
                -- Amounts chosen by hand are saved with the crafter's queue, so every plan for it uses them.
                local want = Alts:Taken(key, id, crafter)
                if want ~= nil then touched = true end
                if want ~= 0 then it.altAvailable = it.altAvailable + held end
                if it.localShort > 0 then
                    -- Every character holding the material is offered, whether or not it ends up supplying any.
                    local o = { key = key, name = rec.name or key, realm = rec.realm, class = rec.class,
                        owns = held, bags = b, bank = k, mail = m, left = held, transfer = 0, fromBags = 0, fromBank = 0, fromMail = 0,
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
                c = { key = s.key, name = s.name, realm = s.realm, class = s.class, items = {}, units = 0, usesBank = false,
                    usesMail = false }
                result.byCharacter[s.key] = c
                result.characters[#result.characters + 1] = c
            end
            c.items[#c.items + 1] = { itemID = it.itemID, need = it.need, transfer = s.transfer, owns = s.owns,
                fromBags = s.fromBags, fromBank = s.fromBank, fromMail = s.fromMail }
            c.units = c.units + s.transfer
            if s.fromBank > 0 then c.usesBank = true end
            if s.fromMail > 0 then c.usesMail = true end
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
--   items[i] / byItem[id] = { itemID, need, bags, bank, mail, have (all three), fromMail (what must be collected
--                             from the mailbox), localShort, altAvailable, transfer, stillMissing,
--                             shortage (what still has to be acquired when alts count),
--                             options = { every enabled character holding it, while it is short: key, name, realm, class,
--                             owns, bags, bank, mail, transfer, fromBags, fromBank, fromMail, manual (amount chosen by
--                             hand), off (set to 0) },
--                             sources = the options that supply something, largest first }
--   characters = { { key, name, realm, class, items = { itemID, transfer, owns, ... }, units, usesBank } }
--   totals, applies
-- Treat the result as read-only. Amounts chosen per character in the Transfer Planner (Alts:SetTake) are final for
-- that material: once any character is set by hand, the planner no longer fills the rest from the others.
-- `crafter`: another character's key to plan for it instead (see Holding); nil plans for the current character.
function Planner:Plan(reqs, crafter)
    local mode = self:Mode()
    local key = mode .. "|" .. (crafter or "") .. "|" .. Signature(reqs)
    local hit = cached[key]
    if hit then return hit end
    if cacheSize >= MAX_CACHED then wipe(cached) cacheSize = 0 end
    local result = Allocate(Normalize(reqs), mode, crafter)
    cached[key], cacheSize = result, cacheSize + 1
    return result
end

-- Crafts possible when everything enabled alts hold is added to what the crafter (nil = current character) has.
-- reagents: { itemID, qty }. Never lower than the crafter alone can do.
function Planner:MaxCrafts(reagents, crafter)
    if #reagents == 0 then return 0 end
    local useAlts = self:Mode() ~= "never"
    local sources = crafter and useAlts and Sources(crafter)
    local best = huge
    for _, r in ipairs(reagents) do
        local _, _, total = self:Holding(crafter, r.itemID)
        local alts = 0
        if sources then
            for _, key in ipairs(sources) do
                local _, _, held, mail = self:Holding(key, r.itemID)
                alts = alts + held + mail
            end
        elseif useAlts then
            alts = FP.Alts:GetEnabledAltTotal(r.itemID)
        end
        best = min(best, floor((total + alts) / r.qty))
    end
    return best
end

---------------------------------------------------------------------------
-- What the current character should fetch from its own bank and mailbox
---------------------------------------------------------------------------
-- What this character must have in its bags: per material, what its queue (`plan`, its own) needs plus what it has
-- to send its other characters (Outgoing:SendTotals). Entries are { itemID, need, bags, bank, mail }: the plan's
-- materials in its order, then those it only sends, by item.
local function Wanted(plan)
    local sends, out, extra = FP.Outgoing:SendTotals(), {}, {}
    for _, it in ipairs(plan.items) do
        out[#out + 1] = { itemID = it.itemID, need = it.need + (sends[it.itemID] or 0), bags = it.bags, bank = it.bank, mail = it.mail }
        sends[it.itemID] = nil
    end
    for itemID, qty in pairs(sends) do
        local bags, bank, _, mail = FP.Inv:Owned(itemID)
        extra[#extra + 1] = { itemID = itemID, need = qty, bags = bags, bank = bank, mail = mail }
    end
    table.sort(extra, function(a, b) return a.itemID < b.itemID end)
    for _, w in ipairs(extra) do out[#out + 1] = w end
    return out
end

-- What this character's bank must supply for its queue and its sends: for each material, the part bags don't cover
-- that the bank does. `plan` is its own.
function Planner.BankNeeds(plan)
    local out = {}
    for _, w in ipairs(Wanted(plan)) do
        local qty = math.min(w.bank, math.max(0, w.need - w.bags))
        if qty > 0 then out[#out + 1] = { itemID = w.itemID, qty = qty, bank = w.bank } end
    end
    return out
end

-- What can be collected from the mailbox. For this character's own plan: for each material its queue and its sends
-- need, the part bags don't cover that the mailbox does. The bank is offered the same part (BankNeeds), so either one
-- can be fetched, whichever is at hand, and fetching it clears the other. For another character's plan (`view`, its
-- key): what its queue needs that its bags and bank don't cover.
function Planner.MailNeeds(plan, view)
    local out = {}
    if view then
        for _, it in ipairs(plan.items) do
            if it.fromMail > 0 then out[#out + 1] = { itemID = it.itemID, qty = it.fromMail, mail = it.mail } end
        end
        return out
    end
    for _, w in ipairs(Wanted(plan)) do
        local short = math.max(0, w.need - w.bags)
        local qty = math.min(w.mail, short)
        -- `either`: the bank is offered some of the same part, so not both amounts have to be fetched.
        if qty > 0 then
            out[#out + 1] = { itemID = w.itemID, qty = qty, mail = w.mail, either = math.min(w.bank, short) + qty > short }
        end
    end
    return out
end
