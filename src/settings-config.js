const fs = require("fs");
const path = require("path");
const { displayLauncherKey, normalizeLauncherKey } = require("./launcher-key");
const {
    configuredItemForName,
    normalizeAppName,
    specialLauncherItemForName
} = require("./launcher-items");

const DEFAULT_CONFIG_PATH = path.join(__dirname, "config.json");

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

function readConfig(configPath = DEFAULT_CONFIG_PATH) {
    const raw = fs.readFileSync(configPath, "utf8");
    const parsed = JSON.parse(raw);
    return normalizeConfig(parsed);
}

function normalizeConfig(config) {
    const normalized = config && typeof config === "object" ? clone(config) : {};
    if (!Array.isArray(normalized.dock_items)) {
        normalized.dock_items = [];
    }
    return normalized;
}

function writeConfig(config, configPath = DEFAULT_CONFIG_PATH) {
    fs.writeFileSync(configPath, `${JSON.stringify(normalizeConfig(config), null, 4)}\n`, "utf8");
}

function visibleDockItems(dockItems) {
    const seenNames = new Set();
    return (dockItems || [])
        .filter(item =>
            item &&
            item.name &&
            item.name !== "Trash" &&
            item.name !== "Downloads" &&
            item.pos &&
            Number.isFinite(item.pos.x)
        )
        .sort((a, b) => a.pos.x - b.pos.x)
        .filter(item => {
            const name = normalizeAppName(item.name);
            if (seenNames.has(name)) return false;
            seenNames.add(name);
            return true;
        });
}

function findConfigItem(configDockItems, appName) {
    const targetName = normalizeAppName(appName);
    return (configDockItems || []).find(entry => normalizeAppName(entry && entry.name) === targetName) || null;
}

function normalizeEditableKey(key) {
    const raw = String(key || "").trim();
    if (!raw) return "";
    return normalizeLauncherKey(raw, "");
}

function normalizeEditableScreen(screen) {
    return String(screen || "").trim();
}

function normalizeEditablePlacement(placement) {
    return String(placement || "").trim();
}

function settingsScreenValue(screen) {
    const value = String(screen || "").trim();
    if (value === "internal") return "1";
    if (value === "external") return "0";
    return value;
}

function hasEditableSetting(update) {
    return !!(
        normalizeEditableKey(update && update.key) ||
        (update && Object.prototype.hasOwnProperty.call(update, "screen") && normalizeEditableScreen(update.screen)) ||
        (update && Object.prototype.hasOwnProperty.call(update, "placement") && normalizeEditablePlacement(update.placement))
    );
}

function isReservedSettingsKey(key, name) {
    if (key === "COMMAND_LEFT" && normalizeAppName(name) === "system settings") {
        return false;
    }
    return key === "COMMAND_LEFT" || key === "COMMAND_RIGHT";
}

function buildSettingsRows(dockItems, config) {
    const configDockItems = normalizeConfig(config).dock_items;
    const rows = [];
    const assignedKeys = new Set(configDockItems.map(item => normalizeEditableKey(item.key)).filter(Boolean));
    let fallbackKey = 1;

    for (const dockItem of visibleDockItems(dockItems)) {
        const specialItem = specialLauncherItemForName(dockItem.name);
        const configItem = findConfigItem(configDockItems, dockItem.name);
        if (specialItem) {
            const source = configItem
                ? configuredItemForName(configDockItems, normalizeAppName(dockItem.name))
                : specialItem;
            const hasConfiguredKey = configItem && Object.prototype.hasOwnProperty.call(configItem, "key");
            const key = hasConfiguredKey ? String(configItem.key || "").trim() : source.key;
            rows.push({
                name: source.name || specialItem.name,
                key: displayLauncherKey(key),
                displayKey: displayLauncherKey(key),
                screen: settingsScreenValue(source.screen),
                placement: String(source.placement || ""),
                status: "configured",
                readonly: false,
                configured: true,
                fallback: false
            });
            continue;
        }

        if (configItem && String(configItem.key || "").trim()) {
            rows.push({
                name: configItem.name || dockItem.name,
                key: displayLauncherKey(configItem.key),
                displayKey: displayLauncherKey(configItem.key),
                screen: String(configItem.screen || ""),
                placement: String(configItem.placement || ""),
                status: "configured",
                readonly: false,
                configured: true,
                fallback: false
            });
            continue;
        }

        while (assignedKeys.has(String(fallbackKey))) fallbackKey += 1;
        rows.push({
            name: dockItem.name,
            key: String(fallbackKey++),
            displayKey: String(fallbackKey - 1),
            screen: String(configItem && configItem.screen || ""),
            placement: String(configItem && configItem.placement || ""),
            status: configItem && (configItem.screen || configItem.placement) ? "configured" : "fallback",
            readonly: false,
            configured: false,
            fallback: true
        });
    }

    return rows;
}

function validateKeyUpdates(updates) {
    const errors = [];
    const byKey = new Map();

    for (const update of updates || []) {
        const name = String(update && update.name || "").trim();
        const key = normalizeEditableKey(update && update.key);
        if (!name || !key) continue;

        if (isReservedSettingsKey(key, name)) {
            errors.push({
                type: "reserved",
                key,
                names: [name],
                message: `${key} is reserved`
            });
            continue;
        }

        if (!byKey.has(key)) {
            byKey.set(key, []);
        }
        byKey.get(key).push(name);
    }

    for (const [key, names] of byKey.entries()) {
        if (names.length > 1) {
            errors.push({
                type: "duplicate",
                key,
                names,
                message: `${key} is assigned to ${names.join(", ")}`
            });
        }
    }

    return errors;
}

function saveDockItemKeys(config, dockItems, updates) {
    return saveDockItemSettings(config, dockItems, updates);
}

function saveDockItemSettings(config, dockItems, updates) {
    const nextConfig = normalizeConfig(config);
    const visibleNames = new Set(visibleDockItems(dockItems).map(item => normalizeAppName(item.name)));
    const updatesByName = new Map();

    for (const update of updates || []) {
        const name = String(update && update.name || "").trim();
        if (!name) continue;
        const normalizedName = normalizeAppName(name);
        if (!visibleNames.has(normalizedName)) continue;
        updatesByName.set(normalizedName, {
            name,
            key: normalizeEditableKey(update.key),
            hasScreen: Object.prototype.hasOwnProperty.call(update, "screen"),
            screen: normalizeEditableScreen(update.screen),
            hasPlacement: Object.prototype.hasOwnProperty.call(update, "placement"),
            placement: normalizeEditablePlacement(update.placement)
        });
    }

    const errors = validateKeyUpdates(Array.from(updatesByName.values()));
    if (errors.length > 0) {
        return {
            ok: false,
            errors,
            config: nextConfig
        };
    }

    const seen = new Set();
    nextConfig.dock_items = nextConfig.dock_items
        .map(item => {
            const normalizedName = normalizeAppName(item && item.name);
            const update = updatesByName.get(normalizedName);
            if (!update) return item;
            seen.add(normalizedName);
            const nextItem = Object.assign({}, item);
            if (update.key) nextItem.key = update.key;
            else delete nextItem.key;
            if (update.hasScreen) {
                if (update.screen) nextItem.screen = update.screen;
                else delete nextItem.screen;
            }
            if (update.hasPlacement) {
                if (update.placement) nextItem.placement = update.placement;
                else delete nextItem.placement;
            }
            return nextItem;
        })
        .filter(Boolean);

    for (const [normalizedName, update] of updatesByName.entries()) {
        if (seen.has(normalizedName) || !hasEditableSetting(update)) continue;
        const nextItem = {
            name: update.name
        };
        if (update.key) nextItem.key = update.key;
        if (update.hasScreen && update.screen) nextItem.screen = update.screen;
        if (update.hasPlacement && update.placement) nextItem.placement = update.placement;
        nextConfig.dock_items.push(nextItem);
    }

    return {
        ok: true,
        errors: [],
        config: nextConfig
    };
}

module.exports = {
    DEFAULT_CONFIG_PATH,
    buildSettingsRows,
    findConfigItem,
    normalizeConfig,
    normalizeEditableKey,
    normalizeEditablePlacement,
    normalizeEditableScreen,
    readConfig,
    saveDockItemKeys,
    saveDockItemSettings,
    validateKeyUpdates,
    visibleDockItems,
    writeConfig
};
