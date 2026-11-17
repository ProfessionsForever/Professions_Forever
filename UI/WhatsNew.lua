local _, FP = ...
local L = FP.L
local UI = FP.UI

-- What's New: at the first login after an update, a short list of the main changes (the full list is the changelog).
-- It shows the newest notes the player hasn't seen yet, so updating past a version (0.9.4 straight to 0.10.1) still
-- shows that version's notes, and a small update without notes of its own shows nothing. A fresh install only notes the
-- version (FP.freshInstall, Core/Core.lua). /pf whatsnew and the About page's button show the newest notes again.
-- FP.db.whatsNewSeen is the version last logged in with.

-- [version] = { { icon (in Interface\\Icons), heading, text }, ... }. A version without an entry shows nothing.
local NOTES = {
    ["0.10.2"] = {
        { "Spell_Fire_Fire", "Set Up Camp", "A new Camp window (footer, quick button or /pf camp) lists every camp feature you hold, can craft, have on an alt or haven't learned yet. Place them with one click, and the shared cooldowns sit right at the top." },
        { "Trade_Fishing", "One-Click Fishing", "Bind one key: it puts on your fishing gear, best pole and lure, casts, and catches when the fish bites. Your normal gear goes back on when you mount or stop fishing, and bites are louder so you don't miss the splash." },
        { "INV_Misc_Coin_02", "Send Stuff by Hand", "The Transfer Planner's letter button opens Manual Transfers: send an alt an item or some gold, or ask one to send you something. Drop a stack from your bags straight on the window. At the mailbox, Mail attaches exactly the right amount, splitting stacks for you. You can ask for gear from Disenchanting Mode too." },
        { "INV_Misc_Key_03", "Keys for Your Quick Buttons", "Bind a key to any window, to Disenchanting Mode or to each of your professions. Hover a button and press a key to bind it (/pf bind). New Overview and Settings buttons, plus rows or columns, growing from any corner." },
        { "INV_Misc_Note_01", "Your Queue on Item Tooltips", "Hover an item and see how many your crafting queues need and how many you still have to buy. Hold Shift for who needs it and for which recipes." },
        { "INV_Fabric_Silk_02", "Smarter Reagent Prices", "A crafted reagent costs whichever is cheaper, buying it or making it. A Bolt of Silk Cloth is priced at four Silk Cloth when that's less, and Cost to Craft shows what it's made from." },
        { "INV_Misc_Wrench_01", "Options, Sorted", "The options are now in categories, and a new Tooltips section lets you switch every line on or off and drag the blocks into any order, with a live preview beside it." },
        { "INV_Misc_Gift_02", "And More", "A two-row footer when it fills up, a Disenchanting footer cell, a note when a newer version is out, and a pile of fixes. The changelog has every detail." },
    },
    ["0.10.0"] = {
        { "INV_Enchant_DustStrange", "Disenchanting Mode", "Hit the dust icon on the Enchanting tab and your recipes turn into a list of everything you could disenchant. See what each piece might give, whether it's worth more vendored, disenchanted or on the auction house, and zap it right there. Your alts' gear shows up too." },
        { "INV_Enchant_EssenceMagicLarge", "Disenchant advice on tooltips", "Hover a weapon or armour piece and it'll tell you whether to disenchant, vendor or auction it. Every disenchant you do gets recorded, so over time you'll see how the real drops stack up against the odds." },
        { "INV_Scroll_03", "Check in on your alts", "Pick any of your characters on the Overview to browse their recipes, and queue crafts for them. Whoever's holding the materials gets told what to mail over." },
        { "INV_Misc_Bag_10", "A shopping list that keeps itself", "Whatever your queues are short of lands on the list on its own, shared across all your characters on the same faction. Your old lists came along for the ride." },
        { "INV_Letter_01", "Mail counts now", "Stuff sitting in a mailbox counts as yours. At the mailbox, the Transfer Planner mails your alts what they need and grabs what your queue needs in one click." },
        { "INV_Misc_Gear_01", "A smarter crafting queue", "Queue something and the bits it needs get queued first. Short on materials? It won't burn them all on the first step and leave the final craft hanging." },
        { "INV_Misc_PocketWatch_01", "Quick buttons", "A little bar that opens your cooldowns, Transfer Planner, shopping list, queue and Disenchanting Mode without the main window, each with a count of what's waiting. It can have a button for each of your professions too. Drag it wherever you like." },
        { "INV_Misc_Map_01", "Tidier windows", "The queue, Transfer Planner and shopping list share one row of buttons, the side windows all match in width, and docked windows never fall off the screen. With the main window closed, they cozy up to the mailbox or bank instead." },
        { "INV_Misc_Gift_02", "And a whole lot more", "Recipe Search, the Skill Up Route (with SkillUp Forever), trainer and vendor locations without needing Questie, an Integrations page, and a pile of fixes. The changelog has every last detail." },
    },
}

local VERSION = C_AddOns.GetAddOnMetadata("ProfessionsForever", "Version")

-- Whether version a comes before version b ("0.9.4" before "0.10.0": compared number by number, not as text).
local function Before(a, b)
    local x, y = {}, {}
    for n in tostring(a):gmatch("%d+") do x[#x + 1] = tonumber(n) end
    for n in tostring(b):gmatch("%d+") do y[#y + 1] = tonumber(n) end
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p < q end
    end
    return false
end

-- The newest version with notes that is no newer than this one and newer than `after` (nil: any); nil when none.
local function NewestNotes(after)
    local best
    for v in pairs(NOTES) do
        if not Before(VERSION, v) and (not after or Before(after, v)) and (not best or Before(best, v)) then best = v end
    end
    return best
end
local W, PAD, GAP = 500, 18, 12
local ICON, ICON_GAP = 34, 12 -- each highlight's icon, and the room between it and the text
local LOGO = 40

local frame

local function Create()
    local f = CreateFrame("Frame", "ProfessionsForeverWhatsNew", UIParent, "BackdropTemplate")
    f:SetWidth(W)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI:Skin(f, "window")
    tinsert(UISpecialFrames, "ProfessionsForeverWhatsNew") -- Escape closes it
    f.logo = f:CreateTexture(nil, "ARTWORK")
    f.logo:SetSize(LOGO, LOGO)
    f.logo:SetPoint("TOPLEFT", PAD, -PAD)
    f.logo:SetTexture(FP.ICON)
    f.title = UI:Text(f, 3)
    f.title:SetPoint("LEFT", f.logo, "RIGHT", 12, 0) -- centred on the logo
    f.title:SetWidth(W - 2 * PAD - LOGO - 12)
    f.title:SetTextColor(1, 0.82, 0)
    -- A thin line in the accent colour under the title.
    f.rule = f:CreateTexture(nil, "ARTWORK")
    f.rule:SetHeight(1)
    f.rule:SetPoint("TOPLEFT", f.logo, "BOTTOMLEFT", 0, -10)
    f.rule:SetPoint("RIGHT", -PAD, 0)
    f.lines = {}
    f.ok = UI:Button(f, L["Got It"], 120, 24, function() f:Hide() end)
    f.ok:SetPoint("BOTTOM", 0, PAD)
    f:Hide()
    return f
end

-- Shows the notes for `version` (the newest ones without it); false when there are none.
function UI:ShowWhatsNew(version)
    version = version or NewestNotes()
    local notes = NOTES[version]
    if not notes then return false end
    frame = frame or Create()
    local f = frame
    f.title:SetText(L["What's New in ProfessionsForever %s"]:format(version))
    local a = UI:GetAccent()
    f.rule:SetColorTexture(a[1], a[2], a[3], 0.6)
    local textW = W - 2 * PAD - ICON - ICON_GAP
    local y = PAD + LOGO + 10 + 1 + GAP + 4
    for i, note in ipairs(notes) do
        local line = f.lines[i]
        if not line then
            line = { head = UI:Text(f, 1), body = UI:Text(f, 0), icon = f:CreateTexture(nil, "ARTWORK") }
            line.icon:SetSize(ICON, ICON)
            line.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trims the icon's own border
            line.head:SetTextColor(1, 0.82, 0)
            line.body:SetTextColor(0.85, 0.85, 0.85)
            line.body:SetJustifyH("LEFT")
            for _, t in ipairs({ line.head, line.body }) do t:SetWidth(textW) t:SetWordWrap(true) end
            f.lines[i] = line
        end
        line.icon:SetTexture("Interface\\Icons\\" .. note[1])
        line.head:SetText(L[note[2]])
        line.body:SetText(L[note[3]])
        line.icon:ClearAllPoints()
        line.icon:SetPoint("TOPLEFT", PAD, -y)
        line.head:ClearAllPoints()
        line.head:SetPoint("TOPLEFT", line.icon, "TOPRIGHT", ICON_GAP, 0)
        line.body:ClearAllPoints()
        line.body:SetPoint("TOPLEFT", line.head, "BOTTOMLEFT", 0, -3)
        for _, t in pairs(line) do t:Show() end
        y = y + math.max(ICON, line.head:GetStringHeight() + 3 + line.body:GetStringHeight()) + GAP
    end
    for i = #notes + 1, #f.lines do
        for _, t in pairs(f.lines[i]) do t:Hide() end
    end
    f:SetHeight(y + 24 + PAD + 4)
    f:Show()
    f:Raise()
    return true
end

-- First login after an update: the newest notes since the version last logged in with, once. A player from before What's
-- New existed has no version noted, so gets the newest notes. Waits for the loading screen to settle and for combat to
-- end, so it never comes up mid-fight.
local function Check()
    local db = FP.db
    local seen = db.whatsNewSeen
    if seen == VERSION then return end
    db.whatsNewSeen = VERSION
    if FP.freshInstall then return end -- a new install has nothing to compare with
    local notes = NewestNotes(seen)
    if notes then UI:ShowWhatsNew(notes) end
end

local waiting
FP:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if waiting ~= nil then return end
    waiting = true
    C_Timer.After(3, function()
        if InCombatLockdown() then return end -- PLAYER_REGEN_ENABLED below picks it up
        waiting = false
        Check()
    end)
end)
FP:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if waiting then
        waiting = false
        Check()
    end
end)
