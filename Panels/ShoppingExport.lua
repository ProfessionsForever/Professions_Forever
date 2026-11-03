local addonName, FP = ...
local L = FP.L
local Shop = FP.Shop
local ACTION_BUTTON_H = Shop.ACTION_BUTTON_H

-- Handing the list to other places: a copyable text export, Auctionator, and the auction house search box.

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
        if FP.UI:AttachEUIThinScrollbar(sf, scrollBar, f, { top = 34, bottom = 40 }, eb) then
            sf:SetPoint("BOTTOMRIGHT", -16, 40) -- the thin bar needs no gutter
        else
            FP.UI:EUIWidget(scrollBar, "scrollbar")
        end
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

-- Auctionator's public API v1: ConvertToSearchString supports exact name + quantity.
function Shop:SendToAuctionator()
    local api = _G.Auctionator and Auctionator.API and Auctionator.API.v1
    if not api then return FP:Print(L["Auctionator is not loaded."]) end
    local terms = {}
    for _, e in ipairs(self:Aggregate()) do
        local name = C_Item.GetItemNameByID(e.itemID)
        if e.toBuy > 0 and name then
            terms[#terms + 1] = api.ConvertToSearchString(addonName, { searchString = name, isExact = true, quantity = e.toBuy })
        end
    end
    local ok, err = pcall(api.CreateShoppingList, addonName, "ProfessionsForever", terms)
    if ok then FP:Print(L["Sent %d item(s) to Auctionator."]:format(#terms)) else FP:Print(err) end
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
