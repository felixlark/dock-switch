#!/usr/bin/env python3
"""Non-secret build identity and sealed-package checks. Never sources a profile."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PUBLIC_ID = 'io.github.felixlark.dock-switch'
CONFIG = Path('Contents/Resources/app/src/config.json')
SETTINGS = Path('Contents/Resources/DockSwitchSettings.app')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def identity(profile=None):
    if not profile:
        return dict(schemaVersion=1, bundleId=PUBLIC_ID, settingsBundleId=PUBLIC_ID+'.settings',
                    dataNamespace=PUBLIC_ID, signingIdentity=os.environ.get('CSC_NAME', '-'))
    path = Path(profile)
    require(path.is_absolute(), 'identity profile must be an absolute path')
    value = json.loads(path.read_text())
    require(isinstance(value, dict) and type(value.get('schemaVersion')) is int and value['schemaVersion'] == 1,
            'identity profile requires schemaVersion 1')
    for key in ('bundleId', 'settingsBundleId', 'dataNamespace', 'signingIdentity'):
        require(isinstance(value.get(key), str) and bool(value[key].strip()), 'identity profile requires '+key)
    require(value['dataNamespace'] == value['bundleId'], 'dataNamespace must equal main bundleId')
    require(value['settingsBundleId'] != value['bundleId'], 'Settings must have a distinct bundleId')
    require(re.fullmatch(r'[A-Fa-f0-9]{40}', value['signingIdentity']) is not None,
            'profile signingIdentity must be a certificate SHA-1 selector')
    return {key: value[key] for key in ('schemaVersion', 'bundleId', 'settingsBundleId', 'dataNamespace', 'signingIdentity')}


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2)+'\n')
    path.chmod(0o600)


def source_digest():
    paths = [ROOT/'native/dock-switch-app/Package.swift', ROOT/'native/dock-switch-app/AppInfo.plist',
        ROOT/'native/settings-app/AppInfo.plist']
    for folder in ('native/dock-switch-app/Sources', 'native/settings-app/Sources'):
        paths += sorted((ROOT/folder).rglob('*.swift'))
    paths += [ROOT/'scripts'/name for name in ('build-identity.py', 'build-native-app.sh', 'build-settings-app.sh')]
    result = hashlib.sha256()
    for path in paths:
        result.update(str(path.relative_to(ROOT)).encode()+b'\0'+path.read_bytes())
    return result.hexdigest()


def generate(directory, profile, config):
    directory = directory.resolve()
    value = identity(profile)
    directory.mkdir(parents=True, exist_ok=True)
    directory.chmod(0o700)
    source = Path(config).resolve()
    before = digest(source)
    # This is an opaque snapshot, never parsed or printed.
    snapshot = directory/'config.json'
    snapshot.write_bytes(source.read_bytes())
    snapshot.chmod(0o600)
    require(before == digest(source) == digest(snapshot), 'configuration changed while snapshotting; check its writer')
    for template, output, bundle_id in [
        ('native/dock-switch-app/AppInfo.plist', 'main.plist', value['bundleId']),
        ('native/settings-app/AppInfo.plist', 'settings.plist', value['settingsBundleId'])]:
        info = plistlib.loads((ROOT/template).read_bytes())
        info['CFBundleIdentifier'] = bundle_id
        info['DockSwitchDataNamespace'] = value['dataNamespace']
        data = plistlib.dumps(info, sort_keys=False)
        (directory/output).write_bytes(data)
        if output == 'main.plist':
            # SwiftPM tracks linker flags, not the contents of -sectcreate files.
            # A content-addressed input forces relinking when identity changes.
            main_info = directory/('main-'+hashlib.sha256(data).hexdigest()+'.plist')
            main_info.write_bytes(data)
    save_json(directory/'manifest.json', {'identity': value, 'configDigest': before,
        'configSource': str(source), 'profileDigest': digest(profile) if profile else None,
        'mainInfo': str(main_info), 'sourceDigest': source_digest(),
        'sourceRevision': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD']).decode().strip()})


def embedded_info(binary):
    """Read the actual arm64 Mach-O section, without executing the candidate."""
    data = Path(binary).read_bytes()
    require(data[:4] == b'\xcf\xfa\xed\xfe', 'expected a 64-bit little-endian Mach-O')
    offset = 32
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, size = struct.unpack_from('<II', data, offset)
        if command == 0x19:  # LC_SEGMENT_64
            for index in range(struct.unpack_from('<I', data, offset+64)[0]):
                section = offset+72+index*80
                if data[section:section+16].split(b'\0')[0] == b'__info_plist':
                    length, start = struct.unpack_from('<QI', data, section+40)
                    return plistlib.loads(data[start:start+length].rstrip(b'\0'))
        offset += size
    raise ValueError('main executable has no embedded Info.plist')


def bundle_info(app):
    return plistlib.loads((Path(app)/'Contents/Info.plist').read_bytes())


def check_metadata(app, value):
    app = Path(app)
    main = bundle_info(app)
    settings = bundle_info(app/SETTINGS)
    embedded = embedded_info(app/'Contents/MacOS/DockSwitch')
    for info, key in ((main, 'bundleId'), (embedded, 'bundleId'), (settings, 'settingsBundleId')):
        require(info.get('CFBundleIdentifier') == value[key], 'packaged bundle identifier mismatch')
        require(info.get('DockSwitchDataNamespace') == value['dataNamespace'], 'packaged data namespace mismatch')
    require(main['CFBundleIdentifier'] == main['DockSwitchDataNamespace'], 'main standard domain mismatch')


def run_checked(arguments, message):
    # codesign errors can include private certificate subjects and identifiers.
    result = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    require(result.returncode == 0, message+' (exit '+str(result.returncode)+')')
    return result


def sign_settings(app, value):
    selector = value['signingIdentity']
    timestamp = '--timestamp=none' if selector == '-' else '--timestamp'
    run_checked(['/usr/bin/xattr', '-cr', str(app)], 'xattr cleanup failed')
    run_checked(['/usr/bin/codesign', '--force', '--options', 'runtime', timestamp,
        '--sign', selector, str(app)], 'Settings code signing failed')
    verify_seal(app)


def sign(app, value):
    app = Path(app)
    selector = value['signingIdentity']
    timestamp = '--timestamp=none' if selector == '-' else '--timestamp'
    run_checked(['/usr/bin/xattr', '-cr', str(app)], 'xattr cleanup failed')
    for target, entitlements in [(app/SETTINGS, False),
            (app/'Contents/Resources/DockSwitchGokit5Serial', False), (app, True)]:
        args = ['/usr/bin/codesign', '--force', '--options', 'runtime', timestamp, '--sign', selector]
        if entitlements:
            args += ['--entitlements', str(ROOT/'resources/entitlements.mac.plist')]
        run_checked(args+[str(target)], 'code signing failed')
    verify_seal(app)


def verify_seal(app):
    run_checked(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], 'signature seal verification failed')


def requirement(app):
    result = run_checked(['/usr/bin/codesign', '-d', '-r-', str(app)], 'cannot read designated requirement')
    text = (result.stdout+result.stderr).decode()
    return next(line for line in text.splitlines() if line.startswith('designated =>'))


def certificate_selector(app):
    # Only the public leaf certificate is read; subjects and identifiers stay local.
    with tempfile.TemporaryDirectory(prefix='dock-certificate-') as directory:
        prefix = Path(directory)/'certificate'
        run_checked(['/usr/bin/codesign', '-d', '--extract-certificates='+str(prefix), str(app)],
            'cannot inspect signing certificate')
        leaf = Path(str(prefix)+'0')
        return hashlib.sha1(leaf.read_bytes()).hexdigest().upper() if leaf.exists() else None


def check_compatibility(candidate, installed, value):
    installed = Path(installed)
    if not installed.exists():
        return
    for target, key in ((Path('.'), 'bundleId'), (SETTINGS, 'settingsBundleId')):
        previous = bundle_info(installed/target)
        require(previous['CFBundleIdentifier'] == value[key],
                'installed identity differs; select its explicit local compatibility profile before stopping the app')
        # Old installs predate the namespace field; their main bundle ID is the data domain.
        domain = previous.get('DockSwitchDataNamespace', bundle_info(installed)['CFBundleIdentifier'])
        require(domain == value['dataNamespace'], 'installed preference namespace differs')
        previous_certificate = certificate_selector(installed/target)
        candidate_certificate = certificate_selector(Path(candidate)/target)
        require(previous_certificate == candidate_certificate, 'signing certificate differs from current installation')
        if re.fullmatch(r'[A-Fa-f0-9]{40}', value['signingIdentity']):
            require(candidate_certificate == value['signingIdentity'].upper(), 'signing certificate differs from profile selector')
        require(requirement(Path(candidate)/target) == requirement(installed/target),
                'designated requirement differs from current installation')


def check_manifest(app, directory, profile):
    manifest = json.loads((directory/'manifest.json').read_text())
    require(manifest['sourceDigest'] == source_digest(), 'candidate source differs; rebuild before installing')
    require(manifest['identity'] == identity(profile), 'candidate identity does not match selected profile')
    require(manifest['profileDigest'] == (digest(profile) if profile else None), 'identity profile changed during build')
    check_metadata(app, manifest['identity'])
    require(digest(Path(app)/CONFIG) == manifest['configDigest'], 'candidate config differs from snapshot')
    return manifest


def check_live_config(installed, manifest):
    path = Path(installed)/CONFIG
    if Path(installed).exists():
        require(path.is_file(), 'installed configuration is missing; installation stopped')
        require(digest(path) == manifest['configDigest'], 'installed configuration changed; keep the old app and rebuild from a fresh snapshot')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['generate', 'sign', 'sign-settings', 'verify'])
    parser.add_argument('--identity-profile', default=os.environ.get('DOCK_SWITCH_IDENTITY_PROFILE'))
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--config', default=os.environ.get('DOCK_SWITCH_CONFIG_SOURCE', str(ROOT/'src/config.json')))
    parser.add_argument('--app', type=Path)
    args = parser.parse_args()
    if args.action == 'generate':
        generate(args.directory, args.identity_profile, args.config)
    elif args.action == 'sign-settings':
        sign_settings(args.app, identity(args.identity_profile))
    elif args.action == 'sign':
        sign(args.app, identity(args.identity_profile))
    else:
        check_manifest(args.app, args.directory, args.identity_profile)
        verify_seal(args.app)
    print('identity '+args.action+' passed')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, StopIteration) as error:
        # Do not echo profile values or opaque config data on failure.
        if isinstance(error, ValueError) and not isinstance(error, (json.JSONDecodeError,)):
            print('error: '+str(error), file=sys.stderr)
        else:
            print('error: identity input or package could not be read', file=sys.stderr)
        sys.exit(1)
