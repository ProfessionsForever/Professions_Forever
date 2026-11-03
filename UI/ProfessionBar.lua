local _, FP = ...
local L = FP.L
local UI = FP.UI
local WHITE = UI.WHITE

---------------------------------------------------------------------------
-- Header: the open skill line's bar (colored per profession) and the chat link button beside it.
---------------------------------------------------------------------------
local PROFESSION_COLORS = {
    [171] = { 0.25, 0.8, 0.45 }, [164] = { 0.8, 0.45, 0.2 }, [333] = { 0.6, 0.4, 0.95 }, [202] = { 0.9, 0.7, 0.15 },
    [182] = { 0.3, 0.75, 0.25 }, [773] = { 0.7, 0.5, 0.3 }, [755] = { 0.9, 0.25, 0.4 }, [165] = { 0.65, 0.45, 0.25 },
    [186] = { 0.5, 0.6, 0.75 }, [393] = { 0.75, 0.6, 0.35 }, [197] = { 0.35, 0.6, 0.95 }, [185] = { 0.95, 0.55, 0.2 },
    [356] = { 0.25, 0.65, 0.9 }, [129] = { 0.85, 0.85, 0.85 },
}

-- The open profession's name, level, modifier, cap and skill line ID.
local function RankInfo()
    local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    if not base then return end
    local name = base.professionName or ""
    local level, max = base.skillLevel or 0, base.maxSkillLevel or 0
    if max == 0 then
        for _, p in ipairs(FP:GetProfessions()) do
            if p.name == name then level, max = p.rank or 0, p.maxRank or 0 break end
        end
    end
    return name, level, base.skillModifier or 0, max, base.professionID
end

local function ChatCall(utilName, legacyName)
    return (ChatFrameUtil and ChatFrameUtil[utilName]) or _G[legacyName]
end

-- Chat-link click (shift by default): puts the link in the active chat box. True when it did, so the click is spent.
function UI.LinkToChat(link)
    if not (link and IsModifiedClick("CHATLINK")) then return false end
    local insert = ChatCall("InsertLink", "ChatEdit_InsertLink")
    return insert and insert(link) and true or false
end

function UI.LinkItemToChat(itemID)
    return itemID and UI.LinkToChat(select(2, C_Item.GetItemInfo(itemID))) or false
end

-- Channels to post the profession link in, as Blizzard's link button offers.
function UI.LinkItems()
    local items = {}
    local function Add(slash, text, enabled)
        items[#items + 1] = { text = text, dim = not enabled, onSelect = enabled and function()
            local link = C_TradeSkillUI.GetTradeSkillListLink()
            local open = ChatCall("OpenChat", "ChatFrame_OpenChat")
            if link and open then open(slash .. " " .. link, DEFAULT_CHAT_FRAME) end
        end or nil }
    end
    Add(SLASH_GUILD1 or "/g", GUILD, IsInGuild())
    Add(SLASH_PARTY1 or "/p", PARTY, GetNumSubgroupMembers() > 0)
    Add(SLASH_RAID1 or "/raid", RAID, IsInRaid())
    local channels = { GetChannelList() }
    local resolve = ChatCall("ResolveChannelName", "ChatFrame_ResolveChannelName")
    for i = 1, #channels, 3 do
        Add("/" .. channels[i], resolve and resolve(channels[i + 1]) or channels[i + 1], not channels[i + 2])
    end
    return items
end

local function OnLinkClick(button)
    local link = C_TradeSkillUI.GetTradeSkillListLink()
    local activeWindow, insert = ChatCall("GetActiveWindow", "ChatEdit_GetActiveWindow"), ChatCall("InsertLink", "ChatEdit_InsertLink")
    if link and insert and activeWindow and activeWindow() then
        insert(link)
    else
        UI:OpenMenu(button, UI.LinkItems(), 160)
    end
end

local function SetRankBar(rank, c, label, level, max)
    rank.bar:SetStatusBarColor(c[1], c[2], c[3])
    rank.bar:SetMinMaxValues(0, math.max(max, 1))
    rank.bar:SetValue(math.min(level, math.max(max, 1)))
    rank.label:SetText(label)
end

-- The skill bar above the panels: the open profession's on the recipe page, all professions' combined on the Overview.
function UI:RefreshHeader()
    local f = self.frame
    local rank = f.rank
    if self.page == "overview" then
        local level, max = 0, 0
        for _, p in ipairs(FP:GetProfessions()) do level, max = level + (p.rank or 0), max + (p.maxRank or 0) end
        rank:SetShown(max > 0)
        SetRankBar(rank, self:GetAccent(), ("%s %d/%d"):format(L["All Professions"], level, max), level, max)
        f.link:Hide()
        return
    end
    local T = C_TradeSkillUI
    local name, level, modifier, max, skillLine = RankInfo()
    rank:SetShown(name ~= nil)
    if name then
        SetRankBar(rank, PROFESSION_COLORS[skillLine] or self:GetAccent(),
            modifier > 0 and ("%s %d (+%d)/%d"):format(name, level, modifier, max) or ("%s %d/%d"):format(name, level, max), level, max)
    end
    f.link:SetShown(name ~= nil and T.CanTradeSkillListLink ~= nil and T.CanTradeSkillListLink() and FP:IsOwnProfession())
end

---------------------------------------------------------------------------
-- Profession bar
---------------------------------------------------------------------------
function UI:RefreshProfessions()
    local f = self.frame
    self:RefreshHeader()
    local profs = FP:GetProfessions()
    local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    f.profButtons = f.profButtons or {}
    if not f.overviewTab then
        local t = self:Button(f.profBar, L["Overview"], 110, 24, function() UI.TabSound() UI:SetPage("overview") end)
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetSize(18, 18)
        t.icon:SetPoint("LEFT", 4, 0)
        t.icon:SetTexture(FP.ICON)
        t.text:ClearAllPoints()
        t.text:SetPoint("LEFT", t.icon, "RIGHT", 4, 0)
        t.text:SetPoint("RIGHT", -4, 0)
        t.text:SetJustifyH("LEFT")
        t:SetPoint("LEFT", 0, 0)
        f.overviewTab = t
    end
    local onOverview = self.page == "overview"
    f.clearWay:ClearAllPoints()
    f.clearWay:SetPoint("RIGHT", f.leftButton, "LEFT", -4, 0)
    local titleAnchor = f.clearWay:IsShown() and f.clearWay or f.leftButton
    f.title:ClearAllPoints()
    f.title:SetPoint("LEFT", f.titleBar, "LEFT", 8, 0)
    f.title:SetPoint("RIGHT", titleAnchor, "LEFT", -4, 0)
    f.overviewTab.text:SetTextColor(onOverview and 1 or 0.8, onOverview and 0.82 or 0.8, onOverview and 0 or 0.8)
    UI.SetSelected(f.overviewTab, onOverview)

    local barW = f.profBar:GetWidth()
    if barW < 100 then barW = f:GetWidth() - 16 end
    local gap = 4
    local w = (barW - #profs * gap) / (#profs + 1)
    f.overviewTab:SetWidth(w)
    local x = w + gap
    for i, p in ipairs(profs) do
        local b = f.profButtons[i]
        if not b then
            b = self:Button(f.profBar, "", 160, 24, function(s, btn)
                if btn == "RightButton" then
                    if FP.Waypoint:NavAvailable() then FP.Waypoint:NearestTrainer(s.profName) end
                else
                    UI.TabSound()
                    UI:SetPage("recipes")
                    FP:OpenProfession(s.skillLine)
                end
            end)
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            b:HookScript("OnEnter", function(s)
                if not FP.Waypoint:NavAvailable() then return end
                s.tipToken = (s.tipToken or 0) + 1
                local token = s.tipToken
                C_Timer.After(0.4, function()
                    if s.tipToken ~= token or not s:IsMouseOver() then return end
                    GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
                    GameTooltip:AddLine(s.profName, 1, 1, 1)
                    GameTooltip:AddLine(L["Right-click: waypoint to the nearest trainer"], 0.5, 0.8, 1)
                    GameTooltip:Show()
                end)
            end)
            b:HookScript("OnLeave", function(s)
                s.tipToken = (s.tipToken or 0) + 1
                GameTooltip:Hide()
            end)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetSize(18, 18)
            b.icon:SetPoint("LEFT", 4, 0)
            b.text:ClearAllPoints()
            b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
            b.text:SetPoint("RIGHT", -6, 0)
            b.text:SetWordWrap(false)
            b.text:SetJustifyH("LEFT")
            f.profButtons[i] = b
        end
        b.skillLine = p.skillLine
        b.profName = p.name
        b.icon:SetTexture(p.icon)
        b.text:SetText(p.name)
        b:ClearAllPoints()
        b:SetWidth(i == #profs and barW - x or w)
        b:SetPoint("LEFT", x, 0)
        x = x + w + gap
        local active = self.page == "recipes" and base and (base.professionID == p.skillLine or base.professionName == p.name)
        b.text:SetTextColor(active and 1 or 0.8, active and 0.82 or 0.8, active and 0 or 0.8)
        UI.SetSelected(b, active)
        b:Show()
    end
    for i = #profs + 1, #f.profButtons do f.profButtons[i]:Hide() end
end

-- Profession bar and the header above the recipe list and detail panel.
function UI:CreateHeader(f)
    -- Profession selector + skill display
    f.profBar = CreateFrame("Frame", "ProfessionsForeverProfBar", f, "BackdropTemplate")
    f.profBar:SetPoint("TOPLEFT", 8, -34)
    f.profBar:SetPoint("TOPRIGHT", -8, -34)
    f.profBar:SetHeight(26)

    -- Header above the panels: the skill bar and its chat link.
    f.header = CreateFrame("Frame", "ProfessionsForeverHeader", f)
    f.header:SetPoint("TOPLEFT", 8, -64)
    f.header:SetPoint("TOPRIGHT", -8, -64)
    f.header:SetHeight(25)

    local rank = self:Button(f.header, "", 320, 22)
    rank:EnableMouse(false)
    f.rank = rank
    rank:SetPoint("CENTER")
    rank.text:Hide()
    rank.bar = CreateFrame("StatusBar", nil, rank)
    rank.bar:SetPoint("TOPLEFT", 1, -1)
    rank.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    rank.bar:SetStatusBarTexture(WHITE)
    rank.label = self:Text(rank.bar, 0, "CENTER")
    rank.label:SetPoint("CENTER")
    rank.label:SetTextColor(1, 1, 1)
    rank.label:SetShadowOffset(1, -1)

    f.link = self:Button(f.header, "", 22, 22, function(s) OnLinkClick(s) end)
    f.link:SetPoint("LEFT", rank, "RIGHT", 6, 0)
    f.link.text:Hide()
    f.link.icon = f.link:CreateTexture(nil, "ARTWORK")
    f.link.icon:SetSize(16, 16)
    f.link.icon:SetPoint("CENTER")
    f.link.icon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
    self:Tooltip(f.link, "ANCHOR_RIGHT", L["Link This Profession in Chat"])
end
UI.RankInfo = RankInfo
