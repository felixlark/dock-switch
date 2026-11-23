#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -gt 0 ]]; then
  [[ $# == 2 && $1 == --identity-profile ]] || { echo 'usage: build-settings-app.sh [--identity-profile /absolute/profile.json]' >&2; exit 1; }
  export DOCK_SWITCH_IDENTITY_PROFILE="$2"
fi
BUILD_ROOT="${DOCK_SWITCH_BUILD_ROOT:-$HOME/Library/Caches/dock-switch/build}"
MODULE_CACHE="${DOCK_SWITCH_MODULE_CACHE:-$HOME/Library/Caches/dock-switch/settings-modules}"
IDENTITY_DIR="$BUILD_ROOT/identity"
APP_DIR="$BUILD_ROOT/settings/DockSwitchSettings.app"
SOURCE_DIR="$ROOT_DIR/native/settings-app/Sources"
python3 "$ROOT_DIR/scripts/build-identity.py" generate --directory "$IDENTITY_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$MODULE_CACHE" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/resources/settings.icns" "$APP_DIR/Contents/Resources/settings.icns"
cp "$IDENTITY_DIR/settings.plist" "$APP_DIR/Contents/Info.plist"
swiftc -module-cache-path "$MODULE_CACHE" -parse-as-library -O -framework SwiftUI -framework AppKit \
  "$SOURCE_DIR"/*.swift \
  "$ROOT_DIR/native/dock-switch-app/Sources/DockSwitchCore/AppIdentity.swift" \
  -o "$APP_DIR/Contents/MacOS/DockSwitchSettings"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
python3 "$ROOT_DIR/scripts/build-identity.py" sign-settings --directory "$IDENTITY_DIR" --app "$APP_DIR"
echo "$APP_DIR"
