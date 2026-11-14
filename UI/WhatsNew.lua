local _, FP = ...
local L = FP.L
local UI = FP.UI

-- What's New: once per version, at the first login after an update, a short list of the main changes (the full list is
-- the changelog). A fresh install only notes the version (FP.freshInstall, Core/Core.lua). /pf whatsnew and the About
-- page's button show it again. FP.db.whatsNewSeen is the last version shown.

-- [version] = { { icon (in Interface\\Icons), heading, text }, ... }. A version without an entry shows nothing.
local NOTES = {
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

-- Shows the notes for `version` (this version without it); false when there are none.
function UI:ShowWhatsNew(version)
    version = version or VERSION
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

-- First login after an update: show this version's notes once. Waits for the loading screen to settle and for combat
-- to end, so it never comes up mid-fight.
local function Check()
    local db = FP.db
    if db.whatsNewSeen == VERSION then return end
    db.whatsNewSeen = VERSION
    if FP.freshInstall then return end -- a new install has nothing to compare with
    UI:ShowWhatsNew()
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
