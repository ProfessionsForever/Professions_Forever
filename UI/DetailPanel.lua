local _, FP = ...
local L = FP.L
local UI = FP.UI
local CARD_H, TILE_W, TILE_H, TILE_GAP = UI.CARD_H, UI.TILE_W, UI.TILE_H, UI.TILE_GAP
local PreviewLink, FillCostTip, FillProfitTip = UI.PreviewLink, UI.FillCostTip, UI.FillProfitTip

-- Building the recipe panel: its header, tiles, reagent area and action buttons. UI/Detail.lua fills it.

local function SelectedRecipe()
    return FP.selected and FP.Recipes.byID[FP.selected]
end

-- How many crafts the panel's quantity box asks for, 1 to 999.
function UI:GetCount()
    local n = tonumber(self.frame and self.frame.detail.qty:GetText()) or 1
    return math.max(1, math.min(999, math.floor(n)))
end

-- Right panel: the selected recipe's details.
function UI:CreateDetailPanel(f)
    local left = f.left
    local right = CreateFrame("Frame", "ProfessionsForeverDetailPanel", f, "BackdropTemplate")
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", -8, 8 + UI:FooterReserve())
    self:Skin(right, "panel")
    f.right = right
    local d = {}
    f.detail = d
    d.hint = self:Text(right, 1, "CENTER")
    d.hint:SetPoint("CENTER")
    d.content = CreateFrame("Frame", nil, right)
    d.content:SetAllPoints()
    local c = d.content
    self:CreateDetailHeader(d, c)
    self:CreateReagentCards(d, c)
    self:CreateDetailActions(d, c)
end

-- Icon, craftable-count tiles, favorite star, name, source line and description.
function UI:CreateDetailHeader(d, c)
    d.icon = c:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(40, 40)
    d.icon:SetPoint("TOPLEFT", 12, -12)
    d.iconHit = CreateFrame("Frame", nil, c)
    d.iconHit:SetAllPoints(d.icon)
    d.iconHit:SetFrameLevel(c:GetFrameLevel() + 2)
    d.iconHit:EnableMouse(true)
    -- How many items one craft makes ("2", or "2-4" for a range), in the icon's corner as in Blizzard's window.
    d.iconCount = self:Text(d.iconHit, 1, "RIGHT")
    d.iconCount:SetPoint("BOTTOMRIGHT", d.icon, "BOTTOMRIGHT", -2, 2)
    d.iconHit:SetScript("OnEnter", function(s)
        local recipe = SelectedRecipe()
        if not recipe then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        local output = FP.Recipes:OutputInfo(recipe.id)
        if output and output.hyperlink then GameTooltip:SetHyperlink(output.hyperlink)
        elseif output and output.itemID then GameTooltip:SetItemByID(output.itemID)
        else GameTooltip:AddLine(recipe.name, 1, 1, 1) end
        GameTooltip:AddLine(recipe.name, 1, 0.82, 0)
        if PreviewLink(recipe.id) then GameTooltip:AddLine(L["Ctrl-click: preview"], 0.5, 0.8, 1) end
        GameTooltip:Show()
        UI:ShowTooltipIcon(recipe.icon)
    end)
    d.iconHit:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or not FP.selected then return end
        local output = FP.Recipes:OutputInfo(FP.selected)
        if UI.LinkOrTrack(output and output.hyperlink or C_TradeSkillUI.GetRecipeLink(FP.selected), SelectedRecipe()) then return end
        if IsControlKeyDown() then UI.PreviewRecipe(FP.selected) end
    end)
    d.iconHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Craftable-count tiles, top right: how many crafts the bags alone / bags plus bank / the other characters' stock can cover.
    local function Tile(label, tipText)
        local t = CreateFrame("Frame", nil, c, "BackdropTemplate")
        t:SetSize(TILE_W, TILE_H)
        self:Skin(t, "button")
        t:EnableMouse(true)
        t.num = self:Text(t, 1, "CENTER")
        t.num:SetPoint("TOP", 0, -5)
        t.label = self:Text(t, -3, "CENTER")
        t.label:SetPoint("BOTTOM", 0, 2)
        t.label:SetText(label)
        t.label:SetTextColor(0.7, 0.7, 0.7)
        self:Tooltip(t, function(tip, s)
            if type(tipText) == "function" then return tipText(tip, s) end
            tip:AddLine(tipText, 1, 1, 1, true)
            if s.isBank and FP.chardb.bankTime then
                tip:AddLine(L["Bank contents last scanned %s"]:format(date("%Y-%m-%d %H:%M", FP.chardb.bankTime)), 0.6, 0.6, 0.6)
            end
            if s.isBank and FP.Waypoint:NavAvailable() then
                tip:AddLine(L["Right-click: waypoint to the nearest banker"], 0.5, 0.8, 1)
            end
        end, "ANCHOR_BOTTOM")
        return t
    end
    d.statBank = Tile(L["From Bank"], L["Extra crafts using materials in your bank."])
    d.statAlts = Tile(L["From Alts"], function(tip, s) UI:FillAltTileTip(tip, s.ev) end)
    d.statAlts:SetPoint("TOPRIGHT", -12, -12)
    d.statBank.isBank = true
    d.statBank:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and FP.Waypoint:NavAvailable() then FP.Waypoint:NearestBanker() end
    end)
    d.statBank:SetPoint("RIGHT", d.statAlts, "LEFT", -TILE_GAP, 0)
    d.statBags = Tile(L["From Bags"], L["Crafts you can make with materials in your bags."])
    d.statBags:SetPoint("RIGHT", d.statBank, "LEFT", -TILE_GAP, 0)
    d.tiles = { d.statBags, d.statBank, d.statAlts }

    -- Favorite toggle; UpdateDetail places it just after the recipe name.
    d.fav = CreateFrame("Button", nil, c)
    d.fav:SetSize(18, 18)
    d.fav:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 8, -2)
    d.fav.star = d.fav:CreateTexture(nil, "ARTWORK")
    d.fav.star:SetAllPoints()
    d.fav.star:SetTexture("Interface\\Common\\ReputationStar")
    d.fav.star:SetTexCoord(0, 0.5, 0, 0.5)
    d.fav:SetScript("OnClick", function()
        local recipe = SelectedRecipe()
        if not recipe then return end
        FP.Recipes:SetFavorite(recipe.id, not recipe.favorite)
        UI:RefreshFilter()
        UI:UpdateList()
        UI:UpdateDetail()
    end)
    self:Tooltip(d.fav, function(tip)
        local recipe = SelectedRecipe()
        tip:AddLine(recipe and recipe.favorite and L["Remove from Favorites"] or L["Set as Favorite"], 1, 1, 1)
    end, "ANCHOR_BOTTOM")

    -- New or changed in Forever; UpdateDetail places it between the recipe name and the favorite star.
    d.forever = CreateFrame("Frame", nil, c)
    d.forever:EnableMouse(true)
    d.forever.icon = d.forever:CreateTexture(nil, "ARTWORK")
    d.forever.icon:SetAllPoints()
    self:Tooltip(d.forever, function(tip)
        tip:AddLine(UI.ForeverTagText(SelectedRecipe().id), 0.5, 0.8, 1)
    end, "ANCHOR_BOTTOM")

    d.name = self:Text(c, 4)
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 8, -2)
    d.name:SetWordWrap(true)
    d.name:SetMaxLines(2)
    d.sub = self:Text(c, -1)
    d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
    d.sub:SetPoint("RIGHT", d.statBags, "LEFT", -8, 0)
    d.sub:SetWordWrap(false)

    -- Where the recipe is learned from (a learned one too with the Tooltips option on); hover for the details.
    d.source = self:Text(c, -1)
    d.source:SetPoint("TOPLEFT", d.sub, "BOTTOMLEFT", 0, -2)
    d.source:SetPoint("RIGHT", d.sub, "RIGHT", 0, 0)
    d.source:SetJustifyH("LEFT")
    d.source:SetWordWrap(false)
    d.sourceHit = CreateFrame("Frame", nil, c)
    d.sourceHit:SetAllPoints(d.source)
    d.sourceHit:SetFrameLevel(c:GetFrameLevel() + 2)
    d.sourceHit:EnableMouse(true)
    self:Tooltip(d.sourceHit, function()
        local recipe = SelectedRecipe()
        if not (recipe and UI.ShowsSource(recipe)) then return false end
        UI.AddSourceLines(recipe.id, recipe.learned)
    end)

    -- Tools the recipe needs, colored by where they are.
    d.tools = self:Text(c, -1)
    d.tools:SetPoint("TOPLEFT", d.source, "BOTTOMLEFT", 0, -2)
    d.tools:SetPoint("RIGHT", d.sub, "RIGHT", 0, 0)
    d.tools:SetJustifyH("LEFT")
    d.tools:SetWordWrap(true)
    d.tools:SetMaxLines(2)

    -- Recipe cooldown, above the description.
    d.cooldown = self:Text(c, 0)
    d.cooldown:SetPoint("TOPLEFT", d.tools, "BOTTOMLEFT", 0, -4)
    d.cooldown:SetPoint("RIGHT", d.sub, "RIGHT", 0, 0)
    d.cooldown:SetJustifyH("LEFT")
    d.cooldown:SetWordWrap(false)

    -- What the craft makes or does ("Craft a ...", the enchant's effect), as in Blizzard's window.
    d.desc = self:Text(c, 0)
    d.desc:SetPoint("TOPLEFT", d.cooldown, "BOTTOMLEFT", 0, -6)
    d.desc:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    d.desc:SetJustifyH("LEFT")
    d.desc:SetJustifyV("TOP")
    d.desc:SetWordWrap(true)
    d.desc:SetMaxLines(2)
    d.desc:SetTextColor(1, 1, 1)
end

-- Banner, requirements, cost, quantity, craft buttons and the enchant target.
function UI:CreateDetailActions(d, c)
    d.banner = self:Text(c, 1)
    d.cost = self:Text(c, -1)
    d.cost:SetPoint("BOTTOMLEFT", 12, 116)
    d.cost:SetPoint("RIGHT", -12, 0)
    d.cost:SetWordWrap(false)
    d.cost:SetTextColor(0.75, 0.75, 0.75)
    d.costHit = CreateFrame("Frame", nil, c)
    d.costHit:SetAllPoints(d.cost)
    d.costHit:EnableMouse(true)
    self:Tooltip(d.costHit, function(tip)
        if not d.costInfo then return false end
        FillCostTip(tip, d.costInfo)
    end, "ANCHOR_TOP")
    d.profit = self:Text(c, -1)
    d.profit:SetPoint("BOTTOMLEFT", 12, 100)
    d.profit:SetPoint("RIGHT", -12, 0)
    d.profit:SetWordWrap(false)
    d.profitHit = CreateFrame("Frame", nil, c)
    d.profitHit:SetAllPoints(d.profit)
    d.profitHit:EnableMouse(true)
    self:Tooltip(d.profitHit, function(tip)
        if not d.profitInfo then return false end
        FillProfitTip(tip, d.profitInfo)
    end, "ANCHOR_TOP")
    d.banner:SetPoint("BOTTOMLEFT", 12, 80)
    d.banner:SetPoint("RIGHT", -12, 0)

    local ql = self:Text(c, 0)
    d.qtyLabel = ql
    ql:SetPoint("BOTTOMLEFT", 12, 18)
    ql:SetText(L["Qty:"])
    -- Unnamed, like the addon's other boxes: Auctionator skips its Shift-click search while a named box has the focus.
    d.qty = CreateFrame("EditBox", nil, c, "InputBoxTemplate")
    d.qty:SetSize(36, 20)
    d.qty:SetPoint("LEFT", ql, "RIGHT", 34, 0)
    self:EUIWidget(d.qty, "numbox")
    d.qty:SetAutoFocus(false)
    d.qty:SetNumeric(true)
    d.qty:SetMaxLetters(3)
    d.qty:SetText("1")
    d.qty:SetScript("OnTextChanged", function() UI:UpdateDetail() end)
    d.qty:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    d.qty:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    self:Stepper(d.qty, 1, 999)

    d.craft = self:Button(c, L["Craft"], 90, 24, function() UI.DoCraft(UI:GetCount()) end)
    d.craft:SetPoint("LEFT", d.qty.plus, "RIGHT", 12, 0)
    d.craftAll = self:Button(c, L["Craft All"], 90, 24, function() UI.DoCraft(math.huge) end)
    d.craftAll:SetPoint("LEFT", d.craft, "RIGHT", 6, 0)
    -- Enchanting applies one enchant to the chosen item, so it replaces the craft buttons; the quantity is for Queue.
    d.enchantBtn = self:Button(c, L["Enchant"], 120, 24, function() UI.DoCraft(1) end)
    d.enchantBtn:SetPoint("LEFT", d.qty.plus, "RIGHT", 12, 0)
    d.enchantBtn:Hide()
    -- In their place for another player's or character's profession: why it can't be crafted here.
    d.readOnly = self:Text(c, 0)
    d.readOnly:SetPoint("BOTTOMLEFT", 12, 23)
    d.readOnly:SetPoint("RIGHT", -12, 0)
    d.readOnly:SetJustifyH("LEFT")
    d.readOnly:SetWordWrap(false)
    d.readOnly:SetTextColor(0.75, 0.75, 0.75)
    d.readOnly:Hide()
    for _, b in ipairs({ d.craft, d.craftAll, d.enchantBtn }) do
        self:Tooltip(b, function(tip)
            if not d.craftBlock then return false end
            tip:AddLine(d.craftBlock, 1, 0.3, 0.3, true)
        end, "ANCHOR_TOP")
    end
    -- Queueing opens the queue, and the transfer planner too when other characters hold materials it needs.
    local function Queue(add)
        FP.Queue:Open()
        add()
        FP.Queue:OpenTransferIfNeeded()
    end
    -- Queueing puts what the recipe is short of on the shopping list (Core/Shopping.lua); the banner opens the list.
    d.bannerBtn = CreateFrame("Button", nil, c)
    d.bannerBtn:SetAllPoints(d.banner)
    d.bannerBtn:SetScript("OnClick", function() FP.Shop:Open() end)
    -- The selected recipe, `count` crafts, into the queue: that character's while viewing another character's profession.
    local function AddSelected(count)
        local viewing = FP.AltProfs.viewing
        if viewing then
            FP.Queue:AddFor(viewing.key, FP.selected, viewing.skillLine, count)
        else
            Queue(function() FP.Queue:AddWithPrerequisites(FP.selected, count) end)
        end
    end
    d.addQueue = self:Button(c, L["Queue"], 80, 24, function()
        if not FP.selected then return end
        AddSelected(UI:GetCount())
        d.qty:SetText("1")
    end)
    d.addQueue:SetPoint("BOTTOMLEFT", 12, 46)
    self:Tooltip(d.addQueue, function(tip)
        local e = SelectedRecipe()
        if not e then return false end
        local enchant = FP.Recipes:IsEnchant(e.id)
        if e.learned and not enchant then return false end
        if not e.learned then
            tip:AddLine(L["Not Learned"], 1, 0.3, 0.3)
            tip:AddLine(L["You can queue it to plan and shop for its materials. The queue skips it until it is learned."], 0.8, 0.8, 0.8, true)
        end
        if enchant then
            tip:AddLine(L["Enchant"], 1, 1, 1)
            tip:AddLine(L["The queue plans and shops for this enchant's materials. Apply it with the Enchant button: each one applied comes off the queue."], 0.8, 0.8, 0.8, true)
        end
    end, "ANCHOR_TOP")
    -- Shop for Reagents takes Queue's place where a recipe can't be queued: one the character whose profession this is
    -- hasn't learned, or another player's. It adds the reagents for the quantity's crafts to the shopping list as items
    -- you added; the list itself takes off what your characters already hold.
    d.shop = self:Button(c, L["Shop for Reagents"], 130, 24, function()
        local reagents = d.shopReagents
        if not reagents then return end
        for _, r in ipairs(reagents) do FP.Shop:Add(r.itemID, r.need) end
        FP.Shop:Open()
        FP:Print(L["Added %d item(s) to the shopping list."]:format(#reagents))
        d.qty:SetText("1")
    end)
    d.shop:SetPoint("BOTTOMLEFT", 12, 46)
    self:Tooltip(d.shop, function(tip)
        local reagents = d.shopReagents
        if not reagents then return false end
        tip:AddLine(L["Shop for Reagents"], 1, 1, 1)
        if d.shopFor then
            tip:AddLine(L["%s hasn't learned this recipe, so it can't be queued for them."]:format(d.shopFor), 1, 0.3, 0.3, true)
        else
            tip:AddLine(L["Another player's recipe can't be queued."], 1, 0.3, 0.3, true)
        end
        tip:AddLine(L["Adds its reagents for the number of crafts in Qty to your shopping list:"], 0.8, 0.8, 0.8, true)
        for _, r in ipairs(reagents) do
            tip:AddDoubleLine(FP.ItemName(r.itemID), r.need, 1, 1, 1, 1, 1, 1)
        end
        tip:AddLine(L["The list counts what you and your other characters already hold, and shows only what is still to buy."],
            0.8, 0.8, 0.8, true)
        tip:AddLine(L["They stay on the list until you remove them, even if you learn the recipe or change your mind."],
            0.6, 0.6, 0.6, true)
    end, "ANCHOR_TOP")
    d.queueAll = self:Button(c, L["Queue All"], 80, 24, function()
        if FP.selected and d.queueAllCount > 0 then Queue(function() FP.Queue:Add(FP.selected, d.queueAllCount) end) end
    end)
    d.queueAll:SetPoint("LEFT", d.addQueue, "RIGHT", 6, 0)
    d.queueAllCount = 0
    self:Tooltip(d.queueAll, L["Queues as many crafts as your bags can supply."], "ANCHOR_TOP")

    -- Queue Needed: queues the crafts that make what the queues still need of this recipe's item (the shopping list's
    -- queue part, net of what other queues make), so 441 Bronze Bar queues 221 Smelt Bronze, not 441.
    d.forQueues = self:Button(c, L["Queue Needed (%d)"], 80, 24, function()
        if FP.selected and d.forQueuesInfo then AddSelected(math.min(999, d.forQueuesInfo.crafts)) end
    end)
    self:Tooltip(d.forQueues, function(tip)
        local info = d.forQueuesInfo
        if not info then return false end
        tip:AddLine(L["Queue Needed (%d)"]:format(info.crafts), 1, 1, 1)
        tip:AddLine(L["Queues the crafts your crafting queues still need."], 0.8, 0.8, 0.8, true)
        tip:AddLine(L["Still needed: %d %s. One craft makes %d."]:format(info.need, FP.ItemName(info.itemID), info.yield),
            0.8, 0.8, 0.8, true)
        FP.Tooltips:AddQueueRecipeLines(tip, info.itemID)
    end, "ANCHOR_TOP")
    d.forQueues:Hide()

    d.track = self:Button(c, L["Track"], 80, 24, function()
        local e = SelectedRecipe()
        if e then UI.TrackRecipe(e) end
    end)
    d.track:SetPoint("LEFT", d.queueAll, "RIGHT", 6, 0)
    self:Tooltip(d.track, function(tip)
        local e = SelectedRecipe()
        if not e or e.learned then return false end
        tip:AddLine(L["Set a waypoint to where this recipe is learned"], 1, 1, 1)
        if not FP.Waypoint:NavAvailable() then tip:AddLine(L["Polestar or TomTom is needed for waypoints."], 0.6, 0.6, 0.6, true) end
    end, "ANCHOR_TOP")
    self:CreateEnchantTarget(d, c)

    -- Search: Auctionator's own button on Blizzard's profession window, which this window replaces. While the auction
    -- house is open it fills Auctionator's Shopping tab with what the recipe makes and each of its reagents.
    d.search = self:Button(c, L["Search"], 80, 24, function() UI.SearchReagents(FP.selected, UI:GetCount()) end)
    d.search:SetPoint("BOTTOMRIGHT", -12, 18)
    self:Tooltip(d.search, function(tip)
        tip:AddLine(L["Search the Auction House"], 1, 1, 1)
        tip:AddLine(L["Searches Auctionator's Shopping tab for what this recipe makes and each of its reagents, with how many the crafts in Qty use."], 0.8, 0.8, 0.8, true)
    end, "ANCHOR_TOP")
    d.search:Hide()
end

local function AuctionHouseOpen() return AuctionHouseFrame and AuctionHouseFrame:IsShown() end

-- Shown while the auction house is open, Auctionator is loaded, the option is on and the recipe has reagents.
function UI:UpdateSearchButton()
    local d = self.frame and self.frame.detail
    if not d then return end
    local A = _G.Auctionator
    local shown = FP.db.ahSearchButton and AuctionHouseOpen() and A and A.API and A.API.v1 and FP.selected
        and #FP.Recipes:GetReagents(FP.selected) > 0 and true or false
    d.search:SetShown(shown)
    -- Why another character's recipe can't be crafted here: the line along the bottom stops short of the button.
    if shown then d.readOnly:SetPoint("RIGHT", d.search, "LEFT", -8, 0) else d.readOnly:SetPoint("RIGHT", d.content, "RIGHT", -12, 0) end
end
FP:RegisterEvent("AUCTION_HOUSE_SHOW", function() UI:UpdateSearchButton() end)
FP:RegisterEvent("AUCTION_HOUSE_CLOSED", function() UI:UpdateSearchButton() end)

-- Searches Auctionator's Shopping tab the way Auctionator's own button on Blizzard's window does: what the recipe
-- makes, exact and any quantity (an enchant's scroll from Auctionator's own table; a recipe with neither, its name),
-- then each reagent exact with how many `count` crafts use (shown on the search as "x10"). Bound items are left out,
-- since they can't be bought. Runs once the game has loaded the items.
local UNBOUND = { [0] = true, [2] = true, [3] = true } -- no binding, binds when equipped, binds when used
function UI.SearchReagents(recipeID, count)
    if not (recipeID and AuctionHouseOpen()) then return end
    local terms, ids, quantities = {}, {}, {}
    local enchants = Auctionator.CraftingInfo and Auctionator.CraftingInfo.EnchantSpellsToItems
    local made = FP.Recipes:OutputItemID(recipeID) or (enchants and enchants[recipeID] and enchants[recipeID][1])
    if made then
        ids[1], quantities[1] = made, 0
    else
        local e = FP.Recipes.byID[recipeID]
        if e then terms[1] = { searchString = e.name } end
    end
    for _, r in ipairs(FP.Recipes:GetReagents(recipeID)) do
        ids[#ids + 1], quantities[#quantities + 1] = r.itemID, r.qty * count
    end
    local items = ContinuableContainer:Create()
    for _, id in ipairs(ids) do items:AddContinuable(Item:CreateFromItemID(id)) end
    items:ContinueOnLoad(function()
        if not AuctionHouseOpen() then return end
        for i, id in ipairs(ids) do
            local name, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(id)
            if name and UNBOUND[bindType] then
                terms[#terms + 1] = { searchString = name, isExact = true, quantity = quantities[i] }
            end
        end
        Auctionator.API.v1.MultiSearchAdvanced("ProfessionsForever", terms)
    end)
end

-- The enchant target picker, shown only for enchants.
function UI:CreateEnchantTarget(d, c)
    -- Enchanting: the item to enchant, a square the height of a reagent card above the cost line, text to its right.
    d.target = CreateFrame("Button", nil, c, "BackdropTemplate")
    d.target:SetSize(CARD_H, CARD_H)
    d.target:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 12, 156)
    self:Skin(d.target, "button")
    d.target.icon = d.target:CreateTexture(nil, "ARTWORK")
    d.target.icon:SetPoint("TOPLEFT", 3, -3)
    d.target.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    UI.TrimIcon(d.target.icon)
    d.target.plus = self:Text(d.target, 8, "CENTER")
    d.target.plus:SetPoint("CENTER")
    d.target.plus:SetText("+")
    d.target.plus:SetTextColor(0.22, 1, 0.08)
    d.target.hl = d.target:CreateTexture(nil, "HIGHLIGHT")
    d.target.hl:SetAllPoints()
    d.target.hl:SetColorTexture(1, 1, 1, 0.1)
    d.targetTitle = self:Text(c, -1)
    d.targetTitle:SetPoint("TOPLEFT", d.target, "TOPRIGHT", 10, -2)
    d.targetTitle:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    d.targetTitle:SetJustifyH("LEFT")
    d.targetTitle:SetTextColor(1, 0.82, 0)
    d.targetTitle:SetText(L["Enchant Target"])
    d.targetName = self:Text(c, 0)
    d.targetName:SetPoint("BOTTOMLEFT", d.target, "BOTTOMRIGHT", 10, 2)
    d.targetName:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    d.targetName:SetJustifyH("LEFT")
    d.targetName:SetWordWrap(false)
    d.target:SetScript("OnClick", function(s) UI:OpenMenu(s, UI.TargetMenu(), 300) end)
    self:Tooltip(d.target, function(tip)
        local guid = UI.craftTarget and UI.craftTarget:GetItemGUID()
        if guid then
            tip:SetItemByGUID(guid)
        else
            tip:AddLine(L["Enchant Target"], 1, 1, 1)
            tip:AddLine(L["Click to choose the item to enchant."], 0.6, 0.6, 0.6, true)
        end
    end, "ANCHOR_TOP")
    d.target:Hide()
    d.targetTitle:Hide()
    d.targetName:Hide()
end
