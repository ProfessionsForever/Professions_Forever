local _, FP = ...
local L = FP.L
local UI = FP.UI
local O = {}
FP.Options = O

-- Each control adds a function that re-reads its value, so the window follows changes made elsewhere.
local refreshers = {}
O.refreshers = refreshers

local LABEL_X, CTRL_X, ROW_H, CTRL_W = 8, 176, 28, 200
O.CTRL_X, O.ROW_H, O.CTRL_W = CTRL_X, ROW_H, CTRL_W

-- Controls are stacked down a page: page.y is the offset of the next row from the page's top.
local function RowCenter(page) return page.y - ROW_H / 2 end

function O.Section(page, title)
    if page.y ~= 0 then page.y = page.y - 12 end
    local t = UI:Text(page, 1)
    t:SetPoint("TOPLEFT", 0, page.y)
    t:SetText(title)
    t:SetTextColor(1, 0.82, 0)
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.12)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, page.y - 20)
    line:SetPoint("TOPRIGHT", 0, page.y - 20)
    page.y = page.y - 28
    return t
end

function O.Label(page, text)
    local t = UI:Text(page, 0)
    t:SetPoint("LEFT", page, "TOPLEFT", LABEL_X, RowCenter(page))
    t:SetText(text)
    return t
end

function O.Slider(page, name, label, min, max, step, get, set, fmt)
    O.Label(page, label)
    local s = CreateFrame("Slider", name, page, "OptionsSliderTemplate")
    s:SetPoint("LEFT", page, "TOPLEFT", CTRL_X, RowCenter(page))
    s:SetWidth(CTRL_W)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    for _, part in ipairs({ "Low", "High", "Text" }) do _G[name .. part]:Hide() end
    local val = UI:Text(page, 0)
    val:SetPoint("LEFT", s, "RIGHT", 10, 0)
    local refreshing
    s:SetScript("OnValueChanged", function(_, v)
        if refreshing then return end
        v = math.floor(v / step + 0.5) * step
        set(v)
        val:SetText(fmt:format(v))
    end)
    refreshers[#refreshers + 1] = function()
        refreshing = true
        s:SetValue(get())
        refreshing = false
        val:SetText(fmt:format(get()))
    end
    refreshers[#refreshers]()
    page.y = page.y - ROW_H
    return s
end

function O.Check(page, label, get, set)
    local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("LEFT", page, "TOPLEFT", LABEL_X - 2, RowCenter(page))
    cb:SetScript("OnClick", function(s) set(s:GetChecked() and true or false) end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
    refreshers[#refreshers]()
    local t = UI:Text(page, 0)
    t:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    t:SetText(label)
    page.y = page.y - ROW_H
    return cb
end

-- Label, then a drop list of choices: getLabel() names the current one, getItems() lists them for UI:OpenMenu.
function O.DropList(page, label, getLabel, getItems)
    O.Label(page, label)
    local dd = UI:Dropdown(page, CTRL_W, 24, getLabel, getItems)
    dd:SetPoint("LEFT", page, "TOPLEFT", CTRL_X, RowCenter(page))
    refreshers[#refreshers + 1] = function() dd:Sync() end
    dd:Sync()
    page.y = page.y - ROW_H
    return dd
end

-- A button in the label column, for actions that have no value to show.
function O.ActionButton(page, label, w, onClick)
    local b = UI:Button(page, label, w, 24, onClick)
    b:SetPoint("LEFT", page, "TOPLEFT", LABEL_X, RowCenter(page))
    page.y = page.y - ROW_H
    return b
end

function O:Refresh()
    for _, refresh in ipairs(refreshers) do refresh() end
end
