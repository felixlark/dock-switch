#!/usr/bin/env node

const {
    applyDockSwitchKarabinerConfig,
    defaultKarabinerConfigPath,
    readKarabinerConfig,
    writeKarabinerConfig
} = require("../src/karabiner-config");

function usage() {
    return [
        "usage: configure-karabiner-f20-shortcuts.js [--config <path>] [--check]",
        "",
        "Installs the dock-switch launcher shortcut rule into the selected Karabiner profile.",
        "F3 opens SmartShadow directly; F6 opens ChatGPT directly.",
        "Legacy left_shift/right_shift launcher mappings are removed so Shift returns to the default behavior.",
        "The rule removes conflicting legacy mappings first."
    ].join("\n");
}

function parseArgs(argv) {
    const options = {
        configPath: defaultKarabinerConfigPath(),
        check: false
    };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === "--check") {
            options.check = true;
            continue;
        }
        if (arg === "--config") {
            const value = argv[i + 1];
            if (!value) throw new Error("--config requires a path");
            options.configPath = value;
            i += 1;
            continue;
        }
        if (arg === "-h" || arg === "--help") {
            options.help = true;
            continue;
        }
        throw new Error(`unknown argument: ${arg}`);
    }
    return options;
}

function main(argv = process.argv.slice(2)) {
    const options = parseArgs(argv);
    if (options.help) {
        console.log(usage());
        return 0;
    }

    const config = readKarabinerConfig(options.configPath);
    const result = applyDockSwitchKarabinerConfig(config);
    if (options.check) {
        if (result.changed) {
            console.error(`Karabiner config is not current: ${options.configPath}`);
            return 1;
        }
        console.log(`Karabiner config is current: ${options.configPath}`);
        return 0;
    }

    if (result.changed) {
        writeKarabinerConfig(config, options.configPath);
        console.log(`Updated Karabiner config: ${options.configPath}`);
    } else {
        console.log(`Karabiner config already current: ${options.configPath}`);
    }
    return 0;
}

if (require.main === module) {
    try {
        process.exitCode = main();
    } catch (error) {
        console.error(error && error.message ? error.message : String(error));
        console.error(usage());
        process.exitCode = 2;
    }
}

module.exports = {
    main,
    parseArgs
};
