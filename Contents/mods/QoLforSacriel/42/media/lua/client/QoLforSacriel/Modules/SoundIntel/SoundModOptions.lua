local SoundModOptions = {}
local MOD_OPTIONS_ID = "QoLforSacriel.SoundIntel"
QoLforSacriel_SoundIntel_Debug = QoLforSacriel_SoundIntel_Debug or {}

local META_TEST_NAMES = {
    "MetaDogBark",
    "MetaScream",
    "MetaOwl",
    "MetaWolfHowl",
}

local function chooseDebugMetaName()
    local index = ZombRand(#META_TEST_NAMES) + 1
    return META_TEST_NAMES[index]
end

local function onTriggerRandomMetaEvent(_, _, logger)
    if not getPlayer or not getPlayer() then
        if logger then
            logger.warn("SoundIntel random meta test requires an active game session")
        end
        return
    end

    if not AmbientStreamManager or not AmbientStreamManager.instance or not AmbientStreamManager.instance.addRandomAmbient then
        if logger then
            logger.error("SoundIntel random meta test unavailable: AmbientStreamManager missing")
        end
        return
    end

    local debugName = chooseDebugMetaName()
    QoLforSacriel_SoundIntel_Debug.pendingMetaTest = {
        name = debugName,
        queuedAtMs = getTimestampMs and getTimestampMs() or math.floor((getTimestamp() or 0) * 1000),
    }

    local ok, err = pcall(function()
        AmbientStreamManager.instance:addRandomAmbient(true)
    end)
    if not ok then
        if logger then
            logger.error("SoundIntel random meta test failed: " .. tostring(err))
        end
        return
    end

    if logger then
        logger.info("SoundIntel random meta test triggered: " .. tostring(debugName))
    end
end

function SoundModOptions.register(logger)
    if not PZAPI or not PZAPI.ModOptions or not PZAPI.ModOptions.create then
        if logger then
            logger.debug("SoundIntel ModOptions unavailable; using fallback settings")
        end
        return nil
    end

    local options = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
    if options then
        return options
    end

    options = PZAPI.ModOptions:create(MOD_OPTIONS_ID, "UI_QoLforSacriel_SoundIntel_Title")
    options:addTitle("UI_QoLforSacriel_SoundIntel_Title")
    options:addDescription("UI_QoLforSacriel_SoundIntel_PerformanceNote")
    options:addTickBox("enabled", "UI_QoLforSacriel_SoundIntel_Enable", false, "UI_QoLforSacriel_SoundIntel_Enable_Tooltip")
    options:addTickBox("useAmbientCorrelation", "UI_QoLforSacriel_SoundIntel_UseAmbientCorrelation", true, "UI_QoLforSacriel_SoundIntel_UseAmbientCorrelation_Tooltip")
    options:addTickBox("zMarkerEnabled", "UI_QoLforSacriel_SoundIntel_ZMarkerEnabled", true, "UI_QoLforSacriel_SoundIntel_ZMarkerEnabled_Tooltip")
    options:addTickBox("enableInferredZombie", "UI_QoLforSacriel_SoundIntel_EnableInferredZombie", true, "UI_QoLforSacriel_SoundIntel_EnableInferredZombie_Tooltip")
    options:addTickBox("enableInferredAnimal", "UI_QoLforSacriel_SoundIntel_EnableInferredAnimal", true, "UI_QoLforSacriel_SoundIntel_EnableInferredAnimal_Tooltip")
    options:addTickBox("showSourceLabel", "UI_QoLforSacriel_SoundIntel_ShowSourceLabel", true, "UI_QoLforSacriel_SoundIntel_ShowSourceLabel_Tooltip")
    options:addTickBox("showOutsideHearing", "UI_QoLforSacriel_SoundIntel_ShowOutsideHearing", false, "UI_QoLforSacriel_SoundIntel_ShowOutsideHearing_Tooltip")
    options:addSlider("arrowScalePercent", "UI_QoLforSacriel_SoundIntel_ArrowScale", 60, 180, 5, 100, "UI_QoLforSacriel_SoundIntel_ArrowScale_Tooltip")

    options:addSlider("maxTrackedCues", "UI_QoLforSacriel_SoundIntel_MaxTrackedCues", 4, 128, 1, 24, "UI_QoLforSacriel_SoundIntel_MaxTrackedCues_Tooltip")
    options:addSlider("cueDurationMs", "UI_QoLforSacriel_SoundIntel_CueDurationMs", 300, 5000, 100, 1400, "UI_QoLforSacriel_SoundIntel_CueDurationMs_Tooltip")
    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_SoundIntel_CategoryTitle")
    options:addTickBox("catPlayerLocal", "UI_QoLforSacriel_SoundIntel_CategoryPlayerLocal", true, "UI_QoLforSacriel_SoundIntel_CategoryPlayerLocal_Tooltip")
    options:addTickBox("catZombie", "UI_QoLforSacriel_SoundIntel_CategoryZombie", true, "UI_QoLforSacriel_SoundIntel_CategoryZombie_Tooltip")
    options:addTickBox("catCombat", "UI_QoLforSacriel_SoundIntel_CategoryCombat", true, "UI_QoLforSacriel_SoundIntel_CategoryCombat_Tooltip")
    options:addTickBox("catEnvironment", "UI_QoLforSacriel_SoundIntel_CategoryEnvironment", true, "UI_QoLforSacriel_SoundIntel_CategoryEnvironment_Tooltip")
    options:addTickBox("catVehicle", "UI_QoLforSacriel_SoundIntel_CategoryVehicle", true, "UI_QoLforSacriel_SoundIntel_CategoryVehicle_Tooltip")
    options:addTickBox("catAlarmAndSignal", "UI_QoLforSacriel_SoundIntel_CategoryAlarmAndSignal", true, "UI_QoLforSacriel_SoundIntel_CategoryAlarmAndSignal_Tooltip")
    options:addTickBox("catMeta", "UI_QoLforSacriel_SoundIntel_CategoryMeta", true, "UI_QoLforSacriel_SoundIntel_CategoryMeta_Tooltip")
    options:addTickBox("catUnknown", "UI_QoLforSacriel_SoundIntel_CategoryUnknown", true, "UI_QoLforSacriel_SoundIntel_CategoryUnknown_Tooltip")

    return options
end

return SoundModOptions
