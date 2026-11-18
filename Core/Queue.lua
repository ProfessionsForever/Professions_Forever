local _, FP = ...
local L = FP.L
local Queue = {}
FP.Queue = Queue

-- The crafting queue's data and what it needs. The window is Panels/Queue.lua; the runner that crafts it is
-- Core/QueueRunner.lua.

-- Each character's queue is kept in its account-wide record, FP.db.characters[key].queue, so the other characters can
-- see and edit it. Without `key`, the current character's. Entries snapshot their reagents so the queue works across
-- professions without reopening them.
function Queue:Data(key)
    local rec = key and FP.db.characters[key] or FP.Alts:Current()
    rec.queue = rec.queue or {}
    return rec.queue
end

-- How many other characters have something queued.
function Queue:OthersQueued()
    local me, n = FP.Alts:GetCharacterKey(), 0
    for key, rec in pairs(FP.db.characters) do
        if key ~= me and rec.queue and #rec.queue > 0 then n = n + 1 end
    end
    return n
end

-- Whether `key` (the current character without it) knows a queued recipe. An unlearned recipe may be queued, to plan
-- and shop for it; the runner skips it until it is learned.
function Queue:IsLearned(q, key)
    if not key then return IsPlayerSpell(q.id) end
    return tContains(FP.Known:Who(q.id), key)
end

-- Per-recipe breakdown of what the queue needs of this reagent.
function Queue:UsageList(itemID)
    local out = {}
    for _, q in ipairs(self:Data()) do
        for _, r in ipairs(q.reagents) do
            if r.itemID == itemID then out[#out + 1] = { name = q.name, crafts = q.qty, need = r.qty * q.qty } end
        end
    end
    return out
end

-- Total of this reagent needed by everything in the queue.
function Queue:QueuedAmount(itemID)
    local total = 0
    for _, q in ipairs(self:Data()) do
        for _, r in ipairs(q.reagents) do
            if r.itemID == itemID then total = total + r.qty * q.qty end
        end
    end
    return total
end

-- Total of this item that the queued crafts will make.
function Queue:QueuedProduction(itemID)
    local total = 0
    for _, q in ipairs(self:Data()) do
        if q.output and q.output.itemID == itemID then total = total + q.qty * q.output.qty end
    end
    return total
end

-- What a queue entry keeps about a recipe of the open profession, so the queue works across professions without
-- reopening them: reagents, what it makes, the skill line to craft it in, and whether it is an enchant (which the
-- runner can't cast: it goes onto an item the player picks, see Core/QueueRunner.lua).
function Queue:InfoFor(recipeID, skillLine)
    local e = FP.Recipes.byID[recipeID]
    if not e then return end
    local reagents = {}
    for i, r in ipairs(FP.Recipes:GetReagents(recipeID)) do
        reagents[i] = { itemID = r.itemID, qty = r.qty }
    end
    local itemID = FP.Recipes:OutputItemID(recipeID)
    return { id = recipeID, name = e.name, icon = e.icon, reagents = reagents, skillLine = skillLine or self:RecipeSkillLine(recipeID),
        output = itemID and { itemID = itemID, qty = (FP.Recipes:OutputQuantity(recipeID)) } or nil,
        enchant = FP.Recipes:IsEnchant(recipeID) or nil }
end

-- Adds crafts of a recipe described by InfoFor to `key`'s queue (the current character's without it), merging into its
-- entry when it is already queued. `from` names the character who queued it for `key`, for the notice `key` gets at its
-- next login. Returns how many crafts were added.
function Queue:AddInfo(info, qty, key, from)
    qty = math.max(1, qty or 1)
    local data = self:Data(key)
    local entry
    for _, q in ipairs(data) do
        if q.id == info.id then entry = q break end
    end
    local added
    if entry then
        local before = entry.qty
        entry.qty = math.min(999, entry.qty + qty)
        added = entry.qty - before
    else
        entry = { id = info.id, name = info.name, icon = info.icon, qty = math.min(999, qty),
            reagents = info.reagents, skillLine = info.skillLine, output = info.output, enchant = info.enchant }
        data[#data + 1] = entry
        added = entry.qty
    end
    if from then entry.from, entry.fromQty = from, (entry.fromQty or 0) + added end
    return added
end

-- Queues crafts for another character, from its profession viewed in the main window (Alts/AltProfessions.lua), straight
-- into that character's queue. `skillLine` is that character's profession: the recipe isn't one of the current character's.
function Queue:AddFor(key, recipeID, skillLine, qty)
    local info = self:InfoFor(recipeID, skillLine)
    if not info then return end
    local added = self:AddInfo(info, qty, key, FP.Alts:Current().name)
    FP:Print(L["Queued %dx %s for %s."]:format(added, info.name, FP.db.characters[key].name))
    FP.Outgoing:AnnouncePlan(key)
    FP:Changed("queue")
end

-- Before 0.10.0 each queue was saved per character, and crafts queued for another character waited in
-- FP.db.pendingQueue until it logged in. Moves both into the account-wide queues; the old queue goes first, ahead of
-- anything queued for this character since.
local function MoveOldQueues(self)
    local old = FP.chardb.queue
    if old then
        local data = self:Data()
        for _, q in ipairs(data) do
            local same
            for _, o in ipairs(old) do
                if o.id == q.id then same = o break end
            end
            if same then
                same.qty = math.min(999, same.qty + q.qty)
                same.from, same.fromQty = q.from, q.fromQty
            else
                old[#old + 1] = q
            end
        end
        FP.Alts:Current().queue = old
        FP.chardb.queue = nil
    end
    for key, list in pairs(FP.db.pendingQueue or {}) do
        if FP.db.characters[key] then
            for _, p in ipairs(list) do self:AddInfo(p.info, p.qty, key, p.from) end
        end
    end
    FP.db.pendingQueue = nil
end

-- Before 0.10.2 a recipe queued by a character that hadn't learned it was saved without what it makes, so the
-- shopping list asked for both the item and its materials. Fills it in from the recipe data on every character's queue.
local function AddMissingOutputs()
    for _, rec in pairs(FP.db.characters) do
        for _, q in ipairs(rec.queue or {}) do
            local made = not q.output and FP.RecipeOutputs[q.id]
            if made then q.output = { itemID = made, qty = (FP.Recipes:OutputQuantity(q.id)) } end
        end
    end
end

-- At login: says what other characters queued for this one since it last played.
function Queue:OnLogin()
    MoveOldQueues(self)
    AddMissingOutputs()
    local told
    for _, q in ipairs(self:Data()) do
        if q.from then
            FP:Print(L["Added %dx %s to the queue (queued from %s)."]:format(q.fromQty or q.qty, q.name, q.from))
            q.from, q.fromQty, told = nil, nil, true
        end
    end
    if told then FP:Changed("queue") end
end

function Queue:Add(recipeID, qty)
    local info = self:InfoFor(recipeID)
    if not info then return end
    local added = self:AddInfo(info, qty)
    FP:Changed("queue")
    FP:Print(L["Added %dx %s to the queue."]:format(added, info.name))
end

local function Consumes(q, itemID)
    for _, r in ipairs(q.reagents) do
        if r.itemID == itemID then return true end
    end
end

-- Moves each entry that makes something a queued entry needs ahead of that entry.
function Queue:OrderByDependency()
    local data = self:Data()
    for _ = 1, #data * #data do
        local moved
        for j = 2, #data do
            local out = data[j].output
            for i = 1, out and j - 1 or 0 do
                if Consumes(data[i], out.itemID) then
                    table.insert(data, i, table.remove(data, j))
                    moved = true
                    break
                end
            end
            if moved then break end
        end
        if not moved then return end
    end
end

-- Like Add, but also queues the crafts of reagents you are short of and know how to make, ahead of the recipe.
function Queue:AddWithPrerequisites(recipeID, qty)
    local info = self:InfoFor(recipeID)
    if not info then return end
    local steps = FP.Chain:Plan(info, math.max(1, qty or 1)).steps
    local first = {}
    for _, step in ipairs(steps) do
        self:AddInfo(step.recipe, step.crafts)
        first[#first + 1] = ("%dx %s"):format(step.crafts, step.recipe.name)
    end
    local added = self:AddInfo(info, qty)
    if #steps > 0 then self:OrderByDependency() end
    FP:Changed("queue")
    FP:Print(L["Added %dx %s to the queue."]:format(added, info.name))
    if not self:IsLearned(info) then FP:Print(L["%s is not learned yet: the queue skips it until you learn it."]:format(info.name)) end
    if #first > 0 then FP:Print(L["Crafting first: %s"]:format(table.concat(first, ", "))) end
end

-- Whole crafts the bags can still supply once everything already queued has its materials.
function Queue:RoomFor(recipeID)
    local reagents = FP.Recipes:GetReagents(recipeID)
    if #reagents == 0 then return 0 end
    local crafts = 999
    for _, r in ipairs(reagents) do
        local bags = FP.Inv:Owned(r.itemID)
        crafts = math.min(crafts, math.floor((bags - self:QueuedAmount(r.itemID)) / r.qty))
    end
    return math.max(crafts, 0)
end

-- Edits of `key`'s queue (the current character's without it). What other characters should send follows on its own
-- (Alts/Outgoing.lua works it out from the queues).
function Queue:Remove(index, key)
    table.remove(self:Data(key), index)
    FP:Changed("queue")
end

function Queue:MoveTo(from, to, key)
    local data = self:Data(key)
    if from == to or not data[from] or not data[to] then return end
    table.insert(data, to, table.remove(data, from))
    FP:Changed("queue")
end

function Queue:Clear(key)
    wipe(self:Data(key))
    FP:Changed("queue")
end

-- What `key`'s queue (the current character's without it) makes of each item. A craft of the current character's just
-- counted off has its output on the way to the bags (Queue.incoming, Core/QueueRunner.lua): it still counts as made, so
-- nothing reads as short for the moment in between.
local function Made(self, key)
    local made = {}
    for _, q in ipairs(self:Data(key)) do
        if q.output then made[q.output.itemID] = (made[q.output.itemID] or 0) + q.qty * q.output.qty end
    end
    if not key or key == FP.Alts:GetCharacterKey() then
        for itemID, n in pairs(self.incoming or {}) do made[itemID] = (made[itemID] or 0) + n end
    end
    return made
end

-- What `key`'s queue makes beyond what that same queue uses: [itemID] = quantity, above zero only.
function Queue:Spare(key)
    local spare = Made(self, key)
    for _, q in ipairs(self:Data(key)) do
        for _, r in ipairs(q.reagents) do
            if spare[r.itemID] then spare[r.itemID] = spare[r.itemID] - r.qty * q.qty end
        end
    end
    for itemID, n in pairs(spare) do
        if n <= 0 then spare[itemID] = nil end
    end
    return spare
end

-- What every queue of this faction makes beyond its own use (the current character's included), with who makes it:
-- [itemID] = { made, by = { [key] = { qty, recipes = { { name, crafts } } } } }. Another faction's crafts can't be
-- mailed across, so they cover nothing.
function Queue:Cover()
    local me, out = FP.Alts:GetCharacterKey(), {}
    for key, rec in pairs(FP.db.characters) do
        if key == me or (rec.queue and #rec.queue > 0 and not FP.Alts:IsOtherFaction(rec)) then
            for itemID, n in pairs(self:Spare(key ~= me and key or nil)) do
                local c = out[itemID]
                if not c then
                    c = { made = 0, by = {} }
                    out[itemID] = c
                end
                local recipes = {}
                for _, q in ipairs(self:Data(key)) do
                    if q.output and q.output.itemID == itemID then recipes[#recipes + 1] = { name = q.name, crafts = q.qty } end
                end
                c.made = c.made + n
                c.by[key] = { qty = n, recipes = recipes }
            end
        end
    end
    return out
end

-- Totals reagents across all queued recipes of `key` (the current character without it) so shared materials are
-- counted once against stock. A changed queue drops the amounts chosen in the Transfer Planner for materials it no
-- longer needs.
local requirementsSig = {}
function Queue:Requirements(key)
    local order, byItem, sig = {}, {}, {}
    for _, q in ipairs(self:Data(key)) do
        sig[#sig + 1] = q.id .. "x" .. q.qty
        for _, r in ipairs(q.reagents) do
            local n = byItem[r.itemID]
            if not n then
                n = { itemID = r.itemID, need = 0 }
                byItem[r.itemID] = n
                order[#order + 1] = n
            end
            n.need = n.need + r.qty * q.qty
        end
    end
    local made = Made(self, key)
    -- What queued crafts will make is not something to acquire.
    local needed = {}
    for _, n in ipairs(order) do
        n.need = n.need - (made[n.itemID] or 0)
        if n.need <= 0 then byItem[n.itemID] = nil else needed[#needed + 1] = n end
    end
    local s = table.concat(sig, ",")
    if s ~= requirementsSig[key or ""] then
        requirementsSig[key or ""] = s
        FP.Alts:KeepTakes(byItem, key)
    end
    return needed
end

-- Which characters should send what to `key` (the current character without it), from the shared transfer plan for
-- its whole queue.
function Queue:TransferNeeds(key)
    if key == FP.Alts:GetCharacterKey() then key = nil end
    return FP.Planner:Plan(self:Requirements(key), key)
end

-- Materials still to acquire: the plan's shortage items, which are net of alts only when alts count toward planning.
function Queue:TrueShortages()
    local out = {}
    for _, it in ipairs(self:TransferNeeds().items) do
        if it.shortage > 0 then out[#out + 1] = it end
    end
    return out
end

-- Per queue entry, the reagents it cannot get: entries are served in queue order from what the plan supplies
-- (bags, bank, mailbox, and alts when they count). Entries with nothing missing are absent.
function Queue:EntryShortages()
    local byItem = self:TransferNeeds().byItem
    local supply, out = {}, {}
    -- A craft just counted off whose output hasn't reached the bags yet (Queue.incoming, Core/QueueRunner.lua) is
    -- added once to what its entry makes, so the entries using it don't flash up as short in between.
    local incoming = {}
    for itemID, n in pairs(self.incoming or {}) do incoming[itemID] = n end
    local function Left(itemID)
        if supply[itemID] then return supply[itemID] end
        local it = byItem[itemID]
        -- An item is left out of the plan when queued crafts cover the need; what the character holds of it is still
        -- there to use.
        if not it then
            local _, _, total, mail = FP.Inv:Owned(itemID)
            return total + mail
        end
        return it.need - it.shortage
    end
    for _, q in ipairs(self:Data()) do
        for _, r in ipairs(q.reagents) do
            local left = Left(r.itemID)
            local need = r.qty * q.qty
            local take = math.min(left, need)
            supply[r.itemID] = left - take
            if take < need then
                out[q] = out[q] or {}
                out[q][#out[q] + 1] = { itemID = r.itemID, qty = need - take }
            end
        end
        -- What this entry makes is there for the entries after it.
        if q.output then
            local id = q.output.itemID
            supply[id] = Left(id) + q.qty * q.output.qty + (incoming[id] or 0)
            incoming[id] = nil
        end
    end
    return out
end

-- Per queue entry, the reagents that have to be fetched first: entries are served in queue order from the bags (plus
-- what earlier entries make), then the bank, then the mailbox. Returns two maps, what to take from the bank and what
-- to collect from the mailbox; entries with nothing to fetch are absent from both.
function Queue:EntryFetch()
    local bags, bank, mail, fromBank, fromMail = {}, {}, {}, {}, {}
    local function Counts(itemID)
        if bags[itemID] then return end
        local inBags, inBank, _, inMail = FP.Inv:Owned(itemID)
        bags[itemID], bank[itemID], mail[itemID] = inBags, inBank, inMail
    end
    local function Take(stock, itemID, want, out, q)
        local n = math.min(stock[itemID], want)
        if n > 0 and out then
            out[q] = out[q] or {}
            out[q][#out[q] + 1] = { itemID = itemID, qty = n }
        end
        stock[itemID] = stock[itemID] - n
        return want - n
    end
    for _, q in ipairs(self:Data()) do
        for _, r in ipairs(q.reagents) do
            Counts(r.itemID)
            local left = Take(bags, r.itemID, r.qty * q.qty)
            left = Take(bank, r.itemID, left, fromBank, q)
            Take(mail, r.itemID, left, fromMail, q)
        end
        if q.output then
            Counts(q.output.itemID)
            bags[q.output.itemID] = bags[q.output.itemID] + q.qty * q.output.qty
        end
    end
    return fromBank, fromMail
end

-- Recipes queued, total crafts, and how many reagents are still short.
function Queue:Summary()
    local data, crafts = self:Data(), 0
    for _, q in ipairs(data) do crafts = crafts + q.qty end
    return #data, crafts, #self:TrueShortages()
end

---------------------------------------------------------------------------
-- Which of your professions a recipe belongs to
---------------------------------------------------------------------------
function Queue:CurrentSkillLine()
    if FP:IsReadOnly() then return nil end
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    return self:OwnedSkillLine(base)
end

-- The skill line of your profession that `info` (a ProfessionInfo) describes.
function Queue:OwnedSkillLine(info)
    if not info then return nil end
    for _, p in ipairs(FP:GetProfessions()) do
        if info.professionID == p.skillLine or info.professionName == p.name then
            return p.skillLine
        end
    end
end

-- Asks the game which profession the recipe belongs to: the open profession's base info can lag behind a switch.
function Queue:RecipeSkillLine(recipeID)
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoByRecipeID, recipeID)
    return ok and self:OwnedSkillLine(info) or self:CurrentSkillLine()
end
