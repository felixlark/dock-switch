const test = require("node:test");
const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");

const {
    createGokit5SerialListener,
    createConfiguredSerialReadStream,
    extractGokit5PortPathsFromIoregText,
    findGokit5SerialPort,
    mapGokit5ButtonToAction,
    mapGokit5ButtonToInputPhrase,
    parseGokit5ButtonLine,
    shouldDispatchButton
} = require("../src/gokit5-serial");

test("parseGokit5ButtonLine extracts stable host button events from ESP logs", () => {
    assert.equal(parseGokit5ButtonLine("GOKIT5_HOST_BUTTON:minus"), "minus");
    assert.equal(parseGokit5ButtonLine("I (123) Gokit5: GOKIT5_HOST_BUTTON:voice"), "voice");
    assert.equal(parseGokit5ButtonLine("GOKIT5_HOST_BUTTON:plus extra"), "plus");
    assert.equal(parseGokit5ButtonLine("GOKIT5_HOST_BUTTON:green"), "green");
    assert.equal(parseGokit5ButtonLine("GOKIT5_HOST_BUTTON:switch"), "switch");
    assert.equal(parseGokit5ButtonLine("I (123) VolcRTCApp: Heap Info"), "");
});

test("mapGokit5ButtonToInputPhrase maps Command-modified buttons to text only", () => {
    assert.equal(mapGokit5ButtonToInputPhrase("voice"), "/goal");
    assert.equal(mapGokit5ButtonToInputPhrase("plus"), "/plan");
    assert.equal(mapGokit5ButtonToInputPhrase("green"), "side chat");
    assert.equal(mapGokit5ButtonToInputPhrase("switch"), "side chat");
    assert.equal(mapGokit5ButtonToInputPhrase("minus"), "continue");
    assert.equal(mapGokit5ButtonToInputPhrase("unknown"), "");
});

test("parseGokit5ButtonLine rejects removed plus aliases", () => {
    assert.equal(parseGokit5ButtonLine("GOKIT5_HOST_BUTTON:+"), "");
    assert.equal(parseGokit5ButtonLine("GOKIT5_HOST_BUTTON:add"), "");
    assert.equal(parseGokit5ButtonLine("GOKIT5_HOST_BUTTON:volume_up"), "");
    assert.equal(parseGokit5ButtonLine("GOKIT5_HOST_BUTTON:volume+"), "");
});

test("mapGokit5ButtonToAction maps physical keys to mouse display actions", () => {
    assert.deepEqual(mapGokit5ButtonToAction("minus"), {
        mouse_target: "side_left"
    });
    assert.deepEqual(mapGokit5ButtonToAction("voice"), {
        mouse_target: "external"
    });
    assert.deepEqual(mapGokit5ButtonToAction("switch"), {
        mouse_target: "side_right"
    });
    assert.deepEqual(mapGokit5ButtonToAction("green"), {
        mouse_target: "side_right"
    });
    assert.deepEqual(mapGokit5ButtonToAction("plus"), {
        mouse_target: "internal"
    });
    assert.equal(mapGokit5ButtonToAction("+"), null);
    assert.equal(mapGokit5ButtonToAction("add"), null);
    assert.equal(mapGokit5ButtonToAction("volume_up"), null);
    assert.equal(mapGokit5ButtonToAction("volume-up"), null);
    assert.equal(mapGokit5ButtonToAction("volume+"), null);
});

test("shouldDispatchButton debounces repeated events per button", () => {
    const last = new Map();
    assert.equal(shouldDispatchButton("minus", 1000, last, 250), true);
    assert.equal(shouldDispatchButton("minus", 1100, last, 250), false);
    assert.equal(shouldDispatchButton("voice", 1100, last, 250), true);
    assert.equal(shouldDispatchButton("minus", 1300, last, 250), true);
});

test("extractGokit5PortPathsFromIoregText finds the Espressif USB serial suffix", () => {
    const sample = `
    +-o USB JTAG/serial debug unit@00131000  <class IOUSBHostDevice>
      |   "idProduct" = 4097
      |   "USB Product Name" = "USB JTAG_serial debug unit"
      |   "kUSBSerialNumberString" = "94:A9:90:10:E5:F4"
      |   "USB Vendor Name" = "Espressif"
      |   "idVendor" = 12346
      +-o AppleUSBACMData
        |   "IOTTYSuffix" = "13101"
    `;

    assert.deepEqual(extractGokit5PortPathsFromIoregText(sample), [
        "/dev/cu.usbmodem13101"
    ]);
});

test("findGokit5SerialPort prefers env override and then detected Espressif ports", () => {
    const fsModule = {
        existsSync(path) {
            return path === "/dev/cu.override" || path === "/dev/cu.usbmodem13101";
        },
        readdirSync() {
            return ["cu.usbmodem99999"];
        }
    };

    assert.equal(findGokit5SerialPort({
        fs: fsModule,
        env: { GOKIT5_SERIAL_PORT: "/dev/cu.override" }
    }), "/dev/cu.override");

    const ioregText = `
    +-o USB JTAG/serial debug unit@00131000  <class IOUSBHostDevice>
      |   "idProduct" = 4097
      |   "USB Product Name" = "USB JTAG_serial debug unit"
      |   "USB Serial Number" = "94:A9:90:10:E5:F4"
      |   "USB Vendor Name" = "Espressif"
      |   "idVendor" = 12346
      +-o AppleUSBACMData
        |   "IOTTYSuffix" = "13101"
    `;

    assert.equal(findGokit5SerialPort({
        fs: fsModule,
        env: {},
        runCommand: () => ({ status: 0, stdout: ioregText })
    }), "/dev/cu.usbmodem13101");
});

test("createGokit5SerialListener keeps the serial fd open while applying stty", () => {
    const events = [];
    const stream = new EventEmitter();
    stream.destroy = () => {
        events.push("destroy");
    };

    const fsModule = {
        openSync(path, flags) {
            events.push(["open", path, flags]);
            return 53;
        },
        closeSync(fd) {
            events.push(["close", fd]);
        },
        createReadStream(path, options) {
            events.push(["read", path, options.fd, options.autoClose, options.encoding]);
            return stream;
        }
    };

    const listener = createGokit5SerialListener({
        fs: fsModule,
        findPort: () => "/dev/cu.usbmodem13101",
        runCommand(command, args) {
            events.push(["stty", command, args]);
            return { status: 0 };
        }
    });

    listener.start();

    assert.deepEqual(events.slice(0, 3), [
        ["open", "/dev/cu.usbmodem13101", "r"],
        ["stty", "stty", [
            "-f",
            "/dev/cu.usbmodem13101",
            "115200",
            "raw",
            "-echo",
            "-icanon",
            "min",
            "1",
            "time",
            "0",
            "clocal",
            "-hupcl"
        ]],
        ["read", null, 53, true, "utf8"]
    ]);

    listener.stop();
    assert.equal(events.at(-1), "destroy");
});

test("createGokit5SerialListener dispatches plus to the internal mouse display action", () => {
    const stream = new EventEmitter();
    stream.destroy = () => {};
    const actions = [];

    const listener = createGokit5SerialListener({
        debounceMs: 0,
        findPort: () => "/dev/cu.usbmodem13101",
        createReadStream: () => stream,
        onAction: (action, event) => {
            actions.push({ action, button: event.button, line: event.line });
        }
    });

    listener.start();
    stream.emit("data", "I (123) Gokit5: GOKIT5_HOST_BUTTON:plus\n");

    assert.equal(actions.length, 1);
    assert.deepEqual(actions[0].action, mapGokit5ButtonToAction("plus"));
    assert.equal(actions[0].button, "plus");
    assert.match(actions[0].line, /plus/);

    listener.stop();
});

test("createGokit5SerialListener survives exceptions thrown by button callbacks", () => {
    const stream = new EventEmitter();
    stream.destroy = () => {};
    const seen = [];

    const listener = createGokit5SerialListener({
        debounceMs: 0,
        findPort: () => "/dev/cu.usbmodem13101",
        createReadStream: () => stream,
        onButton: () => {
            throw new Error("onButton exploded");
        },
        onAction: action => {
            seen.push(action);
            throw new Error("onAction exploded");
        }
    });

    listener.start();
    stream.emit("data", "GOKIT5_HOST_BUTTON:plus\n");
    // A throwing onButton must not stop onAction from running...
    assert.equal(seen.length, 1);
    // ...and a second event must still be dispatched.
    stream.emit("data", "GOKIT5_HOST_BUTTON:minus\n");
    assert.equal(seen.length, 2);
    assert.equal(listener.isRunning(), true);

    listener.stop();
});

test("createGokit5SerialListener survives exceptions thrown by status callbacks", () => {
    const stream = new EventEmitter();
    stream.destroy = () => {};
    const statuses = [];

    const listener = createGokit5SerialListener({
        debounceMs: 0,
        reconnectMs: 60_000,
        findPort: () => "/dev/cu.usbmodem13101",
        createReadStream: () => stream,
        onStatus: status => {
            statuses.push(status.status);
            throw new Error("onStatus exploded");
        }
    });

    listener.start();
    assert.deepEqual(statuses, ["connected"]);

    stream.emit("error", new Error("serial went away"));
    assert.deepEqual(statuses, ["connected", "error"]);
    assert.equal(listener.isRunning(), true);

    listener.stop();
});

test("createGokit5SerialListener reports and retries when findPort throws", () => {
    const statuses = [];
    const listener = createGokit5SerialListener({
        reconnectMs: 60_000,
        findPort: () => {
            throw new Error("ioreg unavailable");
        },
        createReadStream: () => {
            throw new Error("must not be reached");
        },
        onStatus: status => statuses.push(status)
    });

    listener.start();

    assert.equal(statuses.length, 1);
    assert.equal(statuses[0].status, "find_port_failed");
    assert.match(statuses[0].error, /ioreg unavailable/);
    assert.equal(listener.isRunning(), true);

    listener.stop();
});

test("createConfiguredSerialReadStream closes the held fd when stty fails", () => {
    const events = [];
    const fsModule = {
        openSync(path, flags) {
            events.push(["open", path, flags]);
            return 53;
        },
        closeSync(fd) {
            events.push(["close", fd]);
        },
        createReadStream() {
            events.push(["read"]);
            throw new Error("read stream should not be created");
        }
    };

    assert.throws(() => createConfiguredSerialReadStream("/dev/cu.usbmodem13101", 115200, {
        fs: fsModule,
        runCommand(command, args) {
            events.push(["stty", command, args]);
            return { status: 1 };
        }
    }), /Failed to configure serial port/);

    assert.deepEqual(events.map(event => event[0]), ["open", "stty", "close"]);
});
