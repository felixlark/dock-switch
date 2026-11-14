const test = require("node:test");
const assert = require("node:assert/strict");

const {
    buildSettingsRows,
    normalizeEditableKey,
    saveDockItemSettings,
    validateKeyUpdates
} = require("../src/settings-config");

test("buildSettingsRows merges visible Dock apps with configured special defaults and fallback keys", () => {
    const dockItems = [
        { name: "Finder", pos: { x: 10, y: 0 } },
        { name: "ChatGPT", pos: { x: 20, y: 0 } },
        { name: "Codex", pos: { x: 30, y: 0 } },
        { name: "SmartShadow", pos: { x: 40, y: 0 } },
        { name: "Claude", pos: { x: 50, y: 0 } },
        { name: "Temporary App", pos: { x: 60, y: 0 } }
    ];
    const config = {
        dock_items: [
            { name: "Finder", key: "D", screen: "0", placement: "internal_fill" }
        ]
    };

    const rows = buildSettingsRows(dockItems, config);

    assert.deepEqual(rows.map(row => ({
        name: row.name,
        key: row.key,
        screen: row.screen,
        placement: row.placement,
        status: row.status,
        readonly: row.readonly
    })), [
        { name: "Finder", key: "D", screen: "0", placement: "internal_fill", status: "configured", readonly: false },
        { name: "ChatGPT", key: "F6", screen: "side_right", placement: "side_right_fill", status: "configured", readonly: false },
        { name: "Codex", key: "L⇧", screen: "0", placement: "external_fill", status: "configured", readonly: false },
        { name: "SmartShadow", key: "F3", screen: "side_left", placement: "side_left_fill", status: "configured", readonly: false },
        { name: "Claude", key: "R⇧", screen: "side_right", placement: "side_right_fill", status: "configured", readonly: false },
        { name: "Temporary App", key: "1", screen: "", placement: "", status: "fallback", readonly: false }
    ]);
});

test("buildSettingsRows ignores duplicate Dock entries for the same app", () => {
    const rows = buildSettingsRows([
        { name: "Reminders", pos: { x: 10, y: 0 } },
        { name: "Preview", pos: { x: 20, y: 0 } },
        { name: "Reminders", pos: { x: 30, y: 0 } }
    ], {
        dock_items: [
            { name: "Reminders", key: "R", screen: "1", placement: "internal_fill" }
        ]
    });

    assert.deepEqual(rows.map(row => ({ name: row.name, key: row.key })), [
        { name: "Reminders", key: "R" },
        { name: "Preview", key: "1" }
    ]);
    assert.equal(validateKeyUpdates(rows).length, 0);
});

test("normalizeEditableKey uses launcher key normalization for settings input", () => {
    assert.equal(normalizeEditableKey(" f3 "), "F3");
    assert.equal(normalizeEditableKey("space"), "SPACE");
    assert.equal(normalizeEditableKey("left_shift"), "LEFT_SHIFT");
    assert.equal(normalizeEditableKey("right-shift"), "RIGHT_SHIFT");
    assert.equal(normalizeEditableKey("⌘"), "COMMAND_LEFT");
    assert.equal(normalizeEditableKey("cmd_left"), "COMMAND_LEFT");
    assert.equal(normalizeEditableKey("left_cmd"), "COMMAND_LEFT");
    assert.equal(normalizeEditableKey(""), "");
});

test("buildSettingsRows renders command shortcuts with the command icon", () => {
    const rows = buildSettingsRows([
        { name: "System Settings", pos: { x: 10, y: 0 } }
    ], {
        dock_items: [
            { name: "System Settings", key: "COMMAND_LEFT", screen: "1", placement: "internal_fill" }
        ]
    });

    assert.equal(rows[0].key, "⌘");
    assert.equal(rows[0].displayKey, "⌘");
});

test("validateKeyUpdates allows left command for System Settings only", () => {
    const allowed = validateKeyUpdates([
        { name: "System Settings", key: "⌘" }
    ]);
    const rejected = validateKeyUpdates([
        { name: "Finder", key: "⌘" }
    ]);

    assert.equal(allowed.length, 0);
    assert.equal(rejected.some(error => error.type === "reserved" && error.key === "COMMAND_LEFT"), true);
});

test("validateKeyUpdates allows launcher defaults while rejecting duplicates and command reservations", () => {
    const errors = validateKeyUpdates([
        { name: "Finder", key: "D" },
        { name: "Safari", key: "d" },
        { name: "Codex Override", key: "left_shift" },
        { name: "SmartShadow Override", key: "f3" },
        { name: "Claude Override", key: "right_shift" },
        { name: "ChatGPT Override", key: "f6" },
        { name: "Command Trap", key: "COMMAND_RIGHT" }
    ]);

    assert.equal(errors.some(error => error.type === "duplicate" && error.key === "D"), true);
    assert.equal(errors.some(error => error.type === "reserved" && error.key === "COMMAND_RIGHT"), true);
    assert.equal(errors.some(error => error.type === "reserved" && error.key === "LEFT_SHIFT"), false);
    assert.equal(errors.some(error => error.type === "reserved" && error.key === "RIGHT_SHIFT"), false);
    assert.equal(errors.some(error => error.type === "reserved" && error.key === "F3"), false);
    assert.equal(errors.some(error => error.type === "reserved" && error.key === "F6"), false);
});

test("saveDockItemSettings writes configurable special app settings", () => {
    const result = saveDockItemSettings({
        dock_items: []
    }, [
        { name: "Claude", pos: { x: 10, y: 0 } }
    ], [
        { name: "Claude", key: "C", screen: "0", placement: "external_fill" }
    ]);

    assert.equal(result.ok, true);
    assert.deepEqual(result.config.dock_items, [
        { name: "Claude", key: "C", screen: "0", placement: "external_fill" }
    ]);
});

test("saveDockItemSettings writes command icon input as COMMAND_LEFT", () => {
    const result = saveDockItemSettings({
        dock_items: [
            { name: "System Settings", key: "COMMAND_LEFT", screen: "1", placement: "internal_fill" }
        ]
    }, [
        { name: "System Settings", pos: { x: 10, y: 0 } }
    ], [
        { name: "System Settings", key: "⌘", screen: "1", placement: "internal_fill" }
    ]);

    assert.equal(result.ok, true);
    assert.equal(result.config.dock_items[0].key, "COMMAND_LEFT");
});

test("saveDockItemSettings updates only visible Dock app settings and preserves advanced fields", () => {
    const dockItems = [
        { name: "GitHub", pos: { x: 10, y: 0 } },
        { name: "Temporary App", pos: { x: 20, y: 0 } }
    ];
    const config = {
        dock_items: [
            {
                name: "GitHub",
                key: "H",
                screen: "1",
                kind: "web_app",
                open_path: "~/Applications/Chromium Apps.localized/GitHub.app",
                app_url: "https://github.com/repos?q=owner%3A%40me+sort%3Aupdated"
            },
            { name: "Hidden App", key: "Q", screen: "0" }
        ]
    };

    const result = saveDockItemSettings(config, dockItems, [
        { name: "GitHub", key: "J", screen: "0", placement: "external_right_half" },
        { name: "Temporary App", key: "" },
        { name: "Hidden App", key: "Z", screen: "1", placement: "internal_fill" }
    ]);

    assert.equal(result.ok, true);
    assert.deepEqual(result.config.dock_items.find(item => item.name === "GitHub"), {
        name: "GitHub",
        key: "J",
        screen: "0",
        kind: "web_app",
        placement: "external_right_half",
        open_path: "~/Applications/Chromium Apps.localized/GitHub.app",
        app_url: "https://github.com/repos?q=owner%3A%40me+sort%3Aupdated"
    });
    assert.equal(result.config.dock_items.some(item => item.name === "Temporary App"), false);
    assert.deepEqual(result.config.dock_items.find(item => item.name === "Hidden App"), {
        name: "Hidden App",
        key: "Q",
        screen: "0"
    });
});

test("saveDockItemSettings clears an existing key without deleting advanced app metadata", () => {
    const dockItems = [
        { name: "X", pos: { x: 10, y: 0 } }
    ];
    const config = {
        dock_items: [
            {
                name: "X",
                key: "X",
                screen: "1",
                kind: "web_app",
                placement: "internal_fill",
                open_path: "~/Applications/Chromium Apps.localized/X.app",
                app_url: "https://x.com/?utm_source=homescreen&utm_medium=shortcut"
            }
        ]
    };

    const result = saveDockItemSettings(config, dockItems, [
        { name: "X", key: "" }
    ]);

    assert.equal(result.ok, true);
    assert.deepEqual(result.config.dock_items[0], {
        name: "X",
        screen: "1",
        kind: "web_app",
        placement: "internal_fill",
        open_path: "~/Applications/Chromium Apps.localized/X.app",
        app_url: "https://x.com/?utm_source=homescreen&utm_medium=shortcut"
    });
    assert.deepEqual(buildSettingsRows(dockItems, result.config).map(row => row.status), ["configured"]);
});

test("saveDockItemSettings creates a visible fallback app when screen or placement is configured", () => {
    const dockItems = [
        { name: "Preview", pos: { x: 10, y: 0 } }
    ];
    const config = {
        dock_items: []
    };

    const result = saveDockItemSettings(config, dockItems, [
        { name: "Preview", key: "", screen: "side_right", placement: "side_right_fill" }
    ]);

    assert.equal(result.ok, true);
    assert.deepEqual(result.config.dock_items, [
        { name: "Preview", screen: "side_right", placement: "side_right_fill" }
    ]);
});

test("saveDockItemSettings persists a user key that replaces an automatic fallback key", () => {
    const dockItems = [
        { name: "WeChat", pos: { x: 10, y: 0 } }
    ];
    const config = { dock_items: [] };

    const result = saveDockItemSettings(config, dockItems, [
        { name: "WeChat", key: "W", screen: "", placement: "" }
    ]);

    assert.equal(result.ok, true);
    assert.deepEqual(result.config.dock_items, [
        { name: "WeChat", key: "W" }
    ]);
    assert.equal(buildSettingsRows(dockItems, result.config)[0].status, "configured");
});


test("placement-only settings survive reload without assigning their automatic key", () => {
    const dock = [{ name: "WorkBuddy", pos: { x: 10 } }, { name: "Other", pos: { x: 20 } }];
    const config = { dock_items: [{ name: "Other", key: "1" }] };
    const saved = saveDockItemSettings(config, dock, [{ name: "WorkBuddy", key: "", screen: "side_right", placement: "side_right_right_half" }]);
    const row = buildSettingsRows(dock, saved.config)[0];
    assert.equal(row.key, "2");
    assert.equal(row.screen, "side_right");
    assert.equal(row.placement, "side_right_right_half");
    assert.equal(row.configured, false);
    assert.equal(saved.config.dock_items.find(item => item.name === "WorkBuddy").key, undefined);
});
