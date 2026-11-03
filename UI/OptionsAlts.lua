local _, FP = ...
local L = FP.L
local UI = FP.UI
local O = FP.Options
local refreshers = O.refreshers

-- Alt inventory: planning mode and which other characters may supply materials.
local ALT_MODE_LABELS = { never = "Never", show = "Show Only", include = "Include in Planning" }
local CHAR_ROWS, CHAR_ROW_H = 6, 22
local confirmingRemove -- character key awaiting the second click

function O:RefreshCharacters()
    local box = self.charBox
    if not (box and box:IsVisible()) then return end
    local Alts = FP.Alts
    local others = Alts:Others()
    FauxScrollFrame_Update(box.scroll, #others, CHAR_ROWS, CHAR_ROW_H)
    box.rowEdge:SetBar(#others > CHAR_ROWS)
    if box.scroll.fpEUISetRange then box.scroll:fpEUISetRange(math.max(0, #others - CHAR_ROWS) * CHAR_ROW_H) end
    local offset = FauxScrollFrame_GetOffset(box.scroll)
    box.empty:SetShown(#others == 0)
    for i, row in ipairs(box.rows) do
        local c = others[offset + i]
        if c then
            local rec = c.rec
            row.key = c.key
            row.check:SetChecked(rec.enabled ~= false)
            row.name:SetText(Alts:Label({ name = rec.name, key = c.key, realm = rec.realm })
                .. (Alts:IsOtherFaction(rec) and ("  |cff999999(" .. L["other faction"] .. ")|r") or ""))
            row.name:SetTextColor(Alts:ClassColor(rec.class))
            local sure = confirmingRemove == c.key
            row.remove.text:SetText(sure and "?" or "x")
            if sure then row.remove.text:SetTextColor(1, 0.3, 0.3) else row.remove.text:SetTextColor(1, 1, 1) end
            row:Show()
        else
            row.key = nil
            row:Hide()
        end
    end
end

local function BuildCharacterList(page)
    local box = CreateFrame("Frame", nil, page, "BackdropTemplate")
    O.charBox = box
    box:SetPoint("TOPLEFT", 0, page.y)
    box:SetPoint("TOPRIGHT", 0, page.y)
    box:SetHeight(CHAR_ROWS * CHAR_ROW_H + 4)
    page.y = page.y - box:GetHeight()
    UI:Skin(box, "button")
    local scroll = CreateFrame("ScrollFrame", "ProfessionsForeverOptCharScroll", box, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 2, -2)
    scroll:SetPoint("BOTTOMRIGHT", -24, 2)
    scroll:SetScript("OnVerticalScroll", function(s, offset)
        FauxScrollFrame_OnVerticalScroll(s, offset, CHAR_ROW_H, function() O:RefreshCharacters() end)
    end)
    box.scroll = scroll
    local scrollBar = scroll.ScrollBar or _G["ProfessionsForeverOptCharScrollScrollBar"]
    if not UI:AttachEUIThinScrollbar(scroll, scrollBar, box, { top = 2, bottom = 2 }) then
        UI:EUIWidget(scrollBar, "scrollbar")
    end
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, delta)
        if scroll.fpEUIScrollTo then
            scroll.fpEUIScrollTo(scroll:GetVerticalScroll() - delta * CHAR_ROW_H * 2)
        elseif scrollBar then
            scrollBar:SetValue(scrollBar:GetValue() - delta * CHAR_ROW_H * 2)
        end
    end)

    box.rowEdge = UI:RowEdge(box, 24, 4)
    box.rows = {}
    for i = 1, CHAR_ROWS do
        local row = CreateFrame("Frame", nil, box)
        row:SetHeight(CHAR_ROW_H)
        row:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -2 - (i - 1) * CHAR_ROW_H)
        row:SetPoint("TOPRIGHT", box.rowEdge, "TOPRIGHT", 0, -2 - (i - 1) * CHAR_ROW_H)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(22, 22)
        row.check:SetPoint("LEFT", 0, 0)
        row.check:SetScript("OnClick", function(s)
            if row.key then FP.Alts:SetEnabled(row.key, s:GetChecked() and true or false) end
        end)
        UI:Tooltip(row.check, "ANCHOR_RIGHT", L["Enabled for Planning"])
        row.remove = UI:Button(row, "x", 20, 18, function()
            local key = row.key
            if not key then return end
            if confirmingRemove ~= key then
                confirmingRemove = key
                O:RefreshCharacters()
                C_Timer.After(4, function()
                    if confirmingRemove == key then
                        confirmingRemove = nil
                        O:RefreshCharacters()
                    end
                end)
                return
            end
            confirmingRemove = nil
            FP.Alts:Remove(key)
        end)
        row.remove:SetPoint("RIGHT", -2, 0)
        UI:Tooltip(row.remove, "ANCHOR_RIGHT", function(tip)
            if not row.key then return false end
            if confirmingRemove == row.key then
                tip:AddLine(L["Click again to remove the cached inventory of this character."], 1, 0.4, 0.4, true)
            else
                tip:AddLine(L["Remove Character"], 1, 1, 1)
            end
        end)
        row.name = UI:Text(row, 0)
        row.name:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
        row.name:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
        row.name:SetWordWrap(false)
        box.rows[i] = row
    end
    box.empty = UI:Text(box, 0, "CENTER")
    box.empty:SetPoint("CENTER")
    box.empty:SetText(L["No other characters seen yet. Log in to them to cache their inventory."])
    box.empty:SetTextColor(0.6, 0.6, 0.6)
    refreshers[#refreshers + 1] = function() O:RefreshCharacters() end
end

function O.BuildAlts(page)
    O.Section(page, L["Planning"])
    local altMode = O.DropList(page, L["Alt Inventory"], function() return L[ALT_MODE_LABELS[FP.Planner:Mode()]] end, function()
        local items = {}
        for _, mode in ipairs(FP.Planner.MODES) do
            items[#items + 1] = { text = L[ALT_MODE_LABELS[mode]], checked = FP.Planner:Mode() == mode, onSelect = function()
                FP.Planner:SetMode(mode)
                O:Refresh()
            end }
        end
        return items
    end)
    UI:Tooltip(altMode, "ANCHOR_RIGHT", function(tip)
        tip:AddLine(L["Alt Inventory"], 1, 1, 1)
        tip:AddLine(L["Never: other characters' materials are ignored."], 0.8, 0.8, 0.8, true)
        tip:AddLine(L["Show only: shown in tooltips, but never reduces what is missing or what you buy."], 0.8, 0.8, 0.8, true)
        tip:AddLine(L["Include in planning: enabled characters supply materials, so only the remainder goes on the shopping list."], 0.8, 0.8, 0.8, true)
    end)

    O.Section(page, L["Characters"])
    local headerY = page.y + 28
    local disableAll = UI:Button(page, L["Disable All"], 90, 20, function() FP.Alts:SetAllEnabled(false) end)
    disableAll:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, headerY + 2)
    local enableAll = UI:Button(page, L["Enable All"], 90, 20, function() FP.Alts:SetAllEnabled(true) end)
    enableAll:SetPoint("RIGHT", disableAll, "LEFT", -6, 0)
    page.y = page.y - 2
    BuildCharacterList(page)

    page:SetScript("OnShow", function() O:RefreshCharacters() end)
    page:SetScript("OnHide", function() confirmingRemove = nil end)
end
