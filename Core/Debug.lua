local _, FP = ...

-- Developer diagnostics, run with /pf debug <name>. Never packaged: the .toc lists this file inside a
-- do-not-package block and .pkgmeta ignores it, so only deploy.sh installs carry it. Output is not localized.
local commands = FP.commands

---------------------------------------------------------------------------
-- /pf debug links: logs the events and calls around opening a profession, to see what a chat link does
---------------------------------------------------------------------------
local tracing, traceFrame

local function Trace(what)
    if not tracing then return end
    local pf = _G.ProfessionsFrame
    local linked, owner = FP:IsReadOnly()
    FP:Print(("%.2f %s | linked=%s %s ready=%s | pf shown=%s alpha=%s scale=%s | ours shown=%s"):format(
        GetTime() % 1000, what, tostring(linked), tostring(owner or ""), tostring(C_TradeSkillUI.IsTradeSkillReady()),
        tostring(pf and pf:IsShown()), tostring(pf and pf:GetAlpha()), tostring(pf and pf:GetScale()),
        tostring(FP.UI.frame and FP.UI.frame:IsShown())))
end

commands["debug links"] = function()
    tracing = not tracing
    if tracing and not traceFrame then
        traceFrame = CreateFrame("Frame")
        for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "ADDON_LOADED" }) do
            traceFrame:RegisterEvent(e)
        end
        traceFrame:SetScript("OnEvent", function(_, event, name)
            if event ~= "ADDON_LOADED" or (name and name:find("Profession")) then Trace(event .. " " .. tostring(name or "")) end
        end)
        for _, fn in ipairs({ "ProfessionsFrame_LoadUI", "ShowProfessionsFrame", "OpenProfessionUIToSkillLine" }) do
            if type(_G[fn]) == "function" then hooksecurefunc(fn, function() Trace(fn) end) end
        end
        hooksecurefunc("SetItemRef", function(link)
            if not tracing then return end
            Trace("SetItemRef " .. tostring(link))
            for _, delay in ipairs({ 1, 3, 6 }) do C_Timer.After(delay, function() Trace("after " .. delay .. "s") end) end
        end)
        hooksecurefunc("ShowUIPanel", function(frame) if frame == _G.ProfessionsFrame then Trace("ShowUIPanel(ProfessionsFrame)") end end)
        hooksecurefunc("HideUIPanel", function(frame) if frame == _G.ProfessionsFrame then Trace("HideUIPanel(ProfessionsFrame)") end end)
        hooksecurefunc(C_TradeSkillUI, "OpenTradeSkill", function(id) Trace("OpenTradeSkill " .. tostring(id)) end)
        hooksecurefunc(C_TradeSkillUI, "CloseTradeSkill", function() Trace("CloseTradeSkill") end)
    end
    FP:Print(tracing and "Link tracing on. Click a profession link and copy the lines." or "Link tracing off.")
end

---------------------------------------------------------------------------
-- /pf debug cooldowns: checks this client against the cooldown data: whether each listed recipe is known without its
-- profession open, and what the game returns for the open profession's learned recipes.
---------------------------------------------------------------------------
commands["debug cooldowns"] = function()
    local T, Data = C_TradeSkillUI, FP.CooldownData
    local rec = FP.Alts:Current()
    local mine = rec and rec.cooldowns or {}
    for id in pairs(Data) do
        local e = FP.Recipes.byID[id]
        local known = IsPlayerSpell and IsPlayerSpell(id)
        if known or (e and e.learned) or mine[id] then
            FP:Print(("data %d %s: IsPlayerSpell=%s, learned in open profession=%s, tracked=%s, readyAt=%s"):format(id,
                (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or "?", tostring(known),
                tostring(e and e.learned), tostring(mine[id] ~= nil), tostring(mine[id] and mine[id].readyAt)))
        end
    end
    if not T.IsTradeSkillReady() then return FP:Print("Open a profession to also check its recipes.") end
    local scanned, viaRecipe, viaSpell = 0, 0, 0
    for _, e in ipairs(FP.Recipes.list) do
        if e.learned then
            scanned = scanned + 1
            local ok, cooldown, isDay, charges, maxCharges = pcall(T.GetRecipeCooldown, e.id)
            local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(e.id)
            local spellLeft = info and info.duration and info.duration > FP.Cooldowns.MIN_SPELL_COOLDOWN
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

---------------------------------------------------------------------------
-- /pf debug tools: prints what the client reports for the selected recipe, to adjust the lookup if nothing shows up.
---------------------------------------------------------------------------
commands["debug tools"] = function()
    local id = FP.selected
    if not id then return FP:Print("Select a recipe first.") end
    local fn = C_TradeSkillUI and C_TradeSkillUI.GetRecipeRequirements
    FP:Print(("recipe %s: GetRecipeRequirements exists=%s"):format(tostring(id), tostring(fn ~= nil)))
    if fn then
        local ok, list = pcall(fn, id)
        FP:Print(("  call ok=%s type=%s count=%s"):format(tostring(ok), type(list), type(list) == "table" and #list or "-"))
        for i, entry in ipairs(type(list) == "table" and list or {}) do
            if type(entry) == "table" then
                local parts = {}
                for k, v in pairs(entry) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
                FP:Print(("  [%d] %s"):format(i, table.concat(parts, ", ")))
            else
                FP:Print(("  [%d] %s"):format(i, tostring(entry)))
            end
        end
    end
    local info = C_TradeSkillUI.GetRecipeInfo(id)
    for k, v in pairs(info or {}) do
        local key = tostring(k):lower()
        if key:find("tool") or key:find("requir") or key:find("reagent") == nil and key:find("need") then
            FP:Print(("  info.%s = %s"):format(tostring(k), tostring(v)))
        end
    end
    for _, name in ipairs({ "GetTradeSkillTools", "GetRecipeTools", "GetRecipeRequirementText" }) do
        FP:Print(("  %s exists: global=%s, C_TradeSkillUI=%s"):format(name, tostring(_G[name] ~= nil), tostring(C_TradeSkillUI[name] ~= nil)))
    end
end

---------------------------------------------------------------------------
-- /pf debug chain: the queue's entries with what they need and make, then what the plan says is short.
---------------------------------------------------------------------------
commands["debug chain"] = function()
    local function Name(itemID) return C_Item.GetItemNameByID(itemID) or itemID end
    for i, q in ipairs(FP.Queue:Data()) do
        local reagents = {}
        for _, r in ipairs(q.reagents) do reagents[#reagents + 1] = ("%s x%d"):format(Name(r.itemID), r.qty) end
        local makes = q.output and ("%s x%d"):format(Name(q.output.itemID), q.output.qty) or "nothing known"
        FP:Print(("%d. %s x%d makes %s; needs %s"):format(i, q.name, q.qty, makes, #reagents > 0 and table.concat(reagents, ", ") or "nothing"))
    end
    for _, it in ipairs(FP.Queue:TransferNeeds().items) do
        FP:Print(("need %s x%d, own %d, short %d"):format(Name(it.itemID), it.need, it.have, it.shortage))
    end
end

---------------------------------------------------------------------------
-- /pf debug de: the disenchantable items Core/Disenchant.lua finds in your bags (and the bank while it is open),
-- with their loot table, results and values, to check against real items before the window exists.
---------------------------------------------------------------------------
commands["debug de"] = function()
    local DE, P = FP.Disenchant, FP.Prices
    local function Money(c) return c and P:Format(c) or "-" end
    local items = DE:Scan()
    FP:Print(("disenchant scan: %d items (bank %s)"):format(#items, FP.Inv.bankOpen and "open" or "closed, not scanned"))
    for _, it in ipairs(items) do
        local where = (it.inBank and "bank " or "bag ") .. it.bag .. ":" .. it.slot
        FP:Print(("%s ilvl %d, %s, %s, table %d%s"):format(it.link, it.level, it.bound and "soulbound" or "not bound", where,
            it.tableID, it.sets and (" |cffff5555in set: " .. table.concat(it.sets, ", ") .. "|r") or ""))
        for _, r in ipairs(DE:Results(it.tableID)) do
            local name = C_Item.GetItemNameByID(r.itemID) or r.itemID
            local amount = r.min == r.max and r.min or (r.min .. "-" .. r.max)
            print(("     %s  %g%%  x%s  @ %s"):format(name, r.chance * 100, amount, Money(P:Unit(r.itemID))))
        end
        local value, unpriced = DE:ExpectedValue(it.tableID)
        print(("     vendor %s | disenchant %s%s | auction %s"):format(Money(it.sellPrice), Money(value),
            unpriced > 0 and (" (" .. unpriced .. " unpriced)") or "", Money(P:Unit(it.itemID))))
    end
    -- Raw set locations, to check the bag / bank decoding.
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
        local parts = {}
        for slot, loc in pairs(C_EquipmentSet.GetItemLocations(setID) or {}) do parts[#parts + 1] = slot .. "=" .. loc end
        FP:Print(("set %d %s: %s"):format(setID, tostring(C_EquipmentSet.GetEquipmentSetInfo(setID)), table.concat(parts, " ")))
    end
end

---------------------------------------------------------------------------
-- /pf debug select: toggles a chat line after each recipe-list refresh (UI:RefreshFilter) with what the remembered-
-- recipe logic sees: the profession key, the remembered recipe, whether the list holds it, what is selected, and
-- whether that is only a stand-in. To see why the last clicked recipe doesn't come back after a reload.
---------------------------------------------------------------------------
local selectTrace, selectHooked
commands["debug select"] = function()
    selectTrace = not selectTrace
    if not selectHooked then
        selectHooked = true
        hooksecurefunc(FP.UI, "RefreshFilter", function(ui)
            if not selectTrace then return end
            local skillLine = select(5, FP.RankInfo())
            local viewing = FP.AltProfs.viewing
            local key = viewing and (viewing.key .. ":" .. viewing.skillLine) or skillLine
            local last = key and FP.db.lastRecipe[key]
            local listed = false
            for _, e in ipairs(ui.filtered) do if e.id == last then listed = true break end end
            local function Name(id) local e = id and FP.Recipes.byID[id] return e and e.name or tostring(id) end
            FP:Print(("select: key=%s remembered=%s (%s) listed=%d inList=%s selected=%s standIn=%s"):format(
                tostring(key), Name(last), tostring(last), #ui.filtered, tostring(listed), Name(FP.selected),
                tostring(ui.selectionStandIn)))
        end)
    end
    FP:Print("recipe selection trace " .. (selectTrace and "on" or "off"))
end

---------------------------------------------------------------------------
-- /pf debug degear: the unbound gear each character holds, as the other characters' Disenchanting Mode will see it
-- (Alts:Gear). Entries with a GUID come from this addon's own scan, ones without from Syndicator.
---------------------------------------------------------------------------
commands["debug degear"] = function()
    local rec = FP.Alts:Current()
    local own = rec.deGear or {}
    FP:Print(("this character saved: %d in bags, %s in bank"):format(#(own.bags or {}),
        own.bank and tostring(#own.bank) or "nothing (not at the bank since the update)"))
    for _, c in ipairs(FP.Alts:Others()) do
        local bags, bank = FP.Alts:Gear(c.key)
        FP:Print(("%s: %d in bags, %d in bank%s"):format(FP.Alts:Label(c.rec), #bags, #bank,
            FP.Alts:IsEligible(c.key, c.rec) and "" or " (not eligible: other faction or turned off)"))
        for _, list in ipairs({ { "bags", bags }, { "bank", bank } }) do
            for _, g in ipairs(list[2]) do
                print(("     %s %s  %s"):format(list[1], g.link, g.guid or "|cffff8000no guid (Syndicator)|r"))
            end
        end
    end
    -- What Disenchanting Mode will list from that: eligible characters only, disenchantable items only.
    local items = FP.Disenchant:ScanOthers()
    FP:Print(("disenchantable from other characters: %d"):format(#items))
    for _, it in ipairs(items) do
        print(("     %s %s %s ilvl %d, table %d, key %s"):format(FP.Alts:Label(FP.db.characters[it.owner]),
            it.inBank and "bank" or "bags", it.link, it.level, it.tableID, it.guid or it.id))
    end
end

---------------------------------------------------------------------------
-- /pf debug delog: toggles a chat line for each disenchant Core/DisenchantRecord.lua records, and prints what it has
-- recorded so far.
---------------------------------------------------------------------------
local deLogging, deHooked

local function LootText(loot)
    local parts = {}
    for itemID, qty in pairs(loot) do parts[#parts + 1] = (C_Item.GetItemNameByID(itemID) or itemID) .. " x" .. qty end
    return table.concat(parts, ", ")
end

-- While the log is on, the raw data Core/DisenchantRecord.lua works from, to see why something isn't recorded: where
-- each loot slot says it came from, and whether that source is a weapon or armour piece remembered from your bags.
local function TraceLoot()
    if not deLogging then return end
    FP:Print(("trace LOOT_READY: %d slots%s"):format(GetNumLootItems(),
        FP.db.deRecord and "" or " |cffff8000(recording is off in options: nothing will be saved)|r"))
    for slot = 1, GetNumLootItems() do
        local _, name, quantity = GetLootSlotInfo(slot)
        local source = GetLootSourceInfo(slot)
        print(("     slot %d: %s x%s, source %s -> %s"):format(slot, tostring(name), tostring(quantity), tostring(source),
            source and FP.Disenchant:RememberedGear(source) or "not a remembered item"))
    end
end

commands["debug delog"] = function()
    deLogging = not deLogging
    if not deHooked then
        deHooked = true
        hooksecurefunc(FP.Disenchant, "Record", function(_, key, loot)
            if deLogging then FP:Print(("disenchant recorded under %s: %s"):format(key, LootText(loot))) end
        end)
        FP:RegisterEvent("LOOT_READY", TraceLoot)
    end
    FP:Print("disenchant capture log " .. (deLogging and "on" or "off") .. (FP.db.deRecord and "" or " (recording is turned off in options)"))
    if not deLogging then return end
    for key, e in pairs(FP.db.deObserved) do
        local parts = {}
        for itemID, i in pairs(e.items) do
            parts[#parts + 1] = ("%s %d/%d (x%d)"):format(C_Item.GetItemNameByID(itemID) or itemID, i.drops, e.n, i.qty)
        end
        print(("     %s: %d disenchants, builds %s-%s: %s"):format(key, e.n, e.first, e.last, table.concat(parts, ", ")))
    end
end

---------------------------------------------------------------------------
-- /pf debug known: the known-recipe snapshot of every character, and, with a profession open, whether the snapshot
-- matches what the window says this character has learned.
---------------------------------------------------------------------------
commands["debug known"] = function()
    FP.Known:Snapshot()
    for key, rec in pairs(FP.db.characters) do
        local parts = {}
        for line, list in pairs(rec.known or {}) do
            local _, n = list:gsub("%d+", "")
            parts[#parts + 1] = ("%s %d"):format(C_TradeSkillUI.GetTradeSkillDisplayName(line) or line, n)
        end
        FP:Print(("%s: %s"):format(key, #parts > 0 and table.concat(parts, ", ") or "no snapshot"))
    end
    local line = FP.Queue:CurrentSkillLine()
    if not line then return FP:Print("Open a profession to compare it with the snapshot.") end
    local snap, learned, missing = {}, 0, {}
    local rec = FP.Alts:Current()
    for id in ((rec.known or {})[line] or ""):gmatch("%d+") do snap[tonumber(id)] = true end
    for _, e in ipairs(FP.Recipes.list) do
        if e.learned then
            learned = learned + 1
            if not snap[e.id] then missing[#missing + 1] = e.id .. " " .. (e.name or "") end
        end
    end
    FP:Print(("open profession %d: %d learned in the window, %d of them missing from the snapshot%s"):format(
        line, learned, #missing, #missing > 0 and (": " .. table.concat(missing, ", ", 1, math.min(#missing, 10))) or ""))
end

---------------------------------------------------------------------------
-- Protected calls the game blocked for this addon.
---------------------------------------------------------------------------
local blocked = CreateFrame("Frame")
blocked:RegisterEvent("ADDON_ACTION_BLOCKED")
blocked:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blocked:SetScript("OnEvent", function(_, event, addon, func)
    if addon == "ProfessionsForever" then FP:Print(("%s: %s tried %s"):format(event, addon, tostring(func))) end
end)

---------------------------------------------------------------------------
-- /pf debug trainer: with a trainer window open, what the client reports about its rank service and what is saved
-- for the trainer, to check the rank recording in Waypoints/WaypointTrainers.lua.
---------------------------------------------------------------------------
commands["debug trainer"] = function()
    local W = FP.Waypoint
    local id = W.NpcID()
    if not id then return FP:Print("Open a trainer first.") end
    local step = GetTrainerServiceStepIndex()
    FP:Print(("npc %d %s | tradeskill=%s | services=%d | step=%s"):format(id, tostring(UnitName("npc")),
        tostring(IsTradeskillTrainer()), GetNumTrainerServices(), tostring(step)))
    if step then
        local name, serviceType, _, _, subText = GetTrainerServiceInfo(step)
        local skill, rank = GetTrainerServiceSkillReq(step)
        FP:Print(("  step: %s (%s) %s | line=%s | needs %s %s"):format(tostring(name), tostring(subText), tostring(serviceType),
            tostring(GetTrainerServiceSkillLine(step)), tostring(skill), tostring(rank)))
    end
    FP:Print(("  filters: available=%s unavailable=%s used=%s"):format(tostring(GetTrainerServiceTypeFilter("available")),
        tostring(GetTrainerServiceTypeFilter("unavailable")), tostring(GetTrainerServiceTypeFilter("used"))))
    local mine, shipped = FP.db.trainers[id], FP.NpcData.trainers[id]
    FP:Print(("  saved: skill=%s ranks=%s noRanks=%s | shipped: ranks=%s noRanks=%s classic=%s"):format(
        tostring(mine and mine.skill), tostring(mine and mine.ranks), tostring(mine and mine.noRanks),
        tostring(shipped and shipped.ranks), tostring(shipped and shipped.noRanks), tostring(shipped and shipped.classicRanks)))
    local parts = {}
    for cap = 75, 300, 75 do parts[#parts + 1] = cap .. "=" .. tostring(W.TeachesRank(id, cap)) end
    FP:Print("  teaches: " .. table.concat(parts, " "))
end
