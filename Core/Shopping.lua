local _, FP = ...
local Shop = {}
FP.Shop = Shop

-- The shopping list's data and what is still to buy. The window is Panels/Shopping/ShoppingList.lua.
--
-- Each item's quantity has two parts:
--   * the queues' part, worked out from the crafting queues every time (QueueNeeds), so it follows them;
--   * your part, saved in Data(): what you added yourself, or how far you moved a quantity away from the queues' part.
-- The list shows the two added together. A quantity lowered below the queues' part (or removed) gives a negative part,
-- so the item stays lowered while the queues' need holds and comes back with only what the queues add later. Your part
-- is never below minus the queues' part, so a need that went away doesn't swallow the next one.
-- Owned counts are compared live, so the "to buy" column shrinks as items are acquired.

-- Your part: [itemID] = quantity (negative = lowered below the queues' part). The shared list ("Account-Wide" in the
-- options) is one per faction, FP.db.shoppingFaction[faction]: what one faction buys can't be mailed to the other.
local function FactionList()
    local lists, faction = FP.db.shoppingFaction, UnitFactionGroup("player") or "Neutral"
    lists[faction] = lists[faction] or {}
    return lists[faction]
end

function Shop:Data()
    if FP.db.shoppingScope == "account" then return FactionList() end
    return FP.chardb.shopping
end

-- Before 0.10.0 the queue's share was added into the saved quantities when you asked for it, and remembered per character
-- in chardb.shoppingQueue. Takes that share back out, since the queues' part is now worked out on its own.
function Shop:MoveOldQueueShare()
    local from = FP.chardb.shoppingQueue
    if not from then return end
    local d = self:Data()
    for itemID, share in pairs(from) do
        if d[itemID] then
            local left = d[itemID] - share
            d[itemID] = left > 0 and left or nil
        end
    end
    FP.chardb.shoppingQueue = nil
end

-- 0.10.0 makes the shared list (per faction) the default. Once per account the setting is switched to it (later choices
-- are kept). The one shared list from before (FP.db.shopping, for every faction) goes to the faction of the first
-- character to log in. And once per character its own list is added into its faction's list at its next login, then
-- emptied. Only what you added yourself moves: a quantity lowered below a queue's need was about that queue alone.
local function AddInto(into, from)
    for itemID, n in pairs(from) do
        if n > 0 then into[itemID] = (into[itemID] or 0) + n end
    end
    wipe(from)
end

function Shop:MoveToAccountList()
    local db, chardb = FP.db, FP.chardb
    if not db.shopAccountDefault then db.shopAccountDefault, db.shoppingScope = true, "account" end
    if next(db.shopping) then AddInto(FactionList(), db.shopping) end
    if chardb.shopMoved then return end
    chardb.shopMoved = true
    AddInto(FactionList(), chardb.shopping)
end

-- What the crafting queues still need of each item: the current character's queue, and with the shared list every other
-- character's of the same faction too. When alts count toward planning, the list's own plan pools every character's stock, so
-- another queue's full need goes in; otherwise only what that character can't cover from its own bags and bank.
--
-- An item a queue makes for a later entry (bolts for modulators) counts only what is still missing after what that
-- character holds: its need is "what the later entries use, minus what is still queued to make", which grows with each
-- one crafted while the crafted ones sit in the bags. Counted in full, it would climb past a quantity you lowered or
-- cleared and bring the item back with nothing to buy.
local function MadeBy(queue)
    local made = {}
    for _, q in ipairs(queue or {}) do
        if q.output then made[q.output.itemID] = true end
    end
    return made
end

function Shop:QueueNeeds()
    local out, me = {}, FP.Alts:GetCharacterKey()
    local made = MadeBy(FP.Queue:Data())
    for _, r in ipairs(FP.Queue:Requirements()) do
        local need = r.need
        if made[r.itemID] then
            local _, _, total, mail = FP.Inv:Owned(r.itemID)
            need = need - total - mail
        end
        if need > 0 then out[r.itemID] = need end
    end
    self.cover = {}
    if FP.db.shoppingScope ~= "account" then return out end
    local pooled = FP.Planner:Applies()
    for key, rec in pairs(FP.db.characters) do
        -- Only your characters of this faction: what is bought here can't be mailed to the other one.
        if key ~= me and rec.queue and #rec.queue > 0 and not FP.Alts:IsOtherFaction(rec) then
            local theirs = MadeBy(rec.queue)
            for _, r in ipairs(FP.Queue:Requirements(key)) do
                local _, _, held, mail = FP.Planner:Holding(key, r.itemID)
                local need = (pooled and not theirs[r.itemID]) and r.need or r.need - held - mail
                if need > 0 then out[r.itemID] = (out[r.itemID] or 0) + need end
            end
        end
    end
    -- What one character's queue makes beyond its own use covers what the others still need, so the list keeps only
    -- the rest; that craft's materials are already in its queue's needs. self.cover keeps who covers what, for the
    -- tooltips: [itemID] = { need, made, by } (by as in Queue:Cover).
    for itemID, c in pairs(FP.Queue:Cover()) do
        local need = out[itemID]
        if need then
            self.cover[itemID] = { need = need, made = c.made, by = c.by }
            out[itemID] = need > c.made and need - c.made or nil
        end
    end
    return out
end

-- Who covers what of the shared list's queue needs (see QueueNeeds); empty with the character's own list.
function Shop:Cover()
    self:QueueNeeds()
    return self.cover
end

-- Every listed item's quantity, queues' part and your part: { [itemID] = { qty, queue, mine } }.
function Shop:Quantities()
    local d, queue, out = self:Data(), self:QueueNeeds(), {}
    for itemID, mine in pairs(d) do
        local q = queue[itemID] or 0
        if mine < -q then -- the queues need less than when it was lowered
            mine = -q
            d[itemID] = mine ~= 0 and mine or nil
        end
        if q + mine > 0 then out[itemID] = { qty = q + mine, queue = q, mine = mine } end
    end
    for itemID, q in pairs(queue) do
        if not d[itemID] then out[itemID] = { qty = q, queue = q, mine = 0 } end
    end
    return out
end

-- The quantity shown for one item, 0 when it isn't listed.
function Shop:Quantity(itemID)
    local e = self:Quantities()[itemID]
    return e and e.qty or 0
end

-- Sets your part so the item shows `count` against the queues' current part.
local function SetShown(self, itemID, count)
    local mine = count - (self:QueueNeeds()[itemID] or 0)
    self:Data()[itemID] = mine ~= 0 and mine or nil
end

function Shop:Add(itemID, qty)
    local d = self:Data()
    local mine = (d[itemID] or 0) + math.max(1, qty or 1)
    d[itemID] = mine ~= 0 and mine or nil
    FP:Changed("shop")
end

-- Off the list while the queues' need holds; it comes back with what the queues add later.
function Shop:Remove(itemID)
    SetShown(self, itemID, 0)
    FP:Changed("shop")
end

-- Replaces the shown quantity; zero removes the item.
function Shop:SetQuantity(itemID, count)
    SetShown(self, itemID, math.max(0, count))
    FP:Changed("shop")
end

-- Drops your changes to the items the queues need, so they show exactly the queues' part again. Items only you added
-- stay as they are.
function Shop:ResetToQueue()
    local d = self:Data()
    for itemID in pairs(self:QueueNeeds()) do d[itemID] = nil end
    FP:Changed("shop")
end

-- The list is one requirement set for the transfer planner; toBuy is its shortage, so stock that alts can send
-- is not bought when they count toward planning.
function Shop:Aggregate()
    local reqs, parts = {}, self:Quantities()
    for itemID, e in pairs(parts) do reqs[#reqs + 1] = { itemID = itemID, need = e.qty } end
    table.sort(reqs, function(a, b) return a.itemID < b.itemID end) -- a stable order keeps the plan cache key stable
    local plan = FP.Planner:Plan(reqs)
    local out = {}
    for _, r in ipairs(reqs) do
        local it = plan.byItem[r.itemID]
        local owned, toBuy, alts = 0, 0, 0
        if it then owned, toBuy, alts = it.have, it.shortage, plan.applies and it.transfer or 0 end
        local unit = FP.Prices:Unit(r.itemID)
        out[#out + 1] = { itemID = r.itemID, name = FP.ItemName(r.itemID), needed = r.need, owned = owned,
            queue = parts[r.itemID].queue, mine = parts[r.itemID].mine, cover = self.cover[r.itemID],
            alts = alts, plan = it, toBuy = toBuy, unit = unit, cost = unit and unit * toBuy or nil }
    end
    table.sort(out, function(a, b)
        if (a.toBuy > 0) ~= (b.toBuy > 0) then return a.toBuy > 0 end
        return a.name < b.name
    end)
    return out
end

-- What the queues still need of one item that nobody holds: the list's still-to-buy, up to the queues' part. What is
-- left to craft, where QueueNeeds is what the queues use.
function Shop:QueueMissing(itemID)
    for _, e in ipairs(self:Aggregate()) do
        if e.itemID == itemID then return math.min(e.queue, e.toBuy) end
    end
    return 0
end

-- Items still to buy, their estimated total cost, and how many have no auction price. data: an Aggregate result.
function Shop:Summary(data)
    local items, cost, unpriced = 0, 0, 0
    for _, e in ipairs(data or self:Aggregate()) do
        if e.toBuy > 0 then
            items = items + 1
            if e.cost then cost = cost + e.cost else unpriced = unpriced + 1 end
        end
    end
    return items, cost, unpriced
end

-- Empties the list; what the queues need comes back as they add to it.
function Shop:Clear()
    local d = self:Data()
    wipe(d)
    for itemID, q in pairs(self:QueueNeeds()) do d[itemID] = -q end
    FP:Changed("shop")
end

function Shop:RemoveDone()
    for _, e in ipairs(self:Aggregate()) do
        if e.toBuy == 0 then SetShown(self, e.itemID, 0) end
    end
    FP:Changed("shop")
end
