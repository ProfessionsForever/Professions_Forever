local _, FP = ...
local L = FP.L
local Panel = {}
FP.CampPanel = Panel

-- The Camp window: every camp item (Core/Camp.lua) in groups: the hand-picked extras you have (Essentials, a Use
-- button showing their own cooldown), ready to place (a secure Place button that uses it,
-- when you know its profession),
-- you can craft (Craft opens the recipe), on or craftable by another character, and not known (collapsed at first).
-- The two shared cooldowns are along the top; Place waits while its item's cooldown runs.
local ROWS, ROW_H = 18, 22
local LIST_TOP = 62
local REFRESH = 5 -- seconds between redraws while open, for the cooldowns counting down
local GROUP_NAMES = { extras = "Essentials", ready = "Camp Features (In Bags)", craft = "Camp Features (Craftable)",
    alts = "Camp Features (On Alts)", unknown = "Camp Features (Not Learned)" }
local GRAY, WHITE = { 0.6, 0.6, 0.6 }, { 0.92, 0.92, 0.92 }

local function Collapsed(group) return FP.db.campCollapsed[group] end

-- Flat list for the scroll area: a header per group with items, then its items unless collapsed.
local function BuildRows(list)
    local rows, byGroup = {}, {}
    for _, e in ipairs(list) do
        byGroup[e.group] = byGroup[e.group] or {}
        table.insert(byGroup[e.group], e)
    end
    for _, g in ipairs(FP.Camp.GROUPS) do
        local items = byGroup[g]
        if items then
            rows[#rows + 1] = { kind = "group", group = g, count = #items }
            if not Collapsed(g) then
                for _, e in ipairs(items) do rows[#rows + 1] = { kind = "entry", e = e } end
            end
        end
    end
    return rows
end

function Panel:Open()
    -- The Place buttons are secure: the window can't be shown, nor their items set, during combat.
    local f = self.frame
    if (not f and InCombatLockdown()) or (f and not f:IsShown() and FP.UI.CombatBlocked(f)) then
        return FP:Print(L["Cannot do that in combat."])
    end
    FP.UI:ShowSidePanel(self)
end
Panel.Toggle = FP.UI.ToggleSidePanel

local function Names(keys)
    local out = {}
    for _, key in ipairs(keys) do out[#out + 1] = FP.Alts:Label(FP.db.characters[key]) end
    return table.concat(out, ", ")
end

local function RowTooltip(row)
    local r = row.entry
    if not (r and r.kind == "entry") then return false end
    local e, tip = r.e, GameTooltip
    tip:SetItemByID(e.id)
    tip:AddLine(" ")
    if e.extra then
        local left = FP.Camp:EntryRemaining(e)
        if left > 0 then tip:AddLine(L["Can be used again in %s"]:format(FP.Cooldowns.Format(left)), 0.9, 0.2, 0.2) end
        tip:AddLine(e.extra == "toy" and L["A toy: it is never used up."] or L["It is never used up."], 0.6, 0.6, 0.6, true)
        return
    end
    local need = FP.RecipeMinSkill[e.recipe]
    tip:AddLine(need and L["Crafted with %s (skill %d)"]:format(e.prof, need) or L["Crafted with %s"]:format(e.prof), GRAY[1], GRAY[2], GRAY[3])
    if e.bags > 0 then tip:AddLine(L["In your bags: %d"]:format(e.bags), 1, 1, 1) end
    if e.bank > 0 then tip:AddLine(L["In your bank: %d"]:format(e.bank), 1, 1, 1) end
    for _, h in ipairs(e.holders) do
        tip:AddLine(L["%s has %d"]:format(FP.Alts:Label(FP.db.characters[h.key]), h.count), 1, 1, 1)
    end
    if IsPlayerSpell(e.recipe) then tip:AddLine(L["You know the recipe."], 0.2, 0.9, 0.2) end
    if #e.crafters > 0 then tip:AddLine(L["Can craft it: %s"]:format(Names(e.crafters)), 1, 1, 1, true) end
    local left = FP.Camp:Remaining(e.category)
    if left > 0 then
        tip:AddLine(L["Can be placed again in %s"]:format(FP.Cooldowns.Format(left)), 0.9, 0.2, 0.2)
        tip:AddLine(e.category == FP.Camp.CAMPFIRES and L["All campfire kits share this cooldown."]
            or L["All camp features share this cooldown."], 0.6, 0.6, 0.6, true)
    end
    if e.canPlace then
        tip:AddLine(L["It is used up when placed."], 0.6, 0.6, 0.6, true)
    else
        tip:AddLine(L["Placing it needs %s."]:format(e.prof), 0.9, 0.2, 0.2, true)
    end
end

local function RowClick(row)
    local r = row.entry
    if r and r.kind == "group" then
        FP.db.campCollapsed[r.group] = not Collapsed(r.group) or nil
        Panel:Update()
    end
end

-- The cooldown line along the top: "Camp Features: Ready" or the time left, the same for campfires.
local function CooldownText(label, category)
    local left = FP.Camp:Remaining(category)
    if left == 0 then return ("%s: |cff33e633%s|r"):format(label, L["Ready"]) end
    return ("%s: |cffe63333%s|r"):format(label, FP.Cooldowns.Format(left))
end

function Panel:Update()
    local f = self.frame
    if not f or not f:IsShown() or InCombatLockdown() then return end
    local Camp = FP.Camp
    f.cdObjects:SetText(CooldownText(L["Camp Features"], Camp.OBJECTS))
    f.cdFires:SetText(CooldownText(L["Campfires"], Camp.CAMPFIRES))
    local list = BuildRows(Camp:List())

    local shown = FP.UI.PanelRows(f)
    FauxScrollFrame_Update(f.scroll, #list, shown, ROW_H)
    f.scroll.barSetRange(math.max(0, #list - shown) * ROW_H)
    local offset = FauxScrollFrame_GetOffset(f.scroll)

    for i, row in ipairs(f.rows) do
        local r = i <= shown and list[offset + i] or nil
        row.entry = r
        row.place:Hide()
        row.craft:Hide()
        if not r then
            row:Hide()
        else
            local isEntry = r.kind == "entry"
            row.bg:SetShown(not isEntry)
            row.icon:SetShown(isEntry)
            row.name:ClearAllPoints()
            row.prof:SetText("")
            row.status:SetText("")
            if isEntry then
                local e = r.e
                row.icon:SetTexture(C_Item.GetItemIconByID(e.id))
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                row.name:SetPoint("RIGHT", row.prof, "LEFT", -4, 0)
                row.name:SetText(e.name)
                row.name:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
                row.prof:SetText(e.prof)
                if e.group == "ready" or e.group == "extras" then
                    if e.bags > 0 and not e.canPlace then
                        row.status:SetText("|cffe63333" .. L["Needs %s"]:format(e.prof) .. "|r")
                    elseif e.bags > 0 then
                        -- A toy is used from the toy box; the rows are reused, so each sets its own action.
                        local toy = e.extra == "toy"
                        row.place:SetAttribute("type1", toy and "toy" or "macro")
                        row.place:SetAttribute("toy", toy and e.id or nil)
                        row.place:SetAttribute("macrotext1", not toy and ("/use item:" .. e.id) or "")
                        local left = Camp:EntryRemaining(e)
                        row.place:SetActive(left == 0)
                        -- While its cooldown runs (shared, or the extra's own) the button shows the time left.
                        row.place.text:SetText(left > 0 and FP.Cooldowns.Format(left) or e.extra and L["Use"]
                            or L["Place"] .. (e.bags > 1 and (" (" .. e.bags .. ")") or ""))
                        row.place:Show()
                    else
                        row.status:SetText(L["%d in bank"]:format(e.bank))
                    end
                elseif e.group == "craft" then
                    row.craft.entry = e
                    row.craft:Show()
                elseif e.group == "alts" then
                    local h = e.holders[1]
                    row.status:SetText(h and L["%s has %d"]:format(FP.Alts:Label(FP.db.characters[h.key]), h.count)
                        or L["%s can craft"]:format(FP.Alts:Label(FP.db.characters[e.crafters[1]])))
                else
                    local need = FP.RecipeMinSkill[e.recipe]
                    row.name:SetTextColor(0.55, 0.55, 0.55)
                    row.status:SetText(need and L["Skill %d"]:format(need) or "")
                end
            else
                row.name:SetPoint("LEFT", 8, 0)
                row.name:SetPoint("RIGHT", row.status, "LEFT", -4, 0)
                row.name:SetText((Collapsed(r.group) and "+ " or "- ") .. L[GROUP_NAMES[r.group]])
                row.name:SetTextColor(1, 0.82, 0)
                row.status:SetText(r.count)
            end
            row:Show()
        end
    end
end

function Panel:Create()
    local UI = FP.UI
    local f = UI:CreateSidePanel({ name = "ProfessionsForeverCampFrame", key = "camp", title = L["Camp"],
        width = 460, height = 480,
        onShow = function(s)
            s.ticker = C_Timer.NewTicker(REFRESH, function() Panel:Update() end)
            Panel:Update()
        end,
        onHide = function(s)
            if s.ticker then s.ticker:Cancel() s.ticker = nil end
        end })
    self.frame = f
    UI.CloseInCombat(f)

    f.cdObjects = UI:Text(f, 0)
    f.cdObjects:SetPoint("TOPLEFT", 14, -36)
    f.cdFires = UI:Text(f, 0, "RIGHT")
    f.cdFires:SetPoint("TOPRIGHT", -14, -36)

    UI:AddPanelList(f, { name = "ProfessionsForeverCampScroll", top = LIST_TOP, bottom = 14, rows = ROWS, rowH = ROW_H,
        update = function() Panel:Update() end, rowBg = true, tooltip = RowTooltip, onClick = RowClick,
        build = function(row)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ROW_H - 4, ROW_H - 4)
            row.icon:SetPoint("LEFT", 14, 0)
            UI.TrimIcon(row.icon)
            row.status = UI:Text(row, 0, "RIGHT")
            row.status:SetPoint("RIGHT", -6, 0)
            row.status:SetWidth(120)
            row.status:SetWordWrap(false)
            row.status:SetTextColor(0.8, 0.8, 0.8)
            -- Place (secure, uses the item) and Craft sit where the status text is.
            row.place = UI:Button(row, L["Place"], 120, ROW_H - 2, function() C_Timer.After(0.5, function() Panel:Update() end) end, "up")
            row.place:SetPoint("RIGHT", -2, 0)
            row.craft = UI:Button(row, L["Craft"], 120, ROW_H - 2, function(s) UI:OpenRecipe(s.entry.recipe, s.entry.skillLine) end)
            row.craft:SetPoint("RIGHT", -2, 0)
            UI:Tooltip(row.craft, L["Opens the recipe in its profession."])
            row.prof = UI:Text(row, -1, "RIGHT")
            row.prof:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
            row.prof:SetWidth(90)
            row.prof:SetWordWrap(false)
            row.prof:SetTextColor(GRAY[1], GRAY[2], GRAY[3])
            row.name = UI:Text(row, 0)
            row.name:SetWordWrap(false)
        end })
end
