const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const { EventEmitter } = require("node:events");
const source = fs.readFileSync(require.resolve("../bin/dock-switch-cli.js"), "utf8");

function load() {
    const sockets = [];
    const net = { createConnection() {
        const socket = new EventEmitter();
        socket.write = payload => { socket.payload = payload; };
        socket.end = () => {};
        socket.setEncoding = () => {};
        sockets.push(socket);
        return socket;
    } };
    const context = { require: name => name === "net" ? net : require(name), console,
        process: { exit: () => { throw new Error("usage"); } }, URL, setTimeout };
    vm.runInNewContext(source.slice(0, source.lastIndexOf("main().catch")) +
        "\nthis.api = {parseArgs, connectAndSend};", context);
    return { api: context.api, sockets };
}

test("quiet tools require an absolute app path and exact PID/window identity", () => {
    const { api } = load();
    const open = api.parseArgs(["tool-open", "--app-path", "/Applications/Tool.app", "--url", "file:///tmp/tool.txt"]);
    assert.equal(open.appPath, "/Applications/Tool.app");
    assert.equal(open.format, "json");
    assert.throws(() => api.parseArgs(["tool-open", "--app-path", "Tool.app"]), /usage/);
    assert.throws(() => api.parseArgs(["tool-open", "--app-path", "/Applications/Tool.app", "--url", "javascript:bad"]), /usage/);
    assert.throws(() => api.parseArgs(["tool-place", "--pid", "123"]), /usage/);
    const place = api.parseArgs(["tool-place", "--pid", "123", "--window-id", "42"]);
    assert.equal(place.windowID, 42);
});

test("lost response after send is explicitly unknown and cannot trigger auto-replay", async () => {
    const { api, sockets } = load();
    const pending = api.connectAndSend({ command: "tool-open", appPath: "/Applications/Tool.app" });
    sockets[0].emit("connect");
    sockets[0].emit("end");
    await assert.rejects(pending, err => err.requestMayHaveRun === true);
    assert.equal(sockets.length, 1);
    const unsent = api.connectAndSend({ command: "tool-status" });
    sockets[1].emit("error", new Error("not connected"));
    await assert.rejects(unsent, err => err.requestMayHaveRun === false);
});
