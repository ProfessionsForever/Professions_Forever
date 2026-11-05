local _, FP = ...
local L = FP.L
local Queue = {}
FP.Queue = Queue

local ROWS, ROW_H = 11, 28
local STOP_MACRO = "/stopcasting\n/run C_TradeSkillUI.StopRecipeRepeat()"
local MISSING, BANK = FP.UI.STATUS_COLORS.missing, FP.UI.STATUS_COLORS.bank
local function Mark(c) return ("|cff%02x%02x%02x! |r"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) end
local WARN, BANK_MARK = Mark(MISSING), Mark(BANK)

-- Entries snapshot their reagents so the queue works across professions without reopening them.
function Queue:Data() return FP.chardb.queue end

-- Per-recipe breakdown of what the queue needs of this reagent.
function Queue:UsageList(itemID)
    local out = {}
    for _, q in ipairs(self:Data()) do
        for _, r in ipairs(q.reagents) do
            if r.itemID == itemID then out[#out + 1] = { name = q.name, crafts = q.qty, need = r.qty * q.qty } end
        end
    end
    return out
end

-- Total of this reagent needed by everything in the queue.
function Queue:QueuedAmount(itemID)
    local total = 0
    for _, q in ipairs(self:Data()) do
        for _, r in ipairs(q.reagents) do
            if r.itemID == itemID then total = total + r.qty * q.qty end
        end
    end
    return total
end

-- Total of this item that the queued crafts will make.
function Queue:QueuedProduction(itemID)
    local total = 0
    for _, q in ipairs(self:Data()) do
        if q.output and q.output.itemID == itemID then total = total + q.qty * q.output.qty end
    end
    return total
end

function Queue:Open()
    if not self.frame then
        -- The craft buttons are secure; their attributes can't be set during combat.
        if InCombatLockdown() then return FP:Print(L["Cannot do that in combat."]) end
        self:Create()
    end
    if not self.frame:IsShown() then
        if FP.UI.CombatBlocked(self.frame) then return FP:Print(L["Cannot do that in combat."]) end
        FP.UI:PlaceSidePanel(self.frame)
        self.frame:Show()
    end
end

function Queue:OpenTransferIfNeeded()
    if not FP.Planner:Applies() then return end
    local chars = self:TransferNeeds().totals.characters
    if chars == 0 then return end
    FP:Print(L["Materials for the queue are on %d other character(s). Opening the transfer planner."]:format(chars))
    FP.Transfer:Open()
end

-- What a queue entry keeps about a recipe of the open profession, so the queue works across professions without
-- reopening them: reagents, what it makes and the skill line to craft it in.
function Queue:InfoFor(recipeID, skillLine)
    local e = FP.Recipes.byID[recipeID]
    if not e then return end
    local reagents = {}
    for i, r in ipairs(FP.Recipes:GetReagents(recipeID)) do
        reagents[i] = { itemID = r.itemID, qty = r.qty }
    end
    local itemID = FP.Recipes:OutputItemID(recipeID)
    return { id = recipeID, name = e.name, icon = e.icon, reagents = reagents, skillLine = skillLine or self:CurrentSkillLine(),
        output = itemID and { itemID = itemID, qty = (FP.Recipes:OutputQuantity(recipeID)) } or nil }
end

-- Adds crafts of a recipe described by InfoFor, merging into its entry when it is already queued. Returns how many
-- crafts were added.
function Queue:AddInfo(info, qty)
    qty = math.max(1, qty or 1)
    local data = self:Data()
    for _, q in ipairs(data) do
        if q.id == info.id then
            local before = q.qty
            q.qty = math.min(999, q.qty + qty)
            return q.qty - before
        end
    end
    data[#data + 1] = { id = info.id, name = info.name, icon = info.icon, qty = math.min(999, qty),
        reagents = info.reagents, skillLine = info.skillLine, output = info.output }
    return math.min(999, qty)
end

function Queue:Add(recipeID, qty)
    self:Open()
    local info = self:InfoFor(recipeID)
    if not info then return end
    local added = self:AddInfo(info, qty)
    self:Update()
    self:OpenTransferIfNeeded()
    FP:Print(L["Added %dx %s to the queue."]:format(added, info.name))
end

local function Consumes(q, itemID)
    for _, r in ipairs(q.reagents) do
        if r.itemID == itemID then return true end
    end
end

-- Moves each entry that makes something a queued entry needs ahead of that entry.
function Queue:OrderByDependency()
    local data = self:Data()
    for _ = 1, #data * #data do
        local moved
        for j = 2, #data do
            local out = data[j].output
            for i = 1, out and j - 1 or 0 do
                if Consumes(data[i], out.itemID) then
                    table.insert(data, i, table.remove(data, j))
                    moved = true
                    break
                end
            end
            if moved then break end
        end
        if not moved then return end
    end
end

-- Like Add, but also queues the crafts of reagents you are short of and know how to make, ahead of the recipe.
function Queue:AddWithPrerequisites(recipeID, qty)
    self:Open()
    local info = self:InfoFor(recipeID)
    if not info then return end
    local steps = FP.Chain:Plan(info, math.max(1, qty or 1)).steps
    local first = {}
    for _, step in ipairs(steps) do
        self:AddInfo(step.recipe, step.crafts)
        first[#first + 1] = ("%dx %s"):format(step.crafts, step.recipe.name)
    end
    local added = self:AddInfo(info, qty)
    if #steps > 0 then self:OrderByDependency() end
    self:Update()
    self:OpenTransferIfNeeded()
    FP:Print(L["Added %dx %s to the queue."]:format(added, info.name))
    if #first > 0 then FP:Print(L["Crafting first: %s"]:format(table.concat(first, ", "))) end
end

-- Whole crafts the bags can still supply once everything already queued has its materials.
function Queue:RoomFor(recipeID)
    local reagents = FP.Recipes:GetReagents(recipeID)
    if #reagents == 0 then return 0 end
    local crafts = 999
    for _, r in ipairs(reagents) do
        local bags = FP.Inv:Owned(r.itemID)
        crafts = math.min(crafts, math.floor((bags - self:QueuedAmount(r.itemID)) / r.qty))
    end
    return math.max(crafts, 0)
end

function Queue:Remove(index)
    table.remove(self:Data(), index)
    self:Update()
end

function Queue:Move(index, delta)
    local data, to = self:Data(), index + delta
    if not data[index] or not data[to] then return end
    data[index], data[to] = data[to], data[index]
    self:Update()
end

function Queue:Clear()
    wipe(self:Data())
    self:Update()
end

-- Totals reagents across all queued recipes so shared materials are counted once against stock.
-- A changed queue drops the amounts chosen in the Transfer Planner for materials it no longer needs.
function Queue:Requirements()
    local order, byItem, sig, made = {}, {}, {}, {}
    for _, q in ipairs(self:Data()) do
        sig[#sig + 1] = q.id .. "x" .. q.qty
        if q.output then made[q.output.itemID] = (made[q.output.itemID] or 0) + q.qty * q.output.qty end
        for _, r in ipairs(q.reagents) do
            local n = byItem[r.itemID]
            if not n then
                n = { itemID = r.itemID, need = 0 }
                byItem[r.itemID] = n
                order[#order + 1] = n
            end
            n.need = n.need + r.qty * q.qty
        end
    end
    -- What queued crafts will make is not something to acquire.
    local needed = {}
    for _, n in ipairs(order) do
        n.need = n.need - (made[n.itemID] or 0)
        if n.need > 0 then needed[#needed + 1] = n else byItem[n.itemID] = nil end
    end
    local key = table.concat(sig, ",")
    if key ~= self.requirementsSig then
        self.requirementsSig = key
        FP.Alts:KeepTakes(byItem)
    end
    return needed
end

-- Requirements with what the current character alone is short of; alts are not considered.
function Queue:Needs()
    local order = self:Requirements()
    for _, n in ipairs(order) do
        local _, _, total = FP.Inv:Owned(n.itemID)
        n.short = math.max(0, n.need - total)
    end
    return order
end

-- Which characters should send what, from the shared transfer plan for the whole queue.
function Queue:TransferNeeds()
    return FP.Planner:Plan(self:Requirements())
end

-- Materials still to acquire: the plan's shortage items, which are net of alts only when alts count toward planning.
function Queue:TrueShortages()
    local out = {}
    for _, it in ipairs(self:TransferNeeds().items) do
        if it.shortage > 0 then out[#out + 1] = it end
    end
    return out
end

-- Per queue entry, the reagents it cannot get: entries are served in queue order from what the plan supplies
-- (bags, bank, and alts when they count). Entries with nothing missing are absent.
function Queue:EntryShortages()
    local byItem = self:TransferNeeds().byItem
    local supply, out = {}, {}
    local function Left(itemID)
        local it = byItem[itemID]
        return supply[itemID] or (it and it.need - it.shortage or 0)
    end
    for _, q in ipairs(self:Data()) do
        for _, r in ipairs(q.reagents) do
            local left = Left(r.itemID)
            local need = r.qty * q.qty
            local take = math.min(left, need)
            supply[r.itemID] = left - take
            if take < need then
                out[q] = out[q] or {}
                out[q][#out[q] + 1] = { itemID = r.itemID, qty = need - take }
            end
        end
        -- What this entry makes is there for the entries after it.
        if q.output then supply[q.output.itemID] = Left(q.output.itemID) + q.qty * q.output.qty end
    end
    return out
end

-- Per queue entry, the reagents that are only in the bank: entries are served in queue order from the bags (plus what
-- earlier entries make), then the bank. Entries with nothing to fetch are absent.
function Queue:EntryBank()
    local bags, bank, out = {}, {}, {}
    local function Counts(itemID)
        if not bags[itemID] then
            local inBags, inBank = FP.Inv:Owned(itemID)
            bags[itemID], bank[itemID] = inBags, inBank
        end
    end
    for _, q in ipairs(self:Data()) do
        for _, r in ipairs(q.reagents) do
            Counts(r.itemID)
            local need = r.qty * q.qty
            local fromBags = math.min(bags[r.itemID], need)
            bags[r.itemID] = bags[r.itemID] - fromBags
            local fromBank = math.min(bank[r.itemID], need - fromBags)
            if fromBank > 0 then
                bank[r.itemID] = bank[r.itemID] - fromBank
                out[q] = out[q] or {}
                out[q][#out[q] + 1] = { itemID = r.itemID, qty = fromBank }
            end
        end
        if q.output then
            Counts(q.output.itemID)
            bags[q.output.itemID] = bags[q.output.itemID] + q.qty * q.output.qty
        end
    end
    return out
end

-- Recipes queued, total crafts, and how many reagents are still short.
function Queue:Summary()
    local data, crafts = self:Data(), 0
    for _, q in ipairs(data) do crafts = crafts + q.qty end
    return #data, crafts, #self:TrueShortages()
end

-- Adds each short reagent's full need: the shopping list compares it against what you own (and what alts can send).
-- The list remembers the queue's share, so pressing it again leaves the list as it is.
function Queue:AddMissingToShopping()
    local short, changed = self:TrueShortages(), 0
    for _, it in ipairs(short) do
        if FP.Shop:SetFromQueue(it.itemID, it.need) then changed = changed + 1 end
    end
    FP.Shop:Open()
    if #short == 0 then
        FP:Print(L["No missing materials to add."])
    elseif changed == 0 then
        FP:Print(L["The shopping list already has everything the queue needs."])
    else
        FP:Print(L["Added %d item(s) to the shopping list."]:format(changed))
    end
end

function Queue:Update()
    if FP.UI.frame and FP.UI.frame:IsShown() then FP.UI:UpdateDetail() FP.UI:RefreshFooter() end
    FP.Transfer:QueueUpdate()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local busy = self.run and not self.run.ready
    f.craft.text:SetText(busy and L["Stop Queue"] or L["Craft Queue"])
    if not InCombatLockdown() then
        local canSkip = self.run and self.run.entry and true or false
        f.craft:SetAttribute("macrotext", busy and STOP_MACRO or "")
        f.stopCraft:SetAttribute("macrotext", busy and canSkip and STOP_MACRO or "")
        f.stopCraft:SetShown(canSkip)
    end
    local data = self:Data()
    local short, shortCount = self:EntryShortages(), 0
    for _ in pairs(short) do shortCount = shortCount + 1 end
    local inBank, bankCount = self:EntryBank(), 0
    for _ in pairs(inBank) do bankCount = bankCount + 1 end
    f.status:SetText(self.status or (shortCount > 0 and L["%d queued recipe(s) lack materials."]:format(shortCount))
        or (bankCount > 0 and L["%d queued recipe(s) need materials from the bank."]:format(bankCount)) or "")
    FauxScrollFrame_Update(f.scroll, #data, ROWS, ROW_H)
    f.rowEdge:SetBar(#data > ROWS)
    if f.scroll.fpEUISetRange then f.scroll:fpEUISetRange(math.max(0, #data - ROWS) * ROW_H) end
    local offset = FauxScrollFrame_GetOffset(f.scroll)
    f.empty:SetShown(#data == 0)
    for i, row in ipairs(f.rows) do
        local q = data[offset + i]
        if q then
            row.index = offset + i
            row.up:SetShown(row.index > 1)
            row.down:SetShown(row.index < #data)
            row.icon:SetTexture(q.icon)
            row.missing, row.fromBank = short[q], inBank[q]
            row.name:SetText(row.missing and WARN .. q.name or (row.fromBank and BANK_MARK .. q.name) or q.name)
            if not row.qty:HasFocus() then row.qty:SetText(q.qty) end
            row:Show()
        else
            row.index, row.missing, row.fromBank = nil, nil, nil
            row:Hide()
        end
    end
    local missing = #self:TrueShortages()
    f.add:SetActive(missing > 0)
    f.plan:SetActive(#data > 0)
end

-- A bare arrow that moves the row's entry by `delta` places; it fills half the row's height so the pair stacks flush.
local function MoveButton(row, delta)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(ROW_H / 2, ROW_H / 2)
    local tex = "Interface\\Buttons\\Arrow-" .. (delta < 0 and "Up" or "Down") .. "-Up"
    b:SetNormalTexture(tex)
    b:SetHighlightTexture(tex, "ADD")
    b:SetScript("OnClick", function() if row.index then Queue:Move(row.index, delta) end end)
    FP.UI:Tooltip(b, "ANCHOR_RIGHT", delta < 0 and L["Move Up"] or L["Move Down"])
    return b
end

function Queue:Create()
    local UI = FP.UI
    local f = CreateFrame("Frame", "ProfessionsForeverQueueFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:Hide() -- frames start shown, which would skip OnShow and leave unpopulated rows visible
    f:SetSize(400, 460)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    UI:Skin(f, "window")
    tinsert(UISpecialFrames, "ProfessionsForeverQueueFrame")
    UI.CloseInCombat(f)
    f:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_QUEST_LIST_OPEN)
        Queue:Update()
    end)
    f:SetScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_QUEST_LIST_CLOSE)
    end)
    UI:MakeSidePanelDraggable(f, "queue")

    local title = UI:Text(f, 2)
    title:SetPoint("LEFT", f, "TOPLEFT", 12, -UI.TITLE_H / 2)
    title:SetText(L["Crafting Queue"])
    title:SetTextColor(1, 0.82, 0)
    local close = UI:Button(f, "X", 22, 20, function() f:Hide() end)
    close:SetPoint("RIGHT", f, "TOPRIGHT", -6, -UI.TITLE_H / 2)
    UI:AddPinButton(f, close)

    local scroll = CreateFrame("ScrollFrame", "ProfessionsForeverQueueScroll", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -40)
    scroll:SetPoint("BOTTOMRIGHT", -30, 100)
    scroll:SetScript("OnVerticalScroll", function(s, offset)
        FauxScrollFrame_OnVerticalScroll(s, offset, ROW_H, function() Queue:Update() end)
    end)
    f.scroll = scroll
    local scrollBar = scroll.ScrollBar or _G["ProfessionsForeverQueueScrollScrollBar"]
    if not UI:AttachEUIThinScrollbar(scroll, scrollBar, f, { top = 40, bottom = 100 }) then
        UI:EUIWidget(scrollBar, "scrollbar")
    end

    f.rowEdge = UI:RowEdge(f, 30, 8)
    f.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -40 - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", f.rowEdge, "TOPRIGHT", 0, -40 - (i - 1) * ROW_H)
        row:SetScript("OnClick", function()
            local q = row.index and Queue:Data()[row.index]
            if q then UI.LinkToChat(C_TradeSkillUI.GetRecipeLink(q.id)) end
        end)
        row:SetScript("OnEnter", function(s)
            if not (s.missing or s.fromBank) then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            if s.missing then
                GameTooltip:AddLine(L["Missing materials:"], 1, 1, 1)
                for _, m in ipairs(s.missing) do
                    GameTooltip:AddDoubleLine(UI.ItemName(m.itemID), m.qty, 1, 1, 1, MISSING[1], MISSING[2], MISSING[3])
                end
            end
            if s.fromBank then
                GameTooltip:AddLine(L["Needs from the bank:"], 1, 1, 1)
                for _, m in ipairs(s.fromBank) do
                    GameTooltip:AddDoubleLine(UI.ItemName(m.itemID), m.qty, 1, 1, 1, BANK[1], BANK[2], BANK[3])
                end
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ROW_H - 6, ROW_H - 6)
        row.icon:SetPoint("LEFT", 24, 0)
        row.up = MoveButton(row, -1)
        row.up:SetPoint("BOTTOMRIGHT", row.icon, "LEFT", -4, 0)
        row.down = MoveButton(row, 1)
        row.down:SetPoint("TOPRIGHT", row.icon, "LEFT", -4, 0)
        local rm = UI:Button(row, "x", 18, 18, function() if row.index then Queue:Remove(row.index) end end)
        rm:SetPoint("RIGHT", -2, 0)
        row.qty = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        row.qty:SetSize(36, 20)
        row.qty:SetPoint("RIGHT", rm, "LEFT", -32, 0)
        UI:EUIWidget(row.qty, "numbox")
        row.qty:SetAutoFocus(false)
        row.qty:SetNumeric(true)
        row.qty:SetMaxLetters(3)
        row.qty:SetScript("OnTextChanged", function(s, user)
            local q = user and row.index and Queue:Data()[row.index]
            if q then
                q.qty = math.max(1, tonumber(s:GetText()) or 1)
                Queue:Update()
            end
        end)
        row.qty:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        row.qty:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
        UI:Stepper(row.qty, 1, 999, function(v)
            local q = row.index and Queue:Data()[row.index]
            if q then q.qty = v Queue:Update() end
        end)
        row.name = UI:Text(row, 0)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.name:SetPoint("RIGHT", row.qty.minus, "LEFT", -6, 0)
        row.name:SetWordWrap(false)
        f.rows[i] = row
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        if scroll.fpEUIScrollTo then
            scroll.fpEUIScrollTo(scroll:GetVerticalScroll() - delta * ROW_H * 3)
        elseif scrollBar then
            scrollBar:SetValue(scrollBar:GetValue() - delta * ROW_H * 3)
        end
    end)

    f.empty = UI:Text(f, 0, "CENTER")
    f.empty:SetPoint("CENTER", 0, 20)
    f.empty:SetText(L["Crafting queue is empty"])

    f.add = UI:Button(f, L["Add Missing to Shopping List"], 220, 24, function() Queue:AddMissingToShopping() end)
    UI:Tooltip(f.add, "ANCHOR_TOP", function(tip)
        if f.add:IsEnabled() then return false end
        tip:AddLine(L["No missing materials to add."], 1, 1, 1, true)
    end)
    f.add:SetPoint("BOTTOMLEFT", 14, 46)
    f.plan = UI:Button(f, L["Plan Materials"], 146, 24, function() FP.Transfer:Open() end)
    f.plan:SetPoint("LEFT", f.add, "RIGHT", 6, 0)
    local clear = UI:Button(f, L["Clear Queue"], 110, 24, function() Queue:Clear() end)
    clear:SetPoint("BOTTOMLEFT", 14, 14)
    f.craft = UI:Button(f, L["Craft Queue"], 130, 24, function() Queue:ToggleRun() end, true)
    f.craft:SetPoint("LEFT", clear, "RIGHT", 6, 0)
    f.stopCraft = UI:Button(f, L["Stop Craft"], 110, 24, function() Queue:SkipCurrent() end, true)
    f.stopCraft:SetPoint("BOTTOMLEFT", f.craft, "BOTTOMRIGHT", 6, 0)
    f.stopCraft:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
    f.stopCraft:Hide()
    f.status = UI:Text(f, -1)
    f.status:SetPoint("BOTTOMLEFT", 14, 80)
    f.status:SetPoint("RIGHT", -14, 0)
    f.status:SetWordWrap(false)

    -- Own frame above the rows, so the list can't cover it; it never takes the mouse.
    local notice = CreateFrame("Frame", nil, f, "BackdropTemplate")
    notice:SetPoint("BOTTOMLEFT", 14, 104)
    notice:SetPoint("BOTTOMRIGHT", -14, 104)
    notice:SetHeight(44)
    notice:SetFrameLevel(f:GetFrameLevel() + 20)
    UI:Skin(notice, "button")
    notice:SetBackdropBorderColor(1, 0.82, 0, 1)
    notice.text = UI:Text(notice, 1, "CENTER")
    notice.text:SetPoint("LEFT", 8, 0)
    notice.text:SetPoint("RIGHT", -8, 0)
    notice.text:SetTextColor(1, 0.82, 0)
    notice.text:SetText(L["Profession window changed. Click Craft Queue again."])
    notice.anim = notice:CreateAnimationGroup()
    local fade = notice.anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(3)
    fade:SetDuration(4)
    notice.anim:SetScript("OnFinished", function() notice:Hide() end)
    notice:Hide()
    f.notice = notice
end

function Queue:ShowNotice()
    local n = self.frame and self.frame.notice
    if not n then return end
    n.anim:Stop()
    n:SetAlpha(1)
    n:Show()
    n.anim:Play()
end

function Queue:HideNotice()
    local n = self.frame and self.frame.notice
    if not n then return end
    n.anim:Stop()
    n:Hide()
end

---------------------------------------------------------------------------
-- Crafting runner. Each entry is crafted in turn, opening its profession when needed.
-- Opening a profession and CraftRecipe both need a hardware event, so they only run from a Craft Queue
-- click; when the runner gets ahead of the player (profession opened, batch done) it waits in the "ready" state.
---------------------------------------------------------------------------
local WATCHDOG = 6

function Queue:CurrentSkillLine()
    local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    if not base then return nil end
    for _, p in ipairs(FP:GetProfessions()) do
        if base.professionID == p.skillLine or base.professionName == p.name then
            return p.skillLine
        end
    end
end

function Queue:IsOpen(q)
    local T = C_TradeSkillUI
    return T.IsTradeSkillReady and T.IsTradeSkillReady() and self:CurrentSkillLine() == q.skillLine
end

local function CraftsFromBags(q)
    local n = math.huge
    for _, r in ipairs(q.reagents) do
        local bags = FP.Inv:Owned(r.itemID)
        n = math.min(n, math.floor(bags / r.qty))
    end
    return n == math.huge and 0 or math.min(n, q.qty)
end

function Queue:SetStatus(text)
    self.status = text
    self:Update()
end

function Queue:Stop(msg)
    self.run = nil
    self.token = (self.token or 0) + 1
    self:HideNotice()
    self:SetStatus(msg)
    if msg and msg ~= "" then FP:Print(msg) end
end

function Queue:Arm()
    self.token = (self.token or 0) + 1
    local token = self.token
    C_Timer.After(WATCHDOG, function()
        if self.run and self.token == token and not UnitCastingInfo("player") then
            self:Stop(L["Crafting did not start. Click Craft Queue to continue."])
        end
    end)
end

function Queue:NextEntry()
    for _, q in ipairs(self:Data()) do
        if not self.skip[q] then
            if not q.skillLine then
                self.skip[q] = true
            elseif FP.Cooldowns:IsOnCooldown(q.id) then
                self.skip[q] = true
                self.cooling = self.cooling + 1
            elseif self:IsOpen(q) and #FP.Tools:Missing(q.id) > 0 then
                -- Only the open profession's requirements can be read, so this waits for the profession to be opened.
                self.skip[q] = true
                self.noTools = self.noTools + 1
                FP:Print(L["Skipping %s: missing %s."]:format(q.name, table.concat(FP.Tools:Missing(q.id), ", ")))
            elseif CraftsFromBags(q) > 0 then
                return q
            else
                self.skip[q] = true
                self.skipped = self.skipped + 1
            end
        end
    end
end

-- `fromClick`: called inside a Craft Queue click. Opening a profession and crafting both need one.
function Queue:Step(fromClick)
    if not self.run then return end
    if InCombatLockdown() then return self:Stop(L["Cannot do that in combat."]) end
    local q = self:NextEntry()
    if not q then
        local msg = L["Queue finished."]
        if self.skipped > 0 then msg = msg .. " " .. L["%d entries skipped (missing materials)."]:format(self.skipped) end
        if self.cooling > 0 then msg = msg .. " " .. L["%d entries skipped (on cooldown)."]:format(self.cooling) end
        if self.noTools > 0 then msg = msg .. " " .. L["%d entries skipped (missing tools)."]:format(self.noTools) end
        return self:Stop(msg)
    end
    if not fromClick then return self:Ready(q) end
    if not self:IsOpen(q) then
        self.run = { entry = q, waiting = true }
        self:SetStatus(L["Opening profession for %s..."]:format(q.name))
        FP:OpenProfession(q.skillLine)
        return self:Arm()
    end
    self:StartCraft(q)
end

-- `changed`: the profession window was just switched, so the player must click again.
function Queue:Ready(q, changed)
    self.token = (self.token or 0) + 1 -- disarm the watchdog: nothing is expected to cast now
    self.run = { entry = q, ready = true }
    local fmt = self:IsOpen(q) and L["Click Craft Queue to craft %s."] or L["Click Craft Queue to open the profession for %s."]
    self:SetStatus(fmt:format(q.name))
    if changed then self:ShowNotice() end
end

function Queue:StartCraft(q)
    local n = CraftsFromBags(q)
    if FP.Cooldowns:IsTracked(q.id) then n = math.min(n, 1) end -- a cooldown allows one craft
    if n < 1 then return self:Step(true) end
    local ok, err = pcall(C_TradeSkillUI.CraftRecipe, q.id, n)
    if not ok then return self:Stop(tostring(err)) end
    self.run = { entry = q, batch = n, made = 0 }
    self:SetStatus(L["Crafting %dx %s"]:format(n, q.name))
    self:Arm()
end

local function CreditOne(entry)
    local data = Queue:Data()
    for i, q in ipairs(data) do
        if q == entry then
            FP.Shop:CreditCraft(q.reagents)
            q.qty = q.qty - 1
            if q.qty <= 0 then table.remove(data, i) end
            return
        end
    end
end

-- Hands off to the next entry shortly after the current one ends.
local function Advance()
    if Queue.run and Queue.run.advancing then
        Queue.run = {}
        Queue:Step()
    end
end

-- Crafts of an interrupted batch that are still in flight keep being credited for a while.
local function KeepTail(run)
    if not (run.batch and run.made < run.batch) then return end
    Queue.tail = run
    C_Timer.After(30, function() if Queue.tail == run then Queue.tail = nil end end)
end

function Queue:FinishBatch()
    if not self.run then return end
    self.run = { advancing = true }
    self:Update()
    C_Timer.After(0.5, Advance)
end

-- The buttons are secure and run /stopcasting while a run is active, since addons can't cancel casts
-- directly. Crafts still in flight afterwards keep being credited via `tail`.
function Queue:SkipCurrent()
    local run = self.run
    if not (run and run.entry) then return end
    self.skip[run.entry] = true
    KeepTail(run)
    self.run = { advancing = true }
    self.token = (self.token or 0) + 1
    self:SetStatus(L["Skipping to the next recipe..."])
    C_Timer.After(0.5, Advance)
end

function Queue:ToggleRun()
    local run = self.run
    if run and run.ready then
        self:HideNotice()
        return self:Step(true)
    end
    if run then
        KeepTail(run)
        return self:Stop(L["Queue stopped."])
    end
    if #self:Data() == 0 then return end
    self.skip, self.skipped, self.cooling, self.noTools, self.run = {}, 0, 0, 0, {}
    self:Step(true)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit, second, spellID)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if unit ~= "ProfessionsForever" then return end
        return FP:Print(("%s: %s tried %s"):format(event, unit, tostring(second)))
    end
    local tail = Queue.tail
    if tail and not (Queue.run and Queue.run.batch) and event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" and spellID == tail.entry.id then
        tail.made = tail.made + 1
        CreditOne(tail.entry)
        if tail.made >= tail.batch then Queue.tail = nil end
        Queue:Update()
        return
    end
    local run = Queue.run
    if not run then return end
    if event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_SHOW" then
        if run.waiting and Queue:IsOpen(run.entry) then
            C_Timer.After(0.2, function()
                if Queue.run == run and Queue:IsOpen(run.entry) then Queue:Ready(run.entry, true) end
            end)
            run.waiting = false
        end
    elseif unit == "player" and run.batch then
        if event == "UNIT_SPELLCAST_SUCCEEDED" and spellID == run.entry.id then
            run.made = run.made + 1
            CreditOne(run.entry)
            if run.made >= run.batch then Queue:FinishBatch() else Queue:Arm() Queue:Update() end
        elseif event ~= "UNIT_SPELLCAST_SUCCEEDED" and spellID == run.entry.id then
            Queue:Stop(L["Crafting interrupted."])
        end
    end
end)
ev:RegisterEvent("ADDON_ACTION_BLOCKED")
ev:RegisterEvent("ADDON_ACTION_FORBIDDEN")
pcall(ev.RegisterEvent, ev, "TRADE_SKILL_LIST_UPDATE")
pcall(ev.RegisterEvent, ev, "TRADE_SKILL_SHOW")
for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
    pcall(ev.RegisterUnitEvent, ev, e, "player")
end

function Queue:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Open() end
end
