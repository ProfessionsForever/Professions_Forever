local _, FP = ...
local UI = FP.UI

-- A frame holding a secure button can't be shown, hidden or moved by addon code in combat.
function UI.CombatBlocked(w)
    return InCombatLockdown() and w:IsProtected()
end

-- A secure handler hides the registered windows as combat starts; the restricted environment may hide protected
-- frames, and the windows can't be shown again until combat ends.
local closer = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
closer:SetAttribute("numFrames", 0)
closer:SetAttribute("_onstate-combat", [[
    if newstate ~= "in" then return end
    for i = 1, self:GetAttribute("numFrames") do
        local frame = self:GetFrameRef("frame" .. i)
        if frame then frame:Hide() end
    end
]])
RegisterStateDriver(closer, "combat", "[combat] in; out")

local pending = {}

local function Add(frame)
    local n = closer:GetAttribute("numFrames") + 1
    closer:SetFrameRef("frame" .. n, frame)
    closer:SetAttribute("numFrames", n)
end

-- Frame references can't be set in combat, so a window created then is registered once combat ends.
function UI.CloseInCombat(frame)
    if InCombatLockdown() then pending[#pending + 1] = frame else Add(frame) end
end

function UI.RegisterPendingCombatClose()
    for _, frame in ipairs(pending) do Add(frame) end
    wipe(pending)
end
