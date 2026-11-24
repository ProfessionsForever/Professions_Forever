local _, FP = ...
local L = FP.L
local Panel = {}
FP.CooldownPanel = Panel

-- The Cooldowns window: every character's recipe cooldowns (Core/Cooldowns.lua).

local ROWS, ROW_H = 17, 22
local REFRESH = 30 -- seconds between redraws while the panel is open

-- Flat list for the scroll area: a header per character, then its cooldowns.
local function BuildRows(groups)
    local rows = {}
    for _, g in ipairs(groups) do
        rows[#rows + 1] = { kind = "char", g = g }
        for _, c in ipairs(g.entries) do rows[#rows + 1] = { kind = "entry", g = g, c = c } end
    end
    return rows
end

function Panel:Open() FP.UI:ShowSidePanel(self) end
Panel.Toggle = FP.UI.ToggleSidePanel

local function RowTooltip(row)
    local e = row.entry
    if not (e and e.kind == "entry") then return false end
    local tip, c = GameTooltip, e.c
    tip:AddLine(c.name, 1, 1, 1)
    tip:AddLine(FP.Alts:Label(e.g.rec), FP.Alts:ClassColor(e.g.rec.class))
    if c.prof then tip:AddLine(c.prof, 0.8, 0.8, 0.8) end
    local length = FP.Cooldowns.Length(c.id)
    if length then tip:AddLine(L["Cooldown: %s"]:format(FP.Cooldowns.Format(length)), 0.8, 0.8, 0.8) end
    if c.unknown then
        tip:AddLine(L["Not seen yet. Learn it, or open its profession, to track it."], 0.6, 0.6, 0.6, true)
    elseif c.ignored then
        tip:AddLine(L["Ignored"], 0.6, 0.6, 0.6)
    elseif c.remaining == 0 then
        local full = FP.UI.STATUS_COLORS.full
        tip:AddLine(L["Cooldown ready"], full[1], full[2], full[3])
    else
        tip:AddLine(L["Ready in %s"]:format(FP.Cooldowns.Format(c.remaining)), 0.9, 0.2, 0.2)
        tip:AddLine(L["Ready at %s"]:format(date("%Y-%m-%d %H:%M", c.readyAt)), 0.6, 0.6, 0.6)
    end
    if e.g.key == FP.Alts:GetCharacterKey() and FP.Cooldowns.SkillLine(c) then tip:AddLine(L["Click: open this recipe"], 0.5, 0.8, 1) end
    tip:AddLine(c.ignored and L["Right-click: stop ignoring this cooldown"] or L["Right-click: ignore this cooldown"], 0.5, 0.8, 1)
end

local function RowClick(row, button)
    local e = row.entry
    if not (e and e.kind == "entry") then return end
    if button == "RightButton" then return FP.Cooldowns:SetIgnored(e.g.key, e.c.id, not e.c.ignored, e.c) end
    if e.g.key == FP.Alts:GetCharacterKey() then
        local line = FP.Cooldowns.SkillLine(e.c)
        if line then FP.UI:OpenRecipe(e.c.id, line) end
    end
end

function Panel:Update()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local UI, Alts = FP.UI, FP.Alts
    local groups = FP.Cooldowns:List()
    f.showIgnored:SetChecked(FP.db.showIgnoredCooldowns)
    local list = BuildRows(groups)
    local colors = UI.STATUS_COLORS

    local shown = FP.UI.PanelRows(f) -- fewer than ROWS while the panel is docked shorter
    FauxScrollFrame_Update(f.scroll, #list, shown, ROW_H)
    f.scroll.fpSetRange(math.max(0, #list - shown) * ROW_H)
    local offset = FauxScrollFrame_GetOffset(f.scroll)
    f.empty:SetShown(#list == 0)

    for i, row in ipairs(f.rows) do
        local e = i <= shown and list[offset + i] or nil
        row.entry = e
        if not e then
            row:Hide()
        else
            local isEntry = e.kind == "entry"
            row.bg:SetShown(not isEntry)
            row.icon:SetShown(isEntry)
            row.name:ClearAllPoints()
            row.prof:SetText("")
            if isEntry then
                local c = e.c
                local color = c.remaining == 0 and colors.full or colors.missing
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                row.name:SetPoint("RIGHT", row.prof, "LEFT", -4, 0)
                row.icon:SetTexture(c.icon)
                row.name:SetText(c.name)
                row.name:SetTextColor(0.92, 0.92, 0.92)
                row.prof:SetText(c.prof or "")
                row.time:SetText(c.remaining == 0 and L["Ready"] or FP.Cooldowns.Format(c.remaining))
                row.time:SetTextColor(color[1], color[2], color[3])
                if c.unknown then
                    row.name:SetTextColor(0.55, 0.55, 0.55)
                    row.time:SetText(FP.Cooldowns.Format(FP.Cooldowns.Length(c.id)))
                    row.time:SetTextColor(0.55, 0.55, 0.55)
                elseif c.ignored then
                    row.name:SetTextColor(0.55, 0.55, 0.55)
                    row.time:SetText(L["Ignored"])
                    row.time:SetTextColor(0.55, 0.55, 0.55)
                end
            else
                local g = e.g
                row.name:SetPoint("LEFT", 8, 0)
                row.name:SetPoint("RIGHT", row.time, "LEFT", -4, 0)
                row.name:SetText(Alts:Label(g.rec))
                row.name:SetTextColor(Alts:ClassColor(g.rec.class))
                row.time:SetText(g.ready > 0 and L["%d ready"]:format(g.ready) or "")
                row.time:SetTextColor(colors.full[1], colors.full[2], colors.full[3])
            end
            row:Show()
        end
    end
    local ready = 0
    for _, g in ipairs(groups) do ready = ready + g.ready end
    f.summary:SetText(#groups > 0 and L["%d ready"]:format(ready) or "")
end

function Panel:Create()
    local UI = FP.UI
    local f = UI:CreateSidePanel({ name = "ProfessionsForeverCooldownFrame", key = "cooldowns", title = L["Cooldowns"],
        width = 460, height = 460,
        onShow = function(s)
            s.ticker = C_Timer.NewTicker(REFRESH, function() Panel:Update() end)
            Panel:Update()
        end,
        onHide = function(s)
            if s.ticker then s.ticker:Cancel() s.ticker = nil end
        end })
    self.frame = f

    UI:AddPanelList(f, { name = "ProfessionsForeverCooldownScroll", top = 40, bottom = 40, rows = ROWS, rowH = ROW_H,
        update = function() Panel:Update() end, rowBg = true, tooltip = RowTooltip, onClick = RowClick, rightClick = true,
        build = function(row)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ROW_H - 4, ROW_H - 4)
            row.icon:SetPoint("LEFT", 14, 0)
            UI.TrimIcon(row.icon)
            row.time = UI:Text(row, 0, "RIGHT")
            row.time:SetPoint("RIGHT", -6, 0)
            row.time:SetWidth(70)
            row.prof = UI:Text(row, -1, "RIGHT")
            row.prof:SetPoint("RIGHT", row.time, "LEFT", -6, 0)
            row.prof:SetWidth(90)
            row.prof:SetWordWrap(false)
            row.prof:SetTextColor(0.6, 0.6, 0.6)
            row.name = UI:Text(row, 0)
            row.name:SetWordWrap(false)
        end })

    f.empty = UI:Text(f, 0, "CENTER")
    f.empty:SetPoint("CENTER", 0, 20)
    f.empty:SetWidth(320)
    f.empty:SetText(L["No recipes with a cooldown known yet. Open a profession that has one."])
    f.summary = UI:Text(f, -1)
    f.summary:SetPoint("BOTTOMLEFT", 14, 14)
    f.summary:SetTextColor(0.7, 0.7, 0.7)

    local showIgnored = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    showIgnored:SetSize(24, 24)
    showIgnored:SetPoint("BOTTOMRIGHT", -100, 8)
    showIgnored:SetChecked(FP.db.showIgnoredCooldowns)
    showIgnored:SetScript("OnClick", function(s)
        FP.db.showIgnoredCooldowns = s:GetChecked() and true or false
        Panel:Update()
    end)
    UI:Tooltip(showIgnored, "ANCHOR_TOP", L["List the cooldowns you ignored, so they can be turned back on."])
    f.showIgnored = showIgnored
    local label = UI:Text(f, 0)
    label:SetPoint("LEFT", showIgnored, "RIGHT", 2, 0)
    label:SetText(L["Show Ignored"])
end
