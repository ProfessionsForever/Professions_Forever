local _, FP = ...
local Shop = FP.Shop

local DELAY, MIN_CHARS = 0.12, 2

-- Item names the add box can complete: reagents of the open profession's recipes and of the queue.
local function BuildPool()
    local pool, seen = {}, {}
    local function Add(itemID)
        if not itemID or seen[itemID] then return end
        seen[itemID] = true
        local name = C_Item.GetItemNameByID(itemID)
        if name then
            pool[#pool + 1] = { id = itemID, name = name, lower = strlower(name) }
        elseif C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID) -- ready the next time the box is focused
        end
    end
    for _, q in ipairs(FP.Queue:Data()) do
        for _, r in ipairs(q.reagents) do Add(r.itemID) end
    end
    for _, e in ipairs(FP.Recipes.list) do
        for _, r in ipairs(FP.Recipes:GetReagents(e.id)) do Add(r.itemID) end
    end
    table.sort(pool, function(a, b) return a.lower < b.lower end)
    return pool
end

-- Suggests item names for the add box, with a list opening upward. The pool is built once per focus and the match
-- runs shortly after the last keystroke, so typing never waits on it.
-- Returns an object: :Resolve(text) gives the item ID for what was typed, :Selected() the row picked with the arrows.
-- onPick(name) is called when a row is clicked.
function Shop:AttachSuggest(eb, onPick)
    local pool, token = {}, 0
    local s = {}

    -- Names containing the text, those starting with it first (the pool is alphabetical).
    local function Matches(text)
        local typed = strlower(text)
        if #typed < MIN_CHARS then return {} end
        local out, within = {}, {}
        for _, e in ipairs(pool) do
            local at = strfind(e.lower, typed, 1, true)
            if at == 1 then out[#out + 1] = e.name elseif at then within[#within + 1] = e.name end
        end
        for _, name in ipairs(within) do out[#out + 1] = name end
        return out
    end

    -- An exact name, then an ID, link or cached name, then the first suggestion.
    function s:Resolve(text)
        local typed = strlower(text)
        for _, e in ipairs(pool) do
            if e.lower == typed then return e.id end
        end
        local id = C_Item.GetItemInfoInstant(text)
        if id then return id end
        local first = Matches(text)[1]
        for _, e in ipairs(pool) do
            if e.name == first then return e.id end
        end
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
    eb:HookScript("OnEditFocusGained", function() pool = BuildPool() end)
    return s
end
