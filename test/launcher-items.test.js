const test = require("node:test");
const assert = require("node:assert/strict");

const {
    buildLauncherItems,
    findLauncherItemForKey,
    isExcludedLauncherApp,
    specialLauncherItemForName
} = require("../src/launcher-items");

test("Feishu localized Dock names retain the configured F shortcut and placement", () => {
    const config = require("../src/config.json").dock_items;
    for (const name of ["Feishu", "飞书", "Lark", " LARK.app "]) {
        const dockItems = [{ name, pos: { x: 10, y: 0 } }];
        const item = findLauncherItemForKey(dockItems, config, "F");
        assert.equal(item.name, "Feishu");
        assert.equal(item.placement, "internal_fill");
        assert.equal(buildLauncherItems(dockItems, config)[0].dockItem.name, name);
    }
    assert.equal(findLauncherItemForKey([{ name: "Feishu Helper", pos: { x: 10, y: 0 } }], config, "F"), null);
});

test("isExcludedLauncherApp marks fixed-key apps as excluded from ordinary fallback keys", () => {
    assert.equal(isExcludedLauncherApp("ChatGPT"), true);
    assert.equal(isExcludedLauncherApp("ChatGPT.app"), true);
    assert.equal(isExcludedLauncherApp("Codex"), true);
    assert.equal(isExcludedLauncherApp("Codex.app"), true);
    assert.equal(isExcludedLauncherApp("SmartShadow"), true);
    assert.equal(isExcludedLauncherApp("SmartShadow.app"), true);
    assert.equal(isExcludedLauncherApp("Claude"), true);
    assert.equal(isExcludedLauncherApp("Claude.app"), true);
});

test("specialLauncherItemForName labels fixed Dock apps with synced key names", () => {
    assert.deepEqual(specialLauncherItemForName("ChatGPT"), {
        name: "ChatGPT",
        key: "F6",
        icon: "F6",
        screen: "side_right",
        placement: "side_right_fill"
    });
    assert.deepEqual(specialLauncherItemForName("Codex.app"), {
        name: "Codex",
        key: "LEFT_SHIFT",
        icon: "L⇧",
        screen: "external",
        placement: "external_fill"
    });
    assert.deepEqual(specialLauncherItemForName("SmartShadow.app"), {
        name: "SmartShadow",
        key: "F3",
        icon: "F3",
        screen: "side_left",
        placement: "side_left_fill",
        open_path: "/Applications/SmartShadow.app"
    });
    assert.deepEqual(specialLauncherItemForName("Claude.app"), {
        name: "Claude",
        key: "RIGHT_SHIFT",
        icon: "R⇧",
        screen: "side_right",
        placement: "side_right_fill",
        open_path: "/Applications/Claude.app"
    });
    assert.equal(specialLauncherItemForName("Finder"), null);
});

test("buildLauncherItems lets config override special app defaults", () => {
    const dockItems = [
        { name: "Claude", pos: { x: 10, y: 0 } }
    ];
    const configDockItems = [
        { name: "Claude", key: "C", screen: "external", placement: "external_fill" }
    ];

    const launcherItems = buildLauncherItems(dockItems, configDockItems);

    assert.deepEqual(launcherItems.map(entry => entry.item), [
        {
            name: "Claude",
            key: "C",
            icon: undefined,
            screen: "external",
            placement: "external_fill",
            open_path: "/Applications/Claude.app"
        }
    ]);
});

test("findLauncherItemForKey resolves configurable modifier app defaults for main-process shortcuts", () => {
    const dockItems = [
        { name: "Codex", pos: { x: 10, y: 0 } },
        { name: "Claude", pos: { x: 20, y: 0 } }
    ];

    assert.equal(findLauncherItemForKey(dockItems, [], "LEFT_SHIFT").name, "Codex");
    assert.deepEqual(findLauncherItemForKey(dockItems, [
        { name: "Claude", key: "C", screen: "external", placement: "external_fill" }
    ], "RIGHT_SHIFT"), null);
    assert.deepEqual(findLauncherItemForKey(dockItems, [
        { name: "Claude", key: "C", screen: "external", placement: "external_fill" }
    ], "C"), {
        name: "Claude",
        key: "C",
        icon: undefined,
        screen: "external",
        placement: "external_fill",
        open_path: "/Applications/Claude.app"
    });
});

test("buildLauncherItems renders special app labels and preserves fallback numeric keys for other apps", () => {
    const dockItems = [
        { name: "Finder", pos: { x: 10, y: 0 } },
        { name: "ChatGPT", pos: { x: 20, y: 0 } },
        { name: "Codex", pos: { x: 30, y: 0 } },
        { name: "System Settings", pos: { x: 40, y: 0 } },
        { name: "SmartShadow", pos: { x: 50, y: 0 } },
        { name: "Claude", pos: { x: 60, y: 0 } },
        { name: "Terminal", pos: { x: 70, y: 0 } },
        { name: "Temporary App", pos: { x: 80, y: 0 } }
    ];
    const configDockItems = [
        { name: "Finder", key: "D" },
        { name: "System Settings", key: "COMMAND_LEFT" },
        { name: "Terminal", key: "\\" }
    ];

    const launcherItems = buildLauncherItems(dockItems, configDockItems);

    assert.deepEqual(
        launcherItems.map(entry => ({ name: entry.item.name, key: entry.item.key })),
        [
            { name: "Finder", key: "D" },
            { name: "ChatGPT", key: "F6" },
            { name: "Codex", key: "LEFT_SHIFT" },
            { name: "System Settings", key: "COMMAND_LEFT" },
            { name: "SmartShadow", key: "F3" },
            { name: "Claude", key: "RIGHT_SHIFT" },
            { name: "Terminal", key: "\\" },
            { name: "Temporary App", key: 1 }
        ]
    );
    assert.deepEqual(
        launcherItems.map(entry => entry.item.icon || entry.item.key),
        ["D", "F6", "L⇧", "⌘", "F3", "R⇧", "\\", 1]
    );
});

test("buildLauncherItems ignores config entries without keys so fallback keys still work", () => {
    const dockItems = [
        { name: "X", pos: { x: 10, y: 0 } }
    ];
    const configDockItems = [
        { name: "X", screen: "1", kind: "web_app", app_url: "https://x.com/" }
    ];

    const launcherItems = buildLauncherItems(dockItems, configDockItems);

    assert.deepEqual(
        launcherItems.map(entry => ({ name: entry.item.name, key: entry.item.key })),
        [
            { name: "X", key: 1 }
        ]
    );
});

test("user-assigned numeric keys take priority over automatic fallback keys", () => {
    const dockItems = [
        { name: "Automatic App", pos: { x: 10, y: 0 } },
        { name: "User App", pos: { x: 20, y: 0 } }
    ];
    const configDockItems = [
        { name: "User App", key: "1" }
    ];

    const launcherItems = buildLauncherItems(dockItems, configDockItems);

    assert.deepEqual(
        launcherItems.map(entry => ({ name: entry.item.name, key: entry.item.key })),
        [
            { name: "Automatic App", key: 2 },
            { name: "User App", key: "1" }
        ]
    );
    assert.equal(findLauncherItemForKey(dockItems, configDockItems, "1").name, "User App");
});
