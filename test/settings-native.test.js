const { test } = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

test('native SettingsStore preserves keyless placement across save and reload', () => {
    if (process.platform !== 'darwin') return;
    const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'dock-switch-settings-test-'));
    try {
        const binary = path.join(scratch, 'settings-checks');
        execFileSync('swiftc', ['-module-cache-path', path.join(os.homedir(), 'Library/Caches/dock-switch/settings-modules'),
            '-parse-as-library', 'native/settings-app/Sources/Models.swift', 'native/settings-app/Sources/SettingsStore.swift',
            'native/dock-switch-app/Sources/DockSwitchCore/CustomPhraseShortcut.swift',
            'native/settings-app/Tests/SettingsStoreChecks.swift', '-o', binary], { stdio: 'pipe' });
        assert.match(execFileSync(binary, { encoding: 'utf8' }), /passed/);
    } finally { fs.rmSync(scratch, { recursive: true, force: true }); }
});
