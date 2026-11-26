--[[
ThreeLightsLib: the confirmation and the text prompt (UI:Confirm, UI:Prompt). One frame, shown for either.
]]
local _, ns = ...
local L = ns.LibHost.L
local UI = ns.UI

---------------------------------------------------------------------------
-- Dialogs: a confirmation and a text prompt, as our own frames.
---------------------------------------------------------------------------
local dialog

local DIALOG_W, DIALOG_PAD = 400, 16

local function MakeDialog()
    dialog = CreateFrame("Frame", ns.LibHost.name .. "Dialog", UIParent, "BackdropTemplate")
    dialog:SetSize(DIALOG_W, 160)
    dialog:SetPoint("CENTER", 0, 120)
    UI:Layer(dialog, "popup")
    dialog:EnableMouse(true)
    UI:Skin(dialog, "window", true)
    UI:Shadow(dialog)
    UI:RegisterDialog(dialog)
    -- Title bar: what the dialog is for, a rule, and a close button.
    dialog.title = UI:Text(dialog, "title")
    dialog.title:SetWordWrap(false)
    dialog.title:SetPoint("TOPLEFT", 12, -10)
    dialog.title:SetPoint("RIGHT", -40, 0)
    local close = UI:Button(dialog, "X", 22, 20, function() dialog:Hide() end)
    close:SetPoint("TOPRIGHT", -6, -6)
    local rule = dialog:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 1, 1, 0.12)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 8, -34)
    rule:SetPoint("TOPRIGHT", -8, -34)
    -- Body: the message or question, then the answer box when there is one.
    dialog.text = UI:Text(dialog, "normal")
    dialog.text:SetPoint("TOPLEFT", DIALOG_PAD, -46)
    dialog.text:SetWidth(DIALOG_W - 2 * DIALOG_PAD)
    dialog.text:SetWordWrap(true)
    dialog.edit = UI:Edit(dialog, DIALOG_W - 2 * DIALOG_PAD, 22, { onEnter = function() dialog.ok:Click() end })
    dialog.edit:SetPoint("TOPLEFT", dialog.text, "BOTTOMLEFT", 0, -10)
    dialog.ok = UI:Button(dialog, L["OK"], 110, 24, function()
        local fn, text = dialog.onOk, dialog.edit:GetText()
        dialog:Hide()
        if fn then fn(text) end
    end)
    dialog.ok:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -6, 14)
    dialog.cancel = UI:Button(dialog, L["Cancel"], 110, 24, function() dialog:Hide() end)
    dialog.cancel:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 6, 14)
    -- Prompts that pass opts.suggest get suggestions; picking one answers the prompt.
    dialog.suggestions = UI:Suggest(dialog.edit, function(text) return dialog.suggest and dialog.suggest(text) end,
        function(m)
            dialog.edit:SetText(m.value)
            dialog.ok:Click()
        end)
    tinsert(UISpecialFrames, ns.LibHost.name .. "Dialog")
end

-- Fills the title and body and sizes the dialog to them.
local function Open(title, text, withEdit)
    if not dialog then MakeDialog() end
    dialog.title:SetText(title)
    dialog.text:SetText(text)
    dialog.edit:SetShown(withEdit)
    dialog.suggest = nil
    dialog.suggestions:Hide()
    local body = math.ceil(dialog.text:GetStringHeight()) + (withEdit and 32 or 0)
    dialog:SetHeight(46 + body + 16 + 24 + 14)
end

-- A yes/no question. title names the action ("Delete Team"); text asks it in full.
function UI:Confirm(title, text, onYes)
    Open(title, text, false)
    dialog.onOk = function() onYes() end
    dialog:Show()
end

-- A question with a typed answer. title names the action; text says what to enter.
-- opts: numeric, suggest (function(text) -> { { label, value } } shown under the box as you type)
function UI:Prompt(title, text, default, onOk, opts)
    Open(title, text, true)
    dialog.edit:SetNumeric(opts and opts.numeric or false)
    dialog.edit:SetText(default or "")
    dialog.suggest = opts and opts.suggest
    dialog.onOk = function(value)
        if value and strtrim(value) ~= "" then onOk(strtrim(value)) end
    end
    dialog:Show()
    dialog.edit:SetFocus()
    dialog.edit:HighlightText()
end
