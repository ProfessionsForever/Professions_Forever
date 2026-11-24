local _, FP = ...
local L = FP.L
local Panel = {}
FP.SkillUpPanel = Panel

-- The levelling route of SkillUp Forever (its public API, read-only): the next steps and the reagents they need, for each profession.
local ROWS, ROW_H = 17, 22
local STEPS_SHOWN = 5

local function API()
    local api = _G.SkillUpForever and SkillUpForever.API
    return api and api.Professions and api.Subscribe and api.Navigate and api or nil
end

function Panel:Available() return API() ~= nil end

-- Flat list for the scroll area: a header per profession, its next steps, then its reagents.
local function BuildRows(list)
    local rows, missingNames = {}, false
    for _, p in ipairs(list) do
        rows[#rows + 1] = { kind = "prof", p = p }
        for i, s in ipairs(p.steps) do rows[#rows + 1] = { kind = "step", p = p, index = i, s = s } end
        if #p.reagents > 0 then
            rows[#rows + 1] = { kind = "head", text = L["Reagents"] }
            for _, r in ipairs(p.reagents) do
                if not C_Item.GetItemNameByID(r.itemID) then missingNames = true end
                rows[#rows + 1] = { kind = "reagent", p = p, r = r }
            end
        end
    end
    return rows, missingNames
end

-- First line of the footer cell: the next thing to do, in the profession that has something to do.
function Panel:Summary()
    local api = API()
    local list = api and api.Professions({ steps = 1, recipes = 1 })
    local p = list and list[1]
    if not p then return end
    local s = p.steps[1]
    return p.name, s and s.text, s and s.detail
end

-- Each profession of the route with its next step only, for the window tooltip: { { name, steps = { { text, detail } } } }.
function Panel:NextSteps()
    local api = API()
    return api and api.Professions({ steps = 1, recipes = 1 }) or {}
end

function Panel:Open() FP.UI:ShowSidePanel(self) end
Panel.Toggle = FP.UI.ToggleSidePanel

local function StepColor(kind)
    local colors = FP.UI.STATUS_COLORS
    if kind == "craft" then return colors.full end
    if kind == "buy" then return colors.partial end
    if kind == "gather" then return colors.bank end
    return FP.UI.CHAIN_COLOR
end

local function RowTooltip(row)
    local e = row.entry
    if not e or e.kind == "head" then return false end
    local tip = GameTooltip
    if e.kind == "prof" then
        tip:AddLine(e.p.name, 1, 1, 1)
        FP.UI.AddSkillLine(tip, e.p.rank, e.p.maxRank)
        if e.p.title then tip:AddLine(e.p.title, 0.8, 0.8, 0.8) end
    elseif e.kind == "step" then
        local s = e.s
        tip:AddLine(s.text, 1, 1, 1, true)
        if s.detail then tip:AddLine(s.detail, 0.8, 0.8, 0.8, true) end
        if s.cost then tip:AddLine(FP.Prices:Format(s.cost), 0.8, 0.8, 0.8) end
        if s.nav then
            tip:AddLine(L["Click: waypoint to the nearest trainer or vendor"], 0.5, 0.8, 1)
        elseif s.kind == "craft" and s.spellID then
            tip:AddLine(L["Click: open this recipe"], 0.5, 0.8, 1)
        end
    else
        local r = e.r
        tip:AddLine(FP.ItemName(r.itemID), 1, 1, 1)
        tip:AddLine(L["You Have"] .. ": " .. r.have .. " / " .. r.need, 0.8, 0.8, 0.8)
    end
end

local function RowClick(row)
    local e = row.entry
    if not (e and e.kind == "step") then return end
    local s = e.s
    if s.nav then
        API().Navigate(e.p.skillLineID, e.index)
    elseif s.kind == "craft" and s.spellID then
        FP.UI:OpenRecipe(s.spellID, e.p.skillLineID)
    end
end

local function RowIcon(e)
    if e.kind == "prof" then return e.p.icon end
    if e.kind == "reagent" then return C_Item.GetItemIconByID(e.r.itemID) end
    local s = e.s
    if s.itemID then return C_Item.GetItemIconByID(s.itemID) end
    return s.spellID and C_Spell.GetSpellTexture(s.spellID)
end

local function PaintRow(row, e)
    local colors = FP.UI.STATUS_COLORS
    local kind = e.kind
    row.bg:SetShown(kind == "prof" or kind == "head")
    local icon = kind ~= "head" and RowIcon(e)
    row.icon:SetShown(icon and true or false)
    row.icon:SetTexture(icon)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", icon and row.icon or row, icon and "RIGHT" or "LEFT", icon and 4 or 8, 0)
    row.name:SetPoint("RIGHT", row.side, "LEFT", -4, 0)
    row.side:SetTextColor(0.6, 0.6, 0.6)
    if kind == "prof" then
        row.name:SetText(e.p.name)
        row.name:SetTextColor(1, 0.82, 0)
        row.side:SetText(e.p.rank .. " / " .. e.p.maxRank)
    elseif kind == "head" then
        row.name:SetText(e.text)
        row.name:SetTextColor(0.7, 0.7, 0.7)
        row.side:SetText("")
    elseif kind == "step" then
        local c = StepColor(e.s.kind)
        row.name:SetText(e.s.text)
        row.name:SetTextColor(c[1], c[2], c[3])
        row.side:SetText(e.s.detail or "")
    else
        local r = e.r
        local c = r.have >= r.need and colors.full or colors.missing
        row.name:SetText(FP.ItemName(r.itemID))
        row.name:SetTextColor(0.92, 0.92, 0.92)
        row.side:SetText(r.have .. " / " .. r.need)
        row.side:SetTextColor(c[1], c[2], c[3])
    end
end

function Panel:Update()
    local f = self.frame
    local api = API()
    if not f or not f:IsShown() or not api then return end
    local list = api.Professions({ steps = STEPS_SHOWN, recipes = 1 }) or {}
    local rows
    rows, self.missingNames = BuildRows(list)

    local shown = FP.UI.PanelRows(f) -- fewer than ROWS while the panel is docked shorter
    FauxScrollFrame_Update(f.scroll, #rows, shown, ROW_H)
    f.scroll.fpSetRange(math.max(0, #rows - shown) * ROW_H)
    local offset = FauxScrollFrame_GetOffset(f.scroll)
    f.empty:SetShown(#rows == 0)
    for i, row in ipairs(f.rows) do
        local e = i <= shown and rows[offset + i] or nil
        row.entry = e
        if e then
            PaintRow(row, e)
            row:Show()
        else
            row:Hide()
        end
    end
end

-- Item names arrive in bursts, so redraw once after the last of them.
function Panel:QueueUpdate()
    if self.pending then return end
    self.pending = true
    C_Timer.After(0.2, function()
        self.pending = false
        self:Update()
    end)
end

function Panel:Create()
    local UI = FP.UI
    local f = UI:CreateSidePanel({ name = "ProfessionsForeverSkillUpFrame", key = "skillup", title = L["Skill Up Route"],
        width = 460, height = 460,
        onShow = function(s)
            s.unsubscribe = API().Subscribe(function() Panel:QueueUpdate() end)
            s:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            Panel:Update()
        end,
        onHide = function(s)
            s:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
            if s.unsubscribe then s.unsubscribe() s.unsubscribe = nil end
        end })
    self.frame = f
    f:SetScript("OnEvent", function()
        if Panel.missingNames then Panel:QueueUpdate() end
    end)

    UI:AddPanelList(f, { name = "ProfessionsForeverSkillUpScroll", top = 40, bottom = 28, rows = ROWS, rowH = ROW_H,
        update = function() Panel:Update() end, rowBg = true, tooltip = RowTooltip, onClick = RowClick,
        build = function(row)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ROW_H - 4, ROW_H - 4)
            row.icon:SetPoint("LEFT", 6, 0)
            UI.TrimIcon(row.icon)
            row.side = UI:Text(row, -1, "RIGHT")
            row.side:SetPoint("RIGHT", -6, 0)
            row.side:SetWidth(150)
            row.side:SetWordWrap(false)
            row.name = UI:Text(row, 0)
            row.name:SetWordWrap(false)
        end })

    f.empty = UI:Text(f, 0, "CENTER")
    f.empty:SetPoint("CENTER", 0, 20)
    f.empty:SetWidth(340)
    f.empty:SetText(L["No levelling route yet. Learn a profession."])
    local credit = UI:Text(f, -1)
    credit:SetPoint("BOTTOMLEFT", 14, 10)
    credit:SetText(L["Route from SkillUp Forever"])
    credit:SetTextColor(0.6, 0.6, 0.6)
end
