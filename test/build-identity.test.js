const { test } = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

test('identity generation pairs all metadata and keeps an opaque configuration snapshot', () => {
    const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'dock-identity-'));
    try {
        const config = path.join(scratch, 'config.json');
        fs.writeFileSync(config, '{"synthetic":"configuration"}\n');
        const profile = path.join(scratch, 'profile.json');
        const value = { schemaVersion: 1, bundleId: 'org.example.launcher',
            settingsBundleId: 'org.example.preferences', dataNamespace: 'org.example.launcher',
            signingIdentity: 'A'.repeat(40) };
        fs.writeFileSync(profile, JSON.stringify(value));
        const output = path.join(scratch, 'identity');
        const run = () => spawnSync('python3', ['scripts/build-identity.py', 'generate',
            '--identity-profile', profile, '--directory', output, '--config', config], { encoding: 'utf8' });
        assert.equal(run().status, 0);
        const metadata = JSON.parse(fs.readFileSync(path.join(output, 'manifest.json')));
        assert.deepEqual(metadata.identity, value);
        assert.equal(path.isAbsolute(metadata.mainInfo), true);
        assert.equal(fs.readFileSync(metadata.mainInfo, 'utf8'), fs.readFileSync(path.join(output, 'main.plist'), 'utf8'));
        assert.equal(fs.readFileSync(path.join(output, 'config.json'), 'utf8'), fs.readFileSync(config, 'utf8'));
        const readPlist = (file) => JSON.parse(spawnSync('python3', ['-c',
            'import plistlib,json,sys; print(json.dumps(plistlib.load(open(sys.argv[1],"rb"))))',
            path.join(output, file)], { encoding: 'utf8' }).stdout);
        assert.equal(readPlist('main.plist').CFBundleIdentifier, value.bundleId);
        assert.equal(readPlist('settings.plist').CFBundleIdentifier, value.settingsBundleId);
        assert.equal(readPlist('main.plist').DockSwitchDataNamespace, value.bundleId);
        assert.equal(readPlist('settings.plist').DockSwitchDataNamespace, value.bundleId);
        const originalMainInfo = metadata.mainInfo;
        value.bundleId = value.dataNamespace = 'org.example.second-launcher';
        fs.writeFileSync(profile, JSON.stringify(value));
        assert.equal(run().status, 0);
        assert.notEqual(JSON.parse(fs.readFileSync(path.join(output, 'manifest.json'))).mainInfo, originalMainInfo);
        const publicResult = spawnSync('python3', ['scripts/build-identity.py', 'generate',
            '--directory', output, '--config', config], { encoding: 'utf8', env: { ...process.env, DOCK_SWITCH_IDENTITY_PROFILE: '', CSC_NAME: '-' } });
        assert.equal(publicResult.status, 0, publicResult.stderr);
        assert.equal(readPlist('main.plist').CFBundleIdentifier, 'io.github.felixlark.dock-switch');
        assert.equal(readPlist('settings.plist').DockSwitchDataNamespace, 'io.github.felixlark.dock-switch');
        value.dataNamespace = 'org.example.wrong-domain';
        fs.writeFileSync(profile, JSON.stringify(value));
        assert.notEqual(run().status, 0);
        assert.match(run().stderr, /dataNamespace must equal/);
        delete value.dataNamespace;
        fs.writeFileSync(profile, JSON.stringify(value));
        assert.notEqual(run().status, 0);
    } finally { fs.rmSync(scratch, { recursive: true, force: true }); }
});

test('config drift at any installation checkpoint refuses stale replacement', () => {
    const code = `
import importlib.util,tempfile,json,sys
sys.dont_write_bytecode=True
from pathlib import Path
spec=importlib.util.spec_from_file_location('identity','scripts/build-identity.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as temp:
 app=Path(temp); config=app/m.CONFIG;config.parent.mkdir(parents=True)
 config.write_bytes(b'synthetic original');manifest={'configDigest':m.digest(config)}
 m.check_live_config(app,manifest)
 config.write_bytes(b'synthetic edit during build or exit')
 try:m.check_live_config(app,manifest)
 except ValueError:pass
 else:raise AssertionError('configuration edit was accepted')
`;
    const result = spawnSync('python3', ['-c', code], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
});


test('same designated requirement cannot hide a different signing certificate', () => {
    const code = `
import importlib.util,tempfile,plistlib,sys
from pathlib import Path
sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location('identity','scripts/build-identity.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as temp:
 old=Path(temp)/'old.app'; new=Path(temp)/'new.app'
 value={'bundleId':'org.example.launcher','settingsBundleId':'org.example.preferences',
        'dataNamespace':'org.example.launcher','signingIdentity':'A'*40}
 for app in (old,new):
  for suffix,key in ((Path('.'),'bundleId'),(m.SETTINGS,'settingsBundleId')):
   info=app/suffix/'Contents/Info.plist';info.parent.mkdir(parents=True)
   info.write_bytes(plistlib.dumps({'CFBundleIdentifier':value[key]}))
 m.requirement=lambda app:'same designated requirement'
 m.certificate_selector=lambda app:'A'*40
 m.check_compatibility(new,old,value)
 m.certificate_selector=lambda app:'B'*40 if Path(app).is_relative_to(new) else 'A'*40
 try:m.check_compatibility(new,old,value)
 except ValueError as error:assert 'certificate differs' in str(error)
 else:raise AssertionError('different certificate was accepted')
 m.certificate_selector=lambda app:'A'*40
 value['signingIdentity']='C'*40
 try:m.check_compatibility(new,old,value)
 except ValueError as error:assert 'profile selector' in str(error)
 else:raise AssertionError('different profile selector was accepted')
`;
    const result = spawnSync('python3', ['-c', code], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
});
