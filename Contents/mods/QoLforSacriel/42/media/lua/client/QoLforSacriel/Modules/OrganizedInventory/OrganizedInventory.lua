-- ff-assisted
local OrganizedInventory = {}

local EquipmentStatsDisplay = require "QoLforSacriel/Modules/UIFixes/EquipmentStatsDisplay"

require "ISUI/InventoryWindow/ISInventoryWindowContainerControls"
require "ISUI/InventoryWindow/ISInventoryWindowControlHandler"
require "ISUI/LootWindow/ISLootWindowContainerControls"
require "ISUI/LootWindow/ISLootWindowObjectControlHandler"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISTickBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollBar"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISInventoryTransferUtil"

local FOOD_ITEM_TAGS = require "QoLforSacriel/Modules/OrganizedInventory/FoodItemTags"

local MODULE_SETTING = "QoLforSacriel_EnableOrganizedInventory"
local TAGS_KEY = "QoLforSacriel.OrganizedInventory.tags"
local TAGS_BY_CONTAINER_INDEX_KEY = "QoLforSacriel.OrganizedInventory.tagsByContainerIndex"
local POPUP_WIDTH = 720
local POPUP_COMPACT_HEIGHT = 220
local TAG_COLUMNS = 3
local TAG_ROW_HEIGHT = 14
local POPUP_SECTION_SPACING = 10
local POPUP_BUTTON_HEIGHT = 25
local POPUP_BOTTOM_MARGIN = 10
local POPUP_SCREEN_MARGIN = 20
local EVERYTHING_ELSE_TAG = "EverythingElse"
local LEGACY_MATERIAL_TAG = "Material"
local MATERIAL_ALL_TAG = "Material.All"
local LEGACY_FOOD_TAG = "Food"
local FOOD_ALL_TAG = "Food.All"
local FOOD_FROZEN_TAG = "Food.Frozen"

local MATERIAL_BASIC_TAG_LIST = {
    "Material.Bone", "Material.Steel", "Material.Cotton", "Material.Fibre", "Material.Iron",
    "Material.Other", "Material.Repair", "Material.Stone", "Material.Wood",
}

local MATERIAL_ADVANCED_TAG_LIST = {
    "Material.Aluminum", "Material.Brass", "Material.Copper", "Material.Gold", "Material.Glass", "Material.Paint",
    "Material.Leather", "Material.Silver", "Material.Clay", "Material.Charcoal", "Material.ToolHead", "Material.Wallpaper",
}

local FOOD_TAG_LIST = {
    FOOD_FROZEN_TAG, "Food.Canned", "Food.Candy", "Food.Drinks", "Food.EvolvedRecipe", "Food.Fruit", "Food.Grain", "Food.Herb",
    "Food.Insect", "Food.Meat", "Food.Miscellaneous", "Food.Pickled", "Food.Plant", "Food.Prepared", "Food.Protein.Egg",
    "Food.Protein.Game", "Food.Protein.Seafood", "Food.Spice", "Food.Vegetable",
}

local BASIC_TAG_LIST = {
    "Accessory", "Clothing", "Cooking", "Electronics", EVERYTHING_ELSE_TAG, "FirstAid", "Fishing", FOOD_ALL_TAG,
    "Gardening", "Literature", MATERIAL_ALL_TAG, "ProtectiveGear", "RecipeResource", "SkillBook", "Sports", "Tool",
    "Water", "WaterContainer", "Weapon",
}

local CATEGORY_TAGS = {
    Accessory = { "Accessory" }, Ammo = { "Ammo" }, Animal = { "Animal" }, AnimalPart = { "AnimalPart" },
    AnimalPartWeapon = { "AnimalPart", "Weapon" }, Appearance = { "Appearance" }, Badger = { "Badger" },
    Bag = { "Bag" }, Bandage = { "Bandage" }, Bear = { "Bear" }, Beaver = { "Beaver" },
    BrokenWeapon = { "Weapon" }, Bug = { "Bug" }, Bunny = { "Bunny" }, Camping = { "Camping" },
    Cartography = { "Cartography" }, Clothing = { "Clothing" }, Communications = { "Communications" },
    Container = { "Container" }, Cooking = { "Cooking" }, CookingWeapon = { "Cooking", "Weapon" },
    Corpse = { "Corpse" }, Dog = { "Dog" }, Duck = { "Duck" }, Ears = { "Ears" }, Electronics = { "Electronics" },
    Entertainment = { "Entertainment" }, Explosives = { "Explosives" }, Eye = { "Eye" }, FireSource = { "FireSource" },
    FirstAid = { "FirstAid" }, FirstAidWeapon = { "FirstAid", "Weapon" }, Fishing = { "Fishing" },
    FishingWeapon = { "Fishing", "Weapon" }, Food = { "Food" }, Fox = { "Fox" }, Frog = { "Frog" },
    Furniture = { "Furniture" }, Gardening = { "Gardening" }, GardeningWeapon = { "Gardening", "Weapon" },
    Generic = { "Generic" }, Goblin = { "Goblin" }, Hedgehog = { "Hedgehog" }, Hidden = { "Hidden" },
    Household = { "Household" }, HouseholdWeapon = { "Household", "Weapon" }, Instrument = { "Instrument" },
    InstrumentWeapon = { "Instrument", "Weapon" }, Junk = { "Junk" }, JunkWeapon = { "Junk", "Weapon" },
    LightSource = { "LightSource" }, Literature = { "Literature" }, MaleBody = { "MaleBody" },
    Memento = { "Memento" }, Mole = { "Mole" }, Paint = { "Paint" },
    ProtectiveGear = { "ProtectiveGear" }, Raccoon = { "Raccoon" }, RecipeResource = { "RecipeResource" },
    Security = { "Security" }, SkillBook = { "SkillBook" }, Spider = { "Spider" }, Sports = { "Sports" },
    SportsWeapon = { "Sports", "Weapon" }, Squirrel = { "Squirrel" }, Tail = { "Tail" }, ["Teddy Bear"] = { "Teddy Bear" },
    Tool = { "Tool" }, ToolWeapon = { "Tool", "Weapon" }, Trapping = { "Trapping" },
    VehicleMaintenance = { "VehicleMaintenance" }, VehicleMaintenanceWeapon = { "VehicleMaintenance", "Weapon" },
    Water = { "Water" }, WaterContainer = { "WaterContainer" }, Weapon = { "Weapon" },
    WeaponCrafted = { "Weapon" }, WeaponImprovised = { "Weapon" }, WeaponPart = { "WeaponPart" }, Wound = { "Wound" },
    ZedDmg = { "ZedDmg" },
}

local MATERIAL_ITEM_TAGS = {}

local function registerMaterialItems(materialTag, itemTypes)
    for _, itemType in ipairs(itemTypes) do
        MATERIAL_ITEM_TAGS[itemType] = materialTag
    end
end

registerMaterialItems("Material.Aluminum", {
    "Base.Aluminum", "Base.AluminumFragments", "Base.AluminumScrap",
})
registerMaterialItems("Material.Bone", {
    "Base.AnimalBone", "Base.LargeAnimalBone", "Base.BoneBead_Large", "Base.SharpBoneFragment",
})
registerMaterialItems("Material.Brass", {
    "Base.BrassIngot", "Base.BrassScrap",
})
registerMaterialItems("Material.Charcoal", {
    "Base.Charcoal", "Base.Coke", "Base.CharcoalCrafted",
})
registerMaterialItems("Material.Clay", {
    "Base.ClayBrick", "Base.BucketClayCement", "Base.BucketCarvedClayCement", "Base.ClayBarMold",
    "Base.ClayBenchAnvilMold", "Base.ClayBlacksmithAnvilMold", "Base.ClayBlockAnvilMold", "Base.CeramicIngotCast",
    "Base.ClayIngotMold", "Base.ClayPot", "Base.ClaySheetMold", "Base.ClayTile", "Base.Clay",
    "Base.ClayBarMoldUnfired", "Base.ClayBenchAnvilMoldUnfired", "Base.ClayBlacksmithAnvilMoldUnfired",
    "Base.ClayBlockAnvilMoldUnfired", "Base.ClayBowlUnfired", "Base.ClayBrickUnfired", "Base.CeramicIngotCastUnfired",
    "Base.ClayIngotMoldUnfired", "Base.ClayJarUnfired", "Base.CeramicMortarandPestleUnfired", "Base.ClayMugUnfired",
    "Base.ClayPipeSegment", "Base.ClayPipeSegmentUnfired", "Base.ClayPlateUnfired", "Base.ClayPotUnfired",
    "Base.ClaySheetMoldUnfired", "Base.ClayShingle", "Base.ClayShingleUnfired", "Base.SmokingPipeUnfired",
    "Base.CeramicTeacupUnfired", "Base.ClayTileUnfired", "Base.CeramicCrucible", "Base.CeramicCrucibleSmall",
    "Base.GlassBlowingPipeUnfired", "Base.ClayJar", "Base.ClayJarGlazed", "Base.CeramicCrucibleUnfired",
    "Base.Claybag", "Base.CeramicCrucibleSmallUnfired",
})
registerMaterialItems("Material.Copper", {
    "Base.CopperIngot", "Base.CopperOre", "Base.Malachite", "Base.CopperScrap", "Base.CopperSheet",
    "Base.SmallCopperSheet", "Base.MalachiteLarge",
})
registerMaterialItems("Material.Cotton", {
    "Base.FabricRoll_Cotton", "Base.RippedSheets", "Base.RippedSheetsDirty", "Base.AlcoholRippedSheets",
    "Base.RippedSheetsBundle", "Base.RippedSheetsDirtyBundle", "Base.RippedSheetsSterilizedBundle", "Base.Sheet",
    "Base.SheetRope", "Base.SheetRopeBundle",
})
registerMaterialItems("Material.Fibre", {
    "Base.Thread_Aramid", "Base.BurlapPiece", "Base.CheeseCloth", "Base.DentalFloss", "Base.FishingLine", "Base.Flax",
    "Base.FlaxBroken", "Base.FlaxDried", "Base.FlaxHeckled", "Base.FlaxRippled", "Base.FlaxScutched", "Base.FlaxTow",
    "Base.HempBroken", "Base.HempScutched", "Base.Dogbane", "Base.PremiumFishingLine", "Base.WoolRaw", "Base.Rope",
    "Base.RopeStack", "Base.Thread_Sinew", "Base.String", "Base.Thread", "Base.Twine", "Base.Yarn",
})
registerMaterialItems("Material.Glass", {
    "Base.GlassBlowingPipe", "Base.GlassPanel", "Base.LanternGlass", "Base.CeramicCrucibleWithGlass",
})
registerMaterialItems("Material.Gold", {
    "Base.GoldCup", "Base.GoldScrap", "Base.Goblet_Gold", "Base.GoldBar", "Base.Hat_HockeyMask_Gold", "Base.GoldSheet",
    "Base.Lantern_Hurricane_Gold", "Base.SmallGoldBar",
})
registerMaterialItems("Material.Iron", {
    "Base.CrudeSwordBlade_Broken", "Base.CrudeSwordBlade_Broken_NoTang", "Base.DrawPlate", "Base.HeavyChainLink",
    "Base.IronBand", "Base.IronBandSmall", "Base.IronBar", "Base.IronBarHalf", "Base.IronBarMold", "Base.IronBarQuarter",
    "Base.IronBlock", "Base.PiercedIronBlock", "Base.IronBloom", "Base.IronChunk", "Base.PiercedIronChunk", "Base.IronIngot",
    "Base.PiercedIronIngot", "Base.IronIngotMold", "Base.IronOre", "Base.Hematite", "Base.IronPiece", "Base.MetalPipe",
    "Base.IronScrap", "Base.CeramicCrucible_Iron", "Base.HematiteLarge", "Base.Latch", "Base.RailroadSpike",
    "Base.ScrapMetal", "Base.Sword_Scrap_Shard", "Base.CrudeSword_Shard", "Base.CeramicCrucibleSmall_Iron",
})
registerMaterialItems("Material.Leather", {
    "Base.CalfLeather_Angus_Fur", "Base.CalfLeather_Angus_Full", "Base.CalfLeather_Angus_Fur_Tan",
    "Base.CalfLeather_Angus_Fur_Tan_Wet", "Base.CowLeather_Angus_Fur", "Base.CowLeather_Angus_Full",
    "Base.CowLeather_Angus_Fur_Tan", "Base.CowLeather_Angus_Fur_Tan_Wet", "Base.CowLeather_Angus_Fur_Tan_Medium",
    "Base.CowLeather_Angus_Fur_Tan_Small", "Base.PigLeather_Black_Fur", "Base.PigLeather_Black_Full",
    "Base.PigLeather_Black_Fur_Tan", "Base.PigLeather_Black_Fur_Tan_Wet", "Base.PigLeather_Black_Fur_Tan_Small",
    "Base.PigletLeather_Black_Fur", "Base.PigletLeather_Black_Full", "Base.PigletLeather_Black_Fur_Tan",
    "Base.PigletLeather_Black_Fur_Tan_Wet", "Base.CowHide", "Base.DappleDeerHide", "Base.DeerHide", "Base.DeerLeather_Fur",
    "Base.DeerLeather_Full", "Base.DeerLeather_Fur_Tan", "Base.DeerLeather_Fur_Tan_Wet", "Base.DeerLeather_Fur_Tan_Small",
    "Base.FawnLeather_Fur", "Base.FawnLeather_Full", "Base.FawnLeather_Fur_Tan", "Base.FawnLeather_Fur_Tan_Wet",
    "Base.CalfLeather_Holstein_Fur", "Base.CalfLeather_Holstein_Full", "Base.CalfLeather_Holstein_Fur_Tan",
    "Base.CalfLeather_Holstein_Fur_Tan_Wet", "Base.CowLeather_Holstein_Fur", "Base.CowLeather_Holstein_Full",
    "Base.CowLeather_Holstein_Fur_Tan", "Base.CowLeather_Holstein_Fur_Tan_Wet", "Base.CowLeather_Holstein_Fur_Tan_Medium",
    "Base.CowLeather_Holstein_Fur_Tan_Small", "Base.LambLeather_Fur", "Base.LambLeather_Full", "Base.LambLeather_Fur_Tan",
    "Base.LambLeather_Fur_Tan_Wet", "Base.PigLeather_Landrace_Fur", "Base.PigLeather_Landrace_Full",
    "Base.PigLeather_Landrace_Fur_Tan", "Base.PigLeather_Landrace_Fur_Tan_Wet", "Base.PigLeather_Landrace_Fur_Tan_Small",
    "Base.PigletLeather_Landrace_Fur", "Base.PigletLeather_Landrace_Full", "Base.PigletLeather_Landrace_Fur_Tan",
    "Base.PigletLeather_Landrace_Fur_Tan_Wet", "Base.Leather_Crude_Large", "Base.Leather_Crude_Large_Tan",
    "Base.Leather_Crude_Large_Tan_Wet", "Base.LeatherStrips", "Base.LeatherStripsDirty", "Base.LeatherStripsBundle",
    "Base.LeatherStripsDirtyBundle", "Base.Leather_Crude_Medium", "Base.Leather_Crude_Medium_Tan",
    "Base.Leather_Crude_Medium_Tan_Wet", "Base.RabbitLeather_Fur", "Base.RabbitLeather_Grey_Fur",
    "Base.RabbitLeather_Full", "Base.RabbitLeather_Grey_Full", "Base.RabbitLeather_Fur_Tan",
    "Base.RabbitLeather_Grey_Fur_Tan", "Base.RabbitLeather_Fur_Tan_Wet", "Base.RabbitLeather_Grey_Fur_Tan_Wet",
    "Base.CalfLeather_Simmental_Fur", "Base.CalfLeather_Simmental_Full", "Base.CalfLeather_Simmental_Fur_Tan",
    "Base.CalfLeather_Simmental_Fur_Tan_Wet", "Base.CowLeather_Simmental_Fur", "Base.CowLeather_Simmental_Full",
    "Base.CowLeather_Simmental_Fur_Tan", "Base.CowLeather_Simmental_Fur_Tan_Wet", "Base.CowLeather_Simmental_Fur_Tan_Medium",
    "Base.CowLeather_Simmental_Fur_Tan_Small", "Base.Leather_Crude_Small", "Base.Leather_Crude_Small_Tan",
    "Base.Leather_Crude_Small_Tan_Wet",
})
registerMaterialItems("Material.Other", {
    "Base.ConcretePowder", "Base.PlasterPowder", "Base.WallpaperPastePowder", "Base.BarbedWire", "Base.BarbedWireStack",
    "Base.BarricadeCube_Folded", "Base.BenchAnvilUntreated", "Base.BlacksmithAnvilUntreated", "Base.BlockAnvilUntreated",
    "Base.BlowerFan", "Base.IndustrialDye", "Base.BrainTan", "Base.AdhesiveTapeBox", "Base.DuctTapeBox", "Base.NailsBox",
    "Base.PaperclipBox", "Base.ScrewsBox", "Base.Sparklers", "Base.BucketConcreteFull", "Base.BucketPlasterFull",
    "Base.BucketWallpaperPaste", "Base.Buckle", "Base.Button", "Base.NailsCarton", "Base.ScrewsCarton",
    "Base.BucketCarvedConcreteFull", "Base.BucketCarvedPlasterFull", "Base.BucketCarvedWallpaperPaste", "Base.Pillow_Crafted",
    "Base.Hinge", "Base.Doorknob", "Base.Drawer", "Base.GunPowder", "Base.LargeBellows", "Base.PackFrameLarge",
    "Base.LeadPipe", "Base.Nails", "Base.NutsBolts", "Base.PackFrame", "Base.Paperclip", "Base.Pillow", "Base.Dirtbag",
    "Base.Gravelbag", "Base.Sandbag", "Base.Screws", "Base.SmokingPipe", "Base.Tarp", "Base.TarpPiece", "Base.TirePiece",
    "Base.WeldingRods", "Base.Wire", "Base.WireStack",
})
registerMaterialItems("Material.Paint", {
    "Base.PaintBlack", "Base.PaintBlue", "Base.PaintBrown", "Base.PaintCyan", "Base.PaintGrey", "Base.PaintGreen",
    "Base.PaintLightBlue", "Base.PaintLightBrown", "Base.PaintOrange", "Base.PaintPink", "Base.PaintPurple", "Base.PaintRed",
    "Base.PaintTurquoise", "Base.PaintWhite", "Base.PaintYellow", "Base.SprayPaint",
})
registerMaterialItems("Material.Repair", {
    "Base.Scotchtape", "Base.DuctTape", "Base.Epoxy", "Base.FiberglassTape", "Base.Glue", "Base.Woodglue",
})
registerMaterialItems("Material.Silver", {
    "Base.Lantern_Hurricane_Silver", "Base.SilverCup", "Base.SilverScrap", "Base.Goblet_Silver", "Base.SilverBar",
    "Base.Hat_HockeyMask_Silver", "Base.SilverSheet", "Base.SmallSilverBar",
})
registerMaterialItems("Material.Steel", {
    "Base.Katana_Blade_Broken", "Base.SwordBlade_Broken", "Base.SwordBlade_Broken_NoTang", "Base.CircularSawblade",
    "Base.CircularSawblade_Half", "Base.Katana_Shard", "Base.CeramicCrucible_Steel", "Base.PropaneTank",
    "Base.CeramicCrucibleSmall_Steel", "Base.SteelBar", "Base.SteelBarHalf", "Base.SteelBarMold", "Base.SteelBarQuarter",
    "Base.SteelBlock", "Base.PiercedSteelBlock", "Base.SteelChunk", "Base.PiercedSteelChunk", "Base.SteelIngot",
    "Base.PiercedSteelIngot", "Base.SteelIngotMold", "Base.SteelPiece", "Base.MetalBar", "Base.SteelRodHalf",
    "Base.SteelRodQuarter", "Base.SteelScrap", "Base.SheetMetal", "Base.SmallSheetMetal", "Base.SteelSlug", "Base.Sword_Shard",
})
registerMaterialItems("Material.Stone", {
    "Base.FlintNodule", "Base.FlatStone", "Base.LargeStone", "Base.Limestone", "Base.Quicklime", "Base.SharpedStone",
    "Base.StoneWheelSmall", "Base.Stone2", "Base.StoneBlock", "Base.StoneWheel",
})
registerMaterialItems("Material.ToolHead", {
    "Base.OldAxeHead", "Base.BallPeenHammerHead", "Base.HatchetHead_Bone", "Base.ClawhammerHead", "Base.ClubHammerHead",
    "Base.FireAxeHead", "Base.GardenForkHead", "Base.GardenForkHead_Forged", "Base.GardenHoeHead", "Base.HacksawBlade",
    "Base.HandScytheBlade", "Base.HandAxeHead", "Base.HuntingKnifeBlade", "Base.Katana_Blade", "Base.KitchenKnifeBlade",
    "Base.LargeKnifeBlade", "Base.StoneAxeHead", "Base.SpearLongHead", "Base.LongCrudeBlade", "Base.StoneBladeLong",
    "Base.MaceHead", "Base.MacheteBlade", "Base.MacheteBlade_NoTang", "Base.MeatCleaverBlade", "Base.SpearHead",
    "Base.PickAxeHead", "Base.RakeHead", "Base.ScytheBlade", "Base.ShortSwordBlade", "Base.ShortSwordBlade_NoTang",
    "Base.CrudeBlade", "Base.CrudeShortSwordBlade", "Base.CrudeShortSwordBlade_NoTang", "Base.CrudeSwordBlade",
    "Base.CrudeSwordBlade_NoTang", "Base.SledgehammerHead", "Base.SmallSawblade", "Base.SmithingHammerHead",
    "Base.SpadeHead_Forged", "Base.StoneBlade", "Base.StoneMaceHead", "Base.StoneMaulHead", "Base.SwordBlade",
    "Base.SwordBlade_NoTang", "Base.WoodAxeHead",
})
registerMaterialItems("Material.Wallpaper", {
    "Base.Wallpaper_BeigeStripe", "Base.Wallpaper_BlackFloral", "Base.Wallpaper_BlueStripe", "Base.Wallpaper_GreenDiamond",
    "Base.Wallpaper_GreenFloral", "Base.Wallpaper_PinkChevron", "Base.Wallpaper_PinkFloral",
})
registerMaterialItems("Material.Wood", {
    "Base.Firewood", "Base.FirewoodBundle", "Base.LargeBranch", "Base.LongHandle", "Base.LargePlank", "Base.Log",
    "Base.LogStacks4", "Base.LogStacks3", "Base.LogStacks2", "Base.LongStick", "Base.Handle", "Base.Plank", "Base.Sapling",
    "Base.SmallHandle", "Base.TreeBranch2", "Base.Twigs", "Base.WoodenBarCastMold", "Base.WoodenBenchAnvilMold",
    "Base.WoodenBlacksmithAnvilMold", "Base.WoodenBlockAnvilMold", "Base.WoodenBrickMold", "Base.WoodenIngotCastMold",
    "Base.WoodenStick2", "Base.WoodenShingleMold", "Base.WoodenTileMold",
})

local TAG_CATALOG = {}
for category, tags in pairs(CATEGORY_TAGS) do
    for index = 1, #tags do
        TAG_CATALOG[tags[index]] = true
    end
end
TAG_CATALOG[EVERYTHING_ELSE_TAG] = true
for _, tag in ipairs(BASIC_TAG_LIST) do
    TAG_CATALOG[tag] = true
end
for _, tag in ipairs(MATERIAL_BASIC_TAG_LIST) do
    TAG_CATALOG[tag] = true
end
for _, tag in ipairs(MATERIAL_ADVANCED_TAG_LIST) do
    TAG_CATALOG[tag] = true
end
for _, tag in ipairs(FOOD_TAG_LIST) do
    TAG_CATALOG[tag] = true
end

local TAG_LIST = {}
for tag in pairs(TAG_CATALOG) do
    table.insert(TAG_LIST, tag)
end
table.sort(TAG_LIST)

local BASIC_TAG_SET = {}
for _, tag in ipairs(BASIC_TAG_LIST) do
    BASIC_TAG_SET[tag] = true
end

local MATERIAL_TAG_SET = {}
for _, tag in ipairs(MATERIAL_BASIC_TAG_LIST) do
    MATERIAL_TAG_SET[tag] = true
end
for _, tag in ipairs(MATERIAL_ADVANCED_TAG_LIST) do
    MATERIAL_TAG_SET[tag] = true
end

local FOOD_TAG_SET = {}
for _, tag in ipairs(FOOD_TAG_LIST) do
    FOOD_TAG_SET[tag] = true
end

local ADVANCED_TAG_LIST = {}
for _, tag in ipairs(TAG_LIST) do
    if not BASIC_TAG_SET[tag] and not MATERIAL_TAG_SET[tag] and not FOOD_TAG_SET[tag] then
        table.insert(ADVANCED_TAG_LIST, tag)
    end
end

local installed = false
local settingsRef = nil
local loggerRef = nil

local function getTextOrFallback(key, fallback)
    if getTextOrNull then
        local translated = getTextOrNull(key)
        if translated and translated ~= "" then
            return translated
        end
    end
    return fallback
end

local function logDebug(message)
    if loggerRef and loggerRef.debug and settingsRef and settingsRef.get
        and settingsRef.get("QoLforSacriel_DebugLogs") == true then
        loggerRef.debug("OrganizedInventory: " .. tostring(message))
    end
end

local function isModuleEnabled()
    return settingsRef and settingsRef.isEnabled and settingsRef.isEnabled(MODULE_SETTING) == true
end

local function callMethod(object, methodName, ...)
    if not object or type(object[methodName]) ~= "function" then
        return nil
    end
    local ok, result = pcall(object[methodName], object, ...)
    if ok then
        return result
    end
    return nil
end

local function getTagOwner(container)
    local parent = callMethod(container, "getParent")
    if parent and type(parent.getModData) == "function" then
        return parent
    end

    local containingItem = callMethod(container, "getContainingItem")
    if containingItem and type(containingItem.getModData) == "function" then
        return containingItem
    end
    return nil
end

local function getContainerTagBucketKey(container, owner)
    local containerIndex = callMethod(owner, "getContainerIndex", container)
    if type(containerIndex) == "number" and containerIndex >= 0 then
        return tostring(containerIndex)
    end
    return nil
end

local function normalizeTagSet(tags)
    if type(tags) ~= "table" then
        return nil
    end
    if tags[LEGACY_MATERIAL_TAG] ~= true and tags[LEGACY_FOOD_TAG] ~= true then
        return tags
    end

    local normalizedTags = {}
    for tag, selected in pairs(tags) do
        if tag ~= LEGACY_MATERIAL_TAG and tag ~= LEGACY_FOOD_TAG then
            normalizedTags[tag] = selected
        end
    end
    if tags[LEGACY_MATERIAL_TAG] == true then
        normalizedTags[MATERIAL_ALL_TAG] = true
    end
    if tags[LEGACY_FOOD_TAG] == true then
        normalizedTags[FOOD_ALL_TAG] = true
    end
    return normalizedTags
end

local function getTagSet(container)
    local owner = getTagOwner(container)
    local modData = owner and callMethod(owner, "getModData") or nil
    if not modData then
        return nil
    end
    local bucketKey = getContainerTagBucketKey(container, owner)
    local tagsByContainerIndex = modData[TAGS_BY_CONTAINER_INDEX_KEY]
    local containerTags = bucketKey and type(tagsByContainerIndex) == "table" and tagsByContainerIndex[bucketKey] or nil
    if type(containerTags) == "table" then
        return normalizeTagSet(containerTags)
    end
    return normalizeTagSet(modData[TAGS_KEY])
end

local function setTagSet(container, owner, modData, tags)
    local bucketKey = getContainerTagBucketKey(container, owner)
    if not bucketKey then
        modData[TAGS_KEY] = tags
        return
    end

    local tagsByContainerIndex = modData[TAGS_BY_CONTAINER_INDEX_KEY]
    if type(tagsByContainerIndex) ~= "table" then
        tagsByContainerIndex = {}
        modData[TAGS_BY_CONTAINER_INDEX_KEY] = tagsByContainerIndex
    end
    tagsByContainerIndex[bucketKey] = tags
    modData[TAGS_KEY] = nil
end

local function getSelectedTagNames(container)
    local tagSet = getTagSet(container)
    if not tagSet then
        return {}
    end

    local names = {}
    for _, tag in ipairs(TAG_LIST) do
        if tagSet[tag] == true then
            table.insert(names, getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryTag_" .. tag, tag))
        end
    end
    table.sort(names)
    return names
end

local function getTagSummary(container)
    local tagNames = getSelectedTagNames(container)
    if #tagNames == 0 then
        return nil, nil
    end

    local shownCount = math.min(#tagNames, 2)
    local summary = getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryTags", "Tags:")
        .. " " .. table.concat(tagNames, ", ", 1, shownCount)
    if #tagNames > shownCount then
        summary = summary .. "..."
    end

    local tooltip = getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryTagsTooltip", "Selected tags")
        .. ": " .. table.concat(tagNames, ", ")
    return summary, tooltip
end

local function hasTags(container)
    local tags = getTagSet(container)
    if not tags then
        return false
    end
    for _ in pairs(tags) do
        return true
    end
    return false
end

local function isPlayerContainer(container, playerObj)
    return callMethod(container, "isInCharacterInventory", playerObj) == true
end

local function getContainerDebugName(container)
    return tostring(callMethod(container, "getType") or "unknown")
end

local function getVehicleContainerLabel(container)
    local parent = callMethod(container, "getParent")
    if not parent or not instanceof or not instanceof(parent, "BaseVehicle")
        or type(parent.getPartCount) ~= "function" or type(parent.getPartByIndex) ~= "function" then
        return nil
    end
    for index = 0, parent:getPartCount() - 1 do
        local vehiclePart = parent:getPartByIndex(index)
        if vehiclePart and vehiclePart:getItemContainer() == container then
            return getTextOrFallback("IGUI_VehiclePart" .. tostring(callMethod(container, "getType") or ""), "Vehicle container")
        end
    end
    return nil
end

local function getContainerLabel(container)
    local vehicleLabel = getVehicleContainerLabel(container)
    if vehicleLabel then
        return vehicleLabel
    end
    local containingItem = callMethod(container, "getContainingItem")
    local itemName = containingItem and callMethod(containingItem, "getName")
    if itemName and itemName ~= "" then
        return tostring(itemName)
    end
    local parentName = callMethod(callMethod(container, "getParent"), "getName")
    if parentName and parentName ~= "" then
        return tostring(parentName)
    end
    return getContainerDebugName(container)
end

local function sayFullDestination(playerObj, container, tag)
    local containerLabel = getContainerLabel(container)
    local tagLabel = getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryTag_" .. tag, tag)
    local fullSuffix = getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryDestinationFull", "is full.")
    local message = containerLabel .. " for " .. tagLabel .. " " .. fullSuffix
    callMethod(playerObj, "Say", message, 0.607, 0.717, 1.000, UIFont.Dialogue, 15, "radio")
end

local function getContainerCapacityDebugText(container, playerObj)
    local capacity = tonumber(callMethod(container, "getCapacity"))
    local effectiveCapacity = tonumber(callMethod(container, "getEffectiveCapacity", playerObj))
    local contentsWeight = tonumber(callMethod(container, "getContentsWeight"))
    local freeCapacity = tonumber(callMethod(container, "getFreeCapacity", playerObj))
    if not capacity or not effectiveCapacity or not contentsWeight or not freeCapacity then
        return "capacity: unavailable | effective capacity: unavailable | contents weight: unavailable | free capacity: unavailable"
    end
    return "capacity: " .. tostring(capacity) .. " | effective capacity: " .. tostring(effectiveCapacity)
        .. " | contents weight: " .. tostring(contentsWeight) .. " | free capacity: " .. tostring(freeCapacity)
end

local function isDirectSourceItemEligible(item, playerObj)
    if not item or callMethod(item, "isEquipped") == true then
        return false
    end
    if callMethod(item, "isFavorite") == true then
        return false
    end
    if callMethod(item, "isItemType", ItemType and ItemType.KEY_RING) == true or callMethod(item, "hasTag", ItemTag and ItemTag.KEY_RING) == true then
        return false
    end
    if callMethod(item, "getInventory") ~= nil then
        return false
    end
    local playerNum = callMethod(playerObj, "getPlayerNum")
    local hotbar = playerNum ~= nil and getPlayerHotbar and getPlayerHotbar(playerNum) or nil
    if hotbar and hotbar.isInHotbar and hotbar:isInHotbar(item) then
        return false
    end
    return true
end

local function getContainerItems(container)
    local results = {}
    local items = callMethod(container, "getItems")
    if not items or type(items.size) ~= "function" then
        return results
    end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item then
            table.insert(results, item)
        end
    end
    return results
end

local function getContainerList(playerObj)
    if not ISInventoryPaneContextMenu or type(ISInventoryPaneContextMenu.getContainers) ~= "function" then
        return {}
    end
    local containers = ISInventoryPaneContextMenu.getContainers(playerObj)
    local results = {}
    if containers and type(containers.size) == "function" then
        for index = 0, containers:size() - 1 do
            table.insert(results, containers:get(index))
        end
    end
    return results
end

local function getItemTags(item, suppressUnmappedLogs)
    local category = callMethod(item, "getDisplayCategory")
    category = category and tostring(category) or nil
    if category == LEGACY_FOOD_TAG then
        local itemType = tostring(callMethod(item, "getFullType") or "")
        local foodTag = FOOD_ITEM_TAGS[itemType]
        local tags = {}
        if callMethod(item, "isFrozen") == true then
            table.insert(tags, FOOD_FROZEN_TAG)
        end
        if foodTag then
            table.insert(tags, foodTag)
        elseif not suppressUnmappedLogs then
            logDebug("Unmapped food item " .. (itemType ~= "" and itemType or "unknown")
                .. "; routing through " .. FOOD_ALL_TAG)
        end
        table.insert(tags, FOOD_ALL_TAG)
        return tags
    end
    if category == LEGACY_MATERIAL_TAG or category == "MaterialWeapon" then
        local itemType = tostring(callMethod(item, "getFullType") or "")
        local materialTag = MATERIAL_ITEM_TAGS[itemType]
        local tags = {}
        if materialTag then
            table.insert(tags, materialTag)
        elseif not suppressUnmappedLogs then
            logDebug("Unmapped material item " .. (itemType ~= "" and itemType or "unknown")
                .. "; routing through " .. MATERIAL_ALL_TAG)
        end
        table.insert(tags, MATERIAL_ALL_TAG)
        if category == "MaterialWeapon" then
            table.insert(tags, "Weapon")
        end
        return tags
    end
    return category and CATEGORY_TAGS[category] or nil
end

local function getTooltipTagNames(item)
    local tags = getItemTags(item, true)
    if not tags then
        return {}
    end

    local names = {}
    for _, tag in ipairs(tags) do
        if tag ~= EVERYTHING_ELSE_TAG and tag ~= FOOD_ALL_TAG and tag ~= MATERIAL_ALL_TAG then
            table.insert(names, getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryTag_" .. tag, tag))
        end
    end
    return names
end

local function getTooltipTagRows(item)
    if not settingsRef or not settingsRef.isEnabled
        or settingsRef.isEnabled(MODULE_SETTING) ~= true
        or settingsRef.get("QoLforSacriel_OrganizedInventory_ShowTooltipTags") ~= true
    then
        return {}
    end

    local names = getTooltipTagNames(item)
    if #names == 0 then
        return {}
    end

    return {
        {
            label = getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryTooltipTags", "Organized Inventory"),
            value = table.concat(names, getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryTooltipTagSeparator", " -> ")),
        },
    }
end

local function getTagsDebugText(tags)
    if not tags or #tags == 0 then
        return "none"
    end
    return table.concat(tags, ", ")
end

local function getItemDebugName(item)
    return tostring(callMethod(item, "getFullType") or callMethod(item, "getName") or "unknown")
end

local function tagSetContainsAll(tagSet, tags)
    for index = 1, #tags do
        if tagSet[tags[index]] ~= true then
            return false
        end
    end
    return true
end

local function getItemWeight(item)
    local weight = callMethod(item, "getUnequippedWeight") or callMethod(item, "getActualWeight") or 0
    return math.max(0, tonumber(weight) or 0)
end

local function hasPlannedCapacity(container, item, playerObj, reservedWeight)
    if callMethod(container, "isItemAllowed", item) ~= true then
        return false
    end
    local freeCapacity = tonumber(callMethod(container, "getFreeCapacity", playerObj))
    if freeCapacity ~= nil and (reservedWeight[container] or 0) + getItemWeight(item) > freeCapacity then
        return false, true
    end
    return callMethod(container, "hasRoomFor", playerObj, item) == true
end

local function collectDestinations(playerObj, source, logCandidates)
    local results = {}
    local seen = {}
    for _, container in ipairs(getContainerList(playerObj)) do
        local exclusionReason = nil
        if not container then
            exclusionReason = "unavailable"
        elseif seen[container] then
            exclusionReason = "duplicate"
        elseif container == source then
            exclusionReason = "source"
        elseif isPlayerContainer(container, playerObj) then
            exclusionReason = "player inventory"
        elseif not hasTags(container) then
            exclusionReason = "no tags"
        end
        if exclusionReason then
            if logCandidates and container then
                logDebug("Container candidate " .. getContainerDebugName(container)
                    .. " | tags: " .. getTagsDebugText(getSelectedTagNames(container))
                    .. " | skipped: " .. exclusionReason)
            end
        else
            seen[container] = true
            table.insert(results, container)
            if logCandidates then
                logDebug("Container candidate " .. getContainerDebugName(container)
                    .. " | tags: " .. getTagsDebugText(getSelectedTagNames(container))
                    .. " | accepted")
            end
        end
    end
    return results
end

local function recordFullDestination(fullDestinations, container, tag)
    local tags = fullDestinations[container]
    if not tags then
        tags = {}
        fullDestinations[container] = tags
    end
    tags[tag] = true
end

local function chooseDestination(item, destinations, playerObj, reservedWeight, fullDestinations)
    local itemFullDestinations = {}
    local tags = getItemTags(item)
    if tags then
        local category = tostring(callMethod(item, "getDisplayCategory") or "")
        if category ~= LEGACY_FOOD_TAG and category ~= LEGACY_MATERIAL_TAG and category ~= "MaterialWeapon" then
            for _, container in ipairs(destinations) do
                if tagSetContainsAll(getTagSet(container), tags) and hasPlannedCapacity(container, item, playerObj, reservedWeight) then
                    return container
                end
            end
        end
        for tagIndex = 1, #tags do
            for _, container in ipairs(destinations) do
                local tagSet = getTagSet(container)
                if tagSet[tags[tagIndex]] == true then
                    local hasCapacity, isFull = hasPlannedCapacity(container, item, playerObj, reservedWeight)
                    if hasCapacity then
                        return container
                    elseif isFull then
                        recordFullDestination(itemFullDestinations, container, tags[tagIndex])
                    end
                end
            end
        end
    end

    for _, container in ipairs(destinations) do
        local tagSet = getTagSet(container)
        if tagSet[EVERYTHING_ELSE_TAG] == true then
            local hasCapacity, isFull = hasPlannedCapacity(container, item, playerObj, reservedWeight)
            if hasCapacity then
                return container
            elseif isFull then
                recordFullDestination(itemFullDestinations, container, EVERYTHING_ELSE_TAG)
            end
        end
    end
    for container, tags in pairs(itemFullDestinations) do
        for tag in pairs(tags) do
            recordFullDestination(fullDestinations, container, tag)
        end
    end
    return nil
end

local function queueUnload(playerObj, source)
    if isGamePaused() or not playerObj or not source or not ISInventoryTransferUtil
        or type(ISInventoryTransferUtil.newInventoryTransferAction) ~= "function"
        or not ISTimedActionQueue or type(ISTimedActionQueue.add) ~= "function" then
        return
    end

    local destinations = collectDestinations(playerObj, source, true)
    local reservedWeight = {}
    local fullDestinations = {}
    local queuedCount = 0
    if #destinations == 0 then
        logDebug("Available tagged destinations: none")
    else
        for _, destination in ipairs(destinations) do
            logDebug("Available tagged destination " .. getContainerDebugName(destination)
                .. " | tags: " .. getTagsDebugText(getSelectedTagNames(destination))
                .. " | " .. getContainerCapacityDebugText(destination, playerObj))
        end
    end

    for _, item in ipairs(getContainerItems(source)) do
        if isDirectSourceItemEligible(item, playerObj) and callMethod(item, "getContainer") == source then
            local itemTags = getItemTags(item)
            logDebug("Eligible item " .. getItemDebugName(item)
                .. " | tags: " .. getTagsDebugText(itemTags))
            local destination = chooseDestination(item, destinations, playerObj, reservedWeight, fullDestinations)
            if destination then
                reservedWeight[destination] = (reservedWeight[destination] or 0) + getItemWeight(item)
                local action = ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, source, destination, 50)
                if action then
                    ISTimedActionQueue.add(action)
                    queuedCount = queuedCount + 1
                end
            end
        end
    end
    for container, tags in pairs(fullDestinations) do
        for tag in pairs(tags) do
            sayFullDestination(playerObj, container, tag)
        end
    end
    logDebug("Unload All queued " .. tostring(queuedCount) .. " item(s) from " .. getContainerDebugName(source)
        .. " using " .. tostring(#destinations) .. " tagged destination(s)")
end

local function hasEligibleSourceItems(container, playerObj)
    for _, item in ipairs(getContainerItems(container)) do
        if isDirectSourceItemEligible(item, playerObj) then
            return true
        end
    end
    return false
end

local function hasAvailableDestination(playerObj, source)
    return #collectDestinations(playerObj, source) > 0
end

local function refreshLootWindowFooter(lootWindow)
    local controls = lootWindow and lootWindow.controlsUI
    if not controls or type(controls.arrange) ~= "function" then
        return
    end

    controls:arrange()
    if lootWindow.inventoryPane and lootWindow.resizeWidget then
        lootWindow.inventoryPane:setHeight(lootWindow.height - lootWindow.inventoryPane.y
            - lootWindow.resizeWidget.height - controls.height)
    end
end

local function copyTagSet(tags)
    local copy = {}
    for tag, selected in pairs(tags or {}) do
        if selected == true then
            copy[tag] = true
        end
    end
    return copy
end

local function hasSelectedTags(tags)
    for _, selected in pairs(tags or {}) do
        if selected == true then
            return true
        end
    end
    return false
end

local function hasSelectedFoodSubtypes(tags)
    for tag, selected in pairs(tags or {}) do
        if selected == true and tag ~= FOOD_FROZEN_TAG then
            return true
        end
    end
    return false
end

local function tagSetsEqual(left, right)
    for tag, selected in pairs(left) do
        if selected == true and right[tag] ~= true then
            return false
        end
    end
    for tag, selected in pairs(right) do
        if selected == true and left[tag] ~= true then
            return false
        end
    end
    return true
end

local function getColumnsTagSet(columns)
    local selectedTags = {}
    for _, tickBox in ipairs(columns) do
        for optionIndex = 1, tickBox:getOptionCount() do
            if tickBox:isSelected(optionIndex) then
                selectedTags[tickBox:getOptionData(optionIndex)] = true
            end
        end
    end
    return selectedTags
end

local function setButtonDirtyStyle(button, dirty, isApply)
    if not button then
        return
    end
    if dirty then
        button.backgroundColor = isApply and { r = 0.12, g = 0.48, b = 0.16, a = 1 } or { r = 0.55, g = 0.12, b = 0.12, a = 1 }
        button.backgroundColorMouseOver = isApply and { r = 0.16, g = 0.62, b = 0.20, a = 1 } or { r = 0.70, g = 0.16, b = 0.16, a = 1 }
    else
        button.backgroundColor = { r = 0, g = 0, b = 0, a = 1 }
        button.backgroundColorMouseOver = { r = 0.15, g = 0.15, b = 0.15, a = 1 }
    end
end

local function getSpecificTagNames(tags, allTag, tagSet)
    local names = {}
    for _, tag in ipairs(TAG_LIST) do
        if tag ~= allTag and tagSet[tag] and tags[tag] == true then
            table.insert(names, getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryTag_" .. tag, tag))
        end
    end
    table.sort(names)
    return names
end

local function getSpecificTagSummary(tags, allTag, tagSet, maxWidth)
    local names = getSpecificTagNames(tags, allTag, tagSet)
    if #names == 0 then
        return nil, nil
    end
    local shownCount = math.min(#names, 2)
    local summary = table.concat(names, ", ", 1, shownCount)
    if #names > shownCount then
        summary = summary .. "..."
    end
    if maxWidth then
        for nameCount = shownCount - 1, 1, -1 do
            if getTextManager():MeasureStringX(UIFont.Small, summary) <= maxWidth then
                break
            end
            summary = names[nameCount] .. "..."
        end
        if getTextManager():MeasureStringX(UIFont.Small, summary) > maxWidth then
            summary = "..."
        end
    end
    return summary, table.concat(names, ", ")
end

local function openSpecificTagPopup(config, existingTags, onApply)
    local popup = ISCollapsableWindow:new(
        (getCore():getScreenWidth() - POPUP_WIDTH) / 2 + 25,
        (getCore():getScreenHeight() - POPUP_COMPACT_HEIGHT) / 2 + 25,
        POPUP_WIDTH,
        POPUP_COMPACT_HEIGHT
    )
    popup:initialise()
    popup:setTitle(getTextOrFallback(config.titleKey, config.titleFallback))
    popup.resizable = false
    popup:addToUIManager()

    local basicColumns = {}
    local advancedColumns = {}
    local columnWidth = math.floor((POPUP_WIDTH - 40) / TAG_COLUMNS)
    local callbackTarget = {}
    local tagsY = popup:titleBarHeight() + POPUP_SECTION_SPACING
    local optionsPanel = ISPanel:new(10, tagsY, POPUP_WIDTH - 20, 0)
    optionsPanel:initialise()
    optionsPanel:noBackground()
    if config.useScrollBars ~= false then
        optionsPanel:addScrollBars()
    end
    popup:addChild(optionsPanel)

    if config.useScrollBars ~= false then
        function optionsPanel:onMouseWheel(delta)
            local maxScroll = math.max(0, self:getScrollHeight() - self:getScrollAreaHeight())
            self:setYScroll(math.max(-maxScroll, math.min(0, self:getYScroll() - delta * 20)))
            if self.vscroll then
                self.vscroll:updatePos()
            end
            return true
        end
    end

    local function addTagColumns(tags, y, columns)
        for columnIndex = 1, TAG_COLUMNS do
            local tickBox = ISTickBox:new(10 + (columnIndex - 1) * columnWidth, y, columnWidth - 10, TAG_ROW_HEIGHT,
                config.tickBoxId, callbackTarget, callbackTarget.onChanged)
            tickBox:initialise()
            optionsPanel:addChild(tickBox)
            columns[columnIndex] = tickBox
        end
        for index = 1, #tags do
            local tag = tags[index]
            local columnIndex = ((index - 1) % TAG_COLUMNS) + 1
            local optionIndex = columns[columnIndex]:addOption(getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryTag_" .. tag, tag), tag)
            columns[columnIndex]:setSelected(optionIndex, existingTags[tag] == true)
        end
    end

    local function getColumnsHeight(columns)
        local height = 0
        for _, tickBox in ipairs(columns) do
            height = math.max(height, tickBox:getHeight())
        end
        return height
    end

    local openingTags = copyTagSet(existingTags)
    addTagColumns(config.basicTags, 0, basicColumns)
    local basicTagsHeight = getColumnsHeight(basicColumns)
    local advancedTagsY = basicTagsHeight + POPUP_SECTION_SPACING
    if config.advancedTags then
        addTagColumns(config.advancedTags, advancedTagsY, advancedColumns)
    end
    local advancedTagsHeight = getColumnsHeight(advancedColumns)
    local compactPopupHeight = tagsY + basicTagsHeight + POPUP_SECTION_SPACING + POPUP_BUTTON_HEIGHT + POPUP_BOTTOM_MARGIN
    local expandedPopupHeight = advancedTagsY + advancedTagsHeight + POPUP_SECTION_SPACING + POPUP_BUTTON_HEIGHT + POPUP_BOTTOM_MARGIN
    local allOptionsHeight = advancedTagsY + advancedTagsHeight
    local maxPopupHeight = getCore():getScreenHeight() - POPUP_SCREEN_MARGIN * 2

    local allColumns = {}
    for _, columns in ipairs({ basicColumns, advancedColumns }) do
        for _, tickBox in ipairs(columns) do
            table.insert(allColumns, tickBox)
        end
    end

    local hasAdvancedTags = #advancedColumns > 0
    local expanded = hasAdvancedTags and config.showAllOptions == true
    local toggleButton = nil
    local clearButton = nil
    local applyButton = nil
    local cancelButton = nil
    local function closePopup()
        popup:removeFromUIManager()
        popup:setVisible(false)
    end
    local function updatePopupLayout()
        local contentHeight = hasAdvancedTags and expanded and allOptionsHeight or basicTagsHeight
        local measuredPopupHeight = hasAdvancedTags and expanded and expandedPopupHeight or compactPopupHeight
        local popupHeight = config.useScrollBars == false and measuredPopupHeight or math.min(measuredPopupHeight, maxPopupHeight)
        local availableContentHeight = popupHeight - tagsY - POPUP_SECTION_SPACING - POPUP_BUTTON_HEIGHT - POPUP_BOTTOM_MARGIN
        popup:setHeight(popupHeight)
        optionsPanel:setHeight(availableContentHeight)
        if config.useScrollBars ~= false then
            optionsPanel:setScrollHeight(contentHeight)
            if not expanded then
                optionsPanel:setYScroll(0)
            end
            if optionsPanel.vscroll then
                optionsPanel.vscroll:refresh()
                optionsPanel.vscroll:updatePos()
            end
        end
        for _, tickBox in ipairs(advancedColumns) do
            tickBox:setVisible(expanded)
        end
        local buttonY = popupHeight - POPUP_BUTTON_HEIGHT - POPUP_BOTTOM_MARGIN
        if toggleButton then
            toggleButton.title = getTextOrFallback(
                expanded and "UI_QoLforSacriel_OrganizedInventoryToggleBasicOptions" or "UI_QoLforSacriel_OrganizedInventoryToggleAllOptions",
                expanded and "Toggle basic options" or "Toggle all options"
            )
            toggleButton:setY(buttonY)
        end
        clearButton:setY(buttonY)
        applyButton:setY(buttonY)
        cancelButton:setY(buttonY)
        local dirty = not tagSetsEqual(getColumnsTagSet(allColumns), openingTags)
        setButtonDirtyStyle(applyButton, dirty, true)
        setButtonDirtyStyle(cancelButton, dirty, false)
    end
    local function applySpecificTags()
        local selectedTags = {}
        for _, tickBox in ipairs(allColumns) do
            for optionIndex = 1, tickBox:getOptionCount() do
                if tickBox:isSelected(optionIndex) then
                    selectedTags[tickBox:getOptionData(optionIndex)] = true
                end
            end
        end
        onApply(selectedTags)
        closePopup()
    end
    local function cancelSpecificTags()
        closePopup()
    end
    local function clearSpecificTags()
        for _, tickBox in ipairs(allColumns) do
            for optionIndex = 1, tickBox:getOptionCount() do
                tickBox:setSelected(optionIndex, false)
            end
        end
        updatePopupLayout()
    end
    local function toggleOptions()
        expanded = not expanded
        updatePopupLayout()
    end

    function callbackTarget:onChanged()
        updatePopupLayout()
    end
    for _, tickBox in ipairs(allColumns) do
        tickBox.changeOptionMethod = callbackTarget.onChanged
    end

    local buttonY = POPUP_COMPACT_HEIGHT - POPUP_BUTTON_HEIGHT - POPUP_BOTTOM_MARGIN
    if hasAdvancedTags then
        toggleButton = ISButton:new(10, buttonY, 160, POPUP_BUTTON_HEIGHT, "", nil, toggleOptions)
        toggleButton:initialise()
        popup:addChild(toggleButton)
    end
    clearButton = ISButton:new(POPUP_WIDTH - 285, buttonY, 85, POPUP_BUTTON_HEIGHT,
        getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryClearAll", "Clear all"), nil, clearSpecificTags)
    clearButton:initialise()
    popup:addChild(clearButton)
    applyButton = ISButton:new(POPUP_WIDTH - 190, buttonY, 85, POPUP_BUTTON_HEIGHT,
        getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryApply", "Apply"), nil, applySpecificTags)
    applyButton:initialise()
    popup:addChild(applyButton)
    cancelButton = ISButton:new(POPUP_WIDTH - 95, buttonY, 85, POPUP_BUTTON_HEIGHT,
        getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryCancel", "Cancel"), nil, cancelSpecificTags)
    cancelButton:initialise()
    popup:addChild(cancelButton)
    updatePopupLayout()
end

local function openTagPopup(container, lootWindow)
    local owner = getTagOwner(container)
    local modData = owner and callMethod(owner, "getModData") or nil
    if not owner or not modData then
        logDebug("Configure unload tags unavailable: no mod-data owner for " .. getContainerDebugName(container))
        return
    end

    logDebug("Opening tag configuration for " .. getContainerDebugName(container))

    local popup = ISCollapsableWindow:new(
        (getCore():getScreenWidth() - POPUP_WIDTH) / 2,
        (getCore():getScreenHeight() - POPUP_COMPACT_HEIGHT) / 2,
        POPUP_WIDTH,
        POPUP_COMPACT_HEIGHT
    )
    popup:initialise()
    popup:setTitle(getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryConfigureTags", "Configure unload tags"))
    popup.resizable = false
    popup:addToUIManager()

    local existingTags = getTagSet(container) or {}
    local materialTags = {}
    for tag in pairs(MATERIAL_TAG_SET) do
        if existingTags[tag] == true then
            materialTags[tag] = true
        end
    end
    local foodTags = {}
    for tag in pairs(FOOD_TAG_SET) do
        if existingTags[tag] == true then
            foodTags[tag] = true
        end
    end
    local basicColumns = {}
    local advancedColumns = {}
    local columnWidth = math.floor((POPUP_WIDTH - 40) / TAG_COLUMNS)
    local openingTags = copyTagSet(existingTags)
    local callbackTarget = {}
    local function addTagColumns(tags, y, columns)
        for columnIndex = 1, TAG_COLUMNS do
            local tickBox = ISTickBox:new(10 + (columnIndex - 1) * columnWidth, y, columnWidth - 10, TAG_ROW_HEIGHT,
                "QoLforSacriel.OrganizedInventory", callbackTarget, callbackTarget.onChanged)
            tickBox:initialise()
            popup:addChild(tickBox)
            columns[columnIndex] = tickBox
        end
        for index = 1, #tags do
            local tag = tags[index]
            local columnIndex = ((index - 1) % TAG_COLUMNS) + 1
            local optionIndex = columns[columnIndex]:addOption(getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryTag_" .. tag, tag), tag)
            columns[columnIndex]:setSelected(optionIndex, existingTags[tag] == true)
        end
    end

    local function getColumnsHeight(columns)
        local height = 0
        for _, tickBox in ipairs(columns) do
            height = math.max(height, tickBox:getHeight())
        end
        return height
    end

    local tagsY = popup:titleBarHeight() + POPUP_SECTION_SPACING
    addTagColumns(BASIC_TAG_LIST, tagsY, basicColumns)
    local basicTagsHeight = getColumnsHeight(basicColumns)
    local advancedTagsY = tagsY + basicTagsHeight + POPUP_SECTION_SPACING
    addTagColumns(ADVANCED_TAG_LIST, advancedTagsY, advancedColumns)
    local advancedTagsHeight = getColumnsHeight(advancedColumns)
    local controlsHeight = POPUP_BUTTON_HEIGHT * 2 + POPUP_SECTION_SPACING + POPUP_BOTTOM_MARGIN
    local compactPopupHeight = tagsY + basicTagsHeight + POPUP_SECTION_SPACING + controlsHeight
    local expandedPopupHeight = advancedTagsY + advancedTagsHeight + POPUP_SECTION_SPACING + controlsHeight

    local allColumns = {}
    for _, columns in ipairs({ basicColumns, advancedColumns }) do
        for _, tickBox in ipairs(columns) do
            table.insert(allColumns, tickBox)
        end
    end

    local expanded = false
    local toggleButton = nil
    local materialButton = nil
    local materialSummary = nil
    local foodButton = nil
    local foodSummary = nil
    local clearButton = nil
    local applyButton = nil
    local cancelButton = nil
    local function updatePopupLayout()
        local popupHeight = expanded and expandedPopupHeight or compactPopupHeight
        popup:setHeight(popupHeight)
        for _, tickBox in ipairs(advancedColumns) do
            tickBox:setVisible(expanded)
        end
        toggleButton.title = getTextOrFallback(
            expanded and "UI_QoLforSacriel_OrganizedInventoryToggleBasicOptions" or "UI_QoLforSacriel_OrganizedInventoryToggleAllOptions",
            expanded and "Toggle basic options" or "Toggle all options"
        )
        local actionY = popupHeight - controlsHeight
        local buttonY = popupHeight - POPUP_BUTTON_HEIGHT - POPUP_BOTTOM_MARGIN
        toggleButton:setY(buttonY)
        materialButton:setY(actionY)
        materialSummary:setY(actionY + 5)
        foodButton:setY(actionY)
        foodSummary:setY(actionY + 5)
        clearButton:setY(buttonY)
        applyButton:setY(buttonY)
        cancelButton:setY(buttonY)
        local selectedTags = getColumnsTagSet(allColumns)
        for tag in pairs(materialTags) do
            selectedTags[tag] = true
        end
        for tag in pairs(foodTags) do
            selectedTags[tag] = true
        end
        local dirty = not tagSetsEqual(selectedTags, openingTags)
        setButtonDirtyStyle(applyButton, dirty, true)
        setButtonDirtyStyle(cancelButton, dirty, false)
        local materialSummaryWidth = 165
        local summary, tooltip = getSpecificTagSummary(materialTags, MATERIAL_ALL_TAG, MATERIAL_TAG_SET, materialSummaryWidth)
        materialSummary:setNameWithoutMoving(summary or "")
        materialSummary:setWidth(materialSummaryWidth)
        materialSummary:setTooltip(tooltip)
        materialSummary:setVisible(summary ~= nil)
        local foodSummaryWidth = 220
        summary, tooltip = getSpecificTagSummary(foodTags, FOOD_ALL_TAG, FOOD_TAG_SET, foodSummaryWidth)
        foodSummary:setNameWithoutMoving(summary or "")
        foodSummary:setWidth(foodSummaryWidth)
        foodSummary:setTooltip(tooltip)
        foodSummary:setVisible(summary ~= nil)
    end

    local function closePopup()
        popup:removeFromUIManager()
        popup:setVisible(false)
    end

    local function applyTags()
        local selectedTags = {}
        local selectedTagNames = {}
        local hasSelectedTags = false
        for _, tickBox in ipairs(allColumns) do
            for optionIndex = 1, tickBox:getOptionCount() do
                if tickBox:isSelected(optionIndex) then
                    local tag = tickBox:getOptionData(optionIndex)
                    selectedTags[tag] = true
                    table.insert(selectedTagNames, tag)
                    hasSelectedTags = true
                end
            end
        end
        for tag in pairs(materialTags) do
            selectedTags[tag] = true
            table.insert(selectedTagNames, tag)
            hasSelectedTags = true
        end
        for tag in pairs(foodTags) do
            selectedTags[tag] = true
            table.insert(selectedTagNames, tag)
            hasSelectedTags = true
        end
        setTagSet(container, owner, modData, hasSelectedTags and selectedTags or nil)
        logDebug("Applied tags for " .. getContainerDebugName(container) .. ": "
            .. (hasSelectedTags and table.concat(selectedTagNames, ", ") or "cleared"))
        refreshLootWindowFooter(lootWindow)
        closePopup()
    end

    local function cancelTags()
        logDebug("Cancelled tag configuration for " .. getContainerDebugName(container))
        closePopup()
    end
    local function clearTags()
        for _, tickBox in ipairs(allColumns) do
            for optionIndex = 1, tickBox:getOptionCount() do
                tickBox:setSelected(optionIndex, false)
            end
        end
        materialTags = {}
        foodTags = {}
        updatePopupLayout()
    end

    local function toggleOptions()
        expanded = not expanded
        updatePopupLayout()
    end

    function callbackTarget:onChanged()
        local selectedTags = getColumnsTagSet(allColumns)
        if selectedTags[MATERIAL_ALL_TAG] == true then
            materialTags = {}
        end
        if selectedTags[FOOD_ALL_TAG] == true then
            foodTags = foodTags[FOOD_FROZEN_TAG] == true and { [FOOD_FROZEN_TAG] = true } or {}
        end
        updatePopupLayout()
    end
    for _, tickBox in ipairs(allColumns) do
        tickBox.changeOptionMethod = callbackTarget.onChanged
    end

    local function configureMaterialTags()
        openSpecificTagPopup({
            basicTags = MATERIAL_BASIC_TAG_LIST,
            advancedTags = MATERIAL_ADVANCED_TAG_LIST,
            tickBoxId = "QoLforSacriel.OrganizedInventory.Material",
            titleKey = "UI_QoLforSacriel_OrganizedInventoryConfigureMaterialTags",
            titleFallback = "Add material tags",
        }, materialTags, function(selectedTags)
            materialTags = selectedTags
            if hasSelectedTags(selectedTags) then
                for _, tickBox in ipairs(allColumns) do
                    for optionIndex = 1, tickBox:getOptionCount() do
                        if tickBox:getOptionData(optionIndex) == MATERIAL_ALL_TAG then
                            tickBox:setSelected(optionIndex, false)
                        end
                    end
                end
            end
            updatePopupLayout()
        end)
    end

    local function configureFoodTags()
        openSpecificTagPopup({
            basicTags = FOOD_TAG_LIST,
            tickBoxId = "QoLforSacriel.OrganizedInventory.Food",
            titleKey = "UI_QoLforSacriel_OrganizedInventoryConfigureFoodTags",
            titleFallback = "Add food tags",
            useScrollBars = false,
        }, foodTags, function(selectedTags)
            foodTags = selectedTags
            if hasSelectedFoodSubtypes(selectedTags) then
                for _, tickBox in ipairs(allColumns) do
                    for optionIndex = 1, tickBox:getOptionCount() do
                        if tickBox:getOptionData(optionIndex) == FOOD_ALL_TAG then
                            tickBox:setSelected(optionIndex, false)
                        end
                    end
                end
            end
            updatePopupLayout()
        end)
    end

    local actionY = POPUP_COMPACT_HEIGHT - controlsHeight
    local buttonY = POPUP_COMPACT_HEIGHT - POPUP_BUTTON_HEIGHT - POPUP_BOTTOM_MARGIN
    toggleButton = ISButton:new(10, buttonY, 160, POPUP_BUTTON_HEIGHT, "", nil, toggleOptions)
    toggleButton:initialise()
    popup:addChild(toggleButton)
    materialButton = ISButton:new(10, actionY, 155, POPUP_BUTTON_HEIGHT,
        getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryAddMaterialTags", "Add material tags"), nil, configureMaterialTags)
    materialButton:initialise()
    popup:addChild(materialButton)
    materialSummary = ISLabel:new(170, actionY + 5, 0, "", 0.9, 0.9, 0.9, 1, UIFont.Small, true)
    materialSummary:initialise()
    popup:addChild(materialSummary)
    foodButton = ISButton:new(340, actionY, 145, POPUP_BUTTON_HEIGHT,
        getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryAddFoodTags", "Add food tags"), nil, configureFoodTags)
    foodButton:initialise()
    popup:addChild(foodButton)
    foodSummary = ISLabel:new(490, actionY + 5, 0, "", 0.9, 0.9, 0.9, 1, UIFont.Small, true)
    foodSummary:initialise()
    popup:addChild(foodSummary)
    clearButton = ISButton:new(POPUP_WIDTH - 285, buttonY, 85, POPUP_BUTTON_HEIGHT,
        getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryClearAll", "Clear all"), nil, clearTags)
    clearButton:initialise()
    popup:addChild(clearButton)
    applyButton = ISButton:new(POPUP_WIDTH - 190, buttonY, 85, POPUP_BUTTON_HEIGHT, getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryApply", "Apply"), nil, applyTags)
    applyButton:initialise()
    popup:addChild(applyButton)
    cancelButton = ISButton:new(POPUP_WIDTH - 95, buttonY, 85, POPUP_BUTTON_HEIGHT, getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryCancel", "Cancel"), nil, cancelTags)
    cancelButton:initialise()
    popup:addChild(cancelButton)
    updatePopupLayout()
end

local UnloadHandler = ISInventoryWindowControlHandler:derive("QoLforSacriel_OrganizedInventoryUnloadHandler")
UnloadHandler.Type = "QoLforSacriel.OrganizedInventory.Unload"

function UnloadHandler:shouldBeVisible()
    return isModuleEnabled() and hasEligibleSourceItems(self.container, self.playerObj)
end

function UnloadHandler:getControl()
    local control = self:getButtonControl(getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryUnloadAll", "Unload All"))
    local enabled = hasAvailableDestination(self.playerObj, self.container)
    control.enable = enabled
    if enabled then
        control.tooltip = nil
    else
        control.tooltip = getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryNoDestination", "No tagged nearby container is available.")
    end
    return control
end

function UnloadHandler:perform()
    logDebug("Unload All button pressed for " .. getContainerDebugName(self.container))
    queueUnload(self.playerObj, self.container)
end

function UnloadHandler:new()
    return ISInventoryWindowControlHandler.new(self)
end

local ConfigureHandler = ISLootWindowObjectControlHandler:derive("QoLforSacriel_OrganizedInventoryConfigureHandler")
ConfigureHandler.Type = "QoLforSacriel.OrganizedInventory.Configure"

function ConfigureHandler:shouldBeVisible()
    return isModuleEnabled() and self.container ~= nil and not isPlayerContainer(self.container, self.playerObj)
        and getTagOwner(self.container) ~= nil
end

function ConfigureHandler:getControl()
    return self:getButtonControl(getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryConfigureTags", "Configure unload tags"))
end

function ConfigureHandler:perform()
    if not isGamePaused() then
        logDebug("Configure unload tags button pressed for " .. getContainerDebugName(self.container))
        openTagPopup(self.container, self.lootWindow)
    else
        logDebug("Configure unload tags button ignored while game is paused")
    end
end

function ConfigureHandler:new()
    return ISLootWindowObjectControlHandler.new(self)
end

local TagSummaryHandler = ISLootWindowObjectControlHandler:derive("QoLforSacriel_OrganizedInventoryTagSummaryHandler")
TagSummaryHandler.Type = "QoLforSacriel.OrganizedInventory.TagSummary"

local function dismissTooltip(label)
    if label and label.tooltipUI and label.tooltipUI:getIsVisible() then
        label.tooltipUI:setVisible(false)
        label.tooltipUI:removeFromUIManager()
    end
end

function TagSummaryHandler:shouldBeVisible()
    local summary = self.container and getTagSummary(self.container) or nil
    local visible = isModuleEnabled() and summary ~= nil and not isPlayerContainer(self.container, self.playerObj)
        and getTagOwner(self.container) ~= nil
    if not visible then
        dismissTooltip(self.control)
    end
    return visible
end

function TagSummaryHandler:getControl()
    local summary, tooltip = getTagSummary(self.container)
    if not self.control then
        self.control = ISLabel:new(0, 0, 0, "", 0.9, 0.9, 0.9, 1, UIFont.Small, true)
        self.control:initialise()
    end
    self.control:setNameWithoutMoving(summary or "")
    self.control:setTooltip(tooltip)
    return self.control
end

function TagSummaryHandler:new()
    return ISLootWindowObjectControlHandler.new(self)
end

function OrganizedInventory.init(settings, logger)
    if installed then
        return
    end
    settingsRef = settings
    loggerRef = logger

    if not ISInventoryWindowContainerControls or not ISInventoryWindowContainerControls.AddHandler
        or not ISLootWindowContainerControls or not ISLootWindowContainerControls.AddHandler
        or not ISInventoryTransferUtil or not ISInventoryTransferUtil.newInventoryTransferAction then
        if loggerRef and loggerRef.error then
            loggerRef.error("OrganizedInventory unavailable: required Build 42 inventory APIs are missing")
        end
        return
    end

    ISInventoryWindowContainerControls.AddHandler(UnloadHandler)
    ISLootWindowContainerControls.AddHandler(ConfigureHandler)
    ISLootWindowContainerControls.AddHandler(TagSummaryHandler)
    if EquipmentStatsDisplay and EquipmentStatsDisplay.registerInventoryTooltipProvider then
        EquipmentStatsDisplay.registerInventoryTooltipProvider(getTooltipTagRows)
    end
    installed = true
    logDebug("installed")
end

return OrganizedInventory