#!/usr/bin/env node
// Read-only runtime diagnostics; never launch or control Codex.
const net = require('node:net');
const path = require('node:path');
const os = require('node:os');
const socket = net.createConnection(path.join(os.homedir(), 'Library', 'Application Support', 'dock-switch', 'control.sock'));
let response = '';
socket.setEncoding('utf8');
socket.on('connect', () => socket.write(JSON.stringify({ command: 'codex-workspace-status' }) + '\n'));
socket.on('data', chunk => { response += chunk; });
socket.on('end', () => {
    try {
        const result = JSON.parse(response);
        console.log(JSON.stringify(result, null, 2));
        if (!result.ok) process.exitCode = 1;
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
});
socket.on('error', error => { console.error(error.message); process.exitCode = 1; });
