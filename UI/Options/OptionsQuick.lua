local _, FP = ...
local L = FP.L
local O = FP.Options
local UI = FP.UI

local GROW_X = { { key = "right", label = "Right" }, { key = "left", label = "Left" } }
local GROW_Y = { { key = "down", label = "Down" }, { key = "up", label = "Up" } }

local function Label(choices, value)
    for _, c in ipairs(choices) do
        if c.key == value then return L[c.label] end
    end
end

local function Items(choices, field)
    local db = FP.db
    local items = {}
    for _, c in ipairs(choices) do
        items[#items + 1] = { text = L[c.label], checked = db[field] == c.key, onSelect = function()
            db[field] = c.key
            FP.Launcher:Update()
            O:Refresh()
        end }
    end
    return items
end

-- The quick buttons page: the bar of buttons that opens the footer windows without the main window.
function O.BuildQuick(page)
    local db = FP.db
    O.Section(page, L["Quick Buttons"])
    O.Check(page, L["Show Quick Buttons"], function() return db.quickButtons end, function(v)
        db.quickButtons = v
        FP.Launcher:Update()
    end)
    O.Check(page, L["Lock Quick Buttons"], function() return db.quickButtonsLocked end, function(v)
        db.quickButtonsLocked = v
        FP.Launcher:Update()
    end)
    local profs = O.Check(page, L["Show Profession Buttons"], function() return db.quickProfessions end, function(v)
        db.quickProfessions = v
        FP.Launcher:Update()
    end)
    UI:Tooltip(profs, "ANCHOR_RIGHT", L["A button for each of your professions with a crafting window, opening it like its tab, without the main window."])

    O.Section(page, L["Appearance"])
    O.Slider(page, "ProfessionsForeverOptQuickColumns", L["Columns"], 1, FP.Launcher.MAX_COLUMNS, 1,
        function() return db.quickColumns end, function(v)
            db.quickColumns = v
            FP.Launcher:Update()
        end, "%d")
    O.DropList(page, L["Grow Horizontally"], function() return Label(GROW_X, db.quickGrowX) end,
        function() return Items(GROW_X, "quickGrowX") end)
    O.DropList(page, L["Grow Vertically"], function() return Label(GROW_Y, db.quickGrowY) end,
        function() return Items(GROW_Y, "quickGrowY") end)
    O.Check(page, L["Show Header"], function() return db.quickHeader end, function(v)
        db.quickHeader = v
        FP.Launcher:Update()
    end)
end

function O.ResetQuick()
    O.ResetKeys("quickButtons", "quickButtonsLocked", "quickProfessions", "quickHeader", "launcherPos", "quickColumns", "quickGrowX", "quickGrowY")
    FP.Launcher:Update()
end
