-- Version line at login, and an alert when a newer release exists.
--
-- Addons can't reach the internet, so the only way to hear of a newer release is from other players. Every copy
-- quietly announces its version to guild, party, raid and instance chat over the hidden addon-message channel; a copy
-- that hears an older version answers with its own. Hearing a higher version prints the alert once a session, and at
-- each login while that version was heard in the last few days (FP.db.newestSeenVersion / newestSeenAt), so a test
-- build heard once doesn't nag forever.
local addonName, FP = ...
local L = FP.L

local PREFIX = "ProfForeverVer"
local VERSION = C_AddOns.GetAddOnMetadata(addonName, "Version")
local SEND_THROTTLE = 10 -- seconds between broadcasts on the same channel
local REMEMBER_FOR = 3 * 24 * 60 * 60 -- seconds a heard version keeps the login alert going
local CHANNELS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

local notified = false
local lastSent, pendingReply = {}, {}
local lastGroupSize = 0

-- "1.4.3" -> { 1, 4, 3 } ("1.4" -> { 1, 4, 0 }). Anything else is rejected, so a malformed or hostile message can never
-- trigger the alert.
local function Parse(text)
    if type(text) ~= "string" or #text > 16 then return nil end
    local a, b, c = text:match("^(%d+)%.(%d+)%.(%d+)$")
    if not a then
        a, b = text:match("^(%d+)%.(%d+)$")
        c = "0"
    end
    if not a then return nil end
    return { tonumber(a), tonumber(b), tonumber(c) }
end

local function IsNewer(x, y)
    for i = 1, 3 do
        if x[i] ~= y[i] then return x[i] > y[i] end
    end
    return false
end

local MINE = Parse(VERSION)

local function Notify(newer)
    if notified or not FP.db.updateNotice then return end
    notified = true
    FP:Print(L["Version %s is available (you have %s). Update on CurseForge."]:format(newer, VERSION))
end

local function Send(channel)
    local now = GetTime()
    if lastSent[channel] and now - lastSent[channel] < SEND_THROTTLE then return end
    lastSent[channel] = now
    C_ChatInfo.SendAddonMessage(PREFIX, VERSION, channel)
end

local function Broadcast()
    if IsInGuild() then Send("GUILD") end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then Send("INSTANCE_CHAT") end
    if IsInRaid(LE_PARTY_CATEGORY_HOME) then
        Send("RAID")
    elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
        Send("PARTY")
    end
end

-- Someone on this channel runs an older copy: answer after a short random delay so it learns of this one. Dropped if
-- another player answers first, which keeps a big guild quiet.
local function ScheduleReply(channel)
    if pendingReply[channel] then return end
    pendingReply[channel] = true
    C_Timer.After(1 + math.random() * 4, function()
        if pendingReply[channel] then
            pendingReply[channel] = nil
            Send(channel)
        end
    end)
end

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

local function OnAddonMessage(self, prefix, text, channel)
    if prefix ~= PREFIX then return end
    local theirs = Parse(text)
    if not theirs then return end
    if IsNewer(MINE, theirs) then
        if CHANNELS[channel] then ScheduleReply(channel) end
        return
    end
    pendingReply[channel] = nil -- same or newer heard here: no reply needed from this copy
    if not IsNewer(theirs, MINE) then return end
    local db = self.db
    local known = Parse(db.newestSeenVersion)
    if not known or not IsNewer(known, theirs) then -- a newer one than before, or the same one heard again
        db.newestSeenVersion, db.newestSeenAt = text, time()
    end
    Notify(text)
end
FP:RegisterEvent("CHAT_MSG_ADDON", OnAddonMessage)

--@debug@
-- For /pf debug vernew and verold (Core/Debug.lua): hear a version as if a player had sent it. Addon whispers to
-- yourself can't be used, since Forever names have a space and the whisper target stops at it.
function FP.HearVersion(text) OnAddonMessage(FP, PREFIX, text, "DEBUG") end
--@end-debug@

FP:RegisterEvent("PLAYER_LOGIN", function(self)
    lastGroupSize = GetNumGroupMembers()
    C_Timer.After(5, function() -- after the loading screen, so the lines aren't lost
        local db = self.db
        if db.versionNotice then
            self:Print(L["Version %s loaded. Type /pf to open."]:format(VERSION))
        end
        local known = Parse(db.newestSeenVersion)
        if known and IsNewer(known, MINE) and time() - db.newestSeenAt < REMEMBER_FOR then
            Notify(db.newestSeenVersion)
        else
            db.newestSeenVersion, db.newestSeenAt = nil, nil
        end
        Broadcast()
    end)
end)

FP:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    local size = GetNumGroupMembers()
    if size > lastGroupSize then Broadcast() end
    lastGroupSize = size
end)
