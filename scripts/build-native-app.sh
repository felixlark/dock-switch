#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -gt 0 ]]; then
  [[ $# == 2 && $1 == --identity-profile ]] || { echo 'usage: build-native-app.sh [--identity-profile /absolute/profile.json]' >&2; exit 1; }
  export DOCK_SWITCH_IDENTITY_PROFILE="$2"
fi
PACKAGE_DIR="$ROOT_DIR/native/dock-switch-app"
BUILD_ROOT="${DOCK_SWITCH_BUILD_ROOT:-$HOME/Library/Caches/dock-switch/build}"
SWIFT_SCRATCH="${DOCK_SWITCH_SWIFT_SCRATCH:-$HOME/Library/Caches/dock-switch/swift-build}"
SWIFT_CACHE="${DOCK_SWITCH_SWIFT_CACHE:-$HOME/Library/Caches/dock-switch/swift-cache}"
IDENTITY_DIR="$BUILD_ROOT/identity"
APP_DIR="$BUILD_ROOT/native/dock-switch.app"
# Rebuild the nested app; a stale package from a different profile is not reused.
/bin/bash "$ROOT_DIR/scripts/build-settings-app.sh"
python3 "$ROOT_DIR/scripts/build-identity.py" generate --directory "$IDENTITY_DIR"
export DOCK_SWITCH_APP_INFO_PLIST="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["mainInfo"])' "$IDENTITY_DIR/manifest.json")"
swift build --package-path "$PACKAGE_DIR" --scratch-path "$SWIFT_SCRATCH" --cache-path "$SWIFT_CACHE" -c release --arch arm64
BUILD_DIR="$(swift build --package-path "$PACKAGE_DIR" --scratch-path "$SWIFT_SCRATCH" --cache-path "$SWIFT_CACHE" -c release --arch arm64 --show-bin-path)"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/app/src" "$APP_DIR/Contents/Resources/app/bin"
cp "$BUILD_DIR/DockSwitch" "$APP_DIR/Contents/MacOS/DockSwitch"
cp "$BUILD_DIR/DockSwitchGokit5Serial" "$APP_DIR/Contents/Resources/DockSwitchGokit5Serial"
cp "$IDENTITY_DIR/config.json" "$APP_DIR/Contents/Resources/app/src/config.json"
cp "$ROOT_DIR/bin/dock-switch-cli.js" "$APP_DIR/Contents/Resources/app/bin/dock-switch-cli.js"
chmod 755 "$APP_DIR/Contents/Resources/app/bin/dock-switch-cli.js"
cp -R "$BUILD_ROOT/settings/DockSwitchSettings.app" "$APP_DIR/Contents/Resources/DockSwitchSettings.app"
cp "$IDENTITY_DIR/main.plist" "$APP_DIR/Contents/Info.plist"
if [[ -f "$ROOT_DIR/resources/icon@2x.icns" ]]; then cp "$ROOT_DIR/resources/icon@2x.icns" "$APP_DIR/Contents/Resources/icon.icns"; fi
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
python3 "$ROOT_DIR/scripts/build-identity.py" sign --directory "$IDENTITY_DIR" --app "$APP_DIR"
python3 "$ROOT_DIR/scripts/build-identity.py" verify --directory "$IDENTITY_DIR" --app "$APP_DIR"
echo "$APP_DIR"
