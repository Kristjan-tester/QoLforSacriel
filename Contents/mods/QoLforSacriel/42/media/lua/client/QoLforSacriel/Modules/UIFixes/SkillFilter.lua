local SkillFilter = {}

local patched = false
local trackingInstalled = false
local originalLoadPerk = nil
local originalCreateChildren = nil
local originalRender = nil

require "ISUI/ISComboBox"

local UI_BORDER_SPACING = 10
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6
local SCROLL_BAR_WIDTH = 13
local MODE_NONE = 1
local MODE_HIDE_ZERO_XP = 2
local MODE_MIN_LEVEL_OR_RECENT = 3
local MODE_DATA_KEY = "QoLforSacriel_SkillFilterMode"
local SKILL_FILTER_HEADER_HGT = BUTTON_HGT + UI_BORDER_SPACING

local xpBaselinesByPlayer = {}
local recentXpByPlayer = {}

local function isSkillFilterEnabled(settings)
    return settings.isEnabled("QoLforSacriel_EnableUIFixes") == true
        and settings.get("QoLforSacriel_UIFixes_EnableSkillFilter") == true
end

local function clampNumber(value, defaultValue, minimum, maximum)
    local numeric = tonumber(value)
    if not numeric or numeric ~= numeric then
        return defaultValue
    end
    numeric = math.floor(numeric)
    return math.max(minimum, math.min(maximum, numeric))
end

local function getRecentMinutes(settings)
    return clampNumber(settings.get("QoLforSacriel_UIFixes_SkillFilterRecentMinutes"), 60, 1, 24 * 60)
end

local function getMinimumFullLevel(settings)
    local value = settings and settings.get
        and settings.get("QoLforSacriel_UIFixes_SkillFilterMinFullLevel") or nil
    return clampNumber(value, 1, 0, 10)
end

local function getFilterModeLabel(mode, settings)
    if mode == MODE_HIDE_ZERO_XP then
        return getTextOrNull("UI_QoLforSacriel_SkillFilterMode_HideZeroXp") or "Hide 0 XP"
    end
    if mode == MODE_MIN_LEVEL_OR_RECENT then
        local template = getTextOrNull("UI_QoLforSacriel_SkillFilterMode_MinLevelOrRecent")
            or "Hide below X full level + recents"
        local label = string.gsub(template, "X", tostring(getMinimumFullLevel(settings)))
        return label
    end
    return getTextOrNull("UI_QoLforSacriel_SkillFilterMode_None") or "No filter"
end

local function getStoredMode(playerObj)
    if not playerObj or not playerObj.getModData then
        return MODE_NONE
    end

    local mode = tonumber(playerObj:getModData()[MODE_DATA_KEY])
    if mode == MODE_HIDE_ZERO_XP or mode == MODE_MIN_LEVEL_OR_RECENT then
        return mode
    end
    return MODE_NONE
end

local function setStoredMode(playerObj, mode)
    if playerObj and playerObj.getModData then
        playerObj:getModData()[MODE_DATA_KEY] = mode
    end
end

local function getPanelMode(self)
    if self.qolSkillFilterMode == nil then
        self.qolSkillFilterMode = getStoredMode(self.char)
    end
    return self.qolSkillFilterMode
end

local function getPlayerState(store, playerIndex)
    if type(store[playerIndex]) ~= "table" then
        store[playerIndex] = {}
    end
    return store[playerIndex]
end

local function getWorldAgeHours()
    local gameTime = getGameTime and getGameTime() or nil
    if not gameTime or not gameTime.getWorldAgeHours then
        return nil
    end
    return gameTime:getWorldAgeHours()
end

local function isRecentXp(playerIndex, perkType, settings)
    local recentForPlayer = recentXpByPlayer[playerIndex]
    local gainedAtHours = recentForPlayer and recentForPlayer[perkType] or nil
    local nowHours = getWorldAgeHours()
    if not gainedAtHours or not nowHours then
        return false
    end

    local ageMinutes = (nowHours - gainedAtHours) * 60
    if ageMinutes < 0 or ageMinutes > getRecentMinutes(settings) then
        recentForPlayer[perkType] = nil
        return false
    end
    return true
end

local function shouldIncludePerk(self, perk, mode, settings)
    if not self or not self.char or not perk or mode == MODE_NONE then
        return true
    end

    local perkType = perk:getType()
    local level = self.char:getPerkLevel(perkType)
    local cumulativeXp = self.char:getXp():getXP(perkType)
    if mode == MODE_HIDE_ZERO_XP then
        return level > 0 or cumulativeXp > 0
    end

    return level >= getMinimumFullLevel(settings)
        or isRecentXp(self.playerNum or 0, perkType, settings)
end

local function sortParentPerks(a, b)
    if a:isPassiv() and not b:isPassiv() then
        return true
    end
    if b:isPassiv() and not a:isPassiv() then
        return false
    end
    return not string.sort(a:getName(), b:getName())
end

local function clearProgressBars(self)
    if not self.progressBars then
        self.progressBars = {}
        self.progressBarLoaded = false
        return
    end

    for i = 1, #self.progressBars do
        self:removeChild(self.progressBars[i])
    end
    self.progressBars = {}
    self.progressBarLoaded = false
end

local function rebuildSkillLayout(self)
    local oldButtons = self.buttonList or {}
    for i = 1, #oldButtons do
        self:removeChild(oldButtons[i])
    end

    self.sorted = {}
    self.nameToPerk = {}
    self.buttonList = {}
    self.collapse = {}
    self.perks = ISCharacterInfo.loadPerk(self) or {}

    for parentType, _ in pairs(self.perks) do
        local parentPerk = PerkFactory.getPerk(parentType)
        if parentPerk then
            table.insert(self.sorted, parentPerk)
            self.nameToPerk[parentPerk:getName()] = parentType
        end
    end

    table.sort(self.sorted, sortParentPerks)

    for i = 1, #self.sorted do
        table.insert(self.collapse, false)
        local collapseButton = ISButton:new(UI_BORDER_SPACING + 1, 0, BUTTON_HGT, BUTTON_HGT, "", self, ISCharacterInfo.collapseSection)
        collapseButton.internal = "COLLAPSE" .. i
        collapseButton:setImage(getTexture("media/ui/inventoryPanes/Button_TreeExpanded.png"))
        collapseButton:initialise()
        self:addChild(collapseButton)
        table.insert(self.buttonList, collapseButton)
    end

    for i = 1, #self.sorted do
        local parentPerk = self.sorted[i]
        local perkList = self.perks[parentPerk:getType()]
        if perkList then
            table.sort(perkList, function(a, b)
                return a:getName() < b:getName()
            end)
        end
    end

    clearProgressBars(self)
    self.reloadSkillBar = true
end

local function getEligibilitySignature(self, mode, settings)
    if mode == MODE_NONE then
        return "all"
    end

    local allPerks = originalLoadPerk(self) or {}
    local eligible = {}
    for _, perkList in pairs(allPerks) do
        for index = 1, #perkList do
            local perk = perkList[index]
            if shouldIncludePerk(self, perk, mode, settings) then
                table.insert(eligible, tostring(perk:getType()))
            end
        end
    end
    table.sort(eligible)
    return tostring(mode) .. ":" .. table.concat(eligible, ",")
end

local function refreshLayoutIfNeeded(self, settings)
    local mode = getPanelMode(self)
    local signature = getEligibilitySignature(self, mode, settings)
    if mode ~= MODE_NONE and (self.qolSkillFilterEligibilitySignature == nil
        or self.qolSkillFilterEligibilitySignature ~= signature) then
        rebuildSkillLayout(self)
    end
    self.qolSkillFilterEligibilitySignature = signature
end

local function updateModeDropdownPosition(self, settings)
    local combo = self.qolSkillFilterModeDropdown
    if not combo then
        return
    end

    local width = 0
    for mode = MODE_NONE, MODE_MIN_LEVEL_OR_RECENT do
        width = math.max(width, getTextManager():MeasureStringX(UIFont.Small, getFilterModeLabel(mode, settings)))
    end
    width = width + BUTTON_HGT + 20
    local x = math.max(UI_BORDER_SPACING + 1, self.width - width - SCROLL_BAR_WIDTH - UI_BORDER_SPACING - 1)
    combo:setWidth(width)
    combo:setX(x)
    combo:setY(1)
end

local function updateModeDropdownOptions(self, settings)
    local combo = self.qolSkillFilterModeDropdown
    local minimumFullLevel = getMinimumFullLevel(settings)
    if not combo or combo.qolSkillFilterMinimumFullLevel == minimumFullLevel then
        return
    end

    combo:clear()
    combo.tooltip = getTextOrNull("UI_QoLforSacriel_SkillFilterMode_Tooltip")
    combo:addOption(getFilterModeLabel(MODE_NONE, settings))
    combo:addOption(getFilterModeLabel(MODE_HIDE_ZERO_XP, settings))
    combo:addOption(getFilterModeLabel(MODE_MIN_LEVEL_OR_RECENT, settings))
    combo.selected = getPanelMode(self)
    combo.qolSkillFilterMinimumFullLevel = minimumFullLevel
end

local function onModeChanged(self, combo)
    if not self or not combo then
        return
    end

    self.qolSkillFilterMode = combo.selected
    setStoredMode(self.char, combo.selected)
    rebuildSkillLayout(self)
end

local function ensureModeDropdown(self, settings)
    local mode = getPanelMode(self)
    if not self.qolSkillFilterModeDropdown then
        local combo = ISComboBox:new(0, UI_BORDER_SPACING, 100, BUTTON_HGT, self, onModeChanged)
        combo:initialise()
        combo.tooltip = getTextOrNull("UI_QoLforSacriel_SkillFilterMode_Tooltip")
        pcall(function()
            combo:setScrollWithParent(false)
        end)
        self.qolSkillFilterModeDropdown = combo
        self:addChild(combo)
    end

    updateModeDropdownOptions(self, settings)
    self.qolSkillFilterModeDropdown.selected = mode
    updateModeDropdownPosition(self, settings)
end

local function renderWithRecentXpHighlights(self, settings)
    local recentSkillNames = {}
    for _, perkList in pairs(self.perks or {}) do
        for index = 1, #perkList do
            local perk = perkList[index]
            if isRecentXp(self.playerNum or 0, perk:getType(), settings) then
                recentSkillNames[perk:getName()] = true
            end
        end
    end

    local y = UI_BORDER_SPACING + SKILL_FILTER_HEADER_HGT

    if self.lastLevelUpTime > 0 then
        self.lastLevelUpTime = self.lastLevelUpTime - 0.0025
    elseif self.lastLevelUpTime < 0 then
        self.lastLevelUpTime = 0
    end

    ISSkillProgressBar.updateAlpha()
    if self.reloadSkillBar then
        self.progressBarLoaded = false
        self.reloadSkillBar = false
        for _, progressBar in pairs(self.progressBars) do
            self:removeChild(progressBar)
        end
        self.progressBars = {}
    end

    local ms = UIManager.getMillisSinceLastRender()
    ISCharacterInfo.timerMultiplierAnim = ISCharacterInfo.timerMultiplierAnim + ms
    if ISCharacterInfo.timerMultiplierAnim <= 500 then
        ISCharacterInfo.animOffset = -1
    elseif ISCharacterInfo.timerMultiplierAnim <= 1000 then
        ISCharacterInfo.animOffset = 0
    elseif ISCharacterInfo.timerMultiplierAnim <= 1500 then
        ISCharacterInfo.animOffset = 15
    elseif ISCharacterInfo.timerMultiplierAnim <= 2000 then
        ISCharacterInfo.animOffset = 30
    else
        ISCharacterInfo.timerMultiplierAnim = 0
    end

    local left = UI_BORDER_SPACING * 2 + BUTTON_HGT + 1
    local fontOffset = (BUTTON_HGT - FONT_HGT_SMALL) / 2
    for index, parentPerk in ipairs(self.sorted) do
        local perkList = self.perks[parentPerk:getType()]
        self:drawText(parentPerk:getName(), left, y + fontOffset, 1, 1, 1, 1, UIFont.Small)
        self.buttonList[index]:setY(y)
        y = y + BUTTON_HGT
        if not self.collapse[index] then
            self:drawTexture(self.SkillBarSeparator, 0, y + UI_BORDER_SPACING, 1, 1, 1, 1)
            y = y + UI_BORDER_SPACING
            for _, perk in ipairs(perkList) do
                local perkType = perk:getType()
                local xpBoost = self.char:getXp():getPerkBoost(perkType)
                local r, g, b = 1, 1, 1
                if xpBoost == 0 then
                    r, g, b = 0.54, 0.54, 0.54
                elseif xpBoost == 1 then
                    r, g, b = 0.8, 0.8, 0.8
                elseif xpBoost == 3 then
                    r, g, b = 1, 0.83, 0
                end
                if recentSkillNames[perk:getName()] then
                    r, g, b = 0.4, 1, 0.4
                end
                self:drawText(perk:getName(), left + UI_BORDER_SPACING * 2, y + fontOffset, r, g, b, 1, UIFont.Small)

                if self.char:getXp():getMultiplier(perkType) > 0 then
                    local arrowPixelOffset = 2
                    local arrowOffset = math.floor((BUTTON_HGT - self.arrow:getHeight()) / 2) - arrowPixelOffset
                    self:drawTexture(self.disabledArrow, UI_BORDER_SPACING + 1 - arrowPixelOffset, y + arrowOffset, 1, 1, 1, 1)
                    self:drawTexture(self.disabledArrow, UI_BORDER_SPACING + 16 - arrowPixelOffset, y + arrowOffset, 1, 1, 1, 1)
                    self:drawTexture(self.disabledArrow, UI_BORDER_SPACING + 31 - arrowPixelOffset, y + arrowOffset, 1, 1, 1, 1)
                    if ISCharacterInfo.animOffset > -1 then
                        self:drawTexture(self.arrow, UI_BORDER_SPACING + 1 + ISCharacterInfo.animOffset - arrowPixelOffset, y + arrowOffset, 1, 1, 1, 1)
                    end
                end

                if not self.progressBarLoaded then
                    local skillPointSize = math.floor((FONT_HGT_SMALL + 6) / 2)
                    local skillPointOffset = (BUTTON_HGT - skillPointSize) / 2
                    local progressBar = ISSkillProgressBar:new(left + UI_BORDER_SPACING * 3 + self.txtLen, y + skillPointOffset, 0, 0, self.playerNum, perk, self)
                    progressBar:initialise()
                    self:addChild(progressBar)
                    table.insert(self.progressBars, progressBar)
                end
                y = y + BUTTON_HGT
            end
        end
        y = y + UI_BORDER_SPACING
    end
    y = y + 1

    local skillPointSize = math.floor((FONT_HGT_SMALL + 6) / 2)
    local skillPointSpacing = getCore():getOptionFontSizeReal()
    self:setWidthAndParentWidth(math.max(self.width, left + UI_BORDER_SPACING * 4 + self.txtLen + skillPointSize * 10 + skillPointSpacing * 9 + SCROLL_BAR_WIDTH + 1))
    self:setHeightAndParentHeight(math.min(y, 800))
    self:setScrollHeight(y)
    self.progressBarLoaded = true

    if self.joyfocus and self.joypadIndex and self.joypadIndex >= 1 and self.joypadIndex <= #self.progressBars then
        local progressBar = self.progressBars[self.joypadIndex]
        local focusLeft = progressBar:getX() - (self.txtLen + 45)
        local focusRight = progressBar:getX() + progressBar:getWidth()
        self:drawRectBorder(focusLeft - 2, progressBar:getY() - 2, (focusRight - focusLeft) + 2, progressBar:getHeight() + 3, 0.4, 0.2, 1.0, 1.0)
        if progressBar.tooltip then
            progressBar.tooltip.followMouse = false
            progressBar.tooltip:setX(progressBar:getAbsoluteX())
            local tooltipY = progressBar:getAbsoluteY() + progressBar:getHeight() + 1
            if tooltipY + progressBar.tooltip:getHeight() > getCore():getScreenHeight() then
                tooltipY = progressBar:getAbsoluteY() - progressBar.tooltip:getHeight() - 1
            end
            progressBar.tooltip:setY(tooltipY)
        end
    end

    self:clearStencilRect()
end

local function updateXpTracking(playerObj, settings)
    if not playerObj or not isSkillFilterEnabled(settings) then
        return
    end

    local nowHours = getWorldAgeHours()
    local xp = playerObj:getXp()
    if not nowHours or not xp then
        return
    end

    local playerIndex = playerObj:getPlayerNum() or 0
    local baselines = getPlayerState(xpBaselinesByPlayer, playerIndex)
    local recent = getPlayerState(recentXpByPlayer, playerIndex)

    for index = 0, PerkFactory.PerkList:size() - 1 do
        local perk = PerkFactory.PerkList:get(index)
        if perk and perk:getParent() ~= Perks.None then
            local perkType = perk:getType()
            local currentXp = xp:getXP(perkType)
            local previousXp = baselines[perkType]
            if previousXp ~= nil and currentXp > previousXp then
                recent[perkType] = nowHours
            end
            baselines[perkType] = currentXp
        end
    end

end

function SkillFilter.init(settings, logger)
    if patched then
        logger.debug("UIFixes.SkillFilter already patched")
        return
    end

    if not ISCharacterInfo or not ISCharacterInfo.loadPerk or not ISCharacterInfo.createChildren or not ISCharacterInfo.render then
        logger.warn("UIFixes.SkillFilter could not patch ISCharacterInfo")
        return
    end

    originalLoadPerk = ISCharacterInfo.loadPerk
    originalCreateChildren = ISCharacterInfo.createChildren
    originalRender = ISCharacterInfo.render

    ISCharacterInfo.loadPerk = function(self)
        local allPerks = originalLoadPerk(self)
        if allPerks == nil or not isSkillFilterEnabled(settings) then
            return allPerks
        end

        local mode = getPanelMode(self)
        if mode == MODE_NONE then
            return allPerks
        end

        local filtered = {}
        for parentPerk, perkList in pairs(allPerks) do
            local keep = {}
            for i = 1, #perkList do
                local perk = perkList[i]
                local ok, include = pcall(function()
                    return shouldIncludePerk(self, perk, mode, settings)
                end)
                if ok and include then
                    table.insert(keep, perk)
                end
            end
            if #keep > 0 then
                filtered[parentPerk] = keep
            end
        end

        return filtered
    end

    ISCharacterInfo.createChildren = function(self)
        originalCreateChildren(self)
        if isSkillFilterEnabled(settings) then
            ensureModeDropdown(self, settings)
        elseif self.qolSkillFilterModeDropdown and self.qolSkillFilterModeDropdown.setVisible then
            self.qolSkillFilterModeDropdown:setVisible(false)
        end
    end

    ISCharacterInfo.render = function(self)
        if isSkillFilterEnabled(settings) then
            ensureModeDropdown(self, settings)
            updateModeDropdownPosition(self, settings)
            refreshLayoutIfNeeded(self, settings)
            if self.qolSkillFilterModeDropdown and self.qolSkillFilterModeDropdown.setVisible then
                self.qolSkillFilterModeDropdown:setVisible(true)
            end
        elseif self.qolSkillFilterModeDropdown and self.qolSkillFilterModeDropdown.setVisible then
            self.qolSkillFilterModeDropdown:setVisible(false)
        end

        if isSkillFilterEnabled(settings) then
            renderWithRecentXpHighlights(self, settings)
        else
            originalRender(self)
        end
    end

    if not trackingInstalled and Events and Events.OnPlayerUpdate then
        Events.OnPlayerUpdate.Add(function(playerObj)
            local ok, err = pcall(function()
                updateXpTracking(playerObj, settings)
            end)
            if not ok then
                logger.error("UIFixes.SkillFilter XP tracker error: " .. tostring(err))
            end
        end)
        trackingInstalled = true
    end

    patched = true
    logger.info("UIFixes.SkillFilter patch active")
end

return SkillFilter
