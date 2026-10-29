-- GearAudit: UI.lua
-- Modern dark UI: flat panels, thin borders, a single accent
-- colour, item icons, and no chunky DialogBox chrome.
-- Column alignment rule: every header is its own FontString
-- at exactly the same X as its row column. A single spaced
-- header string never lines up in a proportional font, which
-- was the previous overview bug.
local _, GA = ...

local ROW_HEIGHT = 34
local MAX_ROWS = 40

-- Overview columns: X and width. Headers and rows share these.
local COL_PLAYER = { x = 12,  w = 140 }
local COL_CLASS  = { x = 158, w = 160 }
local COL_ROLE   = { x = 324, w = 60 }
local COL_ILVL   = { x = 390, w = 50 }
local COL_ENCH   = { x = 446, w = 70 }
local COL_GEM    = { x = 522, w = 80 }
-- Detail columns.
local COL_SLOT    = { x = 50,  w = 60 }
local COL_ITEM    = { x = 116, w = 188 }
local COL_UPGRADE = { x = 310, w = 110 }
local COL_AUDIT   = { x = 426, w = 198 }

local COL_BG     = { 0.07, 0.08, 0.11, 0.97 }
local COL_PANEL  = { 0.11, 0.13, 0.18, 1 }
local COL_HOVER  = { 0.16, 0.18, 0.25, 1 }
local COL_BORDER = { 0.24, 0.27, 0.34, 1 }
local COL_ACCENT = { 0.25, 0.65, 0.95, 1 }
local COL_TEXT   = { 0.92, 0.93, 0.96, 1 }
local COL_DIM    = { 0.62, 0.65, 0.71, 1 }
local COL_GREEN  = { 0.35, 0.85, 0.55, 1 }
local COL_RED    = { 0.95, 0.35, 0.35, 1 }
local COL_TANK   = { 0.45, 0.70, 1.00, 1 }
local COL_HEAL   = { 0.40, 0.90, 0.55, 1 }
local COL_DPS    = { 1.00, 0.45, 0.45, 1 }

local function SetModernBackdrop(frame, bg, border)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function CreateModernFrame(name, width, height)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    SetModernBackdrop(frame, COL_BG, COL_BORDER)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    local bar = frame:CreateTexture(nil, "OVERLAY")
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    bar:SetHeight(3)
    bar:SetColorTexture(COL_ACCENT[1], COL_ACCENT[2], COL_ACCENT[3], 1)
    return frame
end

local function CreateFlatButton(parent, text, width, height, accent, fontTemplate, fontSize)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    if accent then
        SetModernBackdrop(btn, { 0.15, 0.38, 0.60, 1 }, COL_ACCENT)
    else
        SetModernBackdrop(btn, COL_PANEL, COL_BORDER)
    end
    local label = btn:CreateFontString(nil, "OVERLAY", fontTemplate or "GameFontNormalSmall")
    label:SetAllPoints(btn)
    label:SetText(text)
    if fontSize then
        -- Explicit size, not a template: the "×" glyph in the
        -- normal font renders tiny, and a template alone did
        -- not fix it in v1.2.0. A plain "X" at 22pt is unmissable.
        label:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
    end
    label:SetTextColor(COL_TEXT[1], COL_TEXT[2], COL_TEXT[3])
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(COL_HOVER[1], COL_HOVER[2], COL_HOVER[3], 1)
        self:SetBackdropBorderColor(COL_ACCENT[1], COL_ACCENT[2], COL_ACCENT[3], 1)
    end)
    btn:SetScript("OnLeave", function(self)
        if accent then
            self:SetBackdropColor(0.15, 0.38, 0.60, 1)
            self:SetBackdropBorderColor(COL_ACCENT[1], COL_ACCENT[2], COL_ACCENT[3], 1)
        else
            self:SetBackdropColor(COL_PANEL[1], COL_PANEL[2], COL_PANEL[3], 1)
            self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
        end
    end)
    return btn
end

local function CreateCloseButton(parent)
    local btn = CreateFlatButton(parent, "X", 32, 32, false, "GameFontNormalLarge", 22)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -10)
    return btn
end

local function ClassColor(unit)
    if not UnitClass then return { r = 1, g = 1, b = 1 } end
    local _, classFile = UnitClass(unit)
    return GA.GetClassColor(classFile)
end

local function RoleColor(roleLabel)
    if roleLabel == "Tank" then return COL_TANK
    elseif roleLabel == "Healer" then return COL_HEAL
    elseif roleLabel == "DPS" then return COL_DPS end
    return COL_DIM
end

local function CleanItemName(name)
    if not name then return nil end
    name = name:gsub("|A:[^|]*|a", "")
    name = name:gsub("|T[^|]*|t", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return name
end

local function ItemNameFromLink(link)
    local name = link:match("%[(.-)%]")
    if name then return CleanItemName(name) or "Unknown item" end
    local itemName = GA.GetItemInfo(link)
    return CleanItemName(itemName) or "Unknown item"
end

local function SpecText(spec)
    if not spec then return "—" end
    local parts = {}
    if spec.className then parts[#parts + 1] = spec.className end
    if spec.specName then parts[#parts + 1] = spec.specName end
    if #parts == 0 then return "—" end
    return table.concat(parts, " • ")
end

-- ------------------------------------------------------------------
-- Main window
-- ------------------------------------------------------------------
local main = CreateModernFrame("GearAuditFrame", 640, 600)
main:SetPoint("CENTER")
main:SetFrameStrata("MEDIUM")
-- Main stays in the normal layer. The detail panel (below) is
-- in DIALOG, so when the two overlap the detail always covers
-- the main completely instead of their elements interleaving.

local title = main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", main, "TOPLEFT", 16, -16)
title:SetText("Gear Audit")
title:SetTextColor(COL_TEXT[1], COL_TEXT[2], COL_TEXT[3])

local subtitle = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
subtitle:SetText("Party & raid gear  •  Retail 12.1.5")
subtitle:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])

local close = CreateCloseButton(main)
close:SetScript("OnClick", function() main:Hide() end)

local status = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
status:SetPoint("TOPLEFT", main, "TOPLEFT", 16, -62)
status:SetPoint("TOPRIGHT", main, "TOPRIGHT", -16, -62)
status:SetJustifyH("LEFT")
status:SetText("Press Refresh to inspect your party or raid.")
status:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])

local refreshBtn = CreateFlatButton(main, "Refresh All", 120, 28, true)
refreshBtn:SetPoint("TOPLEFT", main, "TOPLEFT", 16, -84)
refreshBtn:SetScript("OnClick", function() GA.RefreshAll() end)

local hint = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hint:SetPoint("LEFT", refreshBtn, "RIGHT", 12, 0)
hint:SetText("Click a player for full gear.")
hint:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])

-- Per-column headers, at exactly the row column X positions.
-- baseX matters: overview rows live inside the scroll child,
-- which is inset 16px from the main frame, so main headers
-- need +16 or every row lands 16px right of its header --
-- the remaining misalignment in v1.2.0. Detail rows are
-- anchored straight to the detail frame, so baseX is 0 there.
local function MakeHeader(parent, col, text, y, baseX)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", col.x + (baseX or 0), y)
    fs:SetWidth(col.w)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    fs:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])
    return fs
end
MakeHeader(main, COL_PLAYER, "PLAYER", -122, 16)
MakeHeader(main, COL_CLASS, "CLASS / SPEC", -122, 16)
MakeHeader(main, COL_ROLE, "ROLE", -122, 16)
MakeHeader(main, COL_ILVL, "ILVL", -122, 16)
MakeHeader(main, COL_ENCH, "ENCHANTS", -122, 16)
MakeHeader(main, COL_GEM, "GEMS", -122, 16)

local headerLine = main:CreateTexture(nil, "OVERLAY")
headerLine:SetPoint("TOPLEFT", main, "TOPLEFT", 16, -136)
headerLine:SetPoint("TOPRIGHT", main, "TOPRIGHT", -16, -136)
headerLine:SetHeight(1)
headerLine:SetColorTexture(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)

local scroll = CreateFrame("ScrollFrame", nil, main)
scroll:SetPoint("TOPLEFT", main, "TOPLEFT", 16, -142)
scroll:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -16, 36)
local scrollChild = CreateFrame("Frame", nil, scroll)
scrollChild:SetSize(608, 1)
scroll:SetScrollChild(scrollChild)
scroll:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll()
    local max = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * ROW_HEIGHT)))
end)
scroll:EnableMouseWheel(true)

local summary = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
summary:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 16, 14)
summary:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -16, 14)
summary:SetJustifyH("LEFT")
summary:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])
summary:SetText("")

local rows = {}
for i = 1, MAX_ROWS do
    local row = CreateFrame("Button", nil, scrollChild, "BackdropTemplate")
    row:SetSize(608, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    SetModernBackdrop(row, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    row.accentBar = row:CreateTexture(nil, "OVERLAY")
    row.accentBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.accentBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.accentBar:SetWidth(3)
    row.accentBar:SetColorTexture(COL_ACCENT[1], COL_ACCENT[2], COL_ACCENT[3], 1)
    row.accentBar:Hide()
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(COL_HOVER[1], COL_HOVER[2], COL_HOVER[3], 1)
    end)
    row:SetScript("OnLeave", function(self)
        if GA.selectedUnit == self.unit then
            self:SetBackdropColor(COL_PANEL[1], COL_PANEL[2], COL_PANEL[3], 1)
        else
            self:SetBackdropColor(0, 0, 0, 0)
        end
    end)
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("LEFT", row, "LEFT", COL_PLAYER.x, 0)
    row.nameText:SetWidth(COL_PLAYER.w)
    row.nameText:SetJustifyH("LEFT")
    row.classText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.classText:SetPoint("LEFT", row, "LEFT", COL_CLASS.x, 0)
    row.classText:SetWidth(COL_CLASS.w)
    row.classText:SetJustifyH("LEFT")
    row.classText:SetTextColor(COL_TEXT[1], COL_TEXT[2], COL_TEXT[3])
    -- Spec icon replaces the Class/Spec text when a spec is
    -- known. Hovering it shows the written "Class • Spec • Role".
    row.specIconBtn = CreateFrame("Button", nil, row)
    row.specIconBtn:SetSize(24, 24)
    row.specIconBtn:SetPoint("LEFT", row, "LEFT", COL_CLASS.x, 0)
    row.specIcon = row.specIconBtn:CreateTexture(nil, "OVERLAY")
    row.specIcon:SetAllPoints(row.specIconBtn)
    row.specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.specIconBtn:SetScript("OnEnter", function(self)
        if self.spec and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(SpecText(self.spec), 1, 1, 1)
            if self.spec.roleLabel then
                GameTooltip:AddLine(self.spec.roleLabel, 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end
    end)
    row.specIconBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row.specIconBtn:SetScript("OnClick", function(self)
        if self.unit then
            GA.selectedUnit = self.unit
            GA.RefreshOverview()
            GA.ShowDetail(self.unit)
        end
    end)
    row.specIconBtn:Hide()
    row.roleText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.roleText:SetPoint("LEFT", row, "LEFT", COL_ROLE.x, 0)
    row.roleText:SetWidth(COL_ROLE.w)
    row.roleText:SetJustifyH("LEFT")
    row.ilvlText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.ilvlText:SetPoint("LEFT", row, "LEFT", COL_ILVL.x, 0)
    row.ilvlText:SetWidth(COL_ILVL.w)
    row.ilvlText:SetJustifyH("LEFT")
    row.ilvlText:SetTextColor(COL_TEXT[1], COL_TEXT[2], COL_TEXT[3])
    row.enchText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.enchText:SetPoint("LEFT", row, "LEFT", COL_ENCH.x, 0)
    row.enchText:SetWidth(COL_ENCH.w)
    row.enchText:SetJustifyH("LEFT")
    row.gemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.gemText:SetPoint("LEFT", row, "LEFT", COL_GEM.x, 0)
    row.gemText:SetWidth(COL_GEM.w)
    row.gemText:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(self)
        GA.selectedUnit = self.unit
        GA.RefreshOverview()
        GA.ShowDetail(self.unit)
    end)
    rows[i] = row
end

-- ------------------------------------------------------------------
-- Detail panel
-- ------------------------------------------------------------------
local detail = CreateModernFrame("GearAuditDetailFrame", 640, 740)
detail:SetPoint("LEFT", main, "RIGHT", 8, 0)
detail:SetFrameStrata("DIALOG")

local detailTitle = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
detailTitle:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -16)
detailTitle:SetText("Gear Detail")
detailTitle:SetTextColor(COL_TEXT[1], COL_TEXT[2], COL_TEXT[3])

local detailClose = CreateCloseButton(detail)
detailClose:SetScript("OnClick", function() detail:Hide() end)

local detailSpec = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
detailSpec:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -40)
detailSpec:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -16, -40)
detailSpec:SetJustifyH("LEFT")
detailSpec:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])
detailSpec:SetText("—")

-- Average item level, deliberately large.
local detailAvg = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
detailAvg:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -64)
detailAvg:SetFont("Fonts\\FRIZQT__.TTF", 28, "OUTLINE")
detailAvg:SetText("—")
detailAvg:SetTextColor(COL_TEXT[1], COL_TEXT[2], COL_TEXT[3])
local detailAvgLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
detailAvgLabel:SetPoint("LEFT", detailAvg, "RIGHT", 10, 0)
detailAvgLabel:SetText("AVERAGE ITEM LEVEL")
detailAvgLabel:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])

local detailSummary = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
detailSummary:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -102)
detailSummary:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -16, -102)
detailSummary:SetJustifyH("LEFT")
detailSummary:SetTextColor(COL_TEXT[1], COL_TEXT[2], COL_TEXT[3])
detailSummary:SetText("")

local detailRefresh = CreateFlatButton(detail, "Re-inspect Player", 150, 28, true)
detailRefresh:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -124)
detailRefresh:SetScript("OnClick", function()
    if GA.selectedUnit then GA.RefreshUnit(GA.selectedUnit) end
end)

-- Gear-stats overview and active set bonuses, at the top of
-- the detail window (above the slot list). Both FontStrings
-- are empty when there is nothing to show, so the block takes
-- no space on players with no usable stat/set data.
local detailStats = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
detailStats:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -156)
detailStats:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -16, -156)
detailStats:SetJustifyH("LEFT")
detailStats:SetTextColor(COL_TEXT[1], COL_TEXT[2], COL_TEXT[3])
detailStats:SetText("")
local detailSets = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
detailSets:SetPoint("TOPLEFT", detailStats, "BOTTOMLEFT", 0, -6)
detailSets:SetPoint("TOPRIGHT", detailStats, "BOTTOMRIGHT", 0, -6)
detailSets:SetJustifyH("LEFT")
detailSets:SetTextColor(COL_TEXT[1], COL_TEXT[2], COL_TEXT[3])
detailSets:SetText("")

-- Detail column headers, same X as the slot columns below.
MakeHeader(detail, COL_SLOT, "SLOT", -264)
MakeHeader(detail, COL_ITEM, "ITEM", -264)
MakeHeader(detail, COL_UPGRADE, "UPGRADE", -264)
MakeHeader(detail, COL_AUDIT, "AUDIT", -264)

local detailHeaderLine = detail:CreateTexture(nil, "OVERLAY")
detailHeaderLine:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -278)
detailHeaderLine:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -16, -278)
detailHeaderLine:SetHeight(1)
detailHeaderLine:SetColorTexture(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)

local detailSlots = {}
for i, slot in ipairs(GA.SLOTS) do
    local y = -288 - (i - 1) * 28
    local iconFrame = CreateFrame("Frame", nil, detail, "BackdropTemplate")
    iconFrame:SetSize(26, 26)
    iconFrame:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, y)
    SetModernBackdrop(iconFrame, COL_PANEL, COL_BORDER)
    local icon = iconFrame:CreateTexture(nil, "OVERLAY")
    icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local label = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", iconFrame, "RIGHT", 8, 0)
    label:SetWidth(COL_SLOT.w)
    label:SetJustifyH("LEFT")
    label:SetText(slot.name)
    label:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])

    local itemBtn = CreateFrame("Button", nil, detail)
    itemBtn:SetPoint("LEFT", label, "RIGHT", 6, 0)
    itemBtn:SetSize(COL_ITEM.w, 20)
    itemBtn.text = itemBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemBtn.text:SetAllPoints(itemBtn)
    itemBtn.text:SetJustifyH("LEFT")
    itemBtn:SetScript("OnEnter", function(self)
        if self.link and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    itemBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    itemBtn:SetScript("OnClick", function(self)
        if IsShiftKeyDown and IsShiftKeyDown() and self.link and ChatEdit_InsertLink then
            ChatEdit_InsertLink(self.link)
        end
    end)

    local upgradeText = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    upgradeText:SetPoint("LEFT", itemBtn, "RIGHT", 6, 0)
    upgradeText:SetWidth(COL_UPGRADE.w)
    upgradeText:SetJustifyH("LEFT")
    upgradeText:SetTextColor(COL_TEXT[1], COL_TEXT[2], COL_TEXT[3])

    local flags = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    flags:SetPoint("LEFT", upgradeText, "RIGHT", 6, 0)
    flags:SetWidth(COL_AUDIT.w)
    flags:SetJustifyH("LEFT")

    detailSlots[i] = { slot = slot, iconFrame = iconFrame, icon = icon, label = label, itemBtn = itemBtn, upgradeText = upgradeText, flags = flags }
end

-- Gear-stats display order: primaries first, then the power
-- stats, then ratings. Any summed stat not listed here still
-- shows, appended after these in label order, so a stat the
-- list missed is never silently dropped.
local STAT_ORDER = {
    "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT",
    "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_INTELLECT_SHORT",
    "ITEM_MOD_SPIRIT_SHORT",
    "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
    "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT",
    "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
    "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT",
    "ITEM_MOD_CRIT_RANGED_RATING_SHORT", "ITEM_MOD_CRIT_SPELL_RATING_SHORT",
    "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT",
    "ITEM_MOD_HIT_RANGED_RATING_SHORT", "ITEM_MOD_HIT_SPELL_RATING_SHORT",
    "ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_MASTERY_RATING_SHORT",
    "ITEM_MOD_VERSATILITY",
    "ITEM_MOD_DODGE_RATING_SHORT", "ITEM_MOD_PARRY_RATING_SHORT",
    "ITEM_MOD_BLOCK_RATING_SHORT", "ITEM_MOD_RESILIENCE_RATING_SHORT",
    "ITEM_MOD_SPELL_PENETRATION_SHORT",
    "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_HEALTH_REGENERATION_SHORT",
    "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT",
    "ITEM_MOD_EXPERTISE_RATING_SHORT",
}

-- Display name for a GetItemStats key. The keys are global
-- string names, so the game's own localized name is used
-- when it exists; otherwise the key is prettified. This keeps
-- the overview correct in any client locale.
local function StatLabel(key)
    if _G and type(_G[key]) == "string" and _G[key] ~= "" then
        return _G[key]
    end
    local s = key:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_", " "):lower()
    return (s:gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

-- One wrapped line of summed gear stats, or "" when there is
-- nothing to show. Values are the summed base item stats
-- only — GetItemStats has no enchant/gem totals — so the
-- second line says so plainly rather than implying more.
local function FormatGearStats(stats)
    if not stats or next(stats) == nil then return "" end
    local parts, seen = {}, {}
    for _, key in ipairs(STAT_ORDER) do
        local v = stats[key]
        if v and v ~= 0 then
            parts[#parts + 1] = string.format("+%d %s", v, StatLabel(key))
            seen[key] = true
        end
    end
    local rest = {}
    for key, v in pairs(stats) do
        if not seen[key] and v ~= 0 then
            rest[#rest + 1] = { label = StatLabel(key), value = v }
        end
    end
    table.sort(rest, function(a, b) return a.label < b.label end)
    for _, r in ipairs(rest) do
        parts[#parts + 1] = string.format("+%d %s", r.value, r.label)
    end
    if #parts == 0 then return "" end
    return "Gear stats: " .. table.concat(parts, "  •  ")
        .. "\n|cff888888Base item stats only — enchant and gem bonuses not included.|r"
end

-- Active set bonuses, one line per set: name and worn count,
-- then the bonuses whose threshold is met. A set with no
-- bonus met yet still shows its count, so progress toward
-- the next bonus is visible. "" when the player wears no
-- set pieces.
local function FormatSetBonuses(sets)
    if not sets or #sets == 0 then return "" end
    local lines = {}
    for _, s in ipairs(sets) do
        local active = {}
        for _, b in ipairs(s.bonusList or {}) do
            if b.active then active[#active + 1] = b.text end
        end
        local line = string.format("%s (%d/%d)", s.name, s.worn, s.total)
        if #active > 0 then
            line = line .. ": " .. table.concat(active, "; ")
        end
        lines[#lines + 1] = line
    end
    if #lines == 0 then return "" end
    return "Set bonuses:\n" .. table.concat(lines, "\n")
end

-- ------------------------------------------------------------------
-- Rendering
-- ------------------------------------------------------------------
function GA.RefreshOverview()
    local units = GA.GetGroupUnits()
    table.sort(units, function(a, b)
        local da, db = GA.data[a], GA.data[b]
        local la = (da and da.avgLevel) or -1
        local lb = (db and db.avgLevel) or -1
        if la ~= lb then return la > lb end
        return (GA.UnitDisplayName(a) or "") < (GA.UnitDisplayName(b) or "")
    end)

    local inspected, totalEnch, totalGems = 0, 0, 0
    for _, unit in ipairs(units) do
        local audit = GA.data[unit]
        if audit and not audit.notInspectable then
            inspected = inspected + 1
            totalEnch = totalEnch + (audit.missingEnchantCount or 0)
            totalGems = totalGems + (audit.missingGemCount or 0)
        end
    end
    summary:SetText(string.format("%d of %d inspected  •  %d missing enchants  •  %d missing gems",
        inspected, #units, totalEnch, totalGems))

    for i, row in ipairs(rows) do
        local unit = units[i]
        row.unit = unit
        if not unit then
            row:Hide()
        else
            row:Show()
            local color = ClassColor(unit)
            row.nameText:SetText(GA.UnitDisplayName(unit))
            row.nameText:SetTextColor(color.r, color.g, color.b)
            local audit = GA.data[unit]
            local spec = audit and audit.spec or nil
            row.specIconBtn.spec = spec
            row.specIconBtn.unit = unit
            if spec then
                if spec.specIcon then
                    row.specIcon:SetTexture(spec.specIcon)
                    row.specIconBtn:Show()
                    row.classText:Hide()
                else
                    row.specIconBtn:Hide()
                    row.classText:Show()
                    row.classText:SetText(SpecText(spec))
                end
                local rc = RoleColor(spec.roleLabel)
                row.roleText:SetText(spec.roleLabel or "—")
                row.roleText:SetTextColor(rc[1], rc[2], rc[3])
            else
                -- Class alone is still useful before a spec is known.
                row.specIconBtn:Hide()
                row.classText:Show()
                local className = nil
                if UnitClass then className = select(1, UnitClass(unit)) end
                row.classText:SetText(className or "—")
                row.roleText:SetText("—")
                row.roleText:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])
            end
            if not audit then
                row.ilvlText:SetText("—")
                row.enchText:SetText("—")
                row.enchText:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])
                row.gemText:SetText("—")
                row.gemText:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])
            elseif audit.notInspectable then
                row.ilvlText:SetText("—")
                row.enchText:SetText("—")
                row.gemText:SetText(audit.reason or "—")
                row.gemText:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])
            else
                row.ilvlText:SetText(string.format("%.0f", audit.avgLevel or 0))
                if audit.missingEnchantCount == 0 then
                    row.enchText:SetText("OK")
                    row.enchText:SetTextColor(COL_GREEN[1], COL_GREEN[2], COL_GREEN[3])
                else
                    row.enchText:SetText(audit.missingEnchantCount .. " missing")
                    row.enchText:SetTextColor(COL_RED[1], COL_RED[2], COL_RED[3])
                end
                if audit.missingGemCount == 0 then
                    row.gemText:SetText("OK")
                    row.gemText:SetTextColor(COL_GREEN[1], COL_GREEN[2], COL_GREEN[3])
                else
                    row.gemText:SetText(audit.missingGemCount .. " missing")
                    row.gemText:SetTextColor(COL_RED[1], COL_RED[2], COL_RED[3])
                end
            end
            if GA.selectedUnit == unit then
                row:SetBackdropColor(COL_PANEL[1], COL_PANEL[2], COL_PANEL[3], 1)
                row.accentBar:Show()
            else
                row:SetBackdropColor(0, 0, 0, 0)
                row.accentBar:Hide()
            end
        end
    end
    scrollChild:SetHeight(math.max(1, #units * ROW_HEIGHT))
    scroll:SetVerticalScroll(0)
end

function GA.ShowDetail(unit)
    if not unit or not UnitExists or not UnitExists(unit) then return end
    GA.selectedUnit = unit
    local audit = GA.data[unit]
    local color = ClassColor(unit)
    detailTitle:SetText(GA.UnitDisplayName(unit))
    detailTitle:SetTextColor(color.r, color.g, color.b)
    local function ClearSlots()
        for _, entry in ipairs(detailSlots) do
            entry.icon:SetTexture(nil)
            entry.iconFrame:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
            entry.itemBtn.text:SetText("—")
            entry.itemBtn.text:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])
            entry.itemBtn.link = nil
            entry.upgradeText:SetText("—")
            entry.upgradeText:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])
            entry.flags:SetText("")
        end
        detailStats:SetText("")
        detailSets:SetText("")
    end
    if not audit then
        detailSpec:SetText("—")
        detailAvg:SetText("—")
        detailSummary:SetText("Not inspected yet. Press Re-inspect Player.")
        ClearSlots()
    elseif audit.notInspectable then
        detailSpec:SetText("—")
        detailAvg:SetText("—")
        detailSummary:SetText(audit.reason or "Could not inspect this player.")
        ClearSlots()
    else
        local spec = audit.spec
        if spec then
            local specLine = SpecText(spec)
            if spec.roleLabel then specLine = specLine .. "  •  " .. spec.roleLabel end
            detailSpec:SetText(specLine)
        else
            detailSpec:SetText("—")
        end
        detailAvg:SetText(string.format("%.0f", audit.avgLevel or 0))
        detailSummary:SetText(string.format("(%d items)   •   Missing enchants: %d   •   Missing gems: %d",
            audit.itemCount or 0, audit.missingEnchantCount or 0, audit.missingGemCount or 0))
        detailStats:SetText(FormatGearStats(audit.stats))
        detailSets:SetText(FormatSetBonuses(audit.sets))
        for _, entry in ipairs(detailSlots) do
            local slotAudit = audit.gear[entry.slot.id]
            if not slotAudit or slotAudit.empty then
                entry.icon:SetTexture(nil)
                entry.iconFrame:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
                entry.itemBtn.text:SetText("(empty)")
                entry.itemBtn.text:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])
                entry.itemBtn.link = nil
                entry.upgradeText:SetText("—")
                entry.upgradeText:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])
                entry.flags:SetText("")
            else
                local r, g, b = GA.GetItemQualityColor(slotAudit.quality)
                if slotAudit.icon then
                    entry.icon:SetTexture(slotAudit.icon)
                else
                    entry.icon:SetTexture(nil)
                end
                entry.iconFrame:SetBackdropBorderColor(r, g, b, 1)
                entry.itemBtn.text:SetText(string.format("%d  %s", slotAudit.itemLevel or 0, ItemNameFromLink(slotAudit.link)))
                entry.itemBtn.text:SetTextColor(r, g, b)
                entry.itemBtn.link = slotAudit.link
                if slotAudit.upgradeText then
                    entry.upgradeText:SetText(slotAudit.upgradeText)
                    entry.upgradeText:SetTextColor(COL_TEXT[1], COL_TEXT[2], COL_TEXT[3])
                else
                    entry.upgradeText:SetText("—")
                    entry.upgradeText:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])
                end
                local parts = {}
                if GA.ENCHANTABLE_SLOTS[entry.slot.id] then
                    if slotAudit.enchantMissing then
                        parts[#parts + 1] = "|cffff5959No enchant|r"
                    else
                        parts[#parts + 1] = "|cff59d98cEnchant|r"
                    end
                end
                if slotAudit.sockets and slotAudit.sockets > 0 then
                    if slotAudit.gemsMissing > 0 then
                        parts[#parts + 1] = "|cffff5959" .. slotAudit.gemsMissing .. " gem(s) missing|r"
                    else
                        parts[#parts + 1] = "|cff59d98cGems OK|r"
                    end
                end
                entry.flags:SetText(table.concat(parts, "  "))
            end
        end
    end
    detail:Show()
    detail:Raise()
end

function GA.OnUnitAudited(unit)
    GA.RefreshOverview()
    if GA.selectedUnit == unit and detail:IsShown() then
        GA.ShowDetail(unit)
    end
end

function GA.OnRefreshStarted(count)
    status:SetText(string.format("Inspecting %d player(s)...", count))
end

function GA.OnInspectFinished()
    status:SetText("Done. Click a player for full gear.")
    GA.RefreshOverview()
end

function GA.OnRosterChanged()
    GA.RefreshOverview()
end

function GA.ToggleWindow(force)
    if force == true then
        main:Show()
        GA.RefreshOverview()
    elseif force == false then
        main:Hide()
        detail:Hide()
    elseif main:IsShown() then
        main:Hide()
        detail:Hide()
    else
        main:Show()
        GA.RefreshOverview()
    end
end
