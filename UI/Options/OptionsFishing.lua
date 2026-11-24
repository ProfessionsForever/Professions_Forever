local _, FP = ...
local L = FP.L
local UI = FP.UI
local O = FP.Options

-- The One-Click Fishing page: the key, what a press gets ready before casting, when the gear goes back, and the sound
-- while the line is out
-- (Core/Fishing.lua).

-- The Fishing Gear Set choices: None, then the character's equipment sets.
local function SetItems()
    local chardb = FP.chardb
    local function Pick(name)
        chardb.fishSet = name
        O:Refresh()
    end
    local items = { { text = L["None"], checked = chardb.fishSet == nil, onSelect = function() Pick(nil) end } }
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
        local name = C_EquipmentSet.GetEquipmentSetInfo(setID)
        items[#items + 1] = { text = name, checked = chardb.fishSet == name, onSelect = function() Pick(name) end }
    end
    return items
end

-- The wait before the gear goes back: "30 sec", "1 min", "1.5 min".
local function WaitText(seconds)
    if seconds < 60 then return L["%d sec"]:format(seconds) end
    return L["%s min"]:format(("%g"):format(seconds / 60))
end

local SKIP_LABELS = { none = "None", shift = "Shift", ctrl = "Ctrl", alt = "Alt" }

-- The lure key's choices (Skip the Lure While Holding, or Add a Lure While Holding).
local function SkipItems()
    local db, items = FP.db, {}
    for _, key in ipairs(FP.Fishing.SKIP_ORDER) do
        items[#items + 1] = { text = L[SKIP_LABELS[key]], checked = db.fishLureSkipKey == key, onSelect = function()
            db.fishLureSkipKey = key
            FP.Fishing:UpdateSkipKeys()
            O:Refresh()
        end }
    end
    return items
end

function O.BuildFishing(page)
    local db = FP.db
    O.Section(page, L["One-Click Fishing"])
    O.KeyBind(page, L["Fishing Key"], UI.FISH_BINDING)
    local pole = O.Check(page, L["Equip Your Best Fishing Pole"], function() return db.fishEquipPole end, function(v)
        db.fishEquipPole = v
    end)
    UI:Tooltip(pole, "ANCHOR_RIGHT", L["Before casting, a press equips the fishing pole in your bags with the highest Fishing bonus, if it's better than the one you hold."])
    -- The lure key does the opposite of Automatically Apply Your Best Lure, so its label follows the box.
    local skip
    local function SkipLabel()
        skip.label:SetText(L[db.fishApplyLure and "Skip the Lure While Holding" or "Add a Lure While Holding"])
    end
    local lure = O.Check(page, L["Automatically Apply Your Best Lure"], function() return db.fishApplyLure end, function(v)
        db.fishApplyLure = v
        SkipLabel()
    end)
    UI:Tooltip(lure, "ANCHOR_RIGHT", L["Before casting, a press puts the strongest lure in your bags that you can use on your pole, when it has none."])
    skip = O.DropList(page, L["Skip the Lure While Holding"], function() return L[SKIP_LABELS[db.fishLureSkipKey]] end, SkipItems)
    O.refreshers[#O.refreshers + 1] = SkipLabel -- a reset puts the box back
    SkipLabel()
    UI:Tooltip(skip, "ANCHOR_RIGHT", function(tip)
        tip:AddLine(L[db.fishApplyLure
            and "Hold this key as you press the Fishing Key to cast without putting a lure on. It works when the Fishing Key with it held is bound to nothing else."
            or "Hold this key as you press the Fishing Key to put your best lure on first, with Automatically Apply Your Best Lure off. It works when the Fishing Key with it held is bound to nothing else."], 1, 1, 1, true)
    end)
    local set = O.DropList(page, L["Fishing Gear Set"], function() return FP.chardb.fishSet or L["None"] end, SetItems)
    UI:Tooltip(set, "ANCHOR_RIGHT", L["An equipment set (made in the character window) to put on before casting. For this character only."])

    O.Section(page, L["Swapping Your Gear Back"])
    O.KeyBind(page, L["Swap Back Key"], UI.FISH_SWAP_BINDING)
    local mount = O.Check(page, L["When You Mount"], function() return db.fishSwapMount end, function(v)
        db.fishSwapMount = v
    end)
    UI:Tooltip(mount, "ANCHOR_RIGHT", L["The gear a press swapped out (gear set, pole) goes back on when you mount. /pf swapback or the Swap Back Key does it any time."])
    local idle = O.Check(page, L["When You Stop Fishing"], function() return db.fishSwapIdle end, function(v)
        db.fishSwapIdle = v
    end)
    UI:Tooltip(idle, "ANCHOR_RIGHT", L["Puts your gear back once you haven't cast for the time below."])
    local after = O.Slider(page, "ProfessionsForeverOptFishWait", L["After"], 30, 600, 30,
        function() return db.fishSwapSeconds end, function(v) db.fishSwapSeconds = v end, WaitText)
    after.label:ClearAllPoints()
    after.label:SetPoint("RIGHT", after, "LEFT", -10, 0) -- beside its slider, under the box it belongs to
    local combat = O.Check(page, L["After Combat"], function() return db.fishSwapCombat end, function(v)
        db.fishSwapCombat = v
    end)
    UI:Tooltip(combat, "ANCHOR_RIGHT", L["Puts your gear back as soon as combat ends. During combat, press the Swap Back Key to swap your weapons back; armor can't be changed until combat ends."])

    O.Section(page, L["Sound While Fishing"])
    local loud = O.Check(page, L["Louder Fishing Sounds"], function() return db.fishLoud end, function(v)
        db.fishLoud = v
    end)
    UI:Tooltip(loud, "ANCHOR_RIGHT", L["While your line is out, sound effects (the splash of a bite is one) are turned up to the volume below, and the master volume to at least that. Your own settings come back when the cast ends."])
    O.Slider(page, "ProfessionsForeverOptFishVolume", L["Sound Effects Volume"], 10, 100, 5,
        function() return db.fishVolume end, function(v) db.fishVolume = v end, "%d%%")
    local mute = O.Check(page, L["Mute Music and Ambience While Fishing"], function() return db.fishMuteMusic end, function(v)
        db.fishMuteMusic = v
    end)
    UI:Tooltip(mute, "ANCHOR_RIGHT", L["Turns music and ambient sound off while your line is out, so the splash stands out."])
    local bg = O.Check(page, L["Play Sound in the Background While Fishing"], function() return db.fishBackground end, function(v)
        db.fishBackground = v
    end)
    UI:Tooltip(bg, "ANCHOR_RIGHT", L["Keeps the game's sound on while your line is out even when another window is in front, so you can hear a bite."])
end

function O.ResetFishing()
    O.ResetKeys("fishEquipPole", "fishApplyLure", "fishLureSkipKey", "fishLoud", "fishVolume", "fishMuteMusic", "fishBackground",
        "fishSwapMount", "fishSwapIdle", "fishSwapSeconds", "fishSwapCombat")
    FP.chardb.fishSet = nil
    FP.Fishing:UpdateSkipKeys()
end
