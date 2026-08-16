// ff-assisted
const fs = require("fs");
const path = require("path");

const sourcePath = process.argv[2];
if (!sourcePath) {
    console.error("Usage: node tools/verify-food-item-tags.js <path-to-generated-items-directory-or-item-file>");
    process.exit(2);
}

const catalogPath = path.join(
    __dirname,
    "..",
    "Contents",
    "mods",
    "QoLforSacriel",
    "42",
    "media",
    "lua",
    "client",
    "QoLforSacriel",
    "Modules",
    "OrganizedInventory",
    "FoodItemTags.lua"
);

const catalogText = fs.readFileSync(catalogPath, "utf8");
const catalogIds = new Set(catalogText.match(/Base\.[A-Za-z0-9_]+/g) || []);
const foodIds = new Set();
const sourcePaths = fs.statSync(sourcePath).isDirectory()
    ? fs.readdirSync(sourcePath)
        .filter((fileName) => fileName.endsWith(".txt"))
        .map((fileName) => path.join(sourcePath, fileName))
    : [sourcePath];

for (const itemSourcePath of sourcePaths) {
    const sourceText = fs.readFileSync(itemSourcePath, "utf8");
    for (const match of sourceText.matchAll(/item\s+([A-Za-z0-9_]+)\s*\{([\s\S]*?)^\s*\}/gm)) {
        if (/DisplayCategory\s*=\s*Food\b/.test(match[2])) {
            foodIds.add(`Base.${match[1]}`);
        }
    }
}

const catalogNotFood = [...catalogIds].filter((itemId) => !foodIds.has(itemId)).sort();
const uncatalogedFood = [...foodIds].filter((itemId) => !catalogIds.has(itemId)).sort();

console.log(`Catalog Food IDs: ${catalogIds.size}`);
console.log(`Source Food IDs: ${foodIds.size}`);
console.log(`Catalog IDs absent or non-Food in source: ${catalogNotFood.length}`);
console.log(`Source Food IDs not in catalog: ${uncatalogedFood.length}`);

if (catalogNotFood.length > 0) {
    console.error(`Invalid catalog IDs: ${catalogNotFood.join(", ")}`);
    process.exitCode = 1;
}

if (uncatalogedFood.length > 0) {
    console.log(`Uncataloged Food IDs: ${uncatalogedFood.join(", ")}`);
}