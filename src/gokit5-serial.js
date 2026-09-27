const childProcess = require("child_process");
const fs = require("fs");

const DEFAULT_BAUD_RATE = 115200;
const DEFAULT_RECONNECT_MS = 2000;
const DEFAULT_DEBOUNCE_MS = 0;
const DEFAULT_SERIAL_NUMBER = "94:A9:90:10:E5:F4";
const HOST_BUTTON_PREFIX = "GOKIT5_HOST_BUTTON:";

const BUTTON_TO_APP_ACTION = Object.freeze({
    minus: Object.freeze({
        mouse_target: "side_left"
    }),
    voice: Object.freeze({
        mouse_target: "external"
    }),
    switch: Object.freeze({
        mouse_target: "side_right"
    }),
    green: Object.freeze({
        mouse_target: "side_right"
    }),
    plus: Object.freeze({
        mouse_target: "internal"
    })
});

const BUTTON_TO_INPUT_PHRASE = Object.freeze({
    voice: "/goal",
    plus: "/plan",
    green: "side chat",
    switch: "side chat",
    minus: "continue"
});

function normalizeGokit5ButtonName(button) {
    const key = String(button || "").trim().toLowerCase().replace(/-/g, "_");
    return key;
}

function mapGokit5ButtonToAction(button) {
    const action = BUTTON_TO_APP_ACTION[normalizeGokit5ButtonName(button)];
    return action ? Object.assign({}, action) : null;
}

function mapGokit5ButtonToInputPhrase(button) {
    return BUTTON_TO_INPUT_PHRASE[normalizeGokit5ButtonName(button)] || "";
}

function parseGokit5ButtonLine(line) {
    const text = String(line || "");
    const markerIndex = text.indexOf(HOST_BUTTON_PREFIX);
    if (markerIndex === -1) {
        return "";
    }

    const rawButton = text.slice(markerIndex + HOST_BUTTON_PREFIX.length)
        .trim()
        .split(/\s+/)[0]
        .replace(/[^A-Za-z0-9_+-].*$/, "");
    const button = normalizeGokit5ButtonName(rawButton);
    return mapGokit5ButtonToAction(button) ? button : "";
}

function shouldDispatchButton(button, nowMs, lastDispatchByButton, debounceMs) {
    const normalized = normalizeGokit5ButtonName(button);
    if (!normalized) return false;
    const last = lastDispatchByButton.get(normalized) || 0;
    if (nowMs - last < debounceMs) {
        return false;
    }
    lastDispatchByButton.set(normalized, nowMs);
    return true;
}

function parseUsbDeviceBlockForSuffixes(block, serialNumber) {
    if (!/idVendor"\s*=\s*12346/.test(block)) return [];
    if (!/idProduct"\s*=\s*4097/.test(block)) return [];
    if (!/USB JTAG[_/]serial debug unit|USB JTAG\/serial debug unit/.test(block)) return [];
    if (serialNumber && !block.includes(`"${serialNumber}"`)) return [];

    const suffixes = [];
    const suffixPattern = /"IOTTYSuffix"\s*=\s*"([^"]+)"/g;
    let match;
    while ((match = suffixPattern.exec(block)) !== null) {
        suffixes.push(match[1]);
    }
    return suffixes;
}

function extractGokit5PortPathsFromIoregText(text, options = {}) {
    const serialNumber = String(options.serialNumber || DEFAULT_SERIAL_NUMBER).trim();
    const lines = String(text || "").split("\n");
    const ports = [];

    for (let i = 0; i < lines.length; i += 1) {
        if (!/USB JTAG[_/]serial debug unit|USB JTAG\/serial debug unit/.test(lines[i])) {
            continue;
        }
        const block = lines.slice(i, Math.min(lines.length, i + 220)).join("\n");
        for (const suffix of parseUsbDeviceBlockForSuffixes(block, serialNumber)) {
            ports.push(`/dev/cu.usbmodem${suffix}`);
        }
    }

    return Array.from(new Set(ports));
}

function listUsbModemPorts(fsModule = fs) {
    let names = [];
    try {
        names = fsModule.readdirSync("/dev");
    } catch (e) {
        return [];
    }
    return names
        .filter(name => /^cu\.usbmodem/.test(name))
        .sort()
        .map(name => `/dev/${name}`);
}

function findGokit5SerialPort(options = {}) {
    const fsModule = options.fs || fs;
    const envPort = String((options.env && options.env.GOKIT5_SERIAL_PORT) || process.env.GOKIT5_SERIAL_PORT || "").trim();
    if (envPort && fsModule.existsSync(envPort)) {
        return envPort;
    }

    const runCommand = options.runCommand || childProcess.spawnSync;
    try {
        const result = runCommand("ioreg", ["-r", "-c", "IOUSBHostDevice", "-l"], { encoding: "utf8" });
        if (result && result.status === 0) {
            const candidates = extractGokit5PortPathsFromIoregText(result.stdout || "", options);
            const existing = candidates.find(port => fsModule.existsSync(port));
            if (existing) return existing;
        }
    } catch (e) {
        // Fall back to visible modem ports.
    }

    return listUsbModemPorts(fsModule)[0] || "";
}

function configureSerialPort(portPath, baudRate, options = {}) {
    const runCommand = options.runCommand || childProcess.spawnSync;
    const result = runCommand("stty", [
        "-f",
        portPath,
        String(baudRate || DEFAULT_BAUD_RATE),
        "raw",
        "-echo",
        "-icanon",
        "min",
        "1",
        "time",
        "0",
        "clocal",
        "-hupcl"
    ], { encoding: "utf8" });
    return !result || result.status === 0;
}

function createConfiguredSerialReadStream(portPath, baudRate, options = {}) {
    const fsModule = options.fs || fs;
    if (typeof fsModule.openSync !== "function") {
        if (!configureSerialPort(portPath, baudRate, options)) {
            throw new Error(`Failed to configure serial port ${portPath}`);
        }
        return fsModule.createReadStream(portPath, { encoding: "utf8" });
    }

    let fd = null;
    try {
        fd = fsModule.openSync(portPath, "r");
        if (!configureSerialPort(portPath, baudRate, options)) {
            throw new Error(`Failed to configure serial port ${portPath}`);
        }
        const stream = fsModule.createReadStream(null, {
            fd,
            autoClose: true,
            encoding: "utf8"
        });
        fd = null;
        return stream;
    } catch (e) {
        if (fd !== null && typeof fsModule.closeSync === "function") {
            try {
                fsModule.closeSync(fd);
            } catch (closeError) {
                // Preserve the original open/configure error.
            }
        }
        throw e;
    }
}

function createGokit5SerialListener(options = {}) {
    const fsModule = options.fs || fs;
    const baudRate = options.baudRate || DEFAULT_BAUD_RATE;
    const reconnectMs = options.reconnectMs || DEFAULT_RECONNECT_MS;
    const debounceMs = options.debounceMs || DEFAULT_DEBOUNCE_MS;
    const onButton = typeof options.onButton === "function" ? options.onButton : () => {};
    const onAction = typeof options.onAction === "function" ? options.onAction : () => {};
    const onStatus = typeof options.onStatus === "function" ? options.onStatus : () => {};
    const findPort = options.findPort || (() => findGokit5SerialPort(options));
    const createReadStream = options.createReadStream
        || ((portPath) => createConfiguredSerialReadStream(portPath, baudRate, options));

    let stream = null;
    let reconnectTimer = null;
    let running = false;
    let lineBuffer = "";
    let currentPort = "";
    const lastDispatchByButton = new Map();

    function notifyStatus(status) {
        try {
            onStatus(status);
        } catch (e) {
            // Status callbacks are best-effort and must not terminate the listener.
        }
    }

    function clearReconnectTimer() {
        if (reconnectTimer) {
            clearTimeout(reconnectTimer);
            reconnectTimer = null;
        }
    }

    function scheduleReconnect() {
        if (!running || reconnectTimer) return;
        reconnectTimer = setTimeout(() => {
            reconnectTimer = null;
            connect();
        }, reconnectMs);
    }

    function closeStream() {
        if (!stream) return;
        const previous = stream;
        stream = null;
        previous.removeAllListeners("data");
        previous.removeAllListeners("error");
        previous.removeAllListeners("close");
        if (typeof previous.destroy === "function") {
            previous.destroy();
        }
    }

    function handleLine(line) {
        const button = parseGokit5ButtonLine(line);
        if (!button) return;
        if (!shouldDispatchButton(button, Date.now(), lastDispatchByButton, debounceMs)) {
            return;
        }
        const action = mapGokit5ButtonToAction(button);
        try {
            onButton(button, action, line);
        } catch (e) {
            // Listener callback failures must not crash the process.
        }
        try {
            onAction(action, { button, line, portPath: currentPort });
        } catch (e) {
            // Listener callback failures must not crash the process.
        }
    }

    function handleChunk(chunk) {
        lineBuffer += String(chunk || "");
        let newlineIndex = lineBuffer.search(/\r?\n/);
        while (newlineIndex !== -1) {
            const line = lineBuffer.slice(0, newlineIndex).trim();
            lineBuffer = lineBuffer.slice(lineBuffer[newlineIndex] === "\r" && lineBuffer[newlineIndex + 1] === "\n"
                ? newlineIndex + 2
                : newlineIndex + 1);
            if (line) handleLine(line);
            newlineIndex = lineBuffer.search(/\r?\n/);
        }
    }

    function connect() {
        if (!running || stream) return;
        let portPath = "";
        try {
            portPath = findPort();
        } catch (e) {
            notifyStatus({ status: "find_port_failed", error: e.message || String(e) });
            scheduleReconnect();
            return;
        }
        if (!portPath) {
            notifyStatus({ status: "not_found" });
            scheduleReconnect();
            return;
        }

        currentPort = portPath;
        lineBuffer = "";
        try {
            stream = createReadStream(portPath);
        } catch (e) {
            notifyStatus({ status: "open_failed", portPath, error: e.message || String(e) });
            scheduleReconnect();
            return;
        }

        notifyStatus({ status: "connected", portPath });
        stream.on("data", handleChunk);
        stream.on("error", err => {
            notifyStatus({ status: "error", portPath, error: err.message || String(err) });
            closeStream();
            scheduleReconnect();
        });
        stream.on("close", () => {
            notifyStatus({ status: "closed", portPath });
            closeStream();
            scheduleReconnect();
        });
    }

    return {
        start() {
            if (running) return;
            running = true;
            connect();
        },
        stop() {
            running = false;
            clearReconnectTimer();
            closeStream();
        },
        isRunning() {
            return running;
        },
        getPortPath() {
            return currentPort;
        }
    };
}

module.exports = {
    BUTTON_TO_APP_ACTION,
    BUTTON_TO_INPUT_PHRASE,
    DEFAULT_SERIAL_NUMBER,
    HOST_BUTTON_PREFIX,
    normalizeGokit5ButtonName,
    mapGokit5ButtonToAction,
    mapGokit5ButtonToInputPhrase,
    parseGokit5ButtonLine,
    shouldDispatchButton,
    extractGokit5PortPathsFromIoregText,
    listUsbModemPorts,
    findGokit5SerialPort,
    configureSerialPort,
    createConfiguredSerialReadStream,
    createGokit5SerialListener
};
