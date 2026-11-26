local _, FP = ...
local L = FP.L
local O = FP.Options
local UI = FP.UI

local LAYOUTS = { { key = "columns", label = "Fixed Columns" }, { key = "rows", label = "Fixed Rows" } }
-- The handle's corner, as the two saved grow directions.
local CORNERS = {
    { x = "right", y = "down", label = "Top Left" }, { x = "left", y = "down", label = "Top Right" },
    { x = "right", y = "up", label = "Bottom Left" }, { x = "left", y = "up", label = "Bottom Right" },
}

local function IsCorner(c) return FP.db.quickGrowX == c.x and FP.db.quickGrowY == c.y end
local function IsLayout(c) return FP.db.quickLayout == c.key end

local function Label(choices, isSet)
    for _, c in ipairs(choices) do
        if isSet(c) then return L[c.label] end
    end
end

local function Items(choices, isSet, apply)
    local items = {}
    for _, c in ipairs(choices) do
        items[#items + 1] = { text = L[c.label], checked = isSet(c), onSelect = function()
            apply(c)
            FP.Launcher:Update()
            O:Refresh()
        end }
    end
    return items
end

-- The slider sets whichever the layout keeps fixed; each keeps its own number.
local function CountKey() return FP.db.quickLayout == "rows" and "quickRows" or "quickColumns" end

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
    UI:Tooltip(profs, L["A button for each of your professions with a crafting window, opening it like its tab, without the main window."])
    O.Check(page, L["Show Overview Button"], function() return db.quickOverview end, function(v)
        db.quickOverview = v
        FP.Launcher:Update()
    end)
    O.Check(page, L["Show Settings Button"], function() return db.quickSettings end, function(v)
        db.quickSettings = v
        FP.Launcher:Update()
    end)
    O.Check(page, L["Show Camp Button"], function() return db.quickCamp end, function(v)
        db.quickCamp = v
        FP.Launcher:Update()
    end)
    O.Check(page, L["Show Crates and Writs Button"], function() return db.quickOrders end, function(v)
        db.quickOrders = v
        FP.Launcher:Update()
    end)
    local de = O.Check(page, L["Show Disenchanting Mode Button"], function() return db.quickDisenchant end, function(v)
        db.quickDisenchant = v
        FP.Launcher:Update()
    end)
    UI:Tooltip(de, L["Shown on a character that knows Disenchant, or that has an enchanter among your characters to send gear to."])

    O.Section(page, L["Appearance"])
    local layout = O.DropList(page, L["Layout"], function() return Label(LAYOUTS, IsLayout) end,
        function() return Items(LAYOUTS, IsLayout, function(c) db.quickLayout = c.key end) end)
    UI:Tooltip(layout, L["Fixed Columns: rows of that many buttons, and more rows as buttons are added. Fixed Rows: columns of that many buttons, and more columns as buttons are added."])
    local count = O.Slider(page, L["Columns"], 1, FP.Launcher.MAX_BUTTONS, 1,
        function() return db[CountKey()] end, function(v)
            db[CountKey()] = v
            FP.Launcher:Update()
        end, "%d")
    local function CountLabel() count.label:SetText(db.quickLayout == "rows" and L["Rows"] or L["Columns"]) end
    O.AddRefresher(CountLabel)
    local corner = O.DropList(page, L["Grow From"], function() return Label(CORNERS, IsCorner) end,
        function() return Items(CORNERS, IsCorner, function(c) db.quickGrowX, db.quickGrowY = c.x, c.y end) end)
    UI:Tooltip(corner, L["The corner the handle sits on. The buttons spread away from it, and it stays put as buttons come and go."])
    O.Check(page, L["Show Header"], function() return db.quickHeader end, function(v)
        db.quickHeader = v
        FP.Launcher:Update()
    end)
    O.Check(page, L["Show Keys on Buttons"], function() return db.quickShowKeys end, function(v)
        db.quickShowKeys = v
        FP.Launcher:RefreshHotkeys()
    end)
end

-- The quick button keys page: the same bindings as the game's Key Bindings, AddOns, ProfessionsForever. Its own page,
-- since the rows would make the Quick Buttons page, and so the whole window, much taller.
function O.BuildQuickKeys(page)
    O.Section(page, L["Key Bindings"])
    local hover = O.ActionButton(page, L["Mouseover Keybinding"], 160, function() FP.Launcher:ToggleBindMode() end)
    UI:Tooltip(hover, L["Hover a quick button and press a key to bind it, or right-click it to unbind. Escape to finish. Also /pf bind."])
    for _, k in ipairs(FP.Launcher.BINDINGS) do
        local label = O.KeyBind(page, k.label and L[k.label] or "", k.action)
        if k.profession then
            -- Named after the profession it opens now, as the buttons are.
            local function Name()
                local p = FP.Launcher.CraftingProfessions()[k.profession]
                label:SetText(p and p.name or L["Profession %d"]:format(k.profession))
            end
            O.AddRefresher(Name)
        end
    end
end

function O.ResetQuick()
    O.ResetKeys("quickButtons", "quickButtonsLocked", "quickProfessions", "quickOverview", "quickSettings", "quickCamp", "quickOrders", "quickDisenchant", "quickHeader", "launcherPos", "quickLayout",
        "quickColumns", "quickShowKeys", "quickRows", "quickGrowX", "quickGrowY")
    FP.Launcher:Update()
end
