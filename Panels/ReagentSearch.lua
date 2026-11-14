local _, FP = ...
local L = FP.L
local Panel = {}
FP.ReagentSearch = Panel

-- Recipe Search: every recipe in the game, found by name ("recipe" mode) or by a reagent it uses ("reagent" mode).
local ROWS, ROW_H = 16, 22
local TOP = 124 -- where the list starts, below the title, mode buttons, search box and header
Panel.mode = "recipe"

function Panel:Open(itemID)
    FP.UI:ShowSidePanel(self)
    if itemID then self:ShowItem(itemID) end
end
Panel.Toggle = FP.UI.ToggleSidePanel

-- For the slash commands: shows the panel in that mode, or hides it when it is already showing that mode.
function Panel:ToggleMode(mode)
    if self.frame and self.frame:IsShown() and self.mode == mode then return self.frame:Hide() end
    FP.UI:ShowSidePanel(self)
    self:SetMode(mode)
end

-- The magnifier buttons across the windows; they light up while the panel is open.
local buttons = {}

function Panel:CreateButton(parent, size, onClick)
    local UI = FP.UI
    local b = UI:Button(parent, "", size, size, onClick or function() Panel:Toggle() end)
    local glass = b:CreateTexture(nil, "ARTWORK")
    glass:SetSize(size - 8, size - 8)
    glass:SetPoint("CENTER")
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    UI:Tooltip(b, "ANCHOR_BOTTOM", L["Search all recipes, by name or by reagent"])
    buttons[#buttons + 1] = b
    UI.SetSelected(b, self.frame and self.frame:IsShown())
    return b
end

function Panel:SyncButton()
    local shown = self.frame and self.frame:IsShown()
    for _, b in ipairs(buttons) do FP.UI.SetSelected(b, shown) end
end

-- Each mode keeps its own search: the recipe mode's typed text, the reagent mode's chosen item.
function Panel:SetMode(mode)
    local UI, f = FP.UI, self.frame
    self.mode = mode
    UI.SetSelected(f.byName, mode == "recipe")
    UI.SetSelected(f.byReagent, mode == "reagent")
    f.placeholder:SetText(mode == "recipe" and L["Recipe name"] or L["Item ID / link / name"])
    local text = mode == "recipe" and (self.query or "") or (self.itemID and C_Item.GetItemNameByID(self.itemID) or "")
    f.search:SetText(text)
    f.search:SetCursorPosition(0)
    f.scroll.fpScrollTo(0)
    self:Update()
end

function Panel:ShowItem(itemID)
    self.itemID = itemID
    self.uses = FP.Uses:Find(itemID)
    self:SetMode("reagent")
    self.frame.search:ClearFocus()
end

function Panel:SearchName(text)
    self.query = text
    self.found = FP.Uses:Search(text)
    self.frame.scroll.fpScrollTo(0)
    self:Update()
end

-- Your characters that know the recipe, the current one first, then by name: { key, label, class }.
local function KnownBy(recipeID)
    local Alts, chars, me = FP.Alts, FP.db.characters, FP.Alts:GetCharacterKey()
    local out = {}
    for _, key in ipairs(FP.Known:Who(recipeID)) do
        local rec = chars[key]
        out[#out + 1] = { key = key, label = Alts:Label({ name = rec.name, key = key, realm = rec.realm }), class = rec.class }
    end
    table.sort(out, function(a, b)
        if (a.key == me) ~= (b.key == me) then return a.key == me end
        return a.label < b.label
    end)
    return out
end

-- For a recipe of a profession you don't have: another of your characters that knows it and has that profession
-- saved, to browse it there (Alts/AltProfessions.lua). An entry of KnownBy, or nil.
local function AltWhoKnows(r)
    local me = FP.Alts:GetCharacterKey()
    for _, k in ipairs(KnownBy(r.id)) do
        local profs = FP.db.characters[k.key].professions
        if k.key ~= me and profs and profs[r.skillLine] then return k end
    end
end

-- What the recipe makes (or the spell, for enchants), then its profession, reagents and who knows it.
local function RowTooltip(row)
    local r = row.result
    if not r then return false end
    local tip, UI, colors = GameTooltip, FP.UI, FP.UI.STATUS_COLORS
    local made = FP.RecipeOutputs[r.id]
    if made then tip:SetItemByID(made) else tip:SetSpellByID(r.id) end
    tip:AddLine(" ")
    local skill = FP.RecipeMinSkill[r.id]
    tip:AddDoubleLine(r.prof, skill and L["Requires skill %d"]:format(skill) or "", 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    tip:AddLine(L["Reagents:"], 1, 1, 1)
    for _, re in ipairs(FP.Uses:ReagentsOf(r.id)) do
        local bags, bank = FP.Inv:Owned(re.itemID)
        local c = bags >= re.qty and colors.full or (bags + bank >= re.qty and colors.bank or colors.missing)
        tip:AddDoubleLine(FP.ItemName(re.itemID), (bags + bank) .. "/" .. re.qty, 0.9, 0.9, 0.9, c[1], c[2], c[3])
    end
    tip:AddLine(L["Known by:"], 1, 1, 1)
    local who = KnownBy(r.id)
    for _, k in ipairs(who) do tip:AddLine(k.label, FP.Alts:ClassColor(k.class)) end
    if #who == 0 then tip:AddLine(L["None of your characters"], 0.6, 0.6, 0.6) end
    local alt = not r.mine and AltWhoKnows(r)
    if r.mine then
        tip:AddLine(L["Click: open this recipe"], 0.5, 0.8, 1)
    elseif alt then
        tip:AddLine(L["Click: browse it on %s"]:format(alt.label), 0.5, 0.8, 1)
    end
    UI:ShowTooltipIcon(r.icon)
end

local function RowClick(row)
    local r = row.result
    if not r then return end
    if r.mine then return FP.UI:OpenRecipe(r.id, r.skillLine) end
    local alt = AltWhoKnows(r)
    if alt then
        FP.UI.pendingRecipe = r.id -- selected once that character's recipes are listed
        FP.AltProfs:View(alt.key, r.skillLine)
    end
end

function Panel:Update()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local list
    if self.mode == "recipe" then
        list = self.found or {}
        local typed = strtrim(self.query or "") ~= ""
        f.header:SetText(typed and L["%d recipes found"]:format(#list) or "")
        f.empty:SetText(typed and L["No recipe has that name."] or L["Search for a recipe by name, in any profession."])
    else
        list = self.uses or {}
        local id = self.itemID
        f.header:SetText(id and L["Used in %d recipes"]:format(#list) or "")
        f.empty:SetText(id and L["No recipe uses this item."] or L["Search for a reagent to see the recipes that use it."])
    end
    f.empty:SetShown(#list == 0)

    local shown = FP.UI.PanelRows(f) -- fewer than ROWS while the panel is docked shorter
    FauxScrollFrame_Update(f.scroll, #list, shown, ROW_H)
    f.scroll.fpSetRange(math.max(0, #list - shown) * ROW_H)
    local offset = FauxScrollFrame_GetOffset(f.scroll)
    for i, row in ipairs(f.rows) do
        local r = i <= shown and list[offset + i] or nil
        row.result = r
        if not r then
            row:Hide()
        else
            row.icon:SetTexture(r.icon)
            row.name:SetText(r.name)
            local shade = r.learned and 0.92 or r.mine and 0.6 or 0.42
            row.name:SetTextColor(shade, shade, shade)
            row.prof:SetText(r.prof)
            row:Show()
        end
    end
end

function Panel:Create()
    local UI = FP.UI
    local f = UI:CreateSidePanel({ name = "ProfessionsForeverReagentFrame", key = "reagents", title = L["Recipe Search"],
        width = 460, height = TOP + ROWS * ROW_H + 12,
        onShow = function()
            -- Recipes learned since the last look change the flags.
            if Panel.itemID then Panel.uses = FP.Uses:Find(Panel.itemID) end
            if Panel.query then Panel.found = FP.Uses:Search(Panel.query) end
            Panel:SyncButton()
            Panel:SetMode(Panel.mode)
        end,
        onHide = function() Panel:SyncButton() end })
    self.frame = f

    f.byName = UI:Button(f, L["By Name"], 110, 22, function() Panel:SetMode("recipe") end)
    f.byName:SetPoint("TOPLEFT", 18, -40)
    f.byReagent = UI:Button(f, L["By Reagent"], 110, 22, function() Panel:SetMode("reagent") end)
    f.byReagent:SetPoint("LEFT", f.byName, "RIGHT", 6, 0)

    local search = CreateFrame("EditBox", "ProfessionsForeverReagentSearch", f, "InputBoxTemplate")
    search:SetHeight(24)
    search:SetPoint("TOPLEFT", 18, -70)
    search:SetPoint("TOPRIGHT", -12, -70)
    search:SetAutoFocus(false)
    search:SetTextInsets(4, 0, 0, 0)
    UI:EUIWidget(search, "editbox")
    f.search = search
    local ph = UI:AddPlaceholder(search) -- its text follows the search mode
    f.placeholder = ph
    -- By name, the list follows the typing; by reagent, it changes when an item is picked.
    search:SetScript("OnTextChanged", function(s)
        local text = s:GetText()
        ph:SetShown(text == "")
        if Panel.mode == "recipe" and text ~= Panel.query then Panel:SearchName(text) end
    end)
    local suggest
    suggest = FP.UI:AttachItemAutocomplete(search, function(name)
        local id = suggest:Resolve(name)
        if id then Panel:ShowItem(id) end
    end, function(itemID) return Panel.mode == "reagent" and FP.Uses.IsReagent(itemID) end)
    search:SetScript("OnEnterPressed", function(s)
        if Panel.mode == "recipe" then return s:ClearFocus() end
        local text = suggest:Selected() or strtrim(s:GetText())
        local id = text ~= "" and suggest:Resolve(text)
        if id then Panel:ShowItem(id) else s:ClearFocus() end
    end)
    search:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    UI:AddClearButton(search, L["Clear Search"])

    f.header = UI:Text(f, 0)
    f.header:SetPoint("TOPLEFT", 18, -102)
    f.header:SetTextColor(0.8, 0.8, 0.8)

    UI:AddPanelList(f, { name = "ProfessionsForeverReagentScroll", top = TOP, bottom = 12, rows = ROWS, rowH = ROW_H,
        update = function() Panel:Update() end, tooltip = RowTooltip, onClick = RowClick,
        build = function(row)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ROW_H - 4, ROW_H - 4)
            row.icon:SetPoint("LEFT", 6, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.prof = UI:Text(row, -1, "RIGHT")
            row.prof:SetPoint("RIGHT", -6, 0)
            row.prof:SetWidth(90)
            row.prof:SetWordWrap(false)
            row.prof:SetTextColor(0.6, 0.6, 0.6)
            row.name = UI:Text(row, 0)
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.name:SetPoint("RIGHT", row.prof, "LEFT", -4, 0)
            row.name:SetWordWrap(false)
        end })

    f.empty = UI:Text(f, 0, "CENTER")
    f.empty:SetPoint("CENTER", 0, 0)
    f.empty:SetWidth(320)
    f.empty:SetTextColor(0.7, 0.7, 0.7)
end
