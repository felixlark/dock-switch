#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawnSync, spawn } = require("node:child_process");

const root = path.resolve(__dirname, "..");
function fail(message) { console.error(message); process.exit(1); }
const args = process.argv.slice(2);
if (args.length !== 4 || args[0] !== "--output" || args[2] !== "--duration") {
    fail("usage: node scripts/record-shortcut-verification.js --output <new .ndjson path> --duration <1..300 seconds>");
}
const output = path.resolve(args[1]);
const duration = Number(args[3]);
if (!Number.isFinite(duration) || duration < 1 || duration > 300) fail("duration must be between 1 and 300 seconds");
if (process.platform !== "darwin") fail("requires macOS");
fs.mkdirSync(path.dirname(output), { recursive: true });
let fd;
try { fd = fs.openSync(output, "wx", 0o600); } catch (error) { fail(error.message); }
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "dock-switch-observer-"));
const cache = path.join(os.homedir(), "Library/Caches/dock-switch/verification-modules");
fs.mkdirSync(cache, { recursive: true });
const binary = path.join(scratch, "observe");
function write(record) { fs.writeSync(fd, JSON.stringify(record) + "\n"); }
function readCommand(command, argv) {
    const result = spawnSync(command, argv, { cwd: root, encoding: "utf8" });
    return { status: result.status, stdout: (result.stdout || "").trim(), stderr: (result.stderr || "").trim() };
}
function digest(file) {
    try { return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex"); }
    catch { return null; }
}
write({ event: "metadata", timestamp: new Date().toISOString(), durationSeconds: duration,
    candidate: readCommand("git", ["rev-parse", "HEAD"]).stdout,
    dirty: readCommand("git", ["status", "--short"]).stdout,
    installedExecutableSHA256: digest("/Applications/dock-switch.app/Contents/MacOS/DockSwitch"),
    observerSHA256: digest(path.join(__dirname, "shortcut-state-observer.swift")),
    recorderSHA256: digest(__filename),
    karabinerConfigSHA256: digest(path.join(os.homedir(), ".config/karabiner/karabiner.json")),
    karabinerCheck: readCommand(process.execPath, ["scripts/configure-karabiner-f20-shortcuts.js", "--check"]),
    scope: "read-only input-source and installed HUD state; no physical-key provenance, typed text or window titles",
    physicalKeyboardAcceptance: "not established by this recorder alone" });
const build = spawnSync("swiftc", ["-module-cache-path", cache, path.join(__dirname, "shortcut-state-observer.swift"), "-o", binary], { encoding: "utf8" });
if (build.status !== 0) {
    write({ event: "error", stage: "compile", diagnostic: build.stderr || build.error?.message });
    fs.closeSync(fd);
    fs.rmSync(scratch, { recursive: true, force: true });
    fail("observer compile failed; see output");
}
console.log(`READY: recording state changes for ${duration}s to ${output}`);
const child = spawn(binary, [String(duration)], { stdio: ["ignore", fd, "pipe"] });
let errorOutput = "";
child.stderr.on("data", data => { errorOutput += data; });
child.on("error", error => { errorOutput += error.message; });
for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => child.kill(signal));
child.on("close", (code, signal) => {
    write({ event: "recorder_exit", code, signal, ...(errorOutput ? { diagnostic: errorOutput } : {}) });
    fs.closeSync(fd);
    fs.rmSync(scratch, { recursive: true, force: true });
    process.exitCode = code === 0 ? 0 : 1;
});
