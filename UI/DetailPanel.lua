local _, FP = ...
local L = FP.L
local UI = FP.UI
local Skin = UI.ActiveSkin
local CARD_H, TILE_W, TILE_H, TILE_GAP = UI.CARD_H, UI.TILE_W, UI.TILE_H, UI.TILE_GAP
local STATUS_COLORS, ItemName = UI.STATUS_COLORS, UI.ItemName
local PreviewLink, FillCostTip, FillProfitTip = UI.PreviewLink, UI.FillCostTip, UI.FillProfitTip

local BADGE_QUEUE = "Interface\\Icons\\Trade_Engineering"
local BADGE_SHOP = "Interface\\Icons\\INV_Misc_Coin_01"
local BADGE_VENDOR = "Interface\\Icons\\INV_Misc_Map_01"
local BADGE_ALTS = "Interface\\Icons\\INV_Letter_15"

local function SelectedRecipe()
    return FP.selected and FP.Recipes.byID[FP.selected]
end

-- Right panel: the selected recipe's details.
function UI:CreateDetailPanel(f)
    local left = f.left
    local right = CreateFrame("Frame", "ProfessionsForeverDetailPanel", f, "BackdropTemplate")
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", -8, 8 + UI.FOOTER_RESERVE)
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
    d.iconHit:SetScript("OnEnter", function(s)
        local recipe = SelectedRecipe()
        if not recipe then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        local output = UI.RecipeOutputInfo(recipe.id)
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
        local output = UI.RecipeOutputInfo(FP.selected)
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
        t.num:SetPoint("TOP", 0, -2)
        t.label = self:Text(t, -3, "CENTER")
        t.label:SetPoint("BOTTOM", 0, 2)
        t.label:SetText(label)
        t.label:SetTextColor(0.7, 0.7, 0.7)
        self:Tooltip(t, "ANCHOR_BOTTOM", function(tip, s)
            if type(tipText) == "function" then return tipText(tip, s) end
            tip:AddLine(tipText, 1, 1, 1, true)
            if s.isBank and FP.chardb.bankTime then
                tip:AddLine(L["Bank contents last scanned %s"]:format(date("%Y-%m-%d %H:%M", FP.chardb.bankTime)), 0.6, 0.6, 0.6)
            end
            if s.isBank and FP.Waypoint:NavAvailable() then
                tip:AddLine(L["Right-click: waypoint to the nearest banker"], 0.5, 0.8, 1)
            end
        end)
        return t
    end
    d.statBank = Tile(L["From Bank"], L["Extra crafts you can make by also using materials in your bank."])
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
    self:Tooltip(d.fav, "ANCHOR_BOTTOM", function(tip)
        local recipe = SelectedRecipe()
        tip:AddLine(recipe and recipe.favorite and L["Remove from Favorites"] or L["Set as Favorite"], 1, 1, 1)
    end)

    d.name = self:Text(c, 4)
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 8, -2)
    d.name:SetWordWrap(true)
    d.name:SetMaxLines(2)
    d.sub = self:Text(c, -1)
    d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
    d.sub:SetPoint("RIGHT", d.statBags, "LEFT", -8, 0)
    d.sub:SetWordWrap(false)

    -- Where an unlearned recipe is learned from; hover for the details.
    d.source = self:Text(c, -1)
    d.source:SetPoint("TOPLEFT", d.sub, "BOTTOMLEFT", 0, -2)
    d.source:SetPoint("RIGHT", d.sub, "RIGHT", 0, 0)
    d.source:SetJustifyH("LEFT")
    d.source:SetWordWrap(false)
    d.sourceHit = CreateFrame("Frame", nil, c)
    d.sourceHit:SetAllPoints(d.source)
    d.sourceHit:SetFrameLevel(c:GetFrameLevel() + 2)
    d.sourceHit:EnableMouse(true)
    self:Tooltip(d.sourceHit, "ANCHOR_RIGHT", function()
        local recipe = SelectedRecipe()
        if not (recipe and not recipe.learned) then return false end
        UI.AddSourceLines(recipe.id)
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

-- The grid of reagent cards; d.AddReagentCard(i) creates card i when a recipe needs it.
function UI:CreateReagentCards(d, c)
    d.rows = {}
    d.AddReagentCard = function(i)
        local row = CreateFrame("Button", nil, c, "BackdropTemplate")
        self:Skin(row, "button")
        row.stripe = row:CreateTexture(nil, "ARTWORK")
        row.stripe:SetWidth(4)
        row.stripe:SetPoint("TOPLEFT", 1, -1)
        row.stripe:SetPoint("BOTTOMLEFT", 1, 1)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(CARD_H - 10, CARD_H - 10)
        row.icon:SetPoint("LEFT", 10, 0)
        row.name = self:Text(row, 0)
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
        row.name:SetPoint("RIGHT", -6, 0)
        row.name:SetWordWrap(false)
        row.count = self:Text(row, 1)
        row.count:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
        row.bankTag = self:Text(row, -1, "RIGHT")
        row.bankTag:SetPoint("BOTTOMRIGHT", -6, 4)
        row.bankTag:SetTextColor(unpack(STATUS_COLORS.bank))
        row.count:SetPoint("RIGHT", row.bankTag, "LEFT", -4, 0)
        row.count:SetWordWrap(false)
        row.vBadge = self:Badge(row, BADGE_VENDOR, function(r)
            GameTooltip:AddLine(L["Sold by a vendor"], 1, 0.82, 0)
            GameTooltip:AddLine(FP.Waypoint:VendorSummary(r.itemID), 1, 1, 1, true)
            GameTooltip:AddLine(L["Click: waypoint to the nearest vendor"], 0.5, 0.8, 1)
        end, function(r) FP.Waypoint:NearestVendor(r.itemID) end)
        row.qBadge = self:Badge(row, BADGE_QUEUE, function(r)
            GameTooltip:AddLine(L["Crafting Queue"], 0.4, 0.8, 1)
            GameTooltip:AddLine(L["%d needed by queued recipes:"]:format(r.queueQty or 0), 1, 1, 1)
            for _, u in ipairs(FP.Queue:UsageList(r.itemID)) do
                GameTooltip:AddDoubleLine(u.name .. " x" .. u.crafts, u.need, 0.8, 0.8, 0.8, 1, 1, 1)
            end
        end)
        row.sBadge = self:Badge(row, BADGE_SHOP, function(r)
            local want, have = r.shopQty or 0, r.owned or 0
            GameTooltip:AddLine(L["Shopping List"], 1, 0.82, 0)
            GameTooltip:AddDoubleLine(L["On the List"], tostring(want), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["You Have"], tostring(have), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Still to Buy"], tostring(math.max(0, want - have)), 0.8, 0.8, 0.8, 1, 1, 1)
        end)
        row.aBadge = self:Badge(row, BADGE_ALTS, function(r)
            local it = r.reagent and r.reagent.plan
            if not it then return end
            GameTooltip:AddLine(ItemName(r.itemID), 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Need for Requested Crafts"], it.need, 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Current Bags"], it.bags, 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Current Bank"], it.bank, 0.8, 0.8, 0.8, 1, 1, 1)
            UI:AddAltLines(GameTooltip, it)
        end)
        row.badges = { row.vBadge, row.sBadge, row.qBadge, row.aBadge }
        row:SetScript("OnEnter", function(s)
            s:SetBackdropBorderColor(unpack(UI:GetAccent()))
            if not s.itemID then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(s.itemID)
            local unit = FP.Prices:Unit(s.itemID)
            if unit then GameTooltip:AddLine(L["Auction Price: %s each"]:format(FP.Prices:Format(unit)), 1, 0.82, 0) end
            GameTooltip:AddLine(" ")
            if (s.queueQty or 0) > 0 then GameTooltip:AddLine(L["In Crafting Queue: %d"]:format(s.queueQty), 0.4, 0.8, 1) end
            if (s.shopQty or 0) > 0 then GameTooltip:AddLine(L["On Shopping List: %d"]:format(s.shopQty), 1, 0.82, 0) end
            if (s.altQty or 0) > 0 then
                GameTooltip:AddLine(L["On Other Characters: %d"]:format(s.altQty), unpack(UI.ALT_COLOR))
            end
            if s.hasVendor then
                GameTooltip:AddLine(L["Sold by: %s"]:format(FP.Waypoint:VendorSummary(s.itemID)), 1, 0.82, 0, true)
                GameTooltip:AddLine(L["Right-click: waypoint to the nearest vendor"], 0.5, 0.8, 1)
            end
            GameTooltip:AddLine(L["Click to add this reagent to the shopping list."], 0.5, 0.8, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(s)
            s:SetBackdropBorderColor(unpack(Skin().button.border))
            GameTooltip:Hide()
        end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(s, btn)
            if UI.LinkItemToChat(s.itemID) then return end
            if btn == "RightButton" then
                if s.hasVendor and s.itemID then FP.Waypoint:NearestVendor(s.itemID) end
            elseif s.itemID and s.need then
                FP.Shop:Add(s.itemID, s.need)
                FP:Print(L["Added %d item(s) to the shopping list."]:format(1))
            end
        end)
        d.rows[i] = row
    end
end

-- Banner, requirements, cost, quantity, craft buttons and the enchant / salvage target.
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
    self:Tooltip(d.costHit, "ANCHOR_TOP", function(tip)
        if not d.costInfo then return false end
        FillCostTip(tip, d.costInfo)
    end)
    d.profit = self:Text(c, -1)
    d.profit:SetPoint("BOTTOMLEFT", 12, 100)
    d.profit:SetPoint("RIGHT", -12, 0)
    d.profit:SetWordWrap(false)
    d.profitHit = CreateFrame("Frame", nil, c)
    d.profitHit:SetAllPoints(d.profit)
    d.profitHit:EnableMouse(true)
    self:Tooltip(d.profitHit, "ANCHOR_TOP", function(tip)
        if not d.profitInfo then return false end
        FillProfitTip(tip, d.profitInfo)
    end)
    d.banner:SetPoint("BOTTOMLEFT", 12, 80)
    d.banner:SetPoint("RIGHT", -12, 0)

    local ql = self:Text(c, 0)
    d.qtyLabel = ql
    ql:SetPoint("BOTTOMLEFT", 12, 18)
    ql:SetText(L["Qty:"])
    d.qty = CreateFrame("EditBox", "ProfessionsForeverQty", c, "InputBoxTemplate")
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
    -- Enchanting applies one enchant to the chosen item, so it replaces the quantity and craft buttons.
    d.enchantBtn = self:Button(c, L["Enchant"], 120, 24, function() UI.DoCraft(1) end)
    d.enchantBtn:SetPoint("BOTTOMLEFT", 12, 18)
    d.enchantBtn:Hide()
    for _, b in ipairs({ d.craft, d.craftAll, d.enchantBtn }) do
        self:Tooltip(b, "ANCHOR_TOP", function(tip)
            if not d.craftBlock then return false end
            tip:AddLine(d.craftBlock, 1, 0.3, 0.3, true)
        end)
    end
    local function AddMissing()
        local e = FP.selected and FP.Recipes:Evaluate(FP.selected, UI:GetCount())
        if not e then return end
        FP.Recipes:EvaluateAlts(e)
        local n = FP.Shop:AddRecipeMissing(e)
        FP:Print(L["Added %d item(s) to the shopping list."]:format(n))
    end
    d.addMissing = self:Button(c, L["Add Missing"], 110, 24, AddMissing)
    d.addMissing:SetPoint("BOTTOMLEFT", 12, 46)
    d.bannerBtn = CreateFrame("Button", nil, c)
    d.bannerBtn:SetAllPoints(d.banner)
    d.bannerBtn:SetScript("OnClick", AddMissing)
    d.addQueue = self:Button(c, L["Queue"], 80, 24, function()
        if not FP.selected then return end
        FP.Queue:Add(FP.selected, UI:GetCount())
        d.qty:SetText("1")
    end)
    d.addQueue:SetPoint("LEFT", d.addMissing, "RIGHT", 6, 0)

    d.track = self:Button(c, L["Track"], 80, 24, function()
        local e = SelectedRecipe()
        if e then UI.TrackRecipe(e) end
    end)
    d.track:SetPoint("LEFT", d.addQueue, "RIGHT", 6, 0)
    self:Tooltip(d.track, "ANCHOR_TOP", function(tip)
        local e = SelectedRecipe()
        if not e or e.learned then return false end
        tip:AddLine(L["Set a waypoint to where this recipe is learned"], 1, 1, 1)
        if not FP.Waypoint:NavAvailable() then tip:AddLine(L["Polestar or TomTom is needed for waypoints."], 0.6, 0.6, 0.6, true) end
    end)
    self:CreateEnchantTarget(d, c)
end

-- The enchant / salvage target picker, shown only for those recipes.
function UI:CreateEnchantTarget(d, c)
    -- Enchanting: the item to enchant, a square the height of a reagent card above the cost line, text to its right.
    d.target = CreateFrame("Button", nil, c, "BackdropTemplate")
    d.target:SetSize(CARD_H, CARD_H)
    d.target:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 12, 156)
    self:Skin(d.target, "button")
    d.target.icon = d.target:CreateTexture(nil, "ARTWORK")
    d.target.icon:SetPoint("TOPLEFT", 3, -3)
    d.target.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    d.target.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
    self:Tooltip(d.target, "ANCHOR_TOP", function(tip)
        local guid = UI.craftTarget and UI.craftTarget:GetItemGUID()
        if guid then
            tip:SetItemByGUID(guid)
        else
            local salvage = FP.selected and FP.Recipes:IsSalvage(FP.selected)
            tip:AddLine(salvage and L["Salvage Item"] or L["Enchant Target"], 1, 1, 1)
            tip:AddLine(salvage and L["Click to choose the item to salvage."] or L["Click to choose the item to enchant."], 0.6, 0.6, 0.6, true)
        end
    end)
    d.target:Hide()
    d.targetTitle:Hide()
    d.targetName:Hide()
end
