-- ff-assisted
local WashAllOrder = {}

local installed = false
local patched = false
local settingsRef = nil
local loggerRef = nil
local originalOnWashClothing = nil

local function logDebug(message)
    if settingsRef
        and settingsRef.get
        and settingsRef.get("QoLforSacriel_DebugLogs") == true
        and loggerRef
        and loggerRef.debug
    then
        loggerRef.debug("UIFixes.WashAllOrder: " .. tostring(message))
    end
end

local function isEnabled()
    return settingsRef
        and settingsRef.isEnabled
        and settingsRef.isEnabled("QoLforSacriel_EnableUIFixes") == true
        and settingsRef.get
        and settingsRef.get("QoLforSacriel_UIFixes_EnableWashAllBloodiestFirst") == true
end

local function getBloodScore(item)
    if not item then
        return 0
    end

    if (instanceof(item, "Clothing") or instanceof(item, "InventoryContainer")) and item.getBloodClothingType then
        local coveredParts = BloodClothingType.getCoveredParts(item:getBloodClothingType())
        if coveredParts then
            local blood = 0
            for index = 0, coveredParts:size() - 1 do
                blood = blood + item:getBlood(coveredParts:get(index))
            end
            return blood
        end
    end

    if item.getBloodLevel then
        return item:getBloodLevel()
    end
    return 0
end

local function getBloodiestFirst(washList)
    if not washList or #washList < 2 then
        return washList
    end

    local scoredItems = {}
    for index, item in ipairs(washList) do
        scoredItems[#scoredItems + 1] = {
            item = item,
            originalIndex = index,
            bloodScore = getBloodScore(item),
        }
    end

    table.sort(scoredItems, function(left, right)
        if left.bloodScore == right.bloodScore then
            return left.originalIndex < right.originalIndex
        end
        return left.bloodScore > right.bloodScore
    end)

    local sortedItems = {}
    for index, entry in ipairs(scoredItems) do
        sortedItems[index] = entry.item
    end
    logDebug("sorted " .. tostring(#sortedItems) .. " Wash All items; highestBlood=" .. tostring(scoredItems[1].bloodScore))
    return sortedItems
end

local function patchWorldContextMenu()
    if patched then
        return true
    end

    pcall(require, "ISUI/ISWorldObjectContextMenu")
    if not ISWorldObjectContextMenu or type(ISWorldObjectContextMenu.onWashClothing) ~= "function" then
        return false
    end

    originalOnWashClothing = ISWorldObjectContextMenu.onWashClothing
    ISWorldObjectContextMenu.onWashClothing = function(playerObj, sink, soapList, washList, singleClothing)
        if not isEnabled() or not washList or #washList < 2 then
            return originalOnWashClothing(playerObj, sink, soapList, washList, singleClothing)
        end
        return originalOnWashClothing(playerObj, sink, soapList, getBloodiestFirst(washList), singleClothing)
    end

    patched = true
    if loggerRef and loggerRef.info then
        loggerRef.info("UIFixes.WashAllOrder patched Wash All ordering")
    end
    return true
end

function WashAllOrder.init(settings, logger)
    if installed then
        return
    end

    settingsRef = settings
    loggerRef = logger
    if not patchWorldContextMenu() and Events and Events.OnGameStart then
        Events.OnGameStart.Add(patchWorldContextMenu)
    end

    installed = true
end

return WashAllOrder