local _, FP = ...
local L = FP.L

-- The lines ProfessionsForever adds to item tooltips (bags, bank, loot window, chat links). Each feature registers a
-- provider; the one hook here runs them in the order Options, Tooltips, General puts them in, so their lines always
-- come in the same order. Also the pieces every block shares: the detail key, spacing, indent and the key hint.
-- Kept apart from the rest of the addon so it could become an addon of its own.

local Tips = {}
FP.Tooltips = Tips
local providers = {}

-- While the options' previewer draws its sample (Tooltips/Preview.lua): { key = true while it holds the detail key,
-- plus the made-up data each provider shows }. Providers read it in place of the real queue and alts.
Tips.preview = nil

---------------------------------------------------------------------------
-- Shared pieces
---------------------------------------------------------------------------
local KEYS = {
    shift = { down = IsShiftKeyDown, label = "Shift", LSHIFT = true, RSHIFT = true },
    ctrl = { down = IsControlKeyDown, label = "Ctrl", LCTRL = true, RCTRL = true },
    alt = { down = IsAltKeyDown, label = "Alt", LALT = true, RALT = true },
}
Tips.KEY_ORDER = { "shift", "ctrl", "alt" }

function Tips:KeyName(key) return L[KEYS[key or FP.db.tipDetailKey].label] end

-- Whether the detail key is held (or, in the previewer, its Hold box ticked).
function Tips:DetailDown()
    if self.preview then return self.preview.key end
    return KEYS[FP.db.tipDetailKey].down() and true or false
end

-- `level` steps of indent.
function Tips:Indent(level) return (" "):rep(FP.db.tipIndent * (level or 1)) end

-- The blank line before a block, unless spacing is off.
function Tips:Space(tip)
    if FP.db.tipSpacing then tip:AddLine(" ") end
end

-- The blocks in their chosen order: { "queue", "disenchant", "alts" }.
function Tips:Order()
    local order = {}
    for key in FP.db.tipOrder:gmatch("[^,]+") do order[#order + 1] = key end
    return order
end

function Tips:SetOrder(order) FP.db.tipOrder = table.concat(order, ",") end

local function Rank(key)
    for i, k in ipairs(Tips:Order()) do
        if k == key then return i end
    end
    return 99
end

---------------------------------------------------------------------------
-- Providers
---------------------------------------------------------------------------

-- `add(tip, data, itemID)` adds its lines; it returns true when it added any, and as a second value true when it
-- holds back detail the detail key would show. `block` names it for the order (queue, disenchant).
-- `changed()`, if given, drops what the provider worked out, when the queue, shopping list, bags or plan change.
function Tips:Register(block, add, changed)
    providers[#providers + 1] = { block = block, add = add, changed = changed }
end

-- Set by the last item tooltip drawn: whether a provider held back detail. A window's own tooltip reads it after
-- SetItemByID, to put the key in its own hint line.
Tips.hidden = false

-- "Hold Shift for details", gray.
function Tips:AddKeyHint(tip)
    tip:AddLine(L["Hold %s for details"]:format(self:KeyName()), 0.5, 0.5, 0.5)
end

local function Run(tip, data)
    Tips.hidden = false
    local preview = Tips.preview
    if (tip ~= GameTooltip and tip ~= ItemRefTooltip and not preview) or tip:IsForbidden() then return end
    local itemID = data and data.id
    -- Checked before anything tests the id: even its truth test errors while it is secret.
    if issecretvalue(itemID) then return end
    if not itemID then return end
    table.sort(providers, function(a, b) return Rank(a.block) < Rank(b.block) end)
    local added, hidden
    for _, p in ipairs(providers) do
        local a, h = p.add(tip, data, itemID)
        added, hidden = added or a, hidden or h
    end
    Tips.hidden = hidden and true or false
    -- A window that writes its own hint line (owner.ownHints) adds the key there.
    local owner = tip:GetOwner()
    if hidden and FP.db.tipKeyHint and not (owner and owner.ownHints) then
        Tips:AddKeyHint(tip)
        added = true
    end
    if added then tip:Show() end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Run)

---------------------------------------------------------------------------
-- Redrawing
---------------------------------------------------------------------------
Tips.onRefresh = {} -- functions run after each redraw (the previewer follows the detail key)

-- One of the addon's own frames: each window is named ProfessionsForever..., and its rows sit inside it.
local function Ours(frame)
    while frame do
        local name = frame:GetName()
        if name and name:find("^ProfessionsForever") then return true end
        frame = frame:GetParent()
    end
end

-- Redraws the item tooltip under the mouse, if one is showing. RefreshData redraws what the game and the addons'
-- post-calls put on it, so a tooltip of the addon's own (a shopping list row: auction price, alts, click hints after
-- the item) would lose the lines it added itself; its frame's OnEnter draws it again whole instead.
local function Refresh()
    for _, f in ipairs(Tips.onRefresh) do f() end
    if not GameTooltip:IsShown() or GameTooltip:IsForbidden() then return end
    local itemID = select(3, GameTooltip:GetItem())
    if issecretvalue(itemID) then return end
    if not itemID then return end
    local owner = GameTooltip:GetOwner()
    if owner and Ours(owner) then
        local onEnter = owner:GetScript("OnEnter")
        if onEnter then onEnter(owner) end
        return
    end
    GameTooltip:RefreshData()
end

-- From FP:Changed (UI/Redraw.lua), at most once a frame: providers start over, and an item tooltip already showing
-- is redrawn so its numbers follow (looting the reagent under the mouse).
function Tips:Changed()
    for _, p in ipairs(providers) do
        if p.changed then p.changed() end
    end
    Refresh()
end

-- The detail key shows, hides or expands lines: redraw as it goes down or up.
FP:RegisterEvent("MODIFIER_STATE_CHANGED", function(_, key)
    if KEYS[FP.db.tipDetailKey][key] then Refresh() end
end)
