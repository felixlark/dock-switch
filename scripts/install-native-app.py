#!/usr/bin/env python3
"""Install a validated candidate, preserving the existing configuration and identity."""
import argparse
import ctypes
import math
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location('build_identity', Path(__file__).with_name('build-identity.py'))
identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(identity)
ROOT = identity.ROOT
TARGET = Path('/Applications/dock-switch.app')


def copy_app(source, destination):
    identity.run_checked(['/usr/bin/ditto', '--norsrc', '--noextattr', str(source), str(destination)], 'bundle copy failed')


def atomic_swap(left, right):
    # Apple public renameatx_np(2), RENAME_SWAP from the macOS SDK sys/stdio.h.
    # Both complete bundles are siblings on /Applications' volume.
    library = ctypes.CDLL(None, use_errno=True)
    rename = library.renameatx_np
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(-2, os.fsencode(left), -2, os.fsencode(right), 0x00000002) != 0:
        raise OSError(ctypes.get_errno(), 'atomic bundle exchange failed')


def start_app():
    identity.run_checked(['/usr/bin/open', '-g', str(TARGET)], 'installed app launch failed')


def install(args):
    if args.stop_timeout_seconds is not None:
        identity.require(math.isfinite(args.stop_timeout_seconds) and args.stop_timeout_seconds > 0,
            'stop timeout must be a positive number when explicitly configured')
        os.environ['DOCK_SWITCH_STOP_TIMEOUT_SECONDS'] = str(args.stop_timeout_seconds)
    value = identity.identity(args.identity_profile)  # Reject bad profiles before building or stopping.
    build_root = Path(os.environ.get('DOCK_SWITCH_BUILD_ROOT', Path.home()/'Library/Caches/dock-switch/build')).resolve()
    source = build_root/'native/dock-switch.app'
    directory = build_root/'identity'
    # Missing-package builds must consume the same explicit profile and installed config.
    if not source.exists():
        env = os.environ.copy()
        if args.identity_profile:
            env['DOCK_SWITCH_IDENTITY_PROFILE'] = args.identity_profile
        if TARGET.exists():
            env['DOCK_SWITCH_CONFIG_SOURCE'] = str(TARGET/identity.CONFIG)
        subprocess.run(['/bin/bash', str(ROOT/'scripts/build-native-app.sh')], env=env, check=True)
    manifest = identity.check_manifest(source, directory, args.identity_profile)
    identity.verify_seal(source)
    cache = Path.home()/'Library/Caches/dock-switch/install'
    cache.mkdir(parents=True, exist_ok=True)
    cache.chmod(0o700)
    helper = cache/'manage-installed-app'
    identity.run_checked(['swiftc', '-module-cache-path', str(cache/'modules'),
        str(ROOT/'scripts/manage-installed-app.swift'), '-o', str(helper)], 'installer lifecycle helper build failed')
    # Prepare and verify the complete final bundle on the target volume before
    # requesting any app stop. The public /Applications path is never a copy target.
    with tempfile.TemporaryDirectory(prefix='.dock-switch-install-', dir=TARGET.parent) as scratch:
        candidate = Path(scratch)/'dock-switch.app'
        copy_app(source, candidate)
        identity.sign(candidate, value)
        identity.check_manifest(candidate, directory, args.identity_profile)
        identity.check_compatibility(candidate, TARGET, value)
        # Source configuration must still match after the entire build and final re-sign.
        identity.check_live_config(TARGET, manifest)
        identity.run_checked([str(helper), 'check'], 'Settings is running; preserve its draft and close it before installing')
        if args.check_only:
            print('installation preflight passed; no application stopped or replaced')
            return
        was_running = identity.run_checked([str(helper), 'status'], 'cannot inspect installed app').stdout.strip() == b'running'
        previous_exists = TARGET.exists()
        backup = cache/('backup-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))/'dock-switch.app'
        backup.parent.mkdir(mode=0o700)
        stopped = False
        replaced = False
        try:
            # Check immediately before stop and once more after exit (which may save).
            identity.check_live_config(TARGET, manifest)
            stopped = True
            identity.run_checked([str(helper), 'stop'], 'could not obtain normal application stop')
            identity.check_live_config(TARGET, manifest)
            if previous_exists:
                copy_app(TARGET, backup)
                identity.require(identity.digest(backup/identity.CONFIG) == manifest['configDigest'], 'backup config differs')
            # A newly opened Settings window is another writer, never a termination target.
            identity.run_checked([str(helper), 'check'], 'Settings opened during install; original application preserved')
            # Recheck just before replacement; never write stale config over a live edit.
            identity.check_live_config(TARGET, manifest)
            if previous_exists:
                atomic_swap(candidate, TARGET)  # candidate now retains the complete old bundle.
            else:
                candidate.rename(TARGET)  # Same-volume atomic rename for a first install.
            replaced = True
            identity.check_manifest(TARGET, directory, args.identity_profile)
            identity.verify_seal(TARGET)
            start_app()
            print('installation verified; application launch requested without activation')
        except Exception:
            if replaced:
                try:
                    if previous_exists:
                        atomic_swap(candidate, TARGET)
                    elif TARGET.exists():
                        TARGET.rename(candidate)
                except Exception as error:
                    raise ValueError('atomic rollback failed; retained private backup: '+str(backup)+
                        '; current application state requires inspection') from error
            if stopped and was_running and TARGET.exists():
                start_app()
            raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identity-profile', default=os.environ.get('DOCK_SWITCH_IDENTITY_PROFILE'))
    parser.add_argument('--check-only', action='store_true')
    parser.add_argument('--stop-timeout-seconds', type=float, default=os.environ.get('DOCK_SWITCH_STOP_TIMEOUT_SECONDS'))
    try:
        install(parser.parse_args())
    except Exception as error:
        # No profile/config/certificate details escape to public command logs.
        if type(error) is ValueError:
            print('error: '+str(error), file=sys.stderr)
        else:
            print('error: installation did not complete; verify application state before retrying', file=sys.stderr)
        sys.exit(1)
