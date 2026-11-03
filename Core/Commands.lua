local _, FP = ...
local L = FP.L

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local COMMANDS = {
    [""] = function() FP:Toggle() end,
    shop = function() FP.Shop:Toggle() end,
    transfer = function() FP.Transfer:Toggle() end,
    cooldowns = function() FP.CooldownPanel:Toggle() end,
    cd = function() FP.CooldownPanel:Toggle() end,
    options = function() FP.Options:Open() end,
    config = function() FP.Options:Open() end,
    reset = function() FP.UI:ResetWindow() end,
    clearway = function() FP.Waypoint:Clear() end,
    ["debug tools"] = function() FP.Tools:Debug() end,
    ["debug cooldowns"] = function() FP.Cooldowns:Debug() end,
}

SLASH_PROFESSIONSFOREVER1 = "/pf"
SLASH_PROFESSIONSFOREVER2 = "/professionsforever"
SLASH_PROFESSIONSFOREVER3 = "/professions"
SlashCmdList.PROFESSIONSFOREVER = function(msg)
    msg = msg or ""
    local cmd = strlower(strtrim(msg))
    local run = COMMANDS[cmd]
    if run then return run() end
    FP:Print(L["Slash commands: /pf, /pf shop, /pf transfer, /pf cooldowns (or /pf cd), /pf options, /pf reset, /pf clearway"])
end

---------------------------------------------------------------------------
-- Addon compartment (the minimap addon menu)
---------------------------------------------------------------------------
function ProfessionsForever_OnAddonCompartmentClick(_, button)
    if button == "RightButton" then FP.Options:Open() else FP:Toggle() end
end
function ProfessionsForever_OnAddonCompartmentEnter(_, anchor)
    GameTooltip:SetOwner(anchor, "ANCHOR_LEFT")
    GameTooltip:AddLine("ProfessionsForever")
    GameTooltip:AddLine(L["Left-click: toggle window"], 1, 1, 1)
    GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
    GameTooltip:Show()
end
function ProfessionsForever_OnAddonCompartmentLeave() GameTooltip:Hide() end
