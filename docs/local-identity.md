# Build identity and local compatibility

Public source builds use `io.github.felixlark.dock-switch`. Settings uses its own
bundle identifier and shares the main app's `DockSwitchDataNamespace`. The main
process keeps `UserDefaults.standard`; Settings opens that same main domain as a
suite. All four custom-phrase notifications use the shared namespace. Existing
shortcut behavior and phrase storage are unchanged.

## Public builds

```sh
yarn build:native
```

This builds both native apps in `~/Library/Caches/dock-switch`, with neutral
metadata and ad-hoc signing by default. `CSC_NAME` can select an installed signing
identity for a public build. `yarn dist:signed` uses this same native build route;
it does not revive the historical Electron release route. `yarn dist` additionally
runs the installer. A public default build cannot replace an installation with a
different identity or designated requirement.

## An existing local installation

Keep its non-secret compatibility profile outside the repository, for example at
`~/Library/Application Support/dock-switch/identity/local-compatibility.json`,
readable only by the local user (0600). The version-1 JSON shape is:

```json
{
  "schemaVersion": 1,
  "bundleId": "org.example.launcher",
  "settingsBundleId": "org.example.preferences",
  "dataNamespace": "org.example.launcher",
  "signingIdentity": "0123456789ABCDEF0123456789ABCDEF01234567"
}
```

Use the existing installed bundle IDs and exact certificate SHA-1 selector.
`dataNamespace` must equal the main bundle ID. These identifiers and certificate
selectors are not credentials; never put passwords, tokens or private keys in the
profile. Do not commit the local profile, configuration snapshots or compatibility
packages. They retain the installation's private identity and are not anonymous
public release artifacts.

```sh
profile="$HOME/Library/Application Support/dock-switch/identity/local-compatibility.json"
export DOCK_SWITCH_CONFIG_SOURCE="/Applications/dock-switch.app/Contents/Resources/app/src/config.json"
bash scripts/build-native-app.sh --identity-profile "$profile"
bash scripts/install-native-app.sh --identity-profile "$profile" --check-only
bash scripts/install-native-app.sh --identity-profile "$profile"
```

The same `--identity-profile` option is supported by the standalone Settings
builder. `DOCK_SWITCH_IDENTITY_PROFILE` propagates it through the existing yarn
commands and any missing-package build invoked by the installer. A supplied
profile must be complete and valid; fields do not silently fall back to defaults.

## What installation verifies

Generated main and Settings Info files live in the external build cache. The main
Info is supplied to SwiftPM before linking, using a content-addressed linker input
so a changed identity causes a relink. The main external Info, its Mach-O embedded
Info and Settings Info must agree on the shared namespace. The build manifest
binds source content, profile, signing selector and opaque configuration digest.

The existing `DOCK_SWITCH_CONFIG_SOURCE` input is snapshotted consistently and
copied into the new bundle before signing. Installation re-signs with the same
selected identity, verifies the complete sealed bundle and compares both app
identities, the shared data domain, exact leaf certificate fingerprints and designated requirements with the installed
apps. It checks the live installed configuration after building, immediately
before stopping, after normal termination, and immediately before replacement.
Any configuration change stops replacement; a previously running app is reopened
without activation. Obtain a fresh snapshot and rebuild after checking the writer.

Installation refuses to stop an already running Settings process, preserving any
unsaved in-memory draft. Review and close Settings before installing. The lifecycle
helper rechecks this at the actual stop boundary. Installation requires one
operator, no other writer and no pending Settings launch; these checks do not
claim to intercept arbitrary uncoordinated external launches. Normal termination
targets only the exact installed main bundle path. Stopping waits without a
deadline by default and never force-kills a process. An operator may explicitly
set `--stop-timeout-seconds` (or `DOCK_SWITCH_STOP_TIMEOUT_SECONDS`) to a positive
number; reaching it refuses replacement. A newly observed Settings process is
preserved and stops the install.

The complete final bundle is staged and verified in a private temporary sibling
under `/Applications` before stopping. Existing installations switch with Apple's
public `renameatx_np(RENAME_SWAP)` operation, retaining the complete old bundle for
atomic rollback. First installation uses a same-volume atomic rename; a copy is
never performed into the live app path. A private backup is also retained under
the external install cache. A failed post-switch check swaps the old bundle back
and reopens the previously running app. After replacement the configuration
digest and new signature seal are checked. The installer does not reset
permissions, change hotkeys, migrate preferences or read phrase content.

Some existing bundles have an invalid seal because Settings can save configuration
inside the bundle. That is an existing architecture limitation. It is recorded as
the old baseline, never treated as a healthy signature. The new package must pass
strict signature verification before and after installation. This change does not
make later in-bundle configuration edits compatible with a sealed signature.

Previously published binaries and certificate subjects are outside this source
change. Their privacy and upgrade policy must be handled separately; this local
compatibility path does not promise identity-preserving upgrades for every old
public release.
