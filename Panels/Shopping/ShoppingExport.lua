local addonName, FP = ...
local L = FP.L
local Shop = FP.Shop
local ACTION_BUTTON_H = Shop.ACTION_BUTTON_H

-- Handing the list to other places: a copyable text export, Auctionator's shopping list, and the auction house search box.

function Shop:ExportText()
    local lines = {}
    for _, e in ipairs(self:Aggregate()) do
        if e.toBuy > 0 then lines[#lines + 1] = ("%s x%d"):format(e.name, e.toBuy) end
    end
    return table.concat(lines, "\n")
end

function Shop:ShowExport()
    local f = self.exportFrame
    if not f then
        f = CreateFrame("Frame", "ProfessionsForeverExportFrame", UIParent, "BackdropTemplate")
        f:SetSize(360, 300)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        FP.UI:Skin(f, "window")
        tinsert(UISpecialFrames, "ProfessionsForeverExportFrame")
        local t = FP.UI:Text(f, 2)
        t:SetPoint("TOPLEFT", 12, -10)
        t:SetText(L["Shopping List Export"])
        local sf = CreateFrame("ScrollFrame", "ProfessionsForeverExportScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -34)
        sf:SetPoint("BOTTOMRIGHT", -32, 40)
        local scrollBar = sf.ScrollBar or _G["ProfessionsForeverExportScrollScrollBar"]
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(300)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        sf:HookScript("OnSizeChanged", function(_, w) eb:SetWidth(w) end)
        FP.UI:AttachScrollbar(sf, scrollBar, f, { top = 34, bottom = 40 }, eb)
        sf:SetPoint("BOTTOMRIGHT", -16, 40) -- the thin bar needs no gutter
        f.edit = eb
        local close = FP.UI:Button(f, L["Close"], 80, ACTION_BUTTON_H, function() f:Hide() end)
        close:SetPoint("BOTTOM", 0, 10)
        self.exportFrame = f
    end
    f.edit:SetText(self:ExportText())
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

-- Keeps Auctionator's "ProfessionsForever" shopping list the same as what is still to buy, through its public API v1
-- (exact name and quantity per item). A changed amount is altered and an item no longer needed is deleted in place,
-- which leaves Auctionator's Shopping tab on the list and results it is showing. The API cannot add one item, so a
-- new item re-creates the list, and at the auction house that opens it in the Shopping tab. Run by FP:Changed
-- (UI/Redraw.lua) on the frame after anything the list depends on changes.
local LIST = "ProfessionsForever"
function Shop:SyncAuctionator()
    local api = FP.db.syncAuctionator and _G.Auctionator and Auctionator.API and Auctionator.API.v1
    if not api then return end
    local want, terms = {}, {}
    for _, e in ipairs(self:Aggregate()) do
        local name = C_Item.GetItemNameByID(e.itemID) -- not loaded yet: synced when "items" says it arrived
        if e.toBuy > 0 and name then
            want[name] = api.ConvertToSearchString(addonName, { searchString = name, isExact = true, quantity = e.toBuy })
            terms[#terms + 1] = want[name]
        end
    end
    local exists, have = pcall(api.GetShoppingListItems, addonName, LIST) -- it throws when there is no such list
    if not exists then
        if #terms > 0 then api.CreateShoppingList(addonName, LIST, terms) end
        return
    end
    local held = {}
    for _, term in ipairs(have) do held[api.ConvertFromSearchString(addonName, term).searchString] = term end
    for name in pairs(want) do
        if not held[name] then return api.CreateShoppingList(addonName, LIST, terms) end
    end
    for name, term in pairs(held) do
        if not want[name] then
            api.DeleteShoppingListItem(addonName, LIST, term)
        elseif want[name] ~= term then
            api.AlterShoppingListItem(addonName, LIST, term, want[name])
        end
    end
end

function Shop:SearchAuctionHouse(itemID)
    local ah = AuctionHouseFrame
    if not (ah and ah:IsShown()) then return FP:Print(L["Open the auction house to search for items."]) end
    local name = C_Item.GetItemNameByID(itemID)
    local bar = ah.SearchBar
    if not (name and bar and bar.SearchBox and bar.StartSearch) then return end
    if ah.SetDisplayMode and AuctionHouseFrameDisplayMode then ah:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy) end
    bar.SearchBox:SetText(name)
    bar:StartSearch()
end
