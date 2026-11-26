--[[
ThreeLightsLib: suggestions under a text box as you type (UI:Suggest).
]]
local _, ns = ...
local UI = ns.UI

---------------------------------------------------------------------------
-- Suggestions under an edit box as you type. fill(text) returns { { label, value, ... } }; onPick(match) runs when one
-- is picked with Enter or a click. Up and Down or Tab move the highlight; Escape closes the list first. Without a
-- highlighted suggestion, Enter and Escape do what the edit box did before. Returns a controller with :Hide().
---------------------------------------------------------------------------
local SUGGEST_ROWS, SUGGEST_H = 8, 20

function UI:Suggest(eb, fill, onPick)
    local sg = CreateFrame("Frame", nil, eb:GetParent(), "BackdropTemplate")
    sg:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", -6, -2)
    sg:SetPoint("TOPRIGHT", eb, "BOTTOMRIGHT", 0, -2)
    sg:SetFrameLevel(eb:GetParent():GetFrameLevel() + 20)  -- over whatever sits below the box
    sg:EnableMouse(true)
    UI:Skin(sg, "button", true)
    sg:Hide()
    local matches, sel = {}, 0

    local function Hide()
        matches, sel = {}, 0
        sg:Hide()
    end

    local function Draw()
        local a = UI:GetAccent()
        for i, row in ipairs(sg.rows) do
            local m = matches[i]
            row.item = m
            if m then
                row.text:SetText(m.label)
                row.sel:SetColorTexture(a[1], a[2], a[3], 0.25)
                row.sel:SetShown(i == sel)
            end
            row:SetShown(m ~= nil)
        end
    end

    local function Pick(m)
        Hide()
        onPick(m)
    end

    local function Move(delta)
        if #matches == 0 then return end
        sel = (sel - 1 + delta) % #matches + 1
        Draw()
    end

    sg.rows = {}
    for i = 1, SUGGEST_ROWS do
        local row = CreateFrame("Button", nil, sg)
        row:SetHeight(SUGGEST_H)
        row:SetPoint("TOPLEFT", 3, -3 - (i - 1) * SUGGEST_H)
        row:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * SUGGEST_H)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.text = UI:Text(row, "normal")
        row.text:SetWordWrap(false)
        row.text:SetPoint("LEFT", 6, 0)
        row.text:SetPoint("RIGHT", -6, 0)
        row:SetScript("OnClick", function(r) Pick(r.item) end)
        sg.rows[i] = row
    end

    local enter, escape = eb:GetScript("OnEnterPressed"), eb:GetScript("OnEscapePressed")
    eb:SetScript("OnEnterPressed", function(box)
        if matches[sel] then Pick(matches[sel]) elseif enter then enter(box) end
    end)
    eb:SetScript("OnEscapePressed", function(box)
        if sg:IsShown() then Hide() elseif escape then escape(box) end
    end)
    eb:HookScript("OnTextChanged", function(box, user)
        if not user then return end
        local text = box:GetText()
        local found = fill(text) or {}
        -- Nothing to offer, or the only match is exactly what's typed.
        if #found == 0 or (#found == 1 and strlower(found[1].value) == strlower(strtrim(text))) then
            Hide()
            return
        end
        while #found > SUGGEST_ROWS do table.remove(found) end
        matches, sel = found, 1
        sg:SetHeight(#found * SUGGEST_H + 6)
        sg:Show()
        Draw()
    end)
    eb:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" then Move(-1) elseif key == "DOWN" then Move(1) end
    end)
    eb:SetScript("OnTabPressed", function() Move(IsShiftKeyDown() and -1 or 1) end)
    eb:HookScript("OnHide", Hide)
    return { Hide = Hide }
end
