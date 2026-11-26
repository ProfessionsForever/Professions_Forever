--[[
ThreeLightsLib: binding keys to the addon's Bindings.xml actions, for the options' key rows (O.KeyBind) and anything
else of the addon's that binds keys. Taken from ProfessionsForever. Bindings go in the game's current binding set
(account or character), so they show on its Key Bindings screen too. Each action has two slots there, the first and
second key.
]]
local _, ns = ...
local host = ns.LibHost
local L = host.L
local UI = ns.UI

-- Pressed alone these only modify the next key.
UI.MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true }
-- Mouse buttons that can be bound, by their click name. Left and right click stay for clicking.
UI.MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

-- The binding name of `key` with the modifiers held now, such as CTRL-SHIFT-F.
function UI.KeyWithModifiers(key)
    return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
end

-- Binds `key` to `action` in slot `index`, replacing what that slot held. A key taken from another action says so.
function UI.BindKey(action, index, key)
    local keys = { GetBindingKey(action) }
    local old = GetBindingAction(key)
    if old ~= "" and old ~= action then
        -- host.print, when given, prints in the addon's own style.
        local msg = L["%s was bound to %s; it now does %s."]:format(GetBindingText(key), GetBindingName(old),
            GetBindingName(action))
        if host.print then host.print(msg) else print(msg) end
    end
    if keys[index] and keys[index] ~= key then SetBinding(keys[index]) end
    SetBinding(key, action)
    SaveBindings(GetCurrentBindingSet())
end

-- Clears slot `index` of `action`, or every key it has without one.
function UI.UnbindKey(action, index)
    local keys = { GetBindingKey(action) }
    for i, key in ipairs(keys) do
        if not index or i == index then SetBinding(key) end
    end
    SaveBindings(GetCurrentBindingSet())
end
