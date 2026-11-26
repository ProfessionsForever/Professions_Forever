--[[
What the shared UI library (Libs/ThreeLightsLib) needs to know about this addon. Loaded just before the library's
files, which build FP.UI (skins, fonts, buttons, menus, scrollbars, item suggestions) and FP.Options (the options
window) from it. The library is a copy of the ThreeLightsLib repository, brought in with its sync.sh; change it there,
not here.
]]
local _, FP = ...
local L = FP.L

FP.LibHost = {
    -- The addon's folder name: prefixes frame names, finds the library's media, names the EllesmereUI skin.
    name = "ProfessionsForever",
    L = L,
    -- Texts wrap unless told not to, as they always have here.
    textWraps = true,
    -- The appearance options (skin, font, fontSize, opacity, accent, scale, locked) live in the account-wide table.
    options = function() return FP.db end,
    print = function(msg) FP:Print(msg) end,
    optionsTitle = "ProfessionsForever",
    optionsWidth = 640,
    resetAll = function() FP:ResetOptions() end,
    -- The main window (UI/UI.lua), for the options' scale slider, lock and window reset.
    applyWindow = function() FP.UI:SetScale(FP.UI.Opt("scale")) end,
    resetWindow = function() FP.UI:ResetWindow() end,
    applyLock = function() FP.UI:ApplyLock() end,
    lockLabel = L["Lock Window Position and Size"],
    scaleTip = L["Ctrl+Mouse wheel on the title bar changes scale."],
}
