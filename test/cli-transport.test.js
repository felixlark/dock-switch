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

test("lost response after send is explicitly unknown and cannot trigger auto-replay", async () => {
    const { api, sockets } = load();
    const pending = api.connectAndSend({ command: "place-pid", pid: 123, placement: "external_fill" });
    sockets[0].emit("connect");
    sockets[0].emit("end");
    await assert.rejects(pending, err => err.requestMayHaveRun === true);
    assert.equal(sockets.length, 1);
    const unsent = api.connectAndSend({ command: "debug-displays" });
    sockets[1].emit("error", new Error("not connected"));
    await assert.rejects(unsent, err => err.requestMayHaveRun === false);
});
