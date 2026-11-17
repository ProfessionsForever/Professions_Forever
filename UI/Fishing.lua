local _, FP = ...
local L = FP.L
local UI = FP.UI
local Fishing = {}
FP.Fishing = Fishing

-- One-Click Fishing: a keybind (Bindings.xml, Key Bindings > AddOns > ProfessionsForever, or Options, General) that casts Fishing, then
-- catches. While the line is out, the bound keys are overridden to the game's Interact action, which soft-targets the
-- bobber, but only while it aims at the bobber (see Aim); the override ends with the channel. Interact only soft-targets objects with the keyboard when the
-- SoftTargetInteract CVar is 3 (Always), so it is set to 3 while fishing and put back after, along with the sound
-- settings of Louder Fishing Sounds (see SetForFishing). Controller buttons bind the same way.
-- Before casting, each press does the next thing still missing, one per press since each is its own action: put on the
-- character's Fishing gear set (FP.chardb.fishSet), equip the best fishing pole (db.fishEquipPole), put the best lure
-- on it (db.fishApplyLure). Gear can't change in combat, so there a press only casts.
-- Each slot a press changes first saves what it held (FP.chardb.fishSaved, by item GUID, false for empty), and
-- Fishing:SwapBack puts that back: on a keybind or /pf swapback, and when you mount, stop fishing for a while or a fight
-- ends (each an option).

local FISHING = 356
local BINDING = "CLICK ProfessionsForeverFishButton:LeftButton"
UI.FISH_BINDING = BINDING -- the Fishing Key option binds it (UI/Options/Options.lua)
_G.BINDING_HEADER_PROFESSIONSFOREVER = "ProfessionsForever"
_G["BINDING_NAME_" .. BINDING] = L["One-Click Fishing"]

local MAIN_HAND = INVSLOT_MAINHAND
-- Lures and how much Fishing each adds; the best one the character can use goes on the pole.
local LURES = {
    [6533] = 100, -- Aquadynamic Fish Attractor
    [6532] = 75,  -- Bright Baubles
    [7307] = 75,  -- Flesh Eating Worm
    [6530] = 50,  -- Nightcrawlers
    [6811] = 50,  -- Aquadynamic Fish Lens
    [6529] = 25,  -- Shiny Bauble
}

local button = CreateFrame("Button", "ProfessionsForeverFishButton", UIParent, "SecureActionButtonTemplate")
button:RegisterForClicks("AnyDown", "AnyUp")
button:SetAttribute("useOnKeyDown", false) -- cast on release, so the override can't catch the same press
button:SetAttribute("type", "spell")

local fishingName -- the cast spell's name, to know its channel
local skillName -- the profession's name, as pole tooltips name it ("Increased Fishing +20")
local overridden, pendingClear

-- The Fishing spell that casts the pole: the one its Overview card drags (UI:DragSlot).
local function FishingSpellID()
    for _, p in ipairs(FP:GetProfessions()) do
        if p.skillLine == FISHING then
            skillName = p.name
            local slot = UI:DragSlot(p)
            local item = slot and C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
            return item and item.spellID
        end
    end
end

-- Points the button at the Fishing cast; nothing to cast without Fishing.
local function SetSpell()
    if InCombatLockdown() then return end
    local id = FishingSpellID()
    fishingName = id and C_Spell.GetSpellName(id)
    button:SetAttribute("spell", fishingName)
end

---------------------------------------------------------------------------
-- Gear before the cast
---------------------------------------------------------------------------
local function IsPole(itemID)
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    return classID == Enum.ItemClass.Weapon and subClassID == Enum.ItemWeaponSubclass.Fishingpole
end

-- The Fishing bonus a pole's tooltip names (0 for a plain pole).
local function PoleBonus(data)
    for _, line in ipairs(data and data.lines or {}) do
        local text = line.leftText
        if text and skillName and text:find(skillName, 1, true) then
            local bonus = text:match("%+(%d+)")
            if bonus then return tonumber(bonus) end
        end
    end
    return 0
end

-- The worn pole's bonus, or nil when the main hand holds no pole.
local function WornPoleBonus()
    local id = GetInventoryItemID("player", MAIN_HAND)
    if id and IsPole(id) then return PoleBonus(C_TooltipInfo.GetInventoryItem("player", MAIN_HAND)) end
end

-- A pole in the bags better than the worn one (any pole when none is worn): bag, slot.
local function BetterPole()
    local best = WornPoleBonus() or -1
    local bestBag, bestSlot
    for _, bag in ipairs(FP.Inv:CarriedBags()) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and IsPole(id) then
                local bonus = PoleBonus(C_TooltipInfo.GetBagItem(bag, slot))
                if bonus > best then best, bestBag, bestSlot = bonus, bag, slot end
            end
        end
    end
    return bestBag, bestSlot
end

-- The best lure in the bags the character can use.
local function BestLure()
    local best, bestID = 0, nil
    for id, bonus in pairs(LURES) do
        if bonus > best and C_Item.GetItemCount(id) > 0 and C_Item.IsUsableItem(id) then best, bestID = bonus, id end
    end
    return bestID
end

-- The Fishing gear set's ID when a piece of it is in the bags instead of worn. The weapon slots are left to the pole
-- step when it is on, so a set without a pole doesn't take the pole off again.
local function SetToWear()
    local name = FP.chardb.fishSet
    local setID = name and C_EquipmentSet.GetEquipmentSetID(name)
    if not setID then return end
    for slot, id in pairs(C_EquipmentSet.GetItemIDs(setID)) do
        local weapon = slot == MAIN_HAND or slot == INVSLOT_OFFHAND
        if id > 0 and not (weapon and FP.db.fishEquipPole) and GetInventoryItemID("player", slot) ~= id
            and C_Item.GetItemCount(id) > 0 then
            return setID
        end
    end
end

-- The GUID of the item worn in a slot, or false when it is empty.
local function WornGUID(slot)
    local loc = ItemLocation:CreateFromEquipmentSlot(slot)
    return C_Item.DoesItemExist(loc) and C_Item.GetItemGUID(loc) or false
end

-- The Swap Back to Normal Gear keybind (Bindings.xml) clicks this secure button. In combat addons can't change gear, but
-- a secure /equipslot can still swap weapons, so its macro holds the weapons saved before the pole went on (set out of
-- combat, whenever they change). Out of combat its PreClick turns the macro off and Fishing:SwapBack does everything.
local SWAP_BINDING = "CLICK ProfessionsForeverSwapBackButton:LeftButton"
UI.FISH_SWAP_BINDING = SWAP_BINDING -- the Swap Back Key option binds it
_G["BINDING_NAME_" .. SWAP_BINDING] = L["Swap Back to Normal Gear"]
local swapButton = CreateFrame("Button", "ProfessionsForeverSwapBackButton", UIParent, "SecureActionButtonTemplate")
swapButton:RegisterForClicks("AnyDown", "AnyUp")
swapButton:SetAttribute("useOnKeyDown", false)
swapButton:SetAttribute("type", "macro")

local function UpdateSwapMacro()
    if InCombatLockdown() then return end
    local saved, names, lines = FP.chardb.fishSaved, FP.chardb.fishWeapons, {}
    for _, slot in ipairs({ MAIN_HAND, INVSLOT_OFFHAND }) do
        if saved[slot] and names[slot] then lines[#lines + 1] = ("/equipslot %d %s"):format(slot, names[slot]) end
    end
    swapButton:SetAttribute("macrotext", table.concat(lines, "\n"))
end

-- Saves what a slot holds before a press changes it; the first save stands until the gear is swapped back. A weapon's
-- name is kept too, for the Swap Back key's macro.
local function Remember(slot)
    local saved = FP.chardb.fishSaved
    if saved[slot] ~= nil then return end
    saved[slot] = WornGUID(slot)
    if saved[slot] and (slot == MAIN_HAND or slot == INVSLOT_OFFHAND) then
        FP.chardb.fishWeapons[slot] = C_Item.GetItemName(ItemLocation:CreateFromEquipmentSlot(slot))
        UpdateSwapMacro()
    end
end

-- Saves every slot the gear set will change.
local function RememberSet(setID)
    for slot, id in pairs(C_EquipmentSet.GetItemIDs(setID)) do
        if id > 0 and GetInventoryItemID("player", slot) ~= id then Remember(slot) end
    end
end

-- Runs before the secure click: does the next gear step itself, or sets the button to put on a lure; with nothing
-- left to do the button keeps its Fishing cast. PostClick puts the cast back.
button:SetScript("PreClick", function(self, _, down)
    if down or InCombatLockdown() or not fishingName then return end
    local db = FP.db
    local setID = SetToWear()
    if setID then
        -- A pole in the set's main hand that isn't worn yet goes on with it, so the message names it
        local poleID = C_EquipmentSet.GetItemIDs(setID)[MAIN_HAND]
        local withPole = poleID and poleID > 0 and IsPole(poleID) and GetInventoryItemID("player", MAIN_HAND) ~= poleID
        RememberSet(setID)
        C_EquipmentSet.UseEquipmentSet(setID)
        if withPole then
            FP:Print(L["Fishing gear equipped, with %s."]:format(select(2, C_Item.GetItemInfo(poleID))))
        else
            FP:Print(L["Fishing gear equipped."])
        end
        self:SetAttribute("type", nil)
        return
    end
    if db.fishEquipPole then
        local bag, slot = BetterPole()
        if bag then
            Remember(MAIN_HAND)
            Remember(INVSLOT_OFFHAND) -- a pole takes both hands
            local link = C_Container.GetContainerItemLink(bag, slot)
            C_Container.PickupContainerItem(bag, slot)
            EquipCursorItem(MAIN_HAND)
            FP:Print(L["%s equipped."]:format(link))
            self:SetAttribute("type", nil)
            return
        end
    end
    if db.fishApplyLure and WornPoleBonus() and not GetWeaponEnchantInfo() then
        local lure = BestLure()
        if lure then
            self:SetAttribute("type", "macro")
            self:SetAttribute("macrotext", ("/use item:%d\n/use %d"):format(lure, MAIN_HAND))
        end
    end
end)
button:SetScript("PostClick", function(self, _, down)
    if down or InCombatLockdown() then return end
    self:SetAttribute("type", "spell")
end)

---------------------------------------------------------------------------
-- Swapping the normal gear back
---------------------------------------------------------------------------
local RETRIES, RETRY_DELAY = 10, 0.5 -- swaps wait for the server, so a slot that didn't take is tried again
local putting, tries, pendingSwap, idleTimer

-- The carried bag slot holding the item with this GUID.
local function FindGUID(guid)
    for _, bag in ipairs(FP.Inv:CarriedBags()) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
            if C_Item.DoesItemExist(loc) and C_Item.GetItemGUID(loc) == guid then return bag, slot end
        end
    end
end

-- One pass over the saved slots, in slot order so the main hand goes back before the off hand. A slot is done when it
-- holds what it held before, or when that item is no longer in the bags (sold, banked) or there's no room to empty it.
local function PutBack()
    local saved = FP.chardb.fishSaved
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local guid = saved[slot]
        if guid ~= nil and WornGUID(slot) == guid then
            saved[slot] = nil
        elseif guid ~= nil and not IsInventoryItemLocked(slot) then
            if guid then
                local bag, bagSlot = FindGUID(guid)
                if not bag then
                    saved[slot] = nil
                elseif not C_Container.GetContainerItemInfo(bag, bagSlot).isLocked then
                    C_Container.PickupContainerItem(bag, bagSlot)
                    EquipCursorItem(slot)
                end
            else
                local bag, bagSlot = FP.Inv:FreeSlot()
                if bag then
                    PickupInventoryItem(slot)
                    C_Container.PickupContainerItem(bag, bagSlot)
                else
                    saved[slot] = nil
                end
            end
        end
    end
    ClearCursor()
    tries = tries + 1
    if next(saved) and tries < RETRIES then return C_Timer.After(RETRY_DELAY, PutBack) end
    wipe(saved)
    wipe(FP.chardb.fishWeapons)
    UpdateSwapMacro()
    putting = false
    FP:Print(L["Your normal gear is back on."])
end

local function StopIdle()
    if idleTimer then idleTimer:Cancel() end
    idleTimer = nil
end

-- Puts back what One-Click Fishing swapped out. In combat it waits for the fight to end. `auto`: started by a
-- trigger, so it says nothing when there is nothing to swap back.
function Fishing:SwapBack(auto)
    if not next(FP.chardb.fishSaved) then
        pendingSwap = false
        if not auto then FP:Print(L["Nothing to swap back."]) end
        return
    end
    if InCombatLockdown() then pendingSwap = true return end
    if putting then return end
    StopIdle()
    putting, tries, pendingSwap = true, 0, false
    PutBack()
end

-- The Swap Back key: in combat its macro swaps the weapons back and the rest goes back once combat ends; out of combat
-- it puts everything back.
swapButton:SetScript("PreClick", function(self, _, down)
    if down or InCombatLockdown() then return end
    self:SetAttribute("type", nil)
end)
swapButton:SetScript("PostClick", function(self, _, down)
    if down then return end
    if InCombatLockdown() then
        pendingSwap = true
        return
    end
    self:SetAttribute("type", "macro")
    Fishing:SwapBack()
end)

-- Starts the wait after a cast ends; the next cast stops it.
local function StartIdle()
    StopIdle()
    if FP.db.fishSwapIdle and next(FP.chardb.fishSaved) then
        idleTimer = C_Timer.NewTimer(FP.db.fishSwapSeconds, function()
            idleTimer = nil
            Fishing:SwapBack(true)
        end)
    end
end

FP:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", function()
    if FP.db.fishSwapMount and IsMounted() then Fishing:SwapBack(true) end
end)
FP:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    pendingSwap = pendingSwap or FP.db.fishSwapCombat -- swap back once combat ends
end)

---------------------------------------------------------------------------
-- The catch
---------------------------------------------------------------------------
-- Game settings changed while the line is out, put back when it comes in. Each one's own value is saved in
-- FP.db.fishCVars first, so a reload or logout mid-cast still restores it at the next login.
local function SetForFishing(name, value)
    local current = C_CVar.GetCVar(name)
    if current == value then return end
    local saved = FP.db.fishCVars
    if saved[name] == nil then saved[name] = current end
    C_CVar.SetCVar(name, value)
end

local function RestoreCVars()
    local saved = FP.db.fishCVars
    for name, value in pairs(saved) do C_CVar.SetCVar(name, value) end
    wipe(saved)
end

-- Louder Fishing Sounds: sound effects (the splash is one) up to the chosen volume, the master volume at least as
-- high, and optionally music and ambience off and sound kept on while the game is in the background.
local function SetSounds()
    local db = FP.db
    if db.fishLoud then
        local volume = db.fishVolume / 100
        SetForFishing("Sound_EnableAllSound", "1")
        SetForFishing("Sound_EnableSFX", "1")
        SetForFishing("Sound_SFXVolume", tostring(volume))
        if (tonumber(C_CVar.GetCVar("Sound_MasterVolume")) or 0) < volume then
            SetForFishing("Sound_MasterVolume", tostring(volume))
        end
    end
    if db.fishMuteMusic then
        SetForFishing("Sound_EnableMusic", "0")
        SetForFishing("Sound_EnableAmbience", "0")
    end
    if db.fishBackground then SetForFishing("Sound_EnableSoundWhenGameIsInBG", "1") end
end

-- Interact aims at the nearest thing in front, which next to an NPC or a mailbox can be that instead of the bobber. So
-- the keys only do Interact while it aims at the bobber (the game object in a GUID's sixth field, as in
-- "GameObject-0-6825-0-2-35591-CA1F3E4CFC"); otherwise they click this button, which says so.
local BOBBER = "35591"
local noop = CreateFrame("Button", "ProfessionsForeverFishNoop", UIParent)
noop:SetScript("OnClick", function()
    UIErrorsFrame:AddMessage(L["The bobber isn't targeted. Face it and try again."], 1, 0.1, 0.1)
end)

local catchKeys, onBobber, ticker

-- Points the keys at Interact or at the no-op button, by what Interact aims at now.
local function Aim()
    if InCombatLockdown() then return end
    local guid = UnitGUID("softinteract")
    local aimed = guid ~= nil and guid:find("^GameObject%-") ~= nil and select(6, strsplit("-", guid)) == BOBBER
    if aimed == onBobber then return end
    onBobber = aimed
    for _, key in ipairs(catchKeys) do
        if aimed then SetOverrideBinding(button, true, key, "INTERACTTARGET")
        else SetOverrideBindingClick(button, true, key, "ProfessionsForeverFishNoop") end
    end
end

local function StartCatch()
    local keys = { GetBindingKey(BINDING) }
    if #keys == 0 then return end
    SetSounds()
    if InCombatLockdown() then return end
    SetForFishing("SoftTargetInteract", "3")
    catchKeys, onBobber = keys, nil
    Aim()
    overridden = true
    ticker = C_Timer.NewTicker(0.1, Aim) -- until the channel ends
end

local function EndCatch()
    RestoreCVars()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if not overridden then return end
    if InCombatLockdown() then pendingClear = true return end
    ClearOverrideBindings(button)
    overridden, pendingClear = false, false
end

FP:RegisterEvent("PLAYER_LOGIN", function()
    RestoreCVars() -- left changed by a reload or logout while fishing
    SetSpell()
    UpdateSwapMacro() -- weapons saved before a reload
end)
FP:RegisterEvent("SKILL_LINES_CHANGED", SetSpell) -- Fishing learned or unlearned
FP:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pendingClear then EndCatch() end
    if pendingSwap then Fishing:SwapBack(true) end
    if not fishingName then SetSpell() end -- Fishing learned in combat
end)

FP:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", function(_, _, _, spellID)
    if fishingName and C_Spell.GetSpellName(spellID) == fishingName then
        StopIdle()
        StartCatch()
    end
end, "player")
FP:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", function(_, _, _, spellID)
    if fishingName and C_Spell.GetSpellName(spellID) == fishingName then
        EndCatch()
        StartIdle()
    end
end, "player")
