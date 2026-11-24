local _, FP = ...
local L = FP.L
local UI = FP.UI

-- The popup for the recipes offered in the zone just entered (Core/ZoneRecipes.lua): a header per profession,
-- then a row per recipe with who sells or teaches it, or the quest that rewards it. A click opens the recipe, a
-- right-click sets a waypoint. It reopens where it was dragged to. Pinned, it stays open (Escape does not close it) and
-- follows you from zone to zone.

local W, PAD, TOP, BOTTOM = 380, 14, 40, 46
local HEAD_H, ROW_H, MAX_LIST = 28, 34, 306 -- the list scrolls past nine recipes
local ICON, INDENT = 20, 26

local NAME = "ProfessionsForeverZoneRecipes"
local frame

-- Where the window was dragged to (its top left corner, so a longer list grows down), else above the middle.
local function PlaceWindow(f)
    local pos = FP.db.zonePos
    f:ClearAllPoints()
    if pos then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2]) else f:SetPoint("TOP", UIParent, "CENTER", 0, 240) end
end

-- The pin: the game's gold map pin while pinned, the grey one otherwise, as on the side panels. Escape closes the
-- window only while it isn't pinned.
local function RefreshPin(f)
    local pinned = FP.db.zonePinned
    f.pin.icon:SetAtlas(pinned and "waypoint-mappin-minimap-tracked" or "waypoint-mappin-minimap-untracked")
    tDeleteItem(UISpecialFrames, NAME)
    if not pinned then tinsert(UISpecialFrames, NAME) end
end

local function Create()
    local f = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
    f:SetWidth(W)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        FP.db.zonePos = { f:GetLeft(), f:GetTop() }
        PlaceWindow(f)
    end)
    f.fpOpaque = true -- a solid layer under the skin, so see-through skins stay readable
    f.fpTitleH = TOP - 6
    UI:Skin(f, "window")
    f.title = UI:Text(f, 2)
    f.title:SetPoint("TOPLEFT", PAD, -12)
    f.title:SetWidth(W - 2 * PAD - 24)
    f.pin = UI:Button(f, "", 20, 20, function()
        FP.db.zonePinned = not FP.db.zonePinned
        FP.ZoneRecipes:PinChanged()
    end)
    f.pin:SetPoint("TOPRIGHT", -PAD + 4, -8)
    f.pin.icon = f.pin:CreateTexture(nil, "ARTWORK")
    f.pin.icon:SetAllPoints()
    UI:Tooltip(f.pin, "ANCHOR_BOTTOM", function(tip)
        tip:AddLine(L[FP.db.zonePinned and "Unpin" or "Pin: Keep Open and Follow Me"], 1, 1, 1)
        tip:AddLine(L["A pinned window stays open, lists each zone you enter, and does not close when you press Escape."], 0.8, 0.8, 0.8, true)
    end)
    f.empty = UI:Text(f, 0, "CENTER")
    f.empty:SetPoint("TOPLEFT", PAD, -TOP - 8)
    f.empty:SetPoint("RIGHT", -PAD, 0)
    f.empty:SetTextColor(0.7, 0.7, 0.7)
    f.empty:SetText(L["No recipes to learn in this zone."])
    RefreshPin(f)
    PlaceWindow(f)
    f.title:SetWordWrap(false)
    f.title:SetTextColor(1, 0.82, 0)

    local scroll = CreateFrame("ScrollFrame", "ProfessionsForeverZoneRecipesScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", PAD, -TOP)
    scroll:SetPoint("BOTTOMRIGHT", -PAD, BOTTOM)
    f.list = CreateFrame("Frame", nil, scroll)
    f.list:SetSize(W - 2 * PAD - UI.BAR_GUTTER, 1)
    scroll:SetScrollChild(f.list)
    UI:AttachScrollbar(scroll, scroll.ScrollBar or _G["ProfessionsForeverZoneRecipesScrollScrollBar"], f,
        { top = TOP, bottom = BOTTOM }, f.list)
    f.scroll = scroll
    f.rows = {}

    f.close = UI:Button(f, L["Close"], 100, 24, function() f:Hide() end)
    f.close:SetPoint("BOTTOM", 0, 12)
    -- Which drops are listed, from the window itself: the options' dropdown.
    f.drops = UI:Dropdown(f, 124, 24, function() return FP.ZoneRecipes:DropScopeLabel() end,
        function() return FP.ZoneRecipes:DropScopeItems() end)
    f.drops:SetPoint("BOTTOMLEFT", PAD, 12)
    UI:Tooltip(f.drops, "ANCHOR_TOP", L["Which of the recipes that creatures drop and that chests and other objects hold are listed. Zone Drops Only leaves out the recipes that also drop in other zones or in a dungeon."])
    -- The recipes ignored in the zone, listed again so they can be turned back on (as on the Cooldowns window).
    f.showIgnored = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.showIgnored:SetSize(24, 24)
    f.showIgnored:SetScript("OnClick", function(s)
        FP.db.zoneShowIgnored = s:GetChecked() and true or false
        FP.ZoneRecipes:Refresh()
    end)
    UI:Tooltip(f.showIgnored, "ANCHOR_TOP", L["List the recipes you ignored in this zone, so they can be turned back on."])
    local ignoredLabel = UI:Text(f, 0)
    ignoredLabel:SetPoint("BOTTOMRIGHT", -PAD, 18)
    ignoredLabel:SetText(L["Show Ignored"])
    f.showIgnored:SetPoint("RIGHT", ignoredLabel, "LEFT", -2, 0)
    f:Hide()
    return f
end

local HINT_COLOR = { 0.5, 0.8, 1 }

-- The recipe's item, as the vendor or the quest hands it over (for a trainer's recipe: what it makes, or the spell
-- for an enchant), where it comes from, and what the clicks do.
local function RowTooltip(tip, row)
    local e = row.entry
    local shown = e.kind ~= "T" and e.item or FP.RecipeOutputs[e.recipe]
    if shown then tip:SetItemByID(shown) else tip:SetSpellByID(e.recipe) end
    tip:AddLine(" ")
    UI.AddSourceLines(e.recipe, true, tip) -- as a learned one: its Ctrl-click waypoint hint is the recipe list's
    if e.held then tip:AddLine(L[e.held], 0.1, 1, 0.1) end
    if e.ignored then tip:AddLine(L["Ignored"], 0.6, 0.6, 0.6) end
    local hints = { { L["Click: Open"], L["Click: open this recipe"] } }
    if FP.Waypoint:NavAvailable() and not e.spot.dungeon then -- inside its dungeon, a creature has no place on a map
        hints[2] = { L["Right-click: Waypoint"], L["Right-click: waypoint to %s"]:format(e.npc) }
    end
    hints[#hints + 1] = e.ignored
        and { L["Shift-click: Stop Ignoring"], L["Shift-click: stop ignoring this recipe in this zone"] }
        or { L["Shift-click: Ignore"], L["Shift-click: ignore this recipe in this zone"] }
    UI:AddHints(tip, hints, false, HINT_COLOR)
end

-- Click: the recipe in the main window. Right-click: a waypoint to the NPC the row names. Shift-click: ignores the
-- recipe in this zone, or stops ignoring it.
local function RowClick(row, button)
    local e = row.entry
    if IsShiftKeyDown() then
        FP.ZoneRecipes:SetIgnored(e.recipe, not e.ignored)
    elseif button == "RightButton" then
        if not e.spot.dungeon then FP.Waypoint:ForSpot(e.spot, e.npc, e.name) end
    else
        UI:OpenRecipe(e.recipe, e.skillLine)
    end
end

-- Row i of the list: a profession's header (icon and name) or a recipe (name, the skill it needs on the right, and
-- its source under it). Only recipe rows take the mouse.
local function Row(f, i)
    local row = f.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, f.list)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", RowClick)
    UI:Tooltip(row, "ANCHOR_RIGHT", RowTooltip)
    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.08)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT")
    UI.TrimIcon(row.icon)
    row.name = UI:Text(row, 0)
    row.skill = UI:Text(row, -1, "RIGHT")
    row.skill:SetPoint("TOPRIGHT", -4, -4)
    row.source = UI:Text(row, -1)
    row.source:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.source:SetTextColor(0.7, 0.7, 0.7)
    row.source:SetWidth(f.list:GetWidth() - INDENT)
    for _, t in ipairs({ row.name, row.source }) do t:SetWordWrap(false) end
    f.rows[i] = row
    return row
end

local function SourceText(e)
    if e.kind == "T" then return L["Trained by: %s"]:format(e.npc) end
    if e.kind == "Q" then return UI.QuestSource(e.spot) end
    if e.kind == "D" then return L["Dropped by: %s"]:format(e.npc) end
    if e.kind == "O" then return L["Found in: %s"]:format(e.npc) end
    local text = L["Sold by: %s"]:format(e.npc)
    return e.kind == "L" and ("%s (%s)"):format(text, L["Limited Supply"]) or text
end

-- Whether the window is on screen.
function UI:ZoneRecipesShown() return frame ~= nil and frame:IsShown() end

-- The pin or the saved position changed (the pin button, the options): the button, Escape and the place follow.
function UI:RefreshZonePin()
    if not frame then return end
    RefreshPin(frame)
    PlaceWindow(frame)
end

-- Shows the recipes found in the zone (Zone:Find's list); an empty list shows a line saying so.
function UI:ShowZoneRecipes(zone, found)
    frame = frame or Create()
    local f = frame
    local title = L["Recipe Scout: %s"]:format(zone)
    local sameZone = f:IsShown() and f.title:GetText() == title -- a redraw keeps the list where it was scrolled to
    f.title:SetText(title)
    f.empty:SetShown(#found == 0)
    f.drops:Sync()
    f.showIgnored:SetChecked(FP.db.zoneShowIgnored)
    local n, y, profession = 0, 0, nil
    local function Place(h)
        n = n + 1
        local row = Row(f, n)
        row:SetHeight(h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("RIGHT")
        row:Show()
        y = y + h
        return row
    end
    for _, e in ipairs(found) do
        if e.profession ~= profession then
            profession = e.profession
            local head = Place(HEAD_H)
            head.entry = nil
            head:EnableMouse(false)
            head.icon:SetTexture(e.icon)
            head.icon:Show()
            head.source:Hide()
            head.skill:Hide()
            head.name:ClearAllPoints()
            head.name:SetPoint("LEFT", INDENT, 0)
            head.name:SetTextColor(1, 0.82, 0)
            head.name:SetWidth(f.list:GetWidth() - INDENT)
            head.name:SetText(profession)
        end
        local row = Place(ROW_H)
        row.icon:Hide()
        row.source:Show()
        row.name:ClearAllPoints()
        row.name:SetPoint("TOPLEFT", INDENT, -3)
        if e.ignored then row.name:SetTextColor(0.5, 0.5, 0.5) else row.name:SetTextColor(1, 1, 1) end
        row.entry = e
        row:EnableMouse(true)
        -- "Requires skill 150": green once the character's skill in the profession reaches it, red until then.
        row.skill:SetShown(e.need ~= nil)
        if e.need then
            local c = UI.STATUS_COLORS[e.rank >= e.need and "full" or "missing"]
            row.skill:SetText(L["Requires skill %d"]:format(e.need))
            row.skill:SetTextColor(c[1], c[2], c[3])
        end
        row.name:SetWidth(f.list:GetWidth() - INDENT - (e.need and row.skill:GetStringWidth() + 12 or 0))
        row.name:SetText(e.name)
        -- A recipe whose item the character already has says where it is, in green, instead of its source.
        -- An ignored one says so, in grey.
        row.source:SetText(e.ignored and L["Ignored"] or e.held and L[e.held] or SourceText(e))
        if e.ignored then
            row.source:SetTextColor(0.5, 0.5, 0.5)
        elseif e.held then
            row.source:SetTextColor(0.1, 1, 0.1)
        else
            row.source:SetTextColor(0.7, 0.7, 0.7)
        end
    end
    for i = n + 1, #f.rows do f.rows[i]:Hide() end
    -- A list that fits must be strictly shorter than the window's room for it, or rounding leaves a sliver to
    -- scroll and the bar stays.
    f.list:SetHeight(y > MAX_LIST and y or 1)
    f:SetHeight(TOP + math.max(math.min(y, MAX_LIST), ROW_H) + BOTTOM)
    if not sameZone then f.scroll.fpScrollTo(0) end
    f:Show()
end
