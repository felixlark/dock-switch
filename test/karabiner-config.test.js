const test = require("node:test");
const assert = require("node:assert/strict");

const {
    DOCK_SWITCH_RULE_DESCRIPTION,
    CHATGPT_DIRECT_COMMAND,
    LOGITECH_TOP_ROW_CONSUMER_DEVICE,
    SMARTSHADOW_DIRECT_COMMAND,
    applyDockSwitchKarabinerConfig,
    applyDockSwitchKarabinerProfile,
    buildDockSwitchKarabinerRule
} = require("../src/karabiner-config");

function directLegacyRule() {
    return {
        description: "F3 opens SmartShadow on the left display; F6 opens ChatGPT on the right display; left Shift opens Codex on the external display; right Shift opens Claude on the right display",
        manipulators: [
            {
                type: "basic",
                from: { key_code: "f3", modifiers: { optional: ["any"] } },
                to: [{ shell_command: "/Users/longbiao/bin/open-hotkey-app.sh smartshadow >/dev/null 2>&1" }]
            },
            {
                type: "basic",
                from: { consumer_key_code: "mission_control", modifiers: { optional: ["any"] } },
                to: [{ shell_command: "/Users/longbiao/bin/open-hotkey-app.sh smartshadow >/dev/null 2>&1" }]
            },
            {
                type: "basic",
                from: { apple_vendor_keyboard_key_code: "mission_control", modifiers: { optional: ["any"] } },
                to: [{ shell_command: "/Users/longbiao/bin/open-hotkey-app.sh smartshadow >/dev/null 2>&1" }]
            },
            {
                type: "basic",
                from: { key_code: "f6", modifiers: { optional: ["any"] } },
                to: [{ shell_command: "/Users/longbiao/bin/open-hotkey-app.sh chatgpt >/dev/null 2>&1" }]
            },
            {
                type: "basic",
                from: { key_code: "left_shift", modifiers: { optional: ["any"] } },
                to: [{ key_code: "left_shift" }],
                to_if_alone: [{ shell_command: "/Users/longbiao/bin/open-hotkey-app.sh codex >/dev/null 2>&1" }]
            },
            {
                type: "basic",
                from: { key_code: "right_shift", modifiers: { optional: ["any"] } },
                to: [{ key_code: "right_shift" }],
                to_if_alone: [{ shell_command: "/Users/longbiao/bin/open-hotkey-app.sh claude >/dev/null 2>&1" }]
            }
        ]
    };
}

test("applyDockSwitchKarabinerProfile keeps F3 and F6 direct while removing Shift launcher mappings", () => {
    const profile = {
        simple_modifications: [
            { from: { key_code: "left_shift" }, to: [{ key_code: "left_shift" }] },
            { from: { key_code: "caps_lock" }, to: [{ key_code: "f20" }] }
        ],
        fn_function_keys: [
            { from: { key_code: "f5" }, to: [{ key_code: "f5" }] },
            { from: { key_code: "f6" }, to: [{ key_code: "f6" }] }
        ],
        devices: [
            {
                identifiers: {
                    is_consumer: true,
                    product_id: 50479,
                    vendor_id: 1133
                },
                ignore: true
            }
        ],
        complex_modifications: {
            rules: [
                directLegacyRule(),
                {
                    description: "Longbiao's Tweaks",
                    manipulators: [
                        {
                            type: "basic",
                            from: { key_code: "d", modifiers: { mandatory: ["right_shift"] } },
                            to: [{ shell_command: "date" }]
                        },
                        {
                            type: "basic",
                            from: { key_code: "f6", modifiers: { optional: ["any"] } },
                            to: [{ key_code: "vk_none" }]
                        },
                        {
                            type: "basic",
                            from: { generic_desktop: "do_not_disturb", modifiers: { optional: ["any"] } },
                            to: [{ key_code: "vk_none" }]
                        },
                        {
                            type: "basic",
                            from: { key_code: "f5", modifiers: { optional: ["any"] } },
                            to: [{ shell_command: "date" }]
                        },
                        {
                            type: "basic",
                            from: { key_code: "f5", modifiers: { mandatory: ["fn"], optional: ["any"] } },
                            to: [{ key_code: "vk_none" }]
                        }
                    ]
                }
            ]
        }
    };

    const result = applyDockSwitchKarabinerProfile(profile);

    assert.equal(result.changed, true);
    assert.equal(
        JSON.stringify(profile).includes("open-hotkey-app.sh"),
        false
    );
    assert.equal(
        profile.complex_modifications.rules.some(rule =>
            rule.manipulators.some(manipulator => manipulator.from && manipulator.from.key_code === "f6" && manipulator.to?.[0]?.key_code === "vk_none")
        ),
        false
    );
    assert.deepEqual(
        profile.complex_modifications.rules.find(rule => rule.description === "Longbiao's Tweaks").manipulators.map(manipulator => manipulator.from.key_code),
        ["d", "f5"]
    );
    assert.deepEqual(profile.simple_modifications, []);
    assert.deepEqual(profile.fn_function_keys, [
        { from: { key_code: "f3" }, to: [{ shell_command: SMARTSHADOW_DIRECT_COMMAND }] },
        { from: { key_code: "f5" }, to: [{ key_code: "f5" }] },
        { from: { key_code: "f6" }, to: [{ shell_command: CHATGPT_DIRECT_COMMAND }] }
    ]);
    assert.deepEqual(profile.devices, [LOGITECH_TOP_ROW_CONSUMER_DEVICE]);

    const dockSwitchRule = profile.complex_modifications.rules[0];
    assert.equal(dockSwitchRule.description, DOCK_SWITCH_RULE_DESCRIPTION);
    assert.equal(dockSwitchRule.manipulators.length, 6);

    const f3 = dockSwitchRule.manipulators.find(manipulator => manipulator.from.key_code === "f3");
    assert.deepEqual(f3.to, [{ shell_command: SMARTSHADOW_DIRECT_COMMAND }]);

    const unsupportedMissionControl = dockSwitchRule.manipulators.find(manipulator =>
        manipulator.from.consumer_key_code === "mission_control"
    );
    assert.equal(unsupportedMissionControl, undefined);

    const missionControl = dockSwitchRule.manipulators.filter(manipulator =>
        manipulator.from.apple_vendor_keyboard_key_code === "mission_control"
    );
    assert.equal(missionControl.length, 1);
    assert.deepEqual(missionControl.map(manipulator => manipulator.to), [
        [{ shell_command: SMARTSHADOW_DIRECT_COMMAND }]
    ]);

    const f6 = dockSwitchRule.manipulators.find(manipulator => manipulator.from.key_code === "f6");
    assert.deepEqual(f6.to, [{ shell_command: CHATGPT_DIRECT_COMMAND }]);

    const fnF5 = dockSwitchRule.manipulators.find(manipulator =>
        manipulator.from.key_code === "f5" && manipulator.from.modifiers?.mandatory?.includes("fn")
    );
    assert.deepEqual(fnF5.to, [{ shell_command: CHATGPT_DIRECT_COMMAND }]);

    const doNotDisturb = dockSwitchRule.manipulators.find(manipulator => manipulator.from.generic_desktop === "do_not_disturb");
    assert.deepEqual(doNotDisturb.to, [{ shell_command: CHATGPT_DIRECT_COMMAND }]);

    const leftShift = dockSwitchRule.manipulators.find(manipulator => manipulator.from.key_code === "left_shift");
    assert.equal(leftShift, undefined);

    const rightShift = dockSwitchRule.manipulators.find(manipulator => manipulator.from.key_code === "right_shift");
    assert.equal(rightShift, undefined);
});

test("applyDockSwitchKarabinerProfile treats Karabiner-reordered manipulators as current", () => {
    const rule = buildDockSwitchKarabinerRule();
    const profile = {
        devices: [LOGITECH_TOP_ROW_CONSUMER_DEVICE],
        fn_function_keys: [
            { from: { key_code: "f3" }, to: [{ shell_command: SMARTSHADOW_DIRECT_COMMAND }] },
            { from: { key_code: "f6" }, to: [{ shell_command: CHATGPT_DIRECT_COMMAND }] }
        ],
        complex_modifications: {
            rules: [
                {
                    description: rule.description,
                    manipulators: rule.manipulators.map(manipulator => ({
                        from: manipulator.from,
                        to: manipulator.to,
                        ...(manipulator.to_if_alone ? { to_if_alone: manipulator.to_if_alone } : {}),
                        type: manipulator.type
                    }))
                }
            ]
        }
    };

    const result = applyDockSwitchKarabinerProfile(profile);

    assert.equal(result.changed, false);
});

test("applyDockSwitchKarabinerProfile installs top-row F3 and F6 as direct function-key launchers", () => {
    const profile = {
        fn_function_keys: [
            { from: { key_code: "f1" }, to: [{ apple_vendor_keyboard_key_code: "brightness_down" }] },
            { from: { key_code: "f7" }, to: [{ key_code: "vk_consumer_previous" }] }
        ],
        complex_modifications: {
            rules: []
        }
    };

    const result = applyDockSwitchKarabinerProfile(profile);

    assert.equal(result.changed, true);
    assert.deepEqual(profile.fn_function_keys, [
        { from: { key_code: "f1" }, to: [{ apple_vendor_keyboard_key_code: "brightness_down" }] },
        { from: { key_code: "f3" }, to: [{ shell_command: SMARTSHADOW_DIRECT_COMMAND }] },
        { from: { key_code: "f6" }, to: [{ shell_command: CHATGPT_DIRECT_COMMAND }] },
        { from: { key_code: "f7" }, to: [{ key_code: "vk_consumer_previous" }] }
    ]);
});

test("applyDockSwitchKarabinerProfile enables the Logitech consumer interface used by top-row keys", () => {
    const profile = {
        devices: [
            {
                identifiers: {
                    is_keyboard: true,
                    product_id: 50484,
                    vendor_id: 1133
                },
                manipulate_caps_lock_led: false
            }
        ],
        complex_modifications: {
            rules: []
        }
    };

    const result = applyDockSwitchKarabinerProfile(profile);

    assert.equal(result.changed, true);
    assert.deepEqual(profile.devices, [
        {
            identifiers: {
                is_keyboard: true,
                product_id: 50484,
                vendor_id: 1133
            },
            manipulate_caps_lock_led: false
        },
        LOGITECH_TOP_ROW_CONSUMER_DEVICE
    ]);
});


test("restores Caps Lock and migrates global and device right Command mappings without touching other keys", () => {
    const old = key => ({ from: { key_code: key }, to: [{ key_code: key === "caps_lock" ? "f20" : "f13" }] });
    const unrelated = { from: { key_code: "right_option" }, to: [{ key_code: "delete_forward" }] };
    const deviceOnly = { from: { key_code: "f3" }, to: [{ key_code: "f4" }] };
    const unrelatedManipulator = { type: "basic", from: { key_code: "a", modifiers: { mandatory: ["right_command"] } }, to: [{ key_code: "b" }] };
    const profile = {
        simple_modifications: [old("caps_lock"), old("right_command"), unrelated],
        devices: [
            { identifiers: { is_keyboard: true, vendor_id: 1452, product_id: 628 }, simple_modifications: [old("caps_lock"), old("right_command"), unrelated, deviceOnly] },
            { identifiers: { is_keyboard: true, vendor_id: 1133, product_id: 50484 }, ignore: false, simple_modifications: [old("right_command"), unrelated, old("caps_lock")] }
        ],
        complex_modifications: { rules: [{ description: "legacy", manipulators: [{ type: "basic", ...old("caps_lock") }, { type: "basic", ...old("right_command") }, unrelatedManipulator] }] }
    };
    assert.equal(applyDockSwitchKarabinerProfile(profile).changed, true);
    assert.deepEqual(profile.simple_modifications, [unrelated]);
    assert.deepEqual(profile.devices[0].simple_modifications, [unrelated, deviceOnly]);
    assert.deepEqual(profile.devices[1].simple_modifications, [unrelated]);
    assert.equal(profile.devices[1].ignore, false);
    assert.deepEqual(profile.complex_modifications.rules[1], { description: "legacy", manipulators: [unrelatedManipulator] });
    const manipulators = profile.complex_modifications.rules.flatMap(rule => rule.manipulators);
    assert.equal(manipulators.some(item => item.from.key_code === "caps_lock"), false);
    const rightCommand = manipulators.filter(item => item.from.key_code === "right_command");
    assert.equal(rightCommand.length, 1);
    assert.deepEqual(rightCommand[0].from, { key_code: "right_command", modifiers: { optional: ["any"] } });
    assert.deepEqual(rightCommand[0].to, [{ key_code: "right_command", lazy: true }]);
    assert.deepEqual(rightCommand[0].to_if_alone, [{ key_code: "f20" }]);
    const after = structuredClone(profile);
    assert.equal(applyDockSwitchKarabinerProfile(profile).changed, false);
    assert.deepEqual(profile, after);
});

test("applyDockSwitchKarabinerConfig migrates only the selected profile", () => {
    const inactive = { selected: false, simple_modifications: [{ from: { key_code: "caps_lock" }, to: [{ key_code: "escape" }] }] };
    const inactiveBefore = structuredClone(inactive);
    const selected = { selected: true, simple_modifications: [{ from: { key_code: "caps_lock" }, to: [{ key_code: "f20" }] }] };
    const config = { global: { show_in_menu_bar: false }, profiles: [inactive, selected] };
    assert.equal(applyDockSwitchKarabinerConfig(config).changed, true);
    assert.deepEqual(inactive, inactiveBefore);
    assert.deepEqual(selected.simple_modifications, []);
    assert.deepEqual(config.global, { show_in_menu_bar: false });
    assert.equal(applyDockSwitchKarabinerConfig(config).changed, false);
});

test("applyDockSwitchKarabinerProfile normalizes a non-array devices field", () => {
    const profile = { devices: {} };
    assert.equal(applyDockSwitchKarabinerProfile(profile).changed, true);
    assert.deepEqual(profile.devices, [LOGITECH_TOP_ROW_CONSUMER_DEVICE]);
    assert.equal(applyDockSwitchKarabinerProfile(profile).changed, false);
});
