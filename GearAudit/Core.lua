-- GearAudit: Core.lua
-- Group roster, inspect queue, and cached audit results.
--
-- Why inspecting is slow on purpose (v1.4.0):
-- A first inspect of a player often returns only 1-2 item
-- links: the rest of their gear simply has not arrived /
-- been cached yet when INSPECT_READY first fires. The old
-- code audited instantly, treated every nil link as an
-- empty slot, and published that partial audit as final --
-- so the overview showed a bad average from 1-2 items.
-- A single re-inspect "fixed" it only because the items
-- were cached by then.
-- The new flow never publishes a partial audit:
--   * wait 0.4s after INSPECT_READY before auditing, so
--     late-arriving gear data is in;
--   * if fewer than 14 slots have links, re-inspect after
--     0.8s and MERGE the new audit into the old one slot
--     by slot (never overwrite a found slot with empty);
--   * stop retrying when the merged audit is complete
--     (>=14 links: 15 is a full set for a two-handed
--     user, 16 for dual-wield/shield), when a retry adds
--     nothing (the player genuinely has fewer items),
--     or after 3 retries, and publish the best merged
--     result found;
--   * leave 0.6s between finishing one player and
--     inspecting the next, so the server's inspect
--     throttle does not silently drop requests.
-- A full 5-man refresh now takes a few seconds longer,
-- but the overview is no longer built on 1-2 items.
local _, GA = ...

GA.data = {}          -- unit -> audit summary (see Audit.lua)
GA.inspectQueue = {}  -- units waiting to be inspected
GA.inspecting = nil   -- unit currently being inspected
GA.inspectDeadline = 0

-- Per-inspect session state, reset on every Refresh.
GA.inspectSession = 0
GA.inspectAttempt = 0
GA.inspectPending = nil
GA.inspectPendingLinks = 0
GA.auditScheduled = false

-- Auto-scan roster tracking (v1.5.0): GUIDs seen on the last
-- roster check. A GUID not in this set is a new joiner.
GA.lastRoster = {}
GA.autoScanPending = false
GA.pendingAutoUnits = {}

-- A geared player has 15-16 equipped slots in GA.SLOTS
-- (16 slots, minus an empty off-hand for two-handed users).
-- 14 is the completeness bar: it accepts a player missing
-- one ring/trinket, but never a 1-2 item partial audit.
local COMPLETE_LINKS = 14
local MAX_RETRIES = 3
local READY_DELAY = 0.4
local RETRY_DELAY = 0.8
local BETWEEN_DELAY = 0.6
local INSPECT_TIMEOUT = 8

local function GetGroupUnits()
    local units = {}
    local numMembers = 0
    if GetNumGroupMembers then
        numMembers = GetNumGroupMembers() or 0
    end
    if IsInRaid and IsInRaid() then
        for i = 1, numMembers do
            units[#units + 1] = "raid" .. i
        end
    elseif IsInGroup and IsInGroup() then
        units[#units + 1] = "player"
        for i = 1, numMembers - 1 do
            units[#units + 1] = "party" .. i
        end
    else
        units[#units + 1] = "player"
    end
    return units
end
GA.GetGroupUnits = GetGroupUnits

local function UnitDisplayName(unit)
    if not UnitName then return unit end
    local name, realm = UnitName(unit)
    if not name then return unit end
    local myRealm = ""
    if GetRealmName then myRealm = GetRealmName() or "" end
    if realm and realm ~= "" and realm ~= myRealm then
        return name .. "-" .. realm
    end
    return name
end
GA.UnitDisplayName = UnitDisplayName

local function CallHook(name, ...)
    local fn = GA[name]
    if type(fn) == "function" then
        fn(...)
    end
end
GA.CallHook = CallHook

local function ClearInspect()
    if ClearInspectPlayer then
        ClearInspectPlayer()
    end
end

local function Now()
    return (GetTime and GetTime()) or 0
end

-- Run fn after delay, unless a newer Refresh has started
-- in the meantime (session check) or the inspect moved on.
local function After(delay, session, unit, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function()
            if session == GA.inspectSession and (unit == nil or GA.inspecting == unit) then
                fn()
            end
        end)
    else
        fn()
    end
end

local function RequestInspect(unit)
    GA.inspecting = unit
    GA.inspectDeadline = Now() + INSPECT_TIMEOUT
    GA.auditScheduled = false
    NotifyInspect(unit)
end

-- Publish a finished audit and move to the next unit,
-- paced so the server throttle does not drop the next
-- request. Queue-empty is the only finished state.
local function FinishUnit(unit, audit)
    if audit then
        GA.data[unit] = audit
        CallHook("OnUnitAudited", unit)
    end
    ClearInspect()
    GA.inspecting = nil
    GA.inspectPending = nil
    GA.auditScheduled = false
    if #GA.inspectQueue == 0 then
        CallHook("OnInspectFinished")
        return
    end
    local session = GA.inspectSession
    After(BETWEEN_DELAY, session, nil, function()
        -- After() with unit=nil skips the inspecting check
        -- above, so re-check here: only advance if nothing
        -- else started inspecting in the meantime.
        if GA.inspecting == nil then
            GA.InspectNext()
        end
    end)
end

-- Audit the inspected unit, merging into any partial audit
-- already collected, and decide whether to retry.
local function TryAudit(unit)
    GA.auditScheduled = false
    if GA.inspecting ~= unit then return end
    local audit = GA.AuditUnit(unit)
    local beforeLinks = GA.inspectPendingLinks
    GA.inspectPending = GA.MergeAudits(GA.inspectPending, audit)
    local links = GA.inspectPending and GA.inspectPending.linkCount or 0
    GA.inspectPendingLinks = links

    if links >= COMPLETE_LINKS then
        FinishUnit(unit, GA.inspectPending)
    elseif GA.inspectAttempt >= MAX_RETRIES then
        FinishUnit(unit, GA.inspectPending)
    elseif GA.inspectAttempt > 0 and links <= beforeLinks then
        -- A retry added nothing: the player genuinely has
        -- this few items. Publish the best result, do not
        -- loop forever chasing slots that do not exist.
        FinishUnit(unit, GA.inspectPending)
    else
        GA.inspectAttempt = GA.inspectAttempt + 1
        ClearInspect()
        local session = GA.inspectSession
        After(RETRY_DELAY, session, unit, function()
            RequestInspect(unit)
        end)
    end
end

-- Inspect the next unit in the queue, or finish the queue.
local function InspectNext()
    GA.inspecting = nil
    local unit = table.remove(GA.inspectQueue, 1)
    if not unit then
        CallHook("OnInspectFinished")
        return
    end
    if not UnitExists or not UnitExists(unit) or not UnitIsPlayer or not UnitIsPlayer(unit) then
        InspectNext()
        return
    end
    if unit == "player" then
        -- Your own gear needs no inspect round-trip.
        GA.data[unit] = GA.AuditUnit(unit)
        CallHook("OnUnitAudited", unit)
        InspectNext()
        return
    end
    if CanInspect and not CanInspect(unit) then
        GA.data[unit] = { notInspectable = true, reason = "Out of range" }
        CallHook("OnUnitAudited", unit)
        InspectNext()
        return
    end
    if not NotifyInspect then
        GA.data[unit] = { notInspectable = true, reason = "Inspect API unavailable" }
        CallHook("OnUnitAudited", unit)
        InspectNext()
        return
    end
    GA.inspectAttempt = 0
    GA.inspectPending = nil
    GA.inspectPendingLinks = 0
    RequestInspect(unit)
    -- INSPECT_READY (or the timeout in OnUpdate) advances
    -- the queue, via TryAudit.
end
GA.InspectNext = InspectNext

function GA.RefreshAll()
    GA.inspectSession = GA.inspectSession + 1
    GA.inspectQueue = {}
    GA.inspecting = nil
    GA.inspectPending = nil
    GA.auditScheduled = false
    local units = GetGroupUnits()
    for _, unit in ipairs(units) do
        if UnitExists and UnitExists(unit) and UnitIsPlayer and UnitIsPlayer(unit) then
            GA.inspectQueue[#GA.inspectQueue + 1] = unit
        end
    end
    CallHook("OnRefreshStarted", #GA.inspectQueue)
    InspectNext()
end

function GA.RefreshUnit(unit)
    if not UnitExists or not UnitExists(unit) then return end
    GA.inspectSession = GA.inspectSession + 1
    GA.inspectQueue = { unit }
    GA.inspecting = nil
    GA.inspectPending = nil
    GA.auditScheduled = false
    InspectNext()
end

-- Queue units for inspection without interrupting a scan
-- already in progress: new units are appended, and if
-- nothing is inspecting right now the queue starts at once.
-- A pacing timer already scheduled by FinishUnit is safe:
-- its callback checks inspecting == nil before advancing,
-- so it will not double-start a unit QueueUnits started.
function GA.QueueUnits(units)
    for _, unit in ipairs(units) do
        if UnitExists and UnitExists(unit) and UnitIsPlayer and UnitIsPlayer(unit) then
            local already = (GA.inspecting == unit)
            if not already then
                for _, queued in ipairs(GA.inspectQueue) do
                    if queued == unit then already = true; break end
                end
            end
            if not already then
                GA.inspectQueue[#GA.inspectQueue + 1] = unit
            end
        end
    end
    if GA.inspecting == nil and #GA.inspectQueue > 0 then
        InspectNext()
    end
end

-- Auto-scan: called on roster changes and on entering the
-- world. Only units whose GUID was not in the last roster
-- are new, so a reshuffle or a role change does not rescan
-- the whole group -- only genuine joiners get inspected,
-- and their data is already cached by the time you open
-- the window. In combat, inspecting is deferred until
-- PLAYER_REGEN_ENABLED instead of being dropped.
function GA.CheckRosterForNewPlayers()
    local units = GetGroupUnits()
    local current = {}
    local unitByGuid = {}
    for _, unit in ipairs(units) do
        local guid = (UnitGUID and UnitGUID(unit)) or unit
        current[guid] = true
        unitByGuid[guid] = unit
    end
    local newUnits = {}
    for guid, unit in pairs(unitByGuid) do
        if not GA.lastRoster[guid] then
            newUnits[#newUnits + 1] = unit
        end
    end
    GA.lastRoster = current
    if #newUnits == 0 then return end
    table.sort(newUnits, function(a, b)
        if a == "player" then return true end
        if b == "player" then return false end
        return a < b
    end)
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        GA.autoScanPending = true
        for _, unit in ipairs(newUnits) do
            GA.pendingAutoUnits[#GA.pendingAutoUnits + 1] = unit
        end
        return
    end
    GA.QueueUnits(newUnits)
end

-- Event frame: roster changes, inspect results, inspect timeout.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("INSPECT_READY")
events:RegisterEvent("PLAYER_REGEN_ENABLED")

events:SetScript("OnEvent", function(_, event, guid)
    if event == "INSPECT_READY" then
        if GA.inspecting and UnitGUID and UnitGUID(GA.inspecting) == guid and not GA.auditScheduled then
            -- Do not audit instantly: gear data is still
            -- arriving when this first fires. A short delay
            -- is what turns a 1-2 item audit into a full one.
            GA.auditScheduled = true
            local unit = GA.inspecting
            local session = GA.inspectSession
            After(READY_DELAY, session, unit, function()
                TryAudit(unit)
            end)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        local stillHere = {}
        for _, unit in ipairs(GetGroupUnits()) do
            local guidForUnit = (UnitGUID and UnitGUID(unit)) or unit
            stillHere[guidForUnit] = true
        end
        for unit, _ in pairs(GA.data) do
            local guidForUnit = (UnitGUID and UnitExists and UnitExists(unit) and UnitGUID(unit)) or unit
            if UnitExists and UnitExists(unit) and not stillHere[guidForUnit] then
                GA.data[unit] = nil
            end
        end
        CallHook("OnRosterChanged")
        -- Auto-scan genuine joiners (no rescan for the rest).
        GA.CheckRosterForNewPlayers()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Covers logging in / reloading already in a group:
        -- the roster update that follows would catch the
        -- same players, but this makes the first check early.
        GA.CheckRosterForNewPlayers()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if GA.autoScanPending then
            GA.autoScanPending = false
            local units = GA.pendingAutoUnits
            GA.pendingAutoUnits = {}
            -- Only queue players still in the group.
            local stillHere = {}
            for _, unit in ipairs(GetGroupUnits()) do
                local guid = (UnitGUID and UnitGUID(unit)) or unit
                stillHere[guid] = true
            end
            local filtered = {}
            for _, unit in ipairs(units) do
                local guid = (UnitGUID and UnitGUID(unit)) or unit
                if stillHere[guid] then
                    filtered[#filtered + 1] = unit
                end
            end
            GA.QueueUnits(filtered)
        end
    end
end)

events:SetScript("OnUpdate", function()
    if GA.inspecting and GetTime and Now() > GA.inspectDeadline then
        -- Inspect timed out (target moved out of range, left,
        -- or the server never answered, including throttle).
        if GA.inspectAttempt < MAX_RETRIES then
            -- One more try before giving up on this player.
            GA.inspectAttempt = GA.inspectAttempt + 1
            ClearInspect()
            RequestInspect(GA.inspecting)
        else
            local unit = GA.inspecting
            if GA.inspectPending and GA.inspectPending.linkCount > 0 then
                FinishUnit(unit, GA.inspectPending)
            else
                GA.data[unit] = { notInspectable = true, reason = "Inspect timed out" }
                CallHook("OnUnitAudited", unit)
                ClearInspect()
                GA.inspecting = nil
                GA.inspectPending = nil
                GA.auditScheduled = false
                if #GA.inspectQueue == 0 then
                    CallHook("OnInspectFinished")
                else
                    GA.InspectNext()
                end
            end
        end
    end
end)

SLASH_GEARAUDIT1 = "/gearaudit"
SLASH_GEARAUDIT2 = "/ga"
SLASH_GEARAUDIT3 = "/gear"
SlashCmdList["GEARAUDIT"] = function(msg)
    msg = (msg or ""):lower()
    if strtrim then
        msg = strtrim(msg)
    else
        msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
    end
    if msg == "refresh" then
        GA.ToggleWindow(true)
        GA.RefreshAll()
    elseif msg == "hide" then
        GA.ToggleWindow(false)
    else
        GA.ToggleWindow()
    end
end
