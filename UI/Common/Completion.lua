local _, FP = ...
local UI = FP.UI

local MAX_ROWS, ROW_H = 6, 20

-- Suggestions for an edit box: a drop list of matches and grey text completing the first one. Tab or a click
-- accepts; Up/Down pick a row. getMatches(text) returns the full names to offer, best first. The caller decides
-- when to call :Update() (so it can wait out typing) and :Clear() on every text change. `up` opens the list above.
-- :Selected() is the row picked with the arrow keys, for a caller that handles Enter itself. With `onPick`, a click
-- on a row calls it with the name instead of filling the box.
function UI:AttachCompletion(eb, getMatches, up, onPick)
    -- Its own frame, so skin addons restyling the edit box's regions can't hide the grey text.
    local holder = CreateFrame("Frame", nil, eb)
    holder:SetAllPoints(eb)
    holder:SetFrameLevel(eb:GetFrameLevel() + 1)
    local ghost = holder:CreateFontString(nil, "OVERLAY")
    ghost:SetTextColor(0.5, 0.5, 0.5)
    ghost:SetWordWrap(false)

    local g = {}
    local names, sel, accepted, list = {}, 0, nil, nil

    local function HideList()
        names, sel = {}, 0
        if list then list:Hide() end
    end

    local function DrawRows()
        local accent = UI:GetAccent()
        for i, row in ipairs(list.rows) do
            row:SetShown(names[i] ~= nil)
            row.text:SetText(names[i] or "")
            row.sel:SetColorTexture(accent[1], accent[2], accent[3], i == sel and 0.35 or 0)
        end
    end

    local function Accept(name)
        accepted = name
        eb:SetText(name)
        eb:SetCursorPosition(strlenutf8(name))
        ghost:Hide()
        HideList()
    end

    local function BuildList()
        list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        list:SetFrameStrata("FULLSCREEN_DIALOG")
        list:EnableMouse(true)
        UI:Skin(list, "button")
        list.rows = {}
        for i = 1, MAX_ROWS do
            local row = CreateFrame("Button", nil, list)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", -2, -2 - (i - 1) * ROW_H)
            row.sel = row:CreateTexture(nil, "BACKGROUND")
            row.sel:SetAllPoints()
            row.hl = row:CreateTexture(nil, "HIGHLIGHT")
            row.hl:SetAllPoints()
            row.hl:SetColorTexture(1, 1, 1, 0.1)
            row.text = UI:Text(row, 0)
            row.text:SetPoint("LEFT", 6, 0)
            row.text:SetPoint("RIGHT", -6, 0)
            row.text:SetWordWrap(false)
            -- On press, before the click could take the keyboard focus from the box.
            row:SetScript("OnMouseDown", function()
                local name = names[i]
                if not name then return end
                if onPick then
                    ghost:Hide()
                    HideList()
                    onPick(name)
                else
                    Accept(name)
                end
            end)
            list.rows[i] = row
        end
    end

    local function ShowList()
        if not list then BuildList() end
        DrawRows()
        -- The list hangs from UIParent, so it takes the scale of the window the box is in.
        list:SetScale(eb:GetEffectiveScale() / UIParent:GetEffectiveScale())
        list:SetSize(eb:GetWidth(), 4 + #names * ROW_H)
        list:ClearAllPoints()
        if up then list:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", 0, 2) else list:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", 0, -2) end
        list:Show()
    end

    local function ShowGhost(text)
        local match = names[1]
        if not match or #match <= #text or strlower(strsub(match, 1, #text)) ~= strlower(text) then return end
        if eb:GetCursorPosition() ~= strlenutf8(text) then return end
        local path, size, flags = eb:GetFont()
        -- Only on a change: a skin addon may react to every font set by re-styling the edit box.
        if ghost.fpPath ~= path or ghost.fpSize ~= size then
            ghost.fpPath, ghost.fpSize = path, size
            if not (path and ghost:SetFont(path, size, flags)) then ghost:SetFont(STANDARD_TEXT_FONT, size or 12, "") end
        end
        ghost:SetText(text)
        local typedWidth = ghost:GetStringWidth()
        ghost:SetText(strsub(match, #text + 1))
        local left, right = eb:GetTextInsets()
        if left + typedWidth + ghost:GetStringWidth() > eb:GetWidth() - right - 4 then return end
        ghost:ClearAllPoints()
        ghost:SetPoint("LEFT", eb, "LEFT", left + typedWidth, 0)
        ghost:Show()
    end

    -- The list stays until the next Update, so it doesn't flicker while typing; only the grey text goes at once.
    function g:Clear()
        ghost:Hide()
        if eb:GetText() ~= accepted then accepted = nil end
    end

    function g:Update()
        ghost:Hide()
        local text = eb:GetText()
        if not eb:HasFocus() or text == accepted then return HideList() end
        local found = getMatches(text)
        names, sel = {}, 0
        for i = 1, math.min(#found, MAX_ROWS) do names[i] = found[i] end
        if #names == 0 then return HideList() end
        ShowList()
        ShowGhost(text)
    end

    function g:Selected() return sel > 0 and names[sel] or nil end

    eb:HookScript("OnEditFocusLost", function()
        ghost:Hide()
        C_Timer.After(0.1, function() if not eb:HasFocus() then HideList() end end)
    end)
    eb:HookScript("OnHide", HideList)
    eb:HookScript("OnArrowPressed", function(_, key)
        if #names == 0 then return end
        if key == "DOWN" then sel = sel >= #names and 1 or sel + 1
        elseif key == "UP" then sel = sel <= 1 and #names or sel - 1
        else return end
        DrawRows()
    end)
    eb:SetScript("OnTabPressed", function(self)
        -- Fresh unless a row was picked: the shown list can lag a keystroke behind.
        local pick = sel > 0 and names[sel] or getMatches(self:GetText())[1]
        if pick then Accept(pick) end
    end)
    return g
end
