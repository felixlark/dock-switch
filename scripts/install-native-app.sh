#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/native/dock-switch.app"
TARGET_APP="/Applications/dock-switch.app"
ENTITLEMENTS="$ROOT_DIR/resources/entitlements.mac.plist"
DEFAULT_IDENTITY="Developer ID Application: LONGBIAO CHEN (HJG65XBC25)"
IDENTITY="${CSC_NAME:-$DEFAULT_IDENTITY}"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "error: built app not found: $SOURCE_APP" >&2
  exit 1
fi

if [[ -z "$IDENTITY" ]] || ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "error: required code signing identity not found: $IDENTITY" >&2
  exit 1
fi

INSTALL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dock-switch-install.XXXXXX")"
INSTALL_APP="$INSTALL_DIR/dock-switch.app"
trap 'rm -rf "$INSTALL_DIR"' EXIT

/usr/bin/ditto --norsrc --noextattr "$SOURCE_APP" "$INSTALL_APP"
/usr/bin/xattr -cr "$INSTALL_APP"
/usr/bin/codesign --force --options runtime --timestamp --sign "$IDENTITY" "$INSTALL_APP/Contents/Resources/DockSwitchSettings.app"
/usr/bin/codesign --force --options runtime --timestamp --sign "$IDENTITY" "$INSTALL_APP/Contents/Resources/DockSwitchGokit5Serial"
/usr/bin/codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$INSTALL_APP"
/usr/bin/codesign --verify --deep --strict "$INSTALL_APP"

killall -9 DockSwitch DockSwitchGokit5Serial dock-switch-runtime dock-switch 2>/dev/null || true
rm -rf "$TARGET_APP"
/usr/bin/ditto --norsrc --noextattr "$INSTALL_APP" "$TARGET_APP"
/usr/bin/xattr -cr "$TARGET_APP"
/usr/bin/codesign --verify --deep --strict "$TARGET_APP"
/usr/bin/open -n "$TARGET_APP"

echo "$TARGET_APP"
