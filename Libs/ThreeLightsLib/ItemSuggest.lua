--[[
ThreeLightsLib: item name suggestions under a text box (UI:ItemSuggest), from the addon's item list.

The list is ns.ItemNames, written by tools/gen_items.py (Data/Items.lua) with the items the addon's filter in
tools/project.json keeps: one string, a line per item, "Name<tab>item ID<tab>quality", sorted by name. It is searched
in place rather than as a table per item, so it costs about the size of the file and each lookup is a plain find.
Without the list only the caller's own items (opts.first) are offered.

Two ways to offer them: the default, UI:Suggest's list under the box (Enter takes the highlighted item), or with
opts.complete, UI:AttachCompletion's list and grey text (Tab takes it, Enter is the caller's; ProfessionsForever's).
]]
local _, ns = ...
local UI = ns.UI

local MIN_CHARS, MOST = 2, 8
-- How long completion waits after the last keystroke before searching, so typing never waits on it.
local DELAY = 0.12

local names, lower

local function Load()
    if lower then return end
    names = ns.ItemNames or "\n"
    lower = strlower(names)  -- same length as `names`, so positions in one are positions in the other
end

local function Label(name, quality)
    local hex = quality and select(4, C_Item.GetItemQualityColor(quality))
    return hex and ("|c" .. hex .. name .. "|r") or name
end

-- Items whose names contain `typed` (lowercase), those starting with it first, each group in the list's alphabetical
-- order. Adds to `out` until it holds MOST, skipping IDs in `seen` and those `filter` refuses.
local function Search(typed, out, seen, filter)
    Load()
    local within = {}
    local function Add(group, from, to)
        local name, id, quality = strmatch(strsub(names, from, to), "^(.-)\t(%d+)\t(%d+)$")
        id = tonumber(id)
        if name and not seen[id] and (not filter or filter(id)) then
            seen[id] = true
            group[#group + 1] = { label = Label(name, tonumber(quality)), value = name, item = id }
        end
    end

    local key, at = "\n" .. typed, 1
    while #out < MOST do
        at = strfind(lower, key, at, true)
        if not at then break end
        local lineEnd = strfind(names, "\n", at + 1, true)
        Add(out, at + 1, lineEnd - 1)
        at = lineEnd
    end

    at = 1
    while #out + #within < MOST do
        at = strfind(lower, typed, at, true)
        if not at then break end
        local back = at > 100 and at - 100 or 1
        local newline = strfind(strsub(lower, back, at - 1), "\n[^\n]*$")
        local lineStart = newline and back + newline or back
        local tab = strfind(names, "\t", lineStart, true)
        local lineEnd = strfind(names, "\n", at, true)
        -- A hit at the start of a name was found above; one after the tab is part of the ID or quality.
        if at > lineStart and at < tab then Add(within, lineStart, lineEnd - 1) end
        at = lineEnd
    end
    for _, m in ipairs(within) do out[#out + 1] = m end
end

-- The matches for what's typed: { { label, value = name, item = itemID }, ... }, the caller's own first.
local function Matches(text, opts)
    local typed = strlower(strtrim(text))
    if #typed < MIN_CHARS or strfind(typed, "[\t\n|]") then return {} end
    local out, seen = {}, {}
    for _, it in ipairs(opts.first and opts.first(typed) or {}) do
        if #out >= MOST then break end
        if not seen[it.item] then
            seen[it.item] = true
            local label = Label(it.name, it.quality)
            if it.note then label = label .. "  " .. UI.Color("dim", it.note) end
            out[#out + 1] = { label = label, value = it.name, item = it.item }
        end
    end
    Search(typed, out, seen, opts.filter)
    return out
end

-- The item ID for an exact name in the item list, or nil.
local function ExactID(text)
    local typed = strlower(strtrim(text))
    if typed == "" or strfind(typed, "[\t\n]") then return end
    Load()
    local at = strfind(lower, "\n" .. typed .. "\t", 1, true)
    if at then return tonumber(strmatch(names, "^\t(%d+)\t", at + #typed + 1)) end
end

-- The completion form (opts.complete): the controller gets :Resolve, :Selected and :IconSlot.
local function Complete(eb, onPick, opts)
    local c, byName, token, last = {}, {}, 0, nil
    local function Names(text)
        wipe(byName)
        local list = {}
        for i, m in ipairs(Matches(text, opts)) do
            byName[m.value] = m
            list[i] = m.value
        end
        return list
    end
    local completion = UI:AttachCompletion(eb, Names, opts.up, onPick and function(name)
        local m = byName[name]
        onPick(m and m.item or ExactID(name), name)
    end, function(name) return byName[name] and byName[name].label or name end)

    -- The item for what was typed: an exact name, then an ID, link or name the client knows, then the first match.
    function c:Resolve(text)
        local id = ExactID(text)
        if id then return id end
        id = C_Item.GetItemInfoInstant(text)
        if id then return id end
        local first = Matches(text, opts)[1]
        return first and first.item or nil
    end

    -- The name picked with the arrow keys, if any: Enter is the caller's, so it asks.
    function c:Selected() return completion:Selected() end

    -- The box fires OnTextChanged repeatedly with the same text, which would hide the grey text over and over.
    eb:HookScript("OnTextChanged", function(box)
        local text = box:GetText()
        if text == last then return end
        last = text
        completion:Clear()
        token = token + 1
        local mine = token
        C_Timer.After(DELAY, function() if token == mine then completion:Update() end end)
    end)

    -- A square slot showing the icon of the item :Resolve gives for the box's text (empty while there is none), with
    -- that item's tooltip, or hint while empty. The caller places it, usually in front of the box.
    function c:IconSlot(size, hint)
        local slot = CreateFrame("Button", nil, eb:GetParent(), "BackdropTemplate")
        slot:SetSize(size, size)
        slot:SetBackdrop({ bgFile = UI.WHITE, edgeFile = UI.WHITE, edgeSize = 1 })
        slot:SetBackdropColor(0, 0, 0, 0.5)
        slot:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetPoint("TOPLEFT", 1, -1)
        slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        slot:SetScript("OnEnter", function(b)
            if not (b.itemID or hint) then return end
            GameTooltip:SetOwner(b, "ANCHOR_TOP")
            if b.itemID then GameTooltip:SetItemByID(b.itemID) else GameTooltip:AddLine(hint, 1, 1, 1) end
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        eb:HookScript("OnTextChanged", function(box)
            local text = strtrim(box:GetText())
            local id = text ~= "" and c:Resolve(text) or nil
            slot.itemID = id
            slot.icon:SetTexture(id and select(5, C_Item.GetItemInfoInstant(id)) or nil)
        end)
        return slot
    end
    return c
end

---------------------------------------------------------------------------
-- Suggests items by name for edit box `eb` as the player types, each in its quality's color. onPick(itemID, name)
-- runs when one is picked with a click (and, without opts.complete, with Enter). opts (optional):
--   filter(itemID)   true for the items that may be offered
--   first(typed)     the caller's own items to list before the item list's, for `typed` (lowercase):
--                    { { item = itemID, name = name, quality = quality or nil, note = text or nil }, ... }
--   complete         grey text finishing the first match, Tab to take it, and Enter left to the box's own script.
--                    The controller then has :Resolve(text) (the item ID for what was typed, or nil), :Selected()
--                    (the name picked with the arrow keys, or nil) and :IconSlot(size, hint) (see Complete above).
--   up               with complete, the list opens above the box
-- Returns a controller: without complete, UI:Suggest's, with :Hide().
---------------------------------------------------------------------------
function UI:ItemSuggest(eb, onPick, opts)
    opts = opts or {}
    if opts.complete then return Complete(eb, onPick, opts) end
    return UI:Suggest(eb, function(text) return Matches(text, opts) end, function(m) onPick(m.item, m.value) end)
end
