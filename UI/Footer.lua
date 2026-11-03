local _, FP = ...
local L = FP.L
local UI = FP.UI

-- Summary cells along the bottom of the window on every page; each one toggles its window.
local CELL_H, GAP = 56, 6
UI.FOOTER_RESERVE = CELL_H + GAP -- height the panels above leave free

local function CutOff(fs)
    return fs:GetStringWidth() > fs:GetWidth() + 0.5
end

local function MakeCell(f, title, onClick)
    local c = UI:Button(f, "", 100, CELL_H, onClick)
    c.title = UI:Text(c, 1)
    c.title:SetPoint("TOPLEFT", 12, -8)
    c.title:SetText(title)
    c.title:SetTextColor(1, 0.82, 0)
    c.line = UI:Text(c, 0)
    c.line:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
    c.sub = UI:Text(c, -1)
    c.sub:SetPoint("TOPLEFT", c.line, "BOTTOMLEFT", 0, -2)
    c.sub:SetTextColor(0.65, 0.65, 0.65)
    for _, fs in ipairs({ c.line, c.sub }) do
        fs:SetPoint("RIGHT", c, "RIGHT", -12, 0)
        fs:SetWordWrap(false)
    end
    UI:Tooltip(c, "ANCHOR_TOP", function(tip, s)
        if not (CutOff(s.line) or CutOff(s.sub)) then return false end
        tip:AddLine(s.title:GetText(), 1, 0.82, 0)
        tip:AddLine(s.line:GetText(), 1, 1, 1, true)
        local sub = s.sub:GetText()
        if sub and sub ~= "" then tip:AddLine(sub, 0.65, 0.65, 0.65, true) end
    end)
    return c
end

function UI:CreateFooter(f)
    local footer = {}
    footer.queue = MakeCell(f, L["Crafting Queue"], function() FP.Queue:Toggle() end)
    footer.cooldowns = MakeCell(f, L["Cooldowns"], function() FP.CooldownPanel:Toggle() end)
    footer.transfer = MakeCell(f, L["Transfer Planner"], function() FP.Transfer:Toggle() end)
    footer.shop = MakeCell(f, L["Shopping List"], function() FP.Shop:Toggle() end)
    footer.cells = { footer.cooldowns, footer.transfer, footer.shop, footer.queue }
    footer.cells[1]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
    for i = 2, #footer.cells do
        footer.cells[i]:SetPoint("BOTTOMLEFT", footer.cells[i - 1], "BOTTOMRIGHT", GAP, 0)
    end
    f.footer = footer
    self:LayoutFooter()
    self:RefreshFooterSelection()
end

-- A cell is lit while its window is open.
function UI:RefreshFooterSelection()
    local footer = self.frame and self.frame.footer
    if not footer then return end
    local windows = { cooldowns = FP.CooldownPanel, transfer = FP.Transfer, shop = FP.Shop, queue = FP.Queue }
    for key, window in pairs(windows) do
        UI.SetSelected(footer[key], window.frame and window.frame:IsShown())
    end
end

-- Sized from the window, as its own size can lag behind while it is being resized.
function UI:LayoutFooter()
    local f = self.frame
    local footer = f and f.footer
    if not footer then return end
    local n = #footer.cells
    local w = (f:GetWidth() - 16 - GAP * (n - 1)) / n
    for _, c in ipairs(footer.cells) do c:SetWidth(w) end
end

function UI:RefreshFooter()
    local f = self.frame
    local footer = f and f.footer
    if not (footer and f:IsShown()) then return end

    local n, crafts, missing = FP.Queue:Summary()
    local plan = FP.Queue:TransferNeeds()
    footer.queue.line:SetText(n == 0 and L["Nothing queued"] or L["%d recipes, %d crafts"]:format(n, crafts))
    local covered = plan.applies and plan.totals.units > 0
    footer.queue.sub:SetText(n > 0 and (missing > 0 and L["%d materials still missing"]:format(missing)
        or (covered and L["Available on Other Characters"] or L["All materials on hand"])) or "")

    local t, mode = plan.totals, FP.Planner:Mode()
    if mode == "never" then
        footer.transfer.line:SetText(L["Alt inventory is off"])
        footer.transfer.sub:SetText("")
    elseif t.units == 0 then
        footer.transfer.line:SetText(L["No transfers needed"])
        footer.transfer.sub:SetText(FP.Alts:HasSources() and "" or L["No alt inventory known"])
    else
        footer.transfer.line:SetText(L["%d alts - %d item types"]:format(t.characters, t.itemTypes))
        footer.transfer.sub:SetText(t.missingTypes > 0 and L["%d materials still unavailable"]:format(t.missingTypes)
            or (mode == "show" and L["Show only - not applied to shopping"] or ""))
    end

    local items, cost, unpriced = FP.Shop:Summary()
    footer.shop.line:SetText(items == 0 and L["Nothing to buy"] or L["%d items to buy"]:format(items))
    local sub = ""
    if items > 0 and FP.Prices:Available() then
        sub = cost > 0 and (L["Estimated Cost"] .. ": " .. FP.Prices:Format(cost)) or ""
        if unpriced > 0 then sub = sub .. (sub ~= "" and "  -  " or "") .. L["%d without an auction price"]:format(unpriced) end
    end
    footer.shop.sub:SetText(sub)

    local ready, chars, soon, soonOwner = 0, 0, nil, nil
    for _, g in ipairs(FP.Cooldowns:List()) do
        ready = ready + g.ready
        if g.ready > 0 then chars = chars + 1 end
        for _, c in ipairs(g.entries) do
            if not (c.unknown or c.ignored) and c.remaining > 0 and (not soon or c.remaining < soon.remaining) then
                soon, soonOwner = c, g.rec
            end
        end
    end
    if ready == 0 then
        footer.cooldowns.line:SetText(L["Nothing ready"])
    else
        local text = chars > 1 and L["%d ready on %d characters"]:format(ready, chars) or L["%d ready"]:format(ready)
        footer.cooldowns.line:SetText("|cff33e633" .. text .. "|r")
    end
    footer.cooldowns.sub:SetText(soon and L["Next: %s in %s (%s)"]:format(soon.name, FP.Cooldowns.Format(soon.remaining),
        FP.Alts:Label(soonOwner)) or "")
end
