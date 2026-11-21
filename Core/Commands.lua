local _, FP = ...
local L = FP.L

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local COMMANDS = {
    [""] = function() FP:Toggle() end,
    shop = function() FP.Shop:Toggle() end,
    ["track shop"] = function() FP.Shop:ToggleTracker() end,
    queue = function() FP.Queue:Toggle() end,
    transfer = function() FP.Transfer:Toggle() end,
    cooldowns = function() FP.CooldownPanel:Toggle() end,
    cd = function() FP.CooldownPanel:Toggle() end,
    camp = function() FP.CampPanel:Toggle() end,
    crates = function() FP.OrdersPanel:Toggle() end,
    writs = function() FP.OrdersPanel:Toggle() end,
    route = function() if FP.SkillUpPanel:Available() then FP.SkillUpPanel:Toggle() else FP:Print(L["SkillUp Forever is not loaded."]) end end,
    recipe = function() FP.ReagentSearch:ToggleMode("recipe") end,
    recipes = function() FP.ReagentSearch:ToggleMode("recipe") end,
    reagent = function() FP.ReagentSearch:ToggleMode("reagent") end,
    reagents = function() FP.ReagentSearch:ToggleMode("reagent") end,
    de = function() FP.UI:ToggleDisenchantMode() end,
    disenchant = function() FP.UI:ToggleDisenchantMode() end,
    options = function() FP.Options:Open() end,
    config = function() FP.Options:Open() end,
    reset = function() FP.UI:ResetWindow() end,
    clearway = function() FP.Waypoint:Clear() end,
    swapback = function() FP.Fishing:SwapBack() end,
    putaway = function() FP.Fishing:SwapBack() end,
    bind = function() FP.Launcher:ToggleBindMode() end,
    whatsnew = function() if not FP.UI:ShowWhatsNew() then FP:Print(L["Nothing new to show for this version."]) end end,
}
FP.commands = COMMANDS -- Core/Debug.lua adds its commands here

SLASH_PROFESSIONSFOREVER1 = "/pf"
SLASH_PROFESSIONSFOREVER2 = "/professionsforever"
SLASH_PROFESSIONSFOREVER3 = "/professions"
SlashCmdList.PROFESSIONSFOREVER = function(msg)
    msg = msg or ""
    local cmd = strlower(strtrim(msg))
    local run = COMMANDS[cmd]
    if run then return run() end
    FP:Print(L["Slash commands: /pf, /pf queue, /pf shop, /pf transfer, /pf cooldowns (or /pf cd), /pf camp, /pf crates, /pf route, /pf recipe, /pf reagent, /pf de, /pf track shop, /pf bind, /pf options, /pf reset, /pf clearway, /pf swapback"])
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
