const test = require("node:test");
const assert = require("node:assert/strict");

const config = require("../src/config.json");

test("default config maps Xiaohongshu web app to R", () => {
    const item = config.dock_items.find(entry => entry.name === "小红书");

    assert.deepEqual(item, {
        name: "小红书",
        key: "R",
        screen: "1",
        kind: "web_app",
        placement: "internal_fill",
        open_path: "~/Applications/Chromium Apps.localized/小红书.app",
        app_url: "https://www.xiaohongshu.com/explore?m_source=pwa"
    });
});

test("default config maps requested apps and web apps to internal fill", () => {
    const expectedInternalFill = [
        "Safari",
        "Google Chrome",
        "WeChat",
        "Feishu",
        "Mail",
        "Calendar",
        "LifeOS",
        "Notes",
        "Contacts",
        "Sublime Text",
        "GitHub",
        "小红书"
    ];

    for (const name of expectedInternalFill) {
        const item = config.dock_items.find(entry => entry.name === name);
        assert.equal(item && item.screen, "1", `${name} should target the internal screen`);
        assert.equal(item && item.placement, "internal_fill", `${name} should be maximized on the internal screen`);
    }
});

test("default config places the X web app on the left display", () => {
    assert.deepEqual(config.dock_items.find(entry => entry.name === "X"), {
        name: "X",
        key: "X",
        screen: "side_left",
        kind: "web_app",
        placement: "side_left_fill",
        open_path: "~/Applications/Chromium Apps.localized/X.app",
        app_url: "https://x.com/?utm_source=homescreen&utm_medium=shortcut"
    });
});

test("default config maps Terminal to right screen fill", () => {
    const terminal = config.dock_items.find(entry => entry.name === "Terminal");
    const x = config.dock_items.find(entry => entry.name === "X");
    const sublimeText = config.dock_items.find(entry => entry.name === "Sublime Text");

    assert.equal(sublimeText && sublimeText.key, "T");
    assert.equal(x && x.key, "X");
    assert.deepEqual(terminal, {
        name: "Terminal",
        key: "\\",
        screen: "side_right",
        placement: "side_right_fill"
    });
});

test("default config maps G to Google Chrome and H to GitHub", () => {
    const chrome = config.dock_items.find(entry => entry.name === "Google Chrome");
    const github = config.dock_items.find(entry => entry.name === "GitHub");

    assert.deepEqual(chrome, {
        name: "Google Chrome",
        key: "G",
        screen: "1",
        placement: "internal_fill"
    });
    assert.equal(config.dock_items.some(entry => /Testing/.test(entry.name)), false);
    assert.equal(github.key, "H");
});

test("default config maps L to LifeOS", () => {
    assert.deepEqual(config.dock_items.find(entry => entry.name === "LifeOS"), {
        name: "LifeOS",
        key: "L",
        screen: "1",
        placement: "internal_fill"
    });
});

test("default config maps left command to System Settings on the internal display", () => {
    assert.deepEqual(config.dock_items.find(entry => entry.name === "System Settings"), {
        name: "System Settings",
        key: "COMMAND_LEFT",
        screen: "1",
        placement: "internal_fill"
    });
});

test("default launcher config leaves SmartShadow out of ordinary HUD keys", () => {
    assert.equal(config.dock_items.some(entry => entry.name === "SmartShadow"), false);
    assert.equal(config.dock_items.some(entry => entry.key === "F3"), false);
    assert.equal(config.dock_items.some(entry => entry.key === "F6"), false);
    assert.equal(config.dock_items.some(entry => entry.key === "LEFT_SHIFT"), false);
    assert.equal(config.dock_items.some(entry => entry.key === "RIGHT_SHIFT"), false);
});

test("default config does not assign duplicate launcher keys", () => {
    const byKey = new Map();

    for (const item of config.dock_items) {
        const key = String(item.key || "");
        if (!key) continue;

        assert.equal(
            byKey.has(key),
            false,
            `key ${key} is assigned to both ${byKey.get(key)} and ${item.name}`
        );
        byKey.set(key, item.name);
    }
});
