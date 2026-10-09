const { launcherKeyIcon } = require("./launcher-key");

function normalizeAppName(name) {
    var normalized = String(name || "")
        .trim()
        .replace(/\.app$/i, "")
        .toLowerCase();

    if (normalized === "chrome") {
        return "google chrome";
    }
    if (["feishu", "lark", "飞书"].includes(normalized)) {
        return "feishu";
    }

    return normalized;
}

var SPECIAL_LAUNCHER_ITEMS = Object.freeze({
    chatgpt: Object.freeze({
        name: "ChatGPT",
        key: "F6",
        icon: "F6",
        screen: "side_right",
        placement: "side_right_fill"
    }),
    codex: Object.freeze({
        name: "Codex",
        key: "LEFT_SHIFT",
        icon: "L⇧",
        screen: "external",
        placement: "external_fill"
    }),
    smartshadow: Object.freeze({
        name: "SmartShadow",
        key: "F3",
        icon: "F3",
        screen: "side_left",
        placement: "side_left_fill",
        open_path: "/Applications/SmartShadow.app"
    }),
    claude: Object.freeze({
        name: "Claude",
        key: "RIGHT_SHIFT",
        icon: "R⇧",
        screen: "side_right",
        placement: "side_right_fill",
        open_path: "/Applications/Claude.app"
    })
});

function isExcludedLauncherApp(name) {
    return !!SPECIAL_LAUNCHER_ITEMS[normalizeAppName(name)];
}

function specialLauncherItemForName(name) {
    var item = SPECIAL_LAUNCHER_ITEMS[normalizeAppName(name)];
    if (!item) return null;
    return Object.assign({}, item);
}

function configuredItemForName(configDockItems, dockName) {
    return (configDockItems || []).find(entry =>
        normalizeAppName(entry && entry.name) === dockName
    );
}

function specialItemWithConfig(specialItem, configItem) {
    if (!configItem) return specialItem;
    var hasKey = Object.prototype.hasOwnProperty.call(configItem, "key");
    var key = hasKey ? String(configItem.key || "").trim() : specialItem.key;
    return Object.assign({}, specialItem, configItem, {
        name: configItem.name || specialItem.name,
        key,
        icon: launcherKeyIcon(key) || configItem.icon
    });
}

function buildLauncherItems(dockItems, configDockItems) {
    var visibleItems = (dockItems || [])
        .filter(item =>
            item &&
            item.name &&
            item.name !== "Trash" &&
            item.name !== "Downloads" &&
            item.pos &&
            Number.isFinite(item.pos.x)
        )
        .sort((a, b) => a.pos.x - b.pos.x);

    var launcherItems = [];
    var userAssignedKeys = new Set((configDockItems || [])
        .map(item => String(item && item.key || "").trim().toUpperCase())
        .filter(Boolean));
    var fallbackKey = 1;
    function nextFallbackKey() {
        while (userAssignedKeys.has(String(fallbackKey))) {
            fallbackKey += 1;
        }
        return fallbackKey++;
    }
    for (var i = 0; i < visibleItems.length; i++) {
        var dockName = normalizeAppName(visibleItems[i].name);
        var configItem = configuredItemForName(configDockItems, dockName);
        var item = specialLauncherItemForName(visibleItems[i].name);
        if (item != undefined) {
            item = specialItemWithConfig(item, configItem);
        } else if (configItem && String(configItem.key || "").trim()) {
            item = Object.assign({}, configItem, {
                icon: launcherKeyIcon(configItem.key) || configItem.icon
            });
        }
        if (item == undefined) {
            item = {
                name: visibleItems[i].name,
                key: nextFallbackKey(),
                screen: ""
            };
        }
        launcherItems.push({
            item,
            dockItem: visibleItems[i]
        });
    }

    return launcherItems;
}

function findLauncherItemForKey(dockItems, configDockItems, normalizedKey) {
    var key = String(normalizedKey || "").trim().toUpperCase();
    if (!key) return null;
    var entry = buildLauncherItems(dockItems, configDockItems).find(candidate => {
        var item = candidate && candidate.item;
        if (!item) return false;
        return String(item.key || "").toUpperCase() === key ||
            String(item.icon || "").toUpperCase() === key;
    });
    return entry ? entry.item : null;
}

module.exports = {
    buildLauncherItems,
    configuredItemForName,
    findLauncherItemForKey,
    isExcludedLauncherApp,
    normalizeAppName,
    specialLauncherItemForName
};
