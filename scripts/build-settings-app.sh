#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${DOCK_SWITCH_BUILD_ROOT:-$HOME/Local/dock-switch/build}"
MODULE_CACHE="${DOCK_SWITCH_MODULE_CACHE:-$HOME/Library/Caches/dock-switch/settings-modules}"
APP_DIR="$BUILD_ROOT/settings/DockSwitchSettings.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
SOURCE_DIR="$ROOT_DIR/native/settings-app/Sources"
DEFAULT_IDENTITY="Developer ID Application: LONGBIAO CHEN (HJG65XBC25)"
IDENTITY="${CSC_NAME:-$DEFAULT_IDENTITY}"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$MODULE_CACHE"

swiftc \
  -module-cache-path "$MODULE_CACHE" \
  -parse-as-library \
  -O \
  -framework SwiftUI \
  -framework AppKit \
  "$SOURCE_DIR"/*.swift \
  -o "$MACOS_DIR/DockSwitchSettings"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>DockSwitchSettings</string>
    <key>CFBundleIdentifier</key>
    <string>me.longbiaochen.dock-switch.settings</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Dock Switch Settings</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>CFBundleShortVersionString</key>
    <string>1.0.3</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>DTCompiler</key>
    <string>com.apple.compilers.llvm.clang.1_0</string>
    <key>DTPlatformBuild</key>
    <string>25F5057f</string>
    <key>DTPlatformName</key>
    <string>macosx</string>
    <key>DTPlatformVersion</key>
    <string>26.5</string>
    <key>DTSDKBuild</key>
    <string>25F5057f</string>
    <key>DTSDKName</key>
    <string>macosx26.5</string>
    <key>DTXcode</key>
    <string>2620</string>
    <key>DTXcodeBuild</key>
    <string>17A400</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if [[ -z "$IDENTITY" ]] || ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "error: required code signing identity not found: $IDENTITY" >&2
  echo "Set CSC_NAME to an installed signing identity, or install the default identity." >&2
  exit 1
fi

# File Provider-backed workspaces can attach metadata to newly-created bundle
# contents. Strip it immediately before signing so it cannot be reintroduced
# while the signing identity is being resolved.
/usr/bin/xattr -cr "$APP_DIR"
/usr/bin/codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_DIR"

echo "$APP_DIR"
