local _, FP = ...
local L = FP.L
local UI = FP.UI
local O = FP.Options

-- Fill in the URLs. A row with an empty URL still shows, so the place for it is visible.
local LINKS = {
    { label = "Discord", url = "https://discord.gg/Ay4E5GEhA2" },
    { label = "Issue Tracker", url = "https://github.com/ProfessionsForever/Professions_Forever/issues" },
    { label = "Donate", url = "https://ko-fi.com/professionsforever" },
}

local WORKS_WITH = {
    { "Auctionator", "prices and cost totals" },
    { "Syndicator", "live bank counts and other characters' inventory" },
    { "Questie", "vendor, trainer and banker locations" },
    { "TomTom", "waypoints" },
    { "Polestar", "waypoints" },
    { "EllesmereUI", "window skin" },
}

local function Meta(field) return C_AddOns.GetAddOnMetadata("ProfessionsForever", field) end
local ICON_SIZE = 96

local function WorksWithLines()
    local out = {}
    for i, a in ipairs(WORKS_WITH) do out[i] = a[1] .. " - " .. L[a[2]] end
    return out
end

local function LinkBox(parent, url, w)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(w, 20)
    eb:SetAutoFocus(false)
    eb:SetText(url)
    eb:SetCursorPosition(0)
    eb:SetScript("OnEditFocusGained", eb.HighlightText)
    eb:SetScript("OnTextChanged", function(s, user)
        if user then s:SetText(url) s:HighlightText() end
    end)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    return eb
end

function O.BuildAbout(page)
    local icon = page:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("TOPLEFT", 0, 0)
    icon:SetTexture(FP.ICON)
    local title = UI:Text(page, 4)
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 14, -2)
    title:SetText("ProfessionsForever")
    title:SetTextColor(1, 0.82, 0)
    local version = UI:Text(page, 0)
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    version:SetText(L["Version"] .. " " .. (Meta("Version") or "?"))
    version:SetTextColor(0.7, 0.7, 0.7)

    local notes = UI:Text(page, 0)
    notes:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -8)
    notes:SetWidth(O.PAGE_W - ICON_SIZE - 14)
    notes:SetText(Meta("Notes") or "")
    notes:SetTextColor(0.8, 0.8, 0.8)
    local textH = 2 + math.ceil(title:GetStringHeight()) + 6 + math.ceil(version:GetStringHeight()) + 8 + math.ceil(notes:GetStringHeight())
    page.y = -math.max(ICON_SIZE, textH) - 4

    O.Section(page, L["Links"])
    for _, link in ipairs(LINKS) do
        O.Label(page, L[link.label])
        local box = LinkBox(page, link.url, O.PAGE_W - O.CTRL_X - 8)
        box:SetPoint("LEFT", page, "TOPLEFT", O.CTRL_X + 6, page.y - O.ROW_H / 2)
        UI:EUIWidget(box, "editbox")
        page.y = page.y - O.ROW_H
    end

    O.Section(page, L["Credits"])
    local function Line(text, color)
        local t = UI:Text(page, 0)
        t:SetPoint("TOPLEFT", 8, page.y)
        t:SetText(text)
        if color then t:SetTextColor(color, color, color) end
        page.y = page.y - 18
    end
    Line(L["Author"] .. ": " .. (Meta("Author") or "?"))
    Line(L["Works with these addons when they are installed:"], 0.7)
    for _, text in ipairs(WorksWithLines()) do Line(text) end
end

-- Adds an entry to Blizzard's AddOns settings list: the same About content, plus a button that opens the options window.
function O:RegisterSettings()
    local panel = CreateFrame("Frame")
    panel.name = "ProfessionsForever"

    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("TOPLEFT", 16, -16)
    icon:SetTexture(FP.ICON)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 14, -4)
    title:SetText("ProfessionsForever")

    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    version:SetText(L["Version"] .. " " .. (Meta("Version") or "?"))

    local notes = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    notes:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -16)
    notes:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    notes:SetJustifyH("LEFT")
    notes:SetText(Meta("Notes") or "")

    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(200, 24)
    button:SetPoint("TOPLEFT", notes, "BOTTOMLEFT", 0, -16)
    button:SetText(L["Open Options Window"])
    button:SetScript("OnClick", function() O:Open() end)

    local linksTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    linksTitle:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -24)
    linksTitle:SetText(L["Links"])
    local anchor = linksTitle
    for _, link in ipairs(LINKS) do
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
        label:SetWidth(110)
        label:SetJustifyH("LEFT")
        label:SetText(L[link.label])
        LinkBox(panel, link.url, 320):SetPoint("LEFT", label, "RIGHT", 10, 0)
        anchor = label
    end

    local credits = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    credits:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -24)
    credits:SetText(L["Credits"])

    local body = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    body:SetPoint("TOPLEFT", credits, "BOTTOMLEFT", 0, -8)
    body:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    body:SetJustifyH("LEFT")
    body:SetSpacing(4)
    body:SetText(L["Author"] .. ": " .. (Meta("Author") or "?") .. "\n\n"
        .. L["Works with these addons when they are installed:"] .. "\n"
        .. table.concat(WorksWithLines(), "\n"))

    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, panel.name))
end
