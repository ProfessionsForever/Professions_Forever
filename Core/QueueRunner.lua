local _, FP = ...
local L = FP.L
local Queue = FP.Queue

---------------------------------------------------------------------------
-- Crafting runner. Each entry is crafted in turn, opening its profession when needed.
-- Opening a profession and CraftRecipe both need a hardware event, so they only run from a Craft Queue
-- click; when the runner gets ahead of the player (profession opened, batch done) it waits in the "ready" state.
---------------------------------------------------------------------------
local WATCHDOG = 6

function Queue:IsOpen(q)
    local T = C_TradeSkillUI
    return T.IsTradeSkillReady() and self:CurrentSkillLine() == q.skillLine
end

local function CraftsFromBags(q)
    local n = math.huge
    for _, r in ipairs(q.reagents) do
        local bags = FP.Inv:Owned(r.itemID)
        n = math.min(n, math.floor(bags / r.qty))
    end
    return n == math.huge and 0 or math.min(n, q.qty)
end

function Queue:SetStatus(text)
    self.status = text
    self:Update()
end

-- Crafting needs a hardware event. While the runner waits to craft in the open profession, a click on the game
-- world supplies one, so the player doesn't have to find the Craft Queue button. Key presses are not used:
-- movement keys such as space cancel the cast.
WorldFrame:HookScript("OnMouseDown", function()
    local run = Queue.run
    if not (run and run.ready) or InCombatLockdown() or not Queue:IsOpen(run.entry) then return end
    Queue:HideNotice()
    Queue:Step(true)
end)

function Queue:Stop(msg)
    self.run = nil
    self.token = (self.token or 0) + 1
    self:HideNotice()
    self:SetStatus(msg)
    if msg and msg ~= "" then FP:Print(msg) end
end

function Queue:Arm()
    self.token = (self.token or 0) + 1
    local token = self.token
    C_Timer.After(WATCHDOG, function()
        if self.run and self.token == token and not UnitCastingInfo("player") then
            self:Stop(L["Crafting did not start. Click Craft Queue to continue."])
        end
    end)
end

function Queue:NextEntry()
    for _, q in ipairs(self:Data()) do
        if not self.skip[q] then
            if not q.skillLine then
                self.skip[q] = true
            elseif not self:IsLearned(q) then
                self.skip[q] = true
                self.unlearned = self.unlearned + 1
                FP:Print(L["Skipping %s: not learned."]:format(q.name))
            elseif q.enchant then
                -- An enchant goes onto an item the player picks, so it is planned and shopped for here and applied
                -- with the Enchant button; OnEvent counts each one off.
                self.skip[q] = true
                self.enchants = self.enchants + q.qty
            elseif FP.Cooldowns:IsOnCooldown(q.id) then
                self.skip[q] = true
                self.cooling = self.cooling + 1
            elseif self:IsOpen(q) and #FP.Tools:Missing(q.id) > 0 then
                -- Only the open profession's requirements can be read, so this waits for the profession to be opened.
                self.skip[q] = true
                self.noTools = self.noTools + 1
                FP:Print(L["Skipping %s: missing %s."]:format(q.name, table.concat(FP.Tools:Missing(q.id), ", ")))
            elseif CraftsFromBags(q) > 0 then
                return q
            else
                self.skip[q] = true
                self.skipped = self.skipped + 1
                FP:Print(L["Skipping %s: not enough materials in your bags."]:format(q.name))
            end
        end
    end
end

-- `fromClick`: called inside a Craft Queue click. Opening a profession and crafting both need one.
function Queue:Step(fromClick)
    if not self.run then return end
    if InCombatLockdown() then return self:Stop(L["Cannot do that in combat."]) end
    local q = self:NextEntry()
    if not q then
        local msg = L["Queue finished."]
        if self.skipped > 0 then msg = msg .. " " .. L["%d recipes skipped (missing materials)."]:format(self.skipped) end
        if self.cooling > 0 then msg = msg .. " " .. L["%d recipes skipped (on cooldown)."]:format(self.cooling) end
        if self.noTools > 0 then msg = msg .. " " .. L["%d recipes skipped (missing tools)."]:format(self.noTools) end
        if self.unlearned > 0 then msg = msg .. " " .. L["%d recipes skipped (not learned)."]:format(self.unlearned) end
        if self.enchants > 0 then msg = msg .. " " .. L["%d enchant(s) left to apply with the Enchant button."]:format(self.enchants) end
        return self:Stop(msg)
    end
    if not fromClick then return self:Ready(q) end
    if not self:IsOpen(q) then
        self.run = { entry = q, waiting = true }
        self:SetStatus(L["Opening profession for %s..."]:format(q.name))
        FP:OpenProfession(q.skillLine)
        return self:Arm()
    end
    self:StartCraft(q)
end

-- `changed`: the profession window was just switched, so the player must click again.
function Queue:Ready(q, changed)
    self.token = (self.token or 0) + 1 -- disarm the watchdog: nothing is expected to cast now
    self.run = { entry = q, ready = true }
    local open = self:IsOpen(q)
    local fmt = open and L["Click the game world to craft %s."] or L["Click Craft Queue to open the profession for %s."]
    local msg = fmt:format(q.name)
    self:SetStatus(msg)
    -- Opening a profession needs a click on the button; crafting in the open one takes a world click.
    if not (self.frame and self.frame:IsShown()) then FP:Print(msg)
    elseif changed then self:ShowNotice()
    else self:ShowNotice(msg) end
end

local function Bags(itemID) return (FP.Inv:Owned(itemID)) end

-- How many crafts of `q` are worth making now, when what it makes is used by an entry after it and an entry after it
-- also needs one of its materials; nil otherwise (it is crafted as far as the bags allow). Crafting each entry to the
-- limit would let an early step use up a material a later one also needs (Copper Bars go into the bolts and into the
-- modulator), leaving the final crafts short. So the rest of the queue is sized as a whole: the largest share of its
-- final crafts (entries whose output nothing later uses) that the bags can supply through every step, and `q` makes
-- only what that share needs. Also returns the first later entry that needs one of its materials.
local function UsefulCrafts(q)
    if not q.output then return end
    local data, list, start = Queue:Data(), {}, nil
    for i, e in ipairs(data) do
        if e == q then start = i end
        if start and (e == q or not Queue.skip[e]) then list[#list + 1] = e end
    end
    local mine = {}
    for _, r in ipairs(q.reagents) do mine[r.itemID] = true end
    local maker, usedLater, shared, consumed = {}, false, nil, {}
    for i, e in ipairs(list) do
        if e.output and not maker[e.output.itemID] then maker[e.output.itemID] = e end
        for _, r in ipairs(e.reagents) do
            consumed[r.itemID] = true
            if i > 1 and r.itemID == q.output.itemID then usedLater = true end
            if i > 1 and mine[r.itemID] then shared = shared or e end
        end
    end
    -- Nothing later wants its materials (smelting ore into bars): making them all leaves no one short.
    if not (usedLater and shared) then return end
    local function IsFinal(e) return not (e.output and consumed[e.output.itemID] and maker[e.output.itemID] == e) end
    local most = 0
    for _, e in ipairs(list) do
        if IsFinal(e) then most = math.max(most, e.qty) end
    end
    if most == 0 then return end
    -- Each entry's crafts with the final ones scaled to k / most, worked backwards from the last entry; nil when the
    -- bags can't supply that (a step would need more crafts than queued, or a raw material more than the bags hold).
    local function Crafts(k)
        local demand, crafts = {}, {}
        for i = #list, 1, -1 do
            local e = list[i]
            local n
            if IsFinal(e) then
                n = math.floor(e.qty * k / most)
            else
                local out = e.output
                local short = (demand[out.itemID] or 0) - Bags(out.itemID)
                n = short > 0 and math.ceil(short / out.qty) or 0
                if n > e.qty then return end
                demand[out.itemID] = nil -- covered by the bags and these crafts
            end
            crafts[e] = n
            for _, r in ipairs(e.reagents) do demand[r.itemID] = (demand[r.itemID] or 0) + r.qty * n end
        end
        for itemID, need in pairs(demand) do
            if need > 0 and not maker[itemID] and need > Bags(itemID) then return end
        end
        return crafts
    end
    local lo, hi = 0, most -- Crafts(0) always fits: nothing at all
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if Crafts(mid) then lo = mid else hi = mid - 1 end
    end
    return Crafts(lo)[q] or 0, shared
end

function Queue:StartCraft(q)
    local n = CraftsFromBags(q)
    if FP.Cooldowns:IsTracked(q.id) then n = math.min(n, 1) end -- a cooldown allows one craft
    if n < 1 then return self:Step(true) end
    local useful, rival = UsefulCrafts(q)
    if useful then
        if useful < 1 then
            -- The entries after it can't use more yet: keep its materials for them.
            self.skip[q] = true
            FP:Print(L["Holding back %s: %s needs the same materials, and your bags can't cover more of both. See the Shopping List for what's missing, or lower a count in the queue."]:format(q.name, rival.name))
            return self:Step(true)
        end
        n = math.min(n, useful)
    end
    local ok, err = pcall(C_TradeSkillUI.CraftRecipe, q.id, n)
    if not ok then return self:Stop(tostring(err)) end
    self.run = { entry = q, batch = n, made = 0 }
    self:SetStatus(L["Crafting %dx %s"]:format(n, q.name))
    self:Arm()
end

-- What a counted-off craft made, between the cast succeeding (when it is counted off) and the item reaching the bags a
-- moment later. Queue:Requirements (shopping list, Transfer Planner) and Queue:EntryShortages (the queue's red "!")
-- count it as still made meanwhile, so a reagent the queue makes for a later entry doesn't flash up as short. Cleared by the next bag update,
-- or after a couple of seconds in case the bags updated first.
Queue.incoming = {}
local INCOMING_SECONDS = 2

local function ExpectOutput(entry)
    if not entry.output then return end
    local id = entry.output.itemID
    Queue.incoming[id] = (Queue.incoming[id] or 0) + entry.output.qty
    local token = {}
    Queue.incomingToken = token
    C_Timer.After(INCOMING_SECONDS, function()
        if Queue.incomingToken == token and next(Queue.incoming) then
            wipe(Queue.incoming)
            FP:Changed("queue")
        end
    end)
end

FP:RegisterEvent("BAG_UPDATE_DELAYED", function() wipe(Queue.incoming) end)

local function CreditOne(entry)
    ExpectOutput(entry)
    local data = Queue:Data()
    for i, q in ipairs(data) do
        if q == entry then
            q.qty = q.qty - 1
            -- What it made is in the bags now, so one less prerequisite craft is owed (entry.auto, Core/Queue.lua).
            if q.auto then q.auto = q.auto > 1 and q.auto - 1 or nil end
            if q.qty <= 0 then table.remove(data, i) end
            return
        end
    end
end

-- The current character's queued enchant with this spell, if any. The runner never casts enchants, so one that
-- succeeds was applied by the player (the Enchant button, or Blizzard's window) and comes off the queue.
local function QueuedEnchant(spellID)
    for _, q in ipairs(Queue:Data()) do
        if q.enchant and q.id == spellID then return q end
    end
end

-- Hands off to the next entry shortly after the current one ends.
local function Advance()
    if Queue.run and Queue.run.advancing then
        Queue.run = {}
        Queue:Step()
    end
end

-- Crafts of an interrupted batch that are still in flight keep being credited for a while.
local function KeepTail(run)
    if not (run.batch and run.made < run.batch) then return end
    Queue.tail = run
    C_Timer.After(30, function() if Queue.tail == run then Queue.tail = nil end end)
end

function Queue:FinishBatch()
    if not self.run then return end
    self.run = { advancing = true }
    FP:Changed("queue")
    C_Timer.After(0.5, Advance)
end

-- The buttons are secure and run /stopcasting while a run is active, since addons can't cancel casts
-- directly. Crafts still in flight afterwards keep being credited via `tail`.
--
-- The interrupt that /stopcasting causes can reach OnEvent before the click handler runs. Taken as an ordinary
-- interruption it would end the run there, and the click handler would then find no run and do nothing. So the
-- buttons' PreClick marks the click, OnEvent leaves that interrupt alone, and the handler below decides what the
-- click does.
function Queue:MarkStopping()
    if self.run and self.run.batch then self.stoppingAt = GetTime() end
end

local function OwnStop()
    return Queue.stoppingAt ~= nil and GetTime() - Queue.stoppingAt < 1
end

function Queue:SkipCurrent()
    self.stoppingAt = nil
    local run = self.run
    if not (run and run.entry) then return end
    self.skip[run.entry] = true
    KeepTail(run)
    self.run = { advancing = true }
    self.token = (self.token or 0) + 1
    self:SetStatus(L["Skipping to the next recipe..."])
    C_Timer.After(0.5, Advance)
end

-- Craft Queue: starts a run, or crafts the next recipe when the run waits for a click. Does nothing mid-craft.
function Queue:StartRun()
    local run = self.run
    if run and run.ready then
        self:HideNotice()
        return self:Step(true)
    end
    if run or #self:Data() == 0 then return end
    self.skip, self.skipped, self.cooling, self.noTools, self.unlearned, self.enchants, self.run = {}, 0, 0, 0, 0, 0, {}
    self:Step(true)
end

-- Stop Queue.
function Queue:StopRun()
    self.stoppingAt = nil
    local run = self.run
    if not run then return end
    KeepTail(run)
    self:Stop(L["Queue stopped."])
end

local function OnEvent(event, _, _, spellID)
    local tail = Queue.tail
    if tail and not (Queue.run and Queue.run.batch) and event == "UNIT_SPELLCAST_SUCCEEDED" and spellID == tail.entry.id then
        tail.made = tail.made + 1
        CreditOne(tail.entry)
        if tail.made >= tail.batch then Queue.tail = nil end
        FP:Changed("queue")
        return
    end
    local applied = event == "UNIT_SPELLCAST_SUCCEEDED" and QueuedEnchant(spellID)
    if applied then
        CreditOne(applied)
        FP:Changed("queue")
        return
    end
    local run = Queue.run
    if not run then return end
    if event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_SHOW" then
        if run.waiting and Queue:IsOpen(run.entry) then
            C_Timer.After(0.2, function()
                if Queue.run == run and Queue:IsOpen(run.entry) then Queue:Ready(run.entry, true) end
            end)
            run.waiting = false
        end
    elseif run.batch then
        if event == "UNIT_SPELLCAST_SUCCEEDED" and spellID == run.entry.id then
            run.made = run.made + 1
            CreditOne(run.entry)
            if run.made >= run.batch then Queue:FinishBatch() else Queue:Arm() FP:Changed("queue") end
        elseif event ~= "UNIT_SPELLCAST_SUCCEEDED" and spellID == run.entry.id then
            if OwnStop() then return end -- our own stop click: its handler deals with it
            KeepTail(run) -- a craft already under way may still complete
            Queue:Stop(L["Crafting interrupted."])
        end
    end
end
for _, e in ipairs({ "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_SHOW" }) do
    FP:RegisterEvent(e, function() OnEvent(e) end)
end
for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET" }) do
    FP:RegisterEvent(e, function(_, ...) OnEvent(e, ...) end, "player")
end
