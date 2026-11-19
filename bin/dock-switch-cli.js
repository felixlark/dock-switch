#!/usr/bin/env node

const childProcess = require("child_process");
const net = require("net");
const os = require("os");
const path = require("path");

const CONTROL_SOCKET_PATH = path.join(
    os.homedir(),
    "Library",
    "Application Support",
    "dock-switch",
    "control.sock"
);

function usage() {
    console.error("Usage:");
    console.error("  dock-switch-cli displays");
    console.error("  dock-switch-cli show-launcher");
    console.error("  dock-switch-cli hide-launcher");
    console.error("  dock-switch-cli capture-launcher --output <PNGPath>");
    console.error("  dock-switch-cli codex-display --target <side_left|external|side_right|internal>");
    console.error("  dock-switch-cli computer-use-browser [--anchor-app <AppName>] [--browser-app <AppName>]");
    console.error("  dock-switch-cli gokit5-status");
    console.error("  dock-switch-cli place (--app <AppName> | --pid <Pid>) --placement <Placement>");
    console.error("  dock-switch-cli move (--app <AppName> | --pid <Pid>) --x <X> --y <Y> --w <W> --h <H>");
    console.error("  dock-switch-cli get-chrome-window --profile-dir <Dir>");
    console.error("  dock-switch-cli move-chrome-window --profile-dir <Dir> --x <X> --y <Y> --w <W> --h <H>");
    process.exit(2);
}

function parseArgs(argv) {
    if (argv.length === 0) usage();

    const command = argv[0];
    let appName = "";
    let pid = null;
    let profileDir = "";
    let placement = "";
    let displayTarget = "";
    let anchorApp = "";
    let browserApp = "";
    let outputPath = "";
    let x = null;
    let y = null;
    let w = null;
    let h = null;
    if (command === "displays") {
        if (argv.length !== 1) usage();
        return { command: "debug-displays", format: "json" };
    }
    if (command === "gokit5-status") {
        if (argv.length !== 1) usage();
        return { command: "gokit5-status", format: "json" };
    }
    if (command === "show-launcher") {
        if (argv.length !== 1) usage();
        return { command: "show-launcher", format: "json" };
    }
    if (command === "hide-launcher") {
        if (argv.length !== 1) usage();
        return { command: "hide-launcher", format: "json" };
    }
    for (let i = 1; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === "--app") {
            appName = argv[i + 1] || "";
            i += 1;
        } else if (arg === "--pid") {
            pid = Number(argv[i + 1]);
            i += 1;
        } else if (arg === "--profile-dir") {
            profileDir = argv[i + 1] || "";
            i += 1;
        } else if (arg === "--placement") {
            placement = argv[i + 1] || "";
            i += 1;
        } else if (arg === "--target") {
            displayTarget = argv[i + 1] || "";
            i += 1;
        } else if (arg === "--anchor-app") {
            anchorApp = argv[i + 1] || "";
            i += 1;
        } else if (arg === "--browser-app") {
            browserApp = argv[i + 1] || "";
            i += 1;
        } else if (arg === "--output") {
            outputPath = argv[i + 1] || "";
            i += 1;
        } else if (arg === "--x") {
            x = Number(argv[i + 1]);
            i += 1;
        } else if (arg === "--y") {
            y = Number(argv[i + 1]);
            i += 1;
        } else if (arg === "--w") {
            w = Number(argv[i + 1]);
            i += 1;
        } else if (arg === "--h") {
            h = Number(argv[i + 1]);
            i += 1;
        } else {
            usage();
        }
    }

    const requiresAppOrPid = command === "place" || command === "move";
    if (requiresAppOrPid &&
        (appName ? 1 : 0) + (Number.isFinite(pid) && pid > 0 ? 1 : 0) !== 1) {
        usage();
    }

    if (command === "capture-launcher") {
        if (!outputPath) usage();
        return {
            command: "capture-launcher",
            outputPath: path.resolve(outputPath),
            format: "json"
        };
    }

    const target = appName
        ? { appName }
        : { pid: Math.round(pid) };

    if (command === "codex-display") {
        if (!displayTarget) usage();
        return {
            command: "select-codex-display",
            target: displayTarget,
            format: "json"
        };
    }

    if (command === "computer-use-browser") {
        return {
            command: "computer-use-browser",
            anchorApp: anchorApp || "Codex",
            browserApp: browserApp || "Google Chrome for Testing",
            format: "json"
        };
    }

    if (command === "place") {
        if (!placement) usage();
        return {
            command: appName ? "place-app" : "place-pid",
            ...target,
            placement
        };
    }

    if (command === "move") {
        if (![x, y, w, h].every(Number.isFinite) || w <= 0 || h <= 0) usage();
        return {
            command: appName ? "move-app" : "move-pid",
            ...target,
            x: Math.round(x),
            y: Math.round(y),
            w: Math.round(w),
            h: Math.round(h)
        };
    }

    if (command === "get-chrome-window") {
        if (!profileDir) usage();
        return {
            command: "get-chrome-window",
            profileDir
        };
    }

    if (command === "move-chrome-window") {
        if (!profileDir) usage();
        if (![x, y, w, h].every(Number.isFinite) || w <= 0 || h <= 0) usage();
        return {
            command: "move-chrome-window",
            profileDir,
            x: Math.round(x),
            y: Math.round(y),
            w: Math.round(w),
            h: Math.round(h)
        };
    }

    usage();
}

function getChromeProcessForProfile(profileDir) {
    const result = childProcess.spawnSync("ps", ["ax", "-o", "pid=,command="], {
        encoding: "utf8"
    });
    if (result.status !== 0) {
        throw new Error(String(result.stderr || "Failed to inspect processes").trim());
    }

    const escaped = profileDir.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const profilePattern = new RegExp(`--user-data-dir=${escaped}(?:\\s|$)`);
    const portPattern = /--remote-debugging-port=(\d+)/;
    const candidates = String(result.stdout || "")
        .split("\n")
        .map(line => line.trim())
        .filter(Boolean)
        .map(line => {
            const match = line.match(/^(\d+)\s+(.*)$/);
            if (!match) return null;
            return {
                pid: Number(match[1]),
                command: match[2]
            };
        })
        .filter(Boolean)
        .filter(entry => /\/Applications\/Google Chrome\.app\/Contents\/MacOS\/Google Chrome/.test(entry.command))
        .filter(entry => !/--type=/.test(entry.command))
        .filter(entry => !/crashpad_handler/.test(entry.command))
        .filter(entry => profilePattern.test(entry.command))
        .map(entry => {
            const portMatch = entry.command.match(portPattern);
            return {
                ...entry,
                debuggingPort: portMatch ? Number(portMatch[1]) : null
            };
        })
        .filter(entry => Number.isFinite(entry.debuggingPort) && entry.debuggingPort > 0)
        .sort((a, b) => b.pid - a.pid);

    if (candidates.length === 0) {
        throw new Error(`No Chrome process found for profile ${profileDir}`);
    }

    return candidates[0];
}

async function fetchJson(url) {
    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`HTTP ${response.status} for ${url}`);
    }
    return await response.json();
}

async function withBrowserWebSocket(webSocketUrl, fn) {
    const socket = new WebSocket(webSocketUrl);
    const pending = new Map();
    let nextId = 1;

    await new Promise((resolve, reject) => {
        socket.addEventListener("open", () => resolve(), { once: true });
        socket.addEventListener("error", event => reject(event.error || new Error("WebSocket connection failed")), { once: true });
    });

    socket.addEventListener("message", event => {
        try {
            const message = JSON.parse(String(event.data));
            if (!message.id) return;
            const record = pending.get(message.id);
            if (!record) return;
            pending.delete(message.id);
            if (message.error) {
                record.reject(new Error(message.error.message || JSON.stringify(message.error)));
                return;
            }
            record.resolve(message.result);
        } catch (error) {
            // Ignore malformed async messages.
        }
    });

    const send = (method, params = {}) => new Promise((resolve, reject) => {
        const id = nextId++;
        pending.set(id, { resolve, reject });
        socket.send(JSON.stringify({ id, method, params }));
    });

    try {
        return await fn(send);
    } finally {
        for (const [, record] of pending) {
            record.reject(new Error("WebSocket closed"));
        }
        pending.clear();
        socket.close();
    }
}

function scoreChromeTarget(target) {
    if (!target || target.type !== "page") return -1;
    let score = 0;
    if (target.url && target.url !== "about:blank") score += 20;
    if (target.url && !target.url.startsWith("devtools://")) score += 5;
    if (target.title) score += 2;
    if (target.attached) score += 1;
    return score;
}

async function moveChromeWindowForProfile(profileDir, bounds) {
    const processInfo = getChromeProcessForProfile(profileDir);
    const version = await fetchJson(`http://127.0.0.1:${processInfo.debuggingPort}/json/version`);
    const targets = await fetchJson(`http://127.0.0.1:${processInfo.debuggingPort}/json/list`);
    const pageTargets = Array.isArray(targets) ? targets : [];
    const target = pageTargets
        .slice()
        .sort((a, b) => scoreChromeTarget(b) - scoreChromeTarget(a))[0];

    if (!target || !target.id) {
        throw new Error(`No page target found for profile ${profileDir}`);
    }
    if (!version.webSocketDebuggerUrl) {
        throw new Error(`No browser websocket available for profile ${profileDir}`);
    }

    return await withBrowserWebSocket(version.webSocketDebuggerUrl, async send => {
        const { windowId } = await send("Browser.getWindowForTarget", { targetId: target.id });
        if (bounds) {
            await send("Target.activateTarget", { targetId: target.id });
            await send("Browser.setWindowBounds", {
                windowId,
                bounds: {
                    windowState: "normal",
                    left: bounds.x,
                    top: bounds.y,
                    width: bounds.w,
                    height: bounds.h
                }
            });
        }
        const result = await send("Browser.getWindowBounds", { windowId });
        return {
            pid: processInfo.pid,
            debuggingPort: processInfo.debuggingPort,
            targetId: target.id,
            targetTitle: target.title || "",
            targetUrl: target.url || "",
            bounds: result.bounds || null
        };
    });
}

function connectAndSend(payload) {
    return new Promise((resolve, reject) => {
        const socket = net.createConnection(CONTROL_SOCKET_PATH);
        let buffer = "";
        let settled = false;
        let sent = false;

        socket.setEncoding("utf8");
        socket.on("connect", () => {
            socket.write(JSON.stringify(payload) + "\n");
            sent = true;
        });
        socket.on("data", chunk => {
            buffer += chunk;
            const newlineIndex = buffer.indexOf("\n");
            if (newlineIndex === -1) return;
            const raw = buffer.slice(0, newlineIndex).trim();
            if (!raw) return;
            settled = true;
            socket.end();
            resolve(JSON.parse(raw));
        });
        socket.on("error", err => {
            if (settled) return;
            err.requestMayHaveRun = sent;
            reject(err);
        });
        socket.on("end", () => {
            if (!settled) {
                const err = new Error("No response from dock-switch; check application state before retrying");
                err.requestMayHaveRun = sent;
                reject(err);
            }
        });
    });
}

function launchDockSwitch() {
    childProcess.spawn("/usr/bin/open", ["/Applications/dock-switch.app"], {
        detached: true,
        stdio: "ignore"
    }).unref();
}

function commandError(message) {
    const error = new Error(message || "dock-switch command failed");
    error.commandFailed = true;
    return error;
}

async function main() {
    const payload = parseArgs(process.argv.slice(2));

    if (payload.command === "get-chrome-window") {
        const result = await moveChromeWindowForProfile(payload.profileDir, null);
        process.stdout.write(JSON.stringify(result) + "\n");
        return;
    }

    if (payload.command === "move-chrome-window") {
        const result = await moveChromeWindowForProfile(payload.profileDir, {
            x: payload.x,
            y: payload.y,
            w: payload.w,
            h: payload.h
        });
        process.stdout.write(JSON.stringify(result) + "\n");
        return;
    }

    try {
        const response = await connectAndSend(payload);
        if (!response.ok) {
            throw commandError(response.error);
        }
        printResponse(payload, response);
        return;
    } catch (err) {
        if (err && (err.commandFailed || err.requestMayHaveRun)) {
            throw err;
        }
        launchDockSwitch();
    }

    const deadline = Date.now() + 4000;
    while (Date.now() < deadline) {
        await new Promise(resolve => setTimeout(resolve, 120));
        try {
            const response = await connectAndSend(payload);
            if (!response.ok) {
                throw commandError(response.error);
            }
            printResponse(payload, response);
            return;
        } catch (err) {
            if (err && (err.commandFailed || err.requestMayHaveRun)) throw err;
            // retry until deadline
        }
    }

    throw new Error("Timed out waiting for dock-switch control server");
}

function printResponse(payload, response) {
    if (payload.format !== "json") {
        return;
    }
    if (payload.command === "debug-displays") {
        process.stdout.write(JSON.stringify(response.displays || [], null, 2) + "\n");
        return;
    }
    process.stdout.write(JSON.stringify(response, null, 2) + "\n");
}

main().catch(err => {
    console.error(err.message || String(err));
    process.exit(1);
});
