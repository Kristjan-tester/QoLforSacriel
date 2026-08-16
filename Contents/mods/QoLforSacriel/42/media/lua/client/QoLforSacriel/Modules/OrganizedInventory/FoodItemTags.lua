-- ff-assisted
local FOOD_ITEM_TAGS = {}

local function registerFoodItems(foodTag, itemTypes)
    for _, itemType in ipairs(itemTypes) do
        local previousTag = FOOD_ITEM_TAGS[itemType]
        if previousTag and previousTag ~= foodTag then
            print("QoLforSacriel OrganizedInventory: Food tag overwrite for " .. itemType
                .. " (" .. previousTag .. " -> " .. foodTag .. ")")
        end
        FOOD_ITEM_TAGS[itemType] = foodTag
    end
end

registerFoodItems("Food.EvolvedRecipe", {
    "Base.BagelPlain", "Base.BagelPoppy", "Base.BagelSesame", "Base.BaguetteSandwich", "Base.BakingTray_Muffin_Recipe",
    "Base.BreadDough", "Base.BucketOfSoup", "Base.BucketOfStew", "Base.Burger", "Base.BurgerRecipe",
    "Base.Burrito", "Base.BurritoRecipe", "Base.CakeRaw", "Base.ConeIcecreamToppings", "Base.FruitSalad",
    "Base.FruitSaladClay", "Base.GriddlePanFriedVegetables", "Base.HotDrink", "Base.HotDrinkClay", "Base.HotDrinkCopper",
    "Base.HotDrinkGold", "Base.HotDrinkMetal", "Base.HotDrinkSilver", "Base.HotDrinkSpiffo", "Base.HotDrinkTea",
    "Base.HotDrinkTeaCeramic", "Base.HotDrinkTumbler", "Base.HotDrinkWhite", "Base.Hotdog", "Base.Oatmeal",
    "Base.OmeletteRecipe", "Base.OmeletteRecipeForged", "Base.PanFriedVegetables", "Base.PanFriedVegetables2", "Base.PanFriedVegetablesForged",
    "Base.PancakesRecipe", "Base.PastaPan", "Base.PastaPanCopper", "Base.PastaPot", "Base.PastaPotForged",
    "Base.PieWholeRaw", "Base.PieWholeRawSweet", "Base.PizzaRecipe", "Base.PizzaWhole", "Base.PotForgedSoupRecipe",
    "Base.PotForgedStew", "Base.PotOfSoup", "Base.PotOfSoupRecipe", "Base.PotOfStew", "Base.RicePan",
    "Base.RicePanCopper", "Base.RicePot", "Base.RicePotForged", "Base.Salad", "Base.SaladClay",
    "Base.Sandwich", "Base.Taco", "Base.TacoRecipe", "Base.Toast", "Base.WafflesRecipe",
    "Base.Baguette", "Base.BakingTray_Muffin", "Base.BreadSlices", "Base.BunsHamburger_single", "Base.CakePrep",
    "Base.ConeIcecream", "Base.Pancakes", "Base.PiePrep", "Base.TacoShell", "Base.Tortilla",
    "Base.Waffles", "Base.WaterPotForgedPasta", "Base.WaterPotForgedRice", "Base.WaterPotPasta", "Base.WaterPotRice",
    "Base.WaterSaucepanPasta", "Base.WaterSaucepanPastaCopper", "Base.WaterSaucepanRice", "Base.WaterSaucepanRiceCopper",
})
registerFoodItems("Food.Prepared", {
    "Base.BaguetteDough", "Base.Biscuit", "Base.CabbageRoll", "Base.CakeSlice", "Base.CerealBowl",
    "Base.CookieChocolateChip", "Base.CookieChocolateChipDough", "Base.CookiesChocolate", "Base.CookiesChocolateDough", "Base.CookiesOatmeal",
    "Base.CookiesOatmealDough", "Base.CookiesShortbread", "Base.CookiesShortbreadDough", "Base.CookiesSugar", "Base.CookiesSugarDough",
    "Base.Gravy", "Base.Guacamole", "Base.HalloweenPumpkin", "Base.Macaroni", "Base.Maki",
    "Base.MuffinGeneric", "Base.Muffintray_Biscuit", "Base.Onigiri", "Base.PancakesCraft", "Base.PastaBowl",
    "Base.PastaBowlClay", "Base.Pie", "Base.Pizza", "Base.RiceBowl", "Base.RiceBowlClay",
    "Base.SoupBowl", "Base.SoupBowlClay", "Base.StewBowl", "Base.StewBowlClay", "Base.TortillaChipsBaked",
    "Base.cheese_powdered",
})
registerFoodItems("Food.Canned", {
    "Base.CannedBolognese", "Base.CannedBologneseOpen", "Base.CannedCarrots2", "Base.CannedCarrotsOpen", "Base.CannedChili",
    "Base.CannedChiliOpen", "Base.CannedCorn", "Base.CannedCornOpen", "Base.CannedCornedBeef", "Base.CannedCornedBeefOpen",
    "Base.CannedFruitBeverage", "Base.CannedFruitBeverageOpen", "Base.CannedFruitCocktail", "Base.CannedFruitCocktailOpen", "Base.CannedMilk",
    "Base.CannedMilkOpen", "Base.CannedMushroomSoup", "Base.CannedMushroomSoupOpen", "Base.CannedPeaches", "Base.CannedPeachesOpen",
    "Base.CannedPeas", "Base.CannedPeasOpen", "Base.CannedPineapple", "Base.CannedPineappleOpen", "Base.CannedPotato2",
    "Base.CannedPotatoOpen", "Base.CannedSardines", "Base.CannedSardinesOpen", "Base.CannedTomato2", "Base.CannedTomatoOpen",
    "Base.DentedCan", "Base.Dogfood", "Base.DogfoodOpen", "Base.MysteryCan", "Base.OpenBeans",
    "Base.TinnedBeans", "Base.TinnedSoup", "Base.TinnedSoupOpen", "Base.TunaTin", "Base.TunaTinOpen",
    "Base.CannedBolognese_Box", "Base.CannedCarrots_Box", "Base.CannedChili_Box", "Base.CannedCorn_Box",
    "Base.CannedCornedBeef_Box", "Base.CannedFruitBeverage_Box", "Base.CannedFruitCocktail_Box", "Base.CannedMilk_Box",
    "Base.CannedMushroomSoup_Box", "Base.CannedPeaches_Box", "Base.CannedPeas_Box", "Base.CannedPineapple_Box",
    "Base.CannedPotato_Box", "Base.CannedSardines_Box", "Base.CannedTomato_Box",
})
registerFoodItems("Food.Drinks", {
    "Base.BeerBottle", "Base.BeerCan", "Base.BeerImported", "Base.Bitters", "Base.Brandy",
    "Base.CakeBatter", "Base.Champagne", "Base.Cider", "Base.CoffeeLiquer", "Base.Curacao",
    "Base.DentedCan_Box", "Base.Dogfood_Box", "Base.Gin", "Base.Grenadine", "Base.JuiceBox",
    "Base.JuiceBoxApple", "Base.JuiceBoxFruitpunch", "Base.JuiceBoxOrange", "Base.JuiceCranberry", "Base.JuiceFruitpunch",
    "Base.JuiceGrape", "Base.JuiceLemon", "Base.JuiceOrange", "Base.JuiceTomato", "Base.Macandcheese_Box",
    "Base.Milk", "Base.MilkBottle", "Base.MilkChocolate_Personalsized", "Base.Milk_Personalsized", "Base.MysteryCan_Box",
    "Base.PieDough", "Base.Pop", "Base.Pop2", "Base.Pop3", "Base.PopBottle",
    "Base.PopBottleRare", "Base.Port", "Base.Rum", "Base.Scotch", "Base.Sherry",
    "Base.SimpleSyrup", "Base.SodaCan", "Base.Tequila", "Base.TinnedBeans_Box", "Base.TinnedSoup_Box",
    "Base.TunaTin_Box", "Base.Vermouth", "Base.Vodka", "Base.WaterRationCan_Box", "Base.Whiskey",
    "Base.Wine", "Base.Wine2", "Base.Wine2Open", "Base.WineAged", "Base.WineBox",
    "Base.WineOpen", "Base.WineRed_Boxed", "Base.WineScrewtop", "Base.WineWhite_Boxed",
})
registerFoodItems("Food.Meat", {
    "Base.Bacon", "Base.BaconBits", "Base.BaconRashers", "Base.Baloney", "Base.BaloneySlice",
    "Base.Beef", "Base.BeefJerky", "Base.Chicken", "Base.ChickenFillet", "Base.ChickenNuggets",
    "Base.ChickenWhole", "Base.ChickenWings", "Base.Ham", "Base.HamSlice", "Base.HotdogPack",
    "Base.Hotdog_single", "Base.MeatDumpling", "Base.MeatPatty", "Base.MincedMeat", "Base.MuttonChop",
    "Base.Pepperoni", "Base.Pork", "Base.PorkChop", "Base.Salami", "Base.SalamiSlice",
    "Base.Sausage", "Base.Steak", "Base.TurkeyFillet", "Base.TurkeyLegs", "Base.TurkeyWhole",
    "Base.TurkeyWings", "Base.Venison",
})
registerFoodItems("Food.Protein.Game", {
    "Base.DeadBird", "Base.DeadMouse", "Base.DeadMousePups", "Base.DeadMousePupsSkinned", "Base.DeadMouseSkinned",
    "Base.DeadRabbit", "Base.DeadRat", "Base.DeadRatBaby", "Base.DeadRatBabySkinned", "Base.DeadRatSkinned",
    "Base.DeadSquirrel", "Base.FrogMeat", "Base.Rabbitmeat", "Base.Smallanimalmeat", "Base.Smallbirdmeat",
})
registerFoodItems("Food.Protein.Seafood", {
    "Base.AligatorGar", "Base.BaitFish", "Base.BlackCrappie", "Base.BlueCatfish", "Base.Bluegill",
    "Base.Caviar", "Base.ChannelCatfish", "Base.Crayfish", "Base.FishFillet", "Base.FishFingers",
    "Base.FishFried", "Base.FishRoe", "Base.FlatheadCatfish", "Base.FreshwaterDrum", "Base.Frozen_FishFingers",
    "Base.GreenSunfish", "Base.LargemouthBass", "Base.Lobster", "Base.Muskellunge", "Base.Mussels",
    "Base.Oysters", "Base.OystersFried", "Base.Paddlefish", "Base.RedearSunfish", "Base.Salmon",
    "Base.Sauger", "Base.Shrimp", "Base.ShrimpDumpling", "Base.ShrimpFried", "Base.ShrimpFriedCraft",
    "Base.SmallmouthBass", "Base.SpottedBass", "Base.Squid", "Base.SquidCalamari", "Base.StripedBass",
    "Base.SushiFish", "Base.Walleye", "Base.WhiteBass", "Base.WhiteCrappie", "Base.YellowPerch",
})
registerFoodItems("Food.Protein.Egg", {
    "Base.Egg", "Base.EggBoiled", "Base.EggCarton", "Base.EggOmelette", "Base.EggPoached",
    "Base.EggScrambled", "Base.TurkeyEgg", "Base.WildEggs",
})
registerFoodItems("Food.Insect", {
    "Base.AmericanLadyCaterpillar", "Base.BandedWoolyBearCaterpillar", "Base.Centipede", "Base.Centipede2", "Base.Cockroach",
    "Base.Cricket", "Base.Grasshopper", "Base.Ladybug", "Base.Leech", "Base.Maggots",
    "Base.Millipede", "Base.Millipede2", "Base.MonarchCaterpillar", "Base.Pillbug", "Base.SawflyLarva",
    "Base.SilkMothCaterpillar", "Base.Slug", "Base.Slug2", "Base.Snail", "Base.SwallowtailCaterpillar",
    "Base.Termites", "Base.Worm",
})
registerFoodItems("Food.Fruit", {
    "Base.Apple", "Base.Banana", "Base.BeautyBerry", "Base.BerryBlack", "Base.BerryBlue",
    "Base.BerryGeneric1", "Base.BerryGeneric2", "Base.BerryGeneric3", "Base.BerryGeneric4", "Base.BerryGeneric5",
    "Base.BerryPoisonIvy", "Base.Cherry", "Base.DriedApricots", "Base.Grapefruit", "Base.Grapes",
    "Base.HollyBerry", "Base.Lemon", "Base.Lime", "Base.Mango", "Base.Orange",
    "Base.Peach", "Base.Pear", "Base.Pineapple", "Base.Rosehips", "Base.Strewberrie",
    "Base.Watermelon", "Base.WatermelonSliced", "Base.WatermelonSmashed", "Base.WinterBerry",
})
registerFoodItems("Food.Vegetable", {
    "Base.Avocado", "Base.BeanBowl", "Base.BellPepper", "Base.Blackbeans", "Base.Broccoli",
    "Base.BrusselSprouts", "Base.Cabbage", "Base.Capers", "Base.Carrots", "Base.Cauliflower",
    "Base.Corn", "Base.CornFrozen", "Base.Cucumber", "Base.Daikon", "Base.Dandelions",
    "Base.DriedBlackBeans", "Base.DriedChickpeas", "Base.DriedKidneyBeans", "Base.DriedLentils", "Base.DriedSplitPeas",
    "Base.DriedWhiteBeans", "Base.Edamame", "Base.Eggplant", "Base.FrenchFries", "Base.FriedOnionRings",
    "Base.FriedOnionRingsCraft", "Base.GrapeLeaves", "Base.Greenpeas", "Base.Kale", "Base.Leek",
    "Base.Lettuce", "Base.MixedVegetables", "Base.MushroomGeneric1", "Base.MushroomGeneric2", "Base.MushroomGeneric3",
    "Base.MushroomGeneric4", "Base.MushroomGeneric5", "Base.MushroomGeneric6", "Base.MushroomGeneric7", "Base.MushroomsButton",
    "Base.Olives", "Base.Onion", "Base.Peanuts", "Base.Peas", "Base.PepperHabanero",
    "Base.PepperHabaneroDried", "Base.PepperJalapeno", "Base.PepperJalapenoDried", "Base.Potato", "Base.Pumpkin",
    "Base.PumpkinSliced", "Base.PumpkinSmashed", "Base.RedRadish", "Base.RefriedBeans", "Base.Soybeans",
    "Base.SoybeansSeed", "Base.Spinach", "Base.Squash", "Base.SugarBeet", "Base.SweetPotato",
    "Base.TatoDots", "Base.Tofu", "Base.TofuFried", "Base.Tomato", "Base.Turnip",
    "Base.Zucchini",
})
registerFoodItems("Food.Pickled", {
    "Base.CannedBellPepper", "Base.CannedBellPepper_Open", "Base.CannedBroccoli", "Base.CannedBroccoli_Open", "Base.CannedCabbage",
    "Base.CannedCabbage_Open", "Base.CannedCarrots", "Base.CannedCarrots_Open", "Base.CannedEggplant", "Base.CannedEggplant_Open",
    "Base.CannedLeek", "Base.CannedLeek_Open", "Base.CannedPotato", "Base.CannedPotato_Open", "Base.CannedRedRadish",
    "Base.CannedRedRadish_Open", "Base.CannedRoe", "Base.CannedRoe_Open", "Base.CannedTomato", "Base.CannedTomato_Open",
})
registerFoodItems("Food.Herb", {
    "Base.Basil", "Base.BasilDried", "Base.Chamomile", "Base.ChamomileDried", "Base.Chives",
    "Base.ChivesDried", "Base.Cilantro", "Base.CilantroDried", "Base.Cinnamon", "Base.FourLeafClover",
    "Base.Garlic", "Base.GreenOnions", "Base.Lavender", "Base.LavenderPetalsDried", "Base.LemonGrass",
    "Base.Marigold", "Base.MarigoldDried", "Base.MintHerb", "Base.MintHerbDried", "Base.Nettles",
    "Base.Oregano", "Base.OreganoDried", "Base.Parsley", "Base.ParsleyDried", "Base.RosePetalsDried",
    "Base.Rosemary", "Base.RosemaryDried", "Base.Roses", "Base.Sage", "Base.SageDried",
    "Base.Seasoning_Basil", "Base.Seasoning_Chives", "Base.Seasoning_Cilantro", "Base.Seasoning_Oregano", "Base.Seasoning_Parsley",
    "Base.Seasoning_Rosemary", "Base.Seasoning_Sage", "Base.Seasoning_Thyme", "Base.Thistle", "Base.Thyme",
    "Base.ThymeDried",
})
registerFoodItems("Food.Plant", {
    "Base.Acorn", "Base.BarleySheaf", "Base.BarleySheafDried", "Base.GrassTuft", "Base.HayTuft",
    "Base.HempBundle", "Base.HempBundleDried", "Base.Hops", "Base.HopsDried", "Base.RyeSheaf",
    "Base.RyeSheafDried", "Base.WheatSheaf", "Base.WheatSheafDried",
})
registerFoodItems("Food.Spice", {
    "Base.BBQSauce", "Base.BalsamicVinegar", "Base.BouillonCube", "Base.Butter", "Base.Cornflour2",
    "Base.Cornmeal2", "Base.Dip_NachoCheese", "Base.Dip_Ranch", "Base.Dip_Salsa", "Base.Flour2",
    "Base.GingerPickled", "Base.GingerRoot", "Base.Honey", "Base.Hotsauce", "Base.Ketchup",
    "Base.Lard", "Base.MapleSyrup", "Base.Margarine", "Base.Marinara", "Base.MayonnaiseFull",
    "Base.Mustard", "Base.OilOlive", "Base.OilVegetable", "Base.Pepper", "Base.Pickles",
    "Base.PoppySeed", "Base.PowderedGarlic", "Base.PowderedOnion", "Base.PumpkinSeed", "Base.RemouladeFull",
    "Base.RiceVinegar", "Base.Salt", "Base.SeasoningSalt", "Base.Seaweed", "Base.SesameOil",
    "Base.SourCream", "Base.Soysauce", "Base.Sugar", "Base.SugarBrown", "Base.SugarCubes",
    "Base.SugarPacket", "Base.SunflowerSeeds", "Base.TomatoPaste", "Base.Violets", "Base.Wasabi",
})
registerFoodItems("Food.Grain", {
    "Base.Bread", "Base.BunsHamburger", "Base.BunsHotdog", "Base.BunsHotdog_single", "Base.Pasta",
    "Base.Ramen", "Base.Rice",
})
registerFoodItems("Food.Candy", {
    "Base.Allsorts", "Base.CandiedApple", "Base.CandyCaramels", "Base.CandyCorn", "Base.CandyFruitSlices",
    "Base.CandyGummyfish", "Base.CandyMolasses", "Base.CandyNovapops", "Base.CandyPackage", "Base.Candycane",
    "Base.Chocolate", "Base.Chocolate_Butterchunkers", "Base.Chocolate_Candy", "Base.Chocolate_Crackle", "Base.Chocolate_Deux",
    "Base.Chocolate_GalacticDairy", "Base.Chocolate_RoysPBPucks", "Base.Chocolate_Smirkers", "Base.Chocolate_SnikSnak", "Base.Gum",
    "Base.GummyBears", "Base.GummyWorms", "Base.HardCandies", "Base.JellyBeans", "Base.Jujubes",
    "Base.LicoriceBlack", "Base.LicoriceRed", "Base.Lollipop", "Base.MintCandy", "Base.RockCandy",
})
registerFoodItems("Food.Miscellaneous", {
    "Base.CakeBlackForest", "Base.CakeCarrot", "Base.CakeCheeseCake", "Base.CakeChocolate", "Base.CakeRedVelvet",
    "Base.CakeStrawberryShortcake", "Base.CatFoodBag", "Base.CatTreats", "Base.Cereal", "Base.Cheese",
    "Base.ChickenFoot", "Base.ChickenFried", "Base.ChocoCakes", "Base.ChocolateChips", "Base.ChocolateCoveredCoffeeBeans",
    "Base.Chocolate_HeartBox", "Base.CinnamonRoll", "Base.CocoaPowder", "Base.Coffee2", "Base.Cone",
    "Base.ConeIcecreamMelted", "Base.CookieJelly", "Base.Cornbread", "Base.Corndog", "Base.Crackers",
    "Base.Creamocle", "Base.Creamocle_Melted", "Base.Crisps", "Base.Crisps2", "Base.Crisps3",
    "Base.Crisps4", "Base.CrispyRiceSquare", "Base.Croissant", "Base.Cupcake", "Base.Danish",
    "Base.DehydratedMeatStick", "Base.DogFoodBag", "Base.Dough", "Base.DoughnutChocolate", "Base.DoughnutFrosted",
    "Base.DoughnutJelly", "Base.DoughnutPlain", "Base.Fries", "Base.Frozen_ChickenNuggets", "Base.Frozen_FrenchFries",
    "Base.Frozen_TatoDots", "Base.FudgeePop", "Base.FudgeePop_Melted", "Base.Gingerbreadman", "Base.GrahamCrackers",
    "Base.GranolaBar", "Base.HiHis", "Base.HotDrinkRed", "Base.Icecream", "Base.IcecreamMelted",
    "Base.IcecreamSandwich", "Base.IcecreamSandwich_Melted", "Base.Icing", "Base.JamFruit", "Base.JamMarmalade",
    "Base.JellyRoll", "Base.LemonBar", "Base.Macandcheese", "Base.Marshmallows", "Base.MeatSteamBun",
    "Base.Modjeska", "Base.MuffinFruit", "Base.NoodleSoup", "Base.OatsRaw", "Base.Painauchocolat",
    "Base.PeanutButter", "Base.Peppermint", "Base.Perogies", "Base.PieApple", "Base.PieBlueberry",
    "Base.PieKeyLime", "Base.PieLemonMeringue", "Base.PiePumpkin", "Base.Plonkies", "Base.Popcorn",
    "Base.Popsicle", "Base.Popsicle_Melted", "Base.PorkRinds", "Base.PotatoPancakes", "Base.Pretzel",
    "Base.Processedcheese", "Base.QuaggaCakes", "Base.RamenBowl", "Base.RicePaper", "Base.ScoutCookies",
    "Base.Smore", "Base.SnoGlobes", "Base.Springroll", "Base.SugarBeetPulpPot", "Base.SugarBeetSugarPot",
    "Base.SugarBeetSyrupPot", "Base.SushiEgg", "Base.TVDinner", "Base.Tadpole", "Base.Teabag2",
    "Base.TestHotDrink", "Base.TortillaChips", "Base.WaterRationCan", "Base.Yoghurt",
    "Base.AnimalMilkPowder", "Base.GravyMix", "Base.PancakeMix", "Base.Vinegar2", "Base.Vinegar_Jug",
    "Base.Yeast",
})

return FOOD_ITEM_TAGS