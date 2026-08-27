const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const files = [
    "Contents/mods/QoLforSacriel/42/media/lua/client/QoLforSacriel/Modules/UIFixes/FitnessNutritionIndicator.lua",
    "Contents/mods/QoLforSacriel/42/media/lua/client/QoLforSacriel/Modules/UIFixes/SleepStructuralSnapshot.lua",
];
const catalogue = new Set([
    "CAPABILITY", "CAPTURE_BEGIN", "CAPTURE_SKIP", "CAPTURE_AMBIGUOUS",
    "CAPTURE_SUMMARY", "COMPARE_BEGIN", "TRANSITION_ACCEPTED",
    "TRANSITION_AMBIGUOUS", "COMPARE_SUMMARY", "CLASSIFY", "CLEANUP", "ERROR",
]);
const emitted = new Set();
const patterns = [
    /emit\(options,\s*"([A-Z_]+)"/g,
    /logStructuralEvent\([^\n]*"([A-Z_]+)"/g,
];

for (const relativePath of files) {
    const source = fs.readFileSync(path.join(root, relativePath), "utf8");
    for (const pattern of patterns) {
        for (const match of source.matchAll(pattern)) emitted.add(match[1]);
    }
}

const unknown = [...emitted].filter((eventName) => !catalogue.has(eventName)).sort();
const missing = [...catalogue].filter((eventName) => !emitted.has(eventName)).sort();
if (unknown.length || missing.length) {
    if (unknown.length) console.error(`Unknown SLEEP_STRUCT events: ${unknown.join(", ")}`);
    if (missing.length) console.error(`Missing SLEEP_STRUCT events: ${missing.join(", ")}`);
    process.exit(1);
}

console.log(`Verified ${emitted.size} SLEEP_STRUCT event names.`);