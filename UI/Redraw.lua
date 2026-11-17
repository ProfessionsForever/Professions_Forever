local _, FP = ...
local UI = FP.UI

-- Data says what changed with FP:Changed(what); each visible window that shows it redraws once on the next frame,
-- however many changes land together, instead of every change redrawing the other windows at once.
--   queue: the queue's entries; shop: the shopping list; plan: what alts can supply, or the planning mode;
--   cooldowns: the tracked cooldowns; sends: what this character should mail other characters (Alts/Outgoing.lua),
--   or the mailbox opening or closing; inventory: the bags or the bank, or the bank opening or closing;
--   items: an item's name or icon arrived from the server; prices: Auctionator's prices changed (Core/Prices.lua);
--   camp: a camp item's shared cooldown started or ended (Core/Camp.lua).
local SHOWN_IN = {
    inventory = { "main", "queue", "shop", "transfer", "launcher", "camp", "tooltips" },
    items = { "main", "queue", "shop", "transfer", "camp", "tooltips" },
    camp = { "camp", "footer", "launcher" },
    queue = { "queue", "detail", "footer", "transfer", "launcher", "shop", "tooltips" },
    shop = { "shop", "detail", "footer", "launcher", "tooltips" },
    plan = { "main", "queue", "shop", "transfer", "characters", "launcher", "tooltips" },
    cooldowns = { "cooldowns", "footer", "launcher" },
    sends = { "footer", "transfer", "launcher", "shop", "disenchant" }, -- Disenchanting Mode marks gear asked for
    prices = { "main", "queue", "shop", "disenchant" },
}

-- Two sets taking turns, so a change made while redrawing is kept for the next frame.
local dirty, spare, scheduled = {}, {}, false

local function Flush()
    local d = dirty
    dirty, spare, scheduled = spare, d, false
    if d.main then
        UI:QueueRefresh() -- the main window's full refresh redraws its recipe panel and footer too
    elseif UI.frame and UI.frame:IsShown() then
        if d.detail then UI:UpdateDetail() end
        if d.footer then UI:RefreshFooter() end
    end
    if d.queue then FP.Queue:Update() end
    if d.shop then FP.Shop:Update() end
    if d.transfer then FP.Transfer:QueueUpdate() end
    if d.cooldowns then FP.CooldownPanel:Update() end
    if d.camp then FP.CampPanel:Update() end
    if d.characters then FP.Options:RefreshCharacters() end
    if d.launcher then FP.Launcher:QueueUpdate() end
    if d.tooltips then FP.Tooltips:Changed() end -- Tooltips/Tooltips.lua: the queue needs on item tooltips
    -- Rescanned too, so the list's Best Value sort and Worth Disenchanting Only filter use the new values.
    if d.disenchant then UI:UpdateDisenchantMode(true) end
    wipe(d)
end

function FP:Changed(what)
    for _, part in ipairs(SHOWN_IN[what]) do dirty[part] = true end
    if not scheduled then
        scheduled = true
        C_Timer.After(0, Flush)
    end
end
