local _, FP = ...
local Shop = FP.Shop

local DELAY, MIN_CHARS, MAX_MATCHES = 0.12, 2, 40

-- The shopping list's search covers every tradeable item the game has (Data/Items.lua). It is searched in place as
-- one string rather than as a table per item, so it costs about the size of the file and each lookup is a plain find.
local names, lower

local function Load()
    if lower then return end
    names = FP.ItemNames or "\n"
    lower = strlower(names) -- same length as `names`, so positions in one are positions in the other
end

-- Names containing `typed` (lowercase), those starting with it first, each in the list's alphabetical order; the
-- names go in `ids` as well. Stops at MAX_MATCHES.
local function Search(typed, ids)
    Load()
    wipe(ids)
    local out, within = {}, {}
    local function Add(group, from, to)
        local line = strsub(names, from, to)
        local name, id = strmatch(line, "^(.-)\t(%d+)$")
        if name then
            ids[name] = tonumber(id)
            group[#group + 1] = name
        end
    end

    local key, at = "\n" .. typed, 1
    while #out < MAX_MATCHES do
        at = strfind(lower, key, at, true)
        if not at then break end
        local lineEnd = strfind(names, "\n", at + 1, true)
        Add(out, at + 1, lineEnd - 1)
        at = lineEnd
    end

    at = 1
    while #out + #within < MAX_MATCHES do
        at = strfind(lower, typed, at, true)
        if not at then break end
        local back = at > 80 and at - 80 or 1
        local newline = strfind(strsub(lower, back, at - 1), "\n[^\n]*$")
        local lineStart = newline and back + newline or back
        local tab = strfind(names, "\t", lineStart, true)
        local lineEnd = strfind(names, "\n", at, true)
        -- A hit at the start was found above; one after the tab is part of the item ID.
        if at > lineStart and at < tab then Add(within, lineStart, lineEnd - 1) end
        at = lineEnd
    end
    for _, name in ipairs(within) do out[#out + 1] = name end
    return out
end

-- Suggests item names for the add box, with a list opening upward. The match runs shortly after the last keystroke,
-- so typing never waits on it.
-- Returns an object: :Resolve(text) gives the item ID for what was typed, :Selected() the row picked with the arrows.
-- onPick(name) is called when a row is clicked.
function Shop:AttachSuggest(eb, onPick)
    local token = 0
    local s, ids = {}, {}

    local function Matches(text)
        local typed = strlower(text)
        if #typed < MIN_CHARS or strfind(typed, "[\t\n]") then return {} end
        return Search(typed, ids)
    end

    -- An exact name, then an ID, link or cached name, then the first suggestion.
    function s:Resolve(text)
        local typed = strlower(text)
        Load()
        local at = not strfind(typed, "[\t\n]") and strfind(lower, "\n" .. typed .. "\t", 1, true)
        if at then return tonumber(strmatch(names, "^\t(%d+)\n", at + #typed + 1)) end
        local id = C_Item.GetItemInfoInstant(text)
        if id then return id end
        return ids[Matches(text)[1]]
    end

    local completion = FP.UI:AttachCompletion(eb, Matches, true, onPick)
    function s:Selected() return completion:Selected() end

    -- The box fires OnTextChanged repeatedly with the same text, which would hide the grey text over and over.
    local last
    eb:HookScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text == last then return end
        last = text
        completion:Clear()
        token = token + 1
        local mine = token
        C_Timer.After(DELAY, function() if token == mine then completion:Update() end end)
    end)
    return s
end
