-- GearAudit: Audit.lua
-- Pure gear-parsing helpers. No UI code lives here, so the audit
-- rules are easy to review and change for a new expansion.
local _, GA = ...

-- Slot IDs used by GetInventoryItemLink. These are WoW's fixed
-- inventory slot numbers, NOT paper-doll display order: slot 4
-- is a shirt and slot 19 is a tabard, so both are left out.
-- Correct mapping: 5 Chest, 6 Waist, 7 Legs, 8 Feet, 9 Wrist,
-- 10 Hands, 11 Finger 1, 12 Finger 2, 13 Trinket 1,
-- 14 Trinket 2, 15 Back, 16 Main Hand, 17 Off Hand.
GA.SLOTS = {
    { id = 1,  name = "Head" },
    { id = 2,  name = "Neck" },
    { id = 3,  name = "Shoulder" },
    { id = 5,  name = "Chest" },
    { id = 6,  name = "Waist" },
    { id = 7,  name = "Legs" },
    { id = 8,  name = "Feet" },
    { id = 9,  name = "Wrist" },
    { id = 10, name = "Hands" },
    { id = 11, name = "Finger 1" },
    { id = 12, name = "Finger 2" },
    { id = 13, name = "Trinket 1" },
    { id = 14, name = "Trinket 2" },
    { id = 15, name = "Back" },
    { id = 16, name = "Main Hand" },
    { id = 17, name = "Off Hand" },
}

-- Slots that can currently take an enchant in retail WoW.
-- This list is deliberately conservative: a slot that is not
-- listed here is never flagged as "missing an enchant", so the
-- audit does not produce false positives when an expansion
-- removes an enchant slot. Update it if Blizzard changes this.
-- Waist, Hands and Trinkets take no enchant and are NOT here.
GA.ENCHANTABLE_SLOTS = {
    [5] = true,   -- Chest
    [7] = true,   -- Legs
    [8] = true,   -- Feet
    [9] = true,   -- Wrist
    [11] = true,  -- Finger 1
    [12] = true,  -- Finger 2
    [15] = true,  -- Back
    [16] = true,  -- Main Hand
    [17] = true,  -- Off Hand (weapon / shield only, checked below)
}

-- Safe item-info lookup for modern retail.
-- The old global GetItemInfo() was removed in Midnight (12.x):
-- calling it is "attempt to call a nil value". The replacement
-- is C_Item.GetItemInfo(), which returns the same fields in
-- the same order. Use this helper everywhere instead of
-- calling either one directly, so a missing API can never
-- crash the audit -- it just returns nil.
function GA.GetItemInfo(link)
    local unpackFn = unpack or table.unpack
    if C_Item and C_Item.GetItemInfo then
        local results = { pcall(C_Item.GetItemInfo, link) }
        if results[1] then
            return unpackFn(results, 2)
        end
        return nil
    end
    if GetItemInfo then
        return GetItemInfo(link)
    end
    return nil
end

-- Quality colour for Midnight: the old global
-- GetItemQualityColor() became C_Item.GetItemQualityColor().
-- Returns r, g, b in 0-1, or white if nothing is available.
function GA.GetItemQualityColor(quality)
    if quality == nil then return 1, 1, 1 end
    if C_Item and C_Item.GetItemQualityColor then
        local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
        if ok then
            -- Some builds return a colour object instead of numbers.
            if type(r) == "table" and r.GetRGB then
                return r:GetRGB()
            end
            if type(r) == "number" then
                return r, g or 1, b or 1
            end
        end
    end
    if GetItemQualityColor then
        local ok, r, g, b = pcall(GetItemQualityColor, quality)
        if ok and type(r) == "number" then
            return r, g, b
        end
    end
    if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local c = ITEM_QUALITY_COLORS[quality]
        if c.GetRGB then return c:GetRGB() end
        if type(c.r) == "number" then return c.r, c.g, c.b end
    end
    return 1, 1, 1
end

-- Class colour for Midnight: prefer C_ClassColor, fall back
-- to the classic RAID_CLASS_COLORS table, then white.
function GA.GetClassColor(classFile)
    if classFile and C_ClassColor and C_ClassColor.GetClassColor then
        local ok, color = pcall(C_ClassColor.GetClassColor, classFile)
        if ok and color then
            if color.GetRGB then
                local r, g, b = color:GetRGB()
                return { r = r, g = g, b = b }
            end
            if type(color.r) == "number" then
                return { r = color.r, g = color.g, b = color.b }
            end
        end
    end
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        return RAID_CLASS_COLORS[classFile]
    end
    return { r = 1, g = 1, b = 1 }
end

-- An item link looks like:
--   |cffa335ee|Hitem:12345:6789:111:222:0:0:0:0:0:0:0|h[Name]|h|r
-- Field 1 is the item ID, field 2 is the enchant ID, and the
-- next fields are gem IDs. Split on ":" and read those fields.
function GA.ParseItemLink(link)
    if not link then return nil end
    local itemString = link:match("item:([^|]+)")
    if not itemString then return nil end
    local parts
    if strsplit then
        parts = { strsplit(":", itemString) }
    else
        -- Fallback if strsplit ever disappears: plain split.
        parts = {}
        for part in (itemString .. ":"):gmatch("([^:]*):") do
            parts[#parts + 1] = part
        end
    end
    local function numAt(i)
        return tonumber(parts[i]) or 0
    end
    local gems = {}
    for i = 3, 6 do
        if numAt(i) ~= 0 then
            gems[#gems + 1] = numAt(i)
        end
    end
    return {
        itemId = numAt(1),
        enchantId = numAt(2),
        gems = gems,
    }
end

-- Tooltip data for one equipped slot, read once and reused
-- for both gem sockets and the upgrade track. Returns a table
-- or nil if tooltip data is unavailable.
--   sockets, filledSockets, upgradeTrack, upgradeLevel, upgradeMax
-- Upgrade track comes from the tooltip line itself, e.g.
-- "Upgrade Level: Champion 4/6". That is the only reliable
-- source: there is no direct upgrade-track API, and the
-- track name in-game is Hero / Myth (not Heroic / Mythic).
-- If no such line exists the item is not upgradeable and
-- upgradeTrack stays nil, never guessed.
function GA.GetTooltipData(unit, slotId)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then
        return nil
    end
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, unit, slotId)
    if not ok or not data or not data.lines then
        return nil
    end
    local total, filled = 0, 0
    local track, level, maxLevel = nil, nil, nil
    local setName, setWorn, setTotal, setBonuses = nil, nil, nil, nil
    for _, line in ipairs(data.lines) do
        local isSocket = false
        if Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.GemSocket then
            isSocket = (line.type == Enum.TooltipDataLineType.GemSocket)
        end
        if not isSocket and line.gemSocket then
            isSocket = true
        end
        if isSocket then
            total = total + 1
            if line.gem ~= nil then
                filled = filled + 1
            end
        end
        local text = line.leftText or line.rightText or ""
        if type(text) == "string" and text ~= "" then
            local t, l, m = text:match("Upgrade Level:%s*(%a+)%s+(%d+)/(%d+)")
            if t and l and m then
                track, level, maxLevel = t, tonumber(l), tonumber(m)
            end
            -- Set header: "Set Name (2/8)" — the worn/total
            -- count for this item's set.
            local name, worn, pieces = text:match("^(.-)%s*%((%d+)/(%d+)%)%s*$")
            if name and worn and pieces then
                setName, setWorn, setTotal = name, tonumber(worn), tonumber(pieces)
            end
            -- Set bonus line: "(2) Set: ..." — the threshold
            -- is the number in parentheses. Active is decided
            -- later by comparing it to the worn count, not by
            -- trusting tooltip colours (which vary by client).
            local threshold, bonus = text:match("^%((%d+)%)%s*(.+)$")
            if threshold and bonus then
                setBonuses = setBonuses or {}
                bonus = bonus:gsub("^Set:%s*", "")
                setBonuses[#setBonuses + 1] = { threshold = tonumber(threshold), text = bonus }
            end
        end
    end
    return {
        sockets = total,
        filledSockets = filled,
        upgradeTrack = track,
        upgradeLevel = level,
        upgradeMax = maxLevel,
        setName = setName,
        setWorn = setWorn,
        setTotal = setTotal,
        setBonuses = setBonuses,
    }
end

-- Backwards-compatible wrapper: socket count only.
function GA.CountSockets(unit, slotId)
    local data = GA.GetTooltipData(unit, slotId)
    if not data then return nil, nil end
    return data.sockets, data.filledSockets
end

-- Base item stats for one item link, via GetItemStats.
-- Guarded like everything else: a missing API gives nil,
-- never an error. IMPORTANT: GetItemStats returns the base
-- version of the item only — enchant and gem bonuses are NOT
-- included, and there is no API that gives the gemmed and
-- enchanted totals. The overview therefore sums base item
-- stats, and the UI says so; it never claims to include
-- enchant/gem contributions. Uncached items return an empty
-- table, which is nil here, so stats fill in as item data
-- loads (the re-inspect/merge flow warms the cache).
function GA.GetItemStats(link)
    if not link or not GetItemStats then return nil end
    local ok, stats = pcall(GetItemStats, link)
    if not ok or type(stats) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(stats) do
        if type(v) == "number" and v ~= 0 then
            out[k] = v
        end
    end
    if next(out) == nil then return nil end
    return out
end

-- Sum base item stats across a gear table (slotId -> audit).
function GA.SumGearStats(gear)
    local total = {}
    if not gear then return total end
    for _, slot in ipairs(GA.SLOTS) do
        local audit = gear[slot.id]
        if audit and audit.stats then
            for k, v in pairs(audit.stats) do
                total[k] = (total[k] or 0) + v
            end
        end
    end
    return total
end

-- Aggregate set bonuses across a gear table. One entry per
-- set, in first-seen slot order, with the worn count (the max
-- count any piece reported) and the bonus list sorted by
-- threshold, each flagged active when its threshold is met.
function GA.AggregateSets(gear)
    local byName = {}
    local order = {}
    if gear then
        for _, slot in ipairs(GA.SLOTS) do
            local audit = gear[slot.id]
            if audit and audit.setName then
                local s = byName[audit.setName]
                if not s then
                    s = { name = audit.setName, worn = 0, total = 0, bonuses = {} }
                    byName[audit.setName] = s
                    order[#order + 1] = s
                end
                if audit.setWorn and audit.setWorn > s.worn then s.worn = audit.setWorn end
                if audit.setTotal and audit.setTotal > s.total then s.total = audit.setTotal end
                if audit.setBonuses then
                    for _, b in ipairs(audit.setBonuses) do
                        if not s.bonuses[b.threshold] then
                            s.bonuses[b.threshold] = b.text
                        end
                    end
                end
            end
        end
    end
    for _, s in ipairs(order) do
        local list = {}
        for threshold, text in pairs(s.bonuses) do
            list[#list + 1] = { threshold = threshold, text = text }
        end
        table.sort(list, function(a, b) return a.threshold < b.threshold end)
        for _, b in ipairs(list) do
            b.active = b.threshold <= s.worn
        end
        s.bonusList = list
        s.bonuses = nil
    end
    return order
end

-- Class / spec / role for a unit.
-- Player: GetSpecialization() + GetSpecializationInfo().
-- Inspected units: GetInspectSpecialization() (only valid
-- after INSPECT_READY, which is exactly when AuditUnit runs)
-- + GetSpecializationInfoByID(). Every call is guarded, so a
-- missing or renamed API gives "unknown" instead of an error.
-- Returns: classFile, className, specName, specID, role, roleLabel
-- Extract spec info from a GetSpecializationInfo-style call.
-- Returns are id, name, description, icon, then role -- but
-- the role's position moved between client versions (it was
-- 6th with a background texture, later 5th), which is exactly
-- why Vengeance showed a blank role in v1.2.0. So scan every
-- return after the icon for a TANK/HEALER/DAMAGER token
-- instead of trusting a fixed position.
local function ExtractSpec(ok, ...)
    if not ok then return nil end
    local args = { ... }
    local id, name, icon = args[1], args[2], args[4]
    local role = nil
    for i = 5, #args do
        if args[i] == "TANK" or args[i] == "HEALER" or args[i] == "DAMAGER" then
            role = args[i]
            break
        end
    end
    if not id and not name then return nil end
    return { id = id, name = name, icon = icon, role = role }
end

function GA.GetSpecRole(unit)
    local className, classFile = nil, nil
    if UnitClass then
        className, classFile = UnitClass(unit)
    end
    local specID, specName, specIcon, role = nil, nil, nil, nil
    if unit == "player" then
        if GetSpecialization and GetSpecializationInfo then
            local ok, index = pcall(GetSpecialization)
            if ok and index then
                local info = ExtractSpec(pcall(GetSpecializationInfo, index))
                if info then
                    specID, specName, specIcon, role = info.id, info.name, info.icon, info.role
                end
            end
        end
        -- Forever-native fallback: C_SpecializationInfo is the
        -- documented system on Forever (Blizzard's own Forever
        -- UI uses it). GetSpecializationInfo returns multiple
        -- values in the same order as the global, so ExtractSpec
        -- handles it; the old code treated the first return as
        -- a table and could never assign anything.
        if not specID and C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecializationInfo then
            local okIdx, index = pcall(C_SpecializationInfo.GetSpecialization)
            if okIdx and index then
                local info = ExtractSpec(pcall(C_SpecializationInfo.GetSpecializationInfo, index))
                if info then
                    specID, specName, specIcon, role = info.id, info.name, info.icon, info.role
                end
            end
        end
    else
        -- Forever-native first: Blizzard's own Forever inspect
        -- UI resolves inspected specs exactly this way
        -- (C_SpecializationInfo.GetInspectSpecialization, then
        -- the GetSpecializationInfoByID global). The bare
        -- global GetInspectSpecialization is only a fallback:
        -- on Midnight-family clients the C_ form is the one
        -- that is documented.
        if C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization then
            local ok, id = pcall(C_SpecializationInfo.GetInspectSpecialization, unit)
            if ok and id and id ~= 0 then
                specID = id
            end
        end
        if not specID and GetInspectSpecialization then
            local ok, id = pcall(GetInspectSpecialization, unit)
            if ok and id and id ~= 0 then
                specID = id
            end
        end
        if specID then
            if GetSpecializationInfoByID then
                local info = ExtractSpec(pcall(GetSpecializationInfoByID, specID))
                if info then
                    specName, specIcon, role = info.name, info.icon, info.role
                end
            end
            if not role and GetSpecializationRoleByID then
                local ok, r = pcall(GetSpecializationRoleByID, specID)
                if ok then role = r end
            end
        end
    end
    local roleLabel = nil
    if role == "TANK" then roleLabel = "Tank"
    elseif role == "HEALER" then roleLabel = "Healer"
    elseif role == "DAMAGER" then roleLabel = "DPS" end
    return {
        classFile = classFile,
        className = className,
        specID = specID,
        specName = specName,
        specIcon = specIcon,
        role = role,
        roleLabel = roleLabel,
    }
end

-- Audit one equipped slot. Returns a table with:
--   link, itemLevel, hasEnchant, enchantMissing, gemsFilled,
--   sockets, gemsMissing
function GA.AuditSlot(unit, slotId)
    -- GetInventoryItemLink is still present in Midnight, but
    -- never call it unguarded: a missing API must give an
    -- empty slot, not a Lua error for the whole refresh.
    if not GetInventoryItemLink then
        return { empty = true }
    end
    local link = GetInventoryItemLink(unit, slotId)
    if not link then
        return { empty = true }
    end
    local parsed = GA.ParseItemLink(link)
    local itemLevel = 0
    -- Modern retail exposes this as C_Item.GetDetailedItemLevelInfo;
    -- keep the old global as a fallback. The base level from
    -- GetItemInfo below is only a last resort, not a substitute
    -- for the upgraded level.
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, lvl = pcall(C_Item.GetDetailedItemLevelInfo, link)
        if ok then itemLevel = lvl or 0 end
    end
    if itemLevel == 0 and GetDetailedItemLevelInfo then
        itemLevel = GetDetailedItemLevelInfo(link) or 0
    end
    -- One item-info call, reused for level, quality, icon and
    -- the off-hand weapon/shield check below.
    local _, _, quality, baseLevel, _, _, itemSubType, _, _, icon, _, classID, subclassID = GA.GetItemInfo(link)
    if itemLevel == 0 then
        itemLevel = baseLevel or 0
    end

    local result = {
        link = link,
        itemLevel = itemLevel,
        quality = quality,
        icon = icon,
        hasEnchant = parsed and parsed.enchantId ~= 0,
        gemsFilled = parsed and #parsed.gems or 0,
        sockets = 0,
        gemsMissing = 0,
        enchantMissing = false,
    }

    -- Off-hand: only flag a missing enchant on a weapon or
    -- shield, never on a held-off-hand frill / focus item.
    if GA.ENCHANTABLE_SLOTS[slotId] then
        local isWeaponOrShield = true
        if slotId == 17 then
            -- Use numeric class/subclass IDs, not English subtype
            -- names, so this works in any client locale.
            -- classID 2 = Weapon, classID 4 + subclassID 6 = Shield.
            -- itemSubType / classID / subclassID come from the
            -- single GA.GetItemInfo call above.
            if classID ~= nil then
                isWeaponOrShield = (classID == 2) or (classID == 4 and subclassID == 6)
            elseif itemSubType ~= nil then
                isWeaponOrShield = (itemSubType == "Shields")
                    or (itemSubType == "One-Handed Axes" or itemSubType == "One-Handed Swords"
                    or itemSubType == "One-Handed Maces" or itemSubType == "Daggers"
                    or itemSubType == "Fist Weapons" or itemSubType == "Warglaives")
            else
                -- Subtype unknown (item not cached yet): do not flag.
                isWeaponOrShield = false
            end
        end
        if isWeaponOrShield and not result.hasEnchant then
            result.enchantMissing = true
        end
    end

    local tooltip = GA.GetTooltipData(unit, slotId)
    if tooltip then
        result.sockets = tooltip.sockets
        -- Prefer the tooltip's filled count when available;
        -- otherwise fall back to the gem IDs in the link.
        if tooltip.filledSockets ~= nil and tooltip.filledSockets > 0 then
            result.gemsFilled = tooltip.filledSockets
        end
        result.gemsMissing = math.max(0, tooltip.sockets - result.gemsFilled)
        result.upgradeTrack = tooltip.upgradeTrack
        result.upgradeLevel = tooltip.upgradeLevel
        result.upgradeMax = tooltip.upgradeMax
        if tooltip.upgradeTrack and tooltip.upgradeLevel and tooltip.upgradeMax then
            result.upgradeText = tooltip.upgradeTrack .. " " .. tooltip.upgradeLevel .. "/" .. tooltip.upgradeMax
        end
        result.setName = tooltip.setName
        result.setWorn = tooltip.setWorn
        result.setTotal = tooltip.setTotal
        result.setBonuses = tooltip.setBonuses
    end
    result.stats = GA.GetItemStats(link)
    return result
end

-- Audit a whole unit. Returns a summary table used by the UI.
function GA.AuditUnit(unit)
    local gear = {}
    local totalLevel, counted = 0, 0
    local missingEnchants, missingGems = {}, 0
    for _, slot in ipairs(GA.SLOTS) do
        -- One bad slot must never kill the whole refresh:
        -- if a future API change breaks a slot, that slot
        -- shows as empty and the rest still audit.
        local ok, audit = pcall(GA.AuditSlot, unit, slot.id)
        if not ok then
            audit = { empty = true }
        end
        audit.slotId = slot.id
        audit.slotName = slot.name
        gear[slot.id] = audit
        if not audit.empty and audit.itemLevel and audit.itemLevel > 0 then
            totalLevel = totalLevel + audit.itemLevel
            counted = counted + 1
        end
        if audit.enchantMissing then
            missingEnchants[#missingEnchants + 1] = slot.name
        end
        missingGems = missingGems + (audit.gemsMissing or 0)
    end
    local avgLevel = 0
    if counted > 0 then
        avgLevel = totalLevel / counted
    end
    local spec = nil
    local okSpec, specResult = pcall(GA.GetSpecRole, unit)
    if okSpec then spec = specResult end
    return {
        gear = gear,
        avgLevel = avgLevel,
        itemCount = counted,
        linkCount = GA.CountLinks(gear),
        missingEnchants = missingEnchants,
        missingEnchantCount = #missingEnchants,
        missingGemCount = missingGems,
        spec = spec,
        stats = GA.SumGearStats(gear),
        sets = GA.AggregateSets(gear),
    }
end

-- How many slots actually have an item link. This is the
-- completeness measure: a slot with a link but an uncached
-- item level is still a found item, while a nil link on a
-- first inspect usually means "not loaded yet", not "empty".
function GA.CountLinks(gear)
    local n = 0
    if not gear then return 0 end
    for _, audit in pairs(gear) do
        if audit and audit.link then n = n + 1 end
    end
    return n
end

-- Merge two audits of the same unit, slot by slot. A later
-- audit never erases a slot an earlier audit found: on a
-- partial first inspect, the retry finds different slots,
-- and only the union is complete. Averages and missing
-- counts are recomputed from the merged gear, never averaged
-- across audits (that would double-count shared slots).
function GA.MergeAudits(old, new)
    if not old then return new end
    if not new then return old end
    local gear = {}
    for _, slot in ipairs(GA.SLOTS) do
        local newSlot = new.gear and new.gear[slot.id]
        local oldSlot = old.gear and old.gear[slot.id]
        if newSlot and not newSlot.empty and newSlot.link then
            gear[slot.id] = newSlot
        elseif oldSlot then
            gear[slot.id] = oldSlot
        elseif newSlot then
            gear[slot.id] = newSlot
        else
            gear[slot.id] = { empty = true, slotId = slot.id, slotName = slot.name }
        end
        gear[slot.id].slotId = slot.id
        gear[slot.id].slotName = slot.name
    end
    local totalLevel, counted, missingGems = 0, 0, 0
    local missingEnchants = {}
    for _, slot in ipairs(GA.SLOTS) do
        local audit = gear[slot.id]
        if audit and not audit.empty and audit.itemLevel and audit.itemLevel > 0 then
            totalLevel = totalLevel + audit.itemLevel
            counted = counted + 1
        end
        if audit and audit.enchantMissing then
            missingEnchants[#missingEnchants + 1] = slot.name
        end
        missingGems = missingGems + (audit and audit.gemsMissing or 0)
    end
    local spec = old.spec
    if new.spec and new.spec.specName then spec = new.spec end
    return {
        gear = gear,
        avgLevel = counted > 0 and (totalLevel / counted) or 0,
        itemCount = counted,
        linkCount = GA.CountLinks(gear),
        missingEnchants = missingEnchants,
        missingEnchantCount = #missingEnchants,
        missingGemCount = missingGems,
        spec = spec,
        stats = GA.SumGearStats(gear),
        sets = GA.AggregateSets(gear),
    }
end
