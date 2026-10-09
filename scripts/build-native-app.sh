#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/native/dock-switch-app"
BUILD_ROOT="${DOCK_SWITCH_BUILD_ROOT:-$HOME/Local/dock-switch/build}"
SWIFT_SCRATCH="${DOCK_SWITCH_SWIFT_SCRATCH:-$HOME/Library/Caches/dock-switch/swift-build}"
SWIFT_CACHE="${DOCK_SWITCH_SWIFT_CACHE:-$HOME/Library/Caches/dock-switch/swift-cache}"
APP_DIR="$BUILD_ROOT/native/dock-switch.app"
SETTINGS_APP="$BUILD_ROOT/settings/DockSwitchSettings.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_RESOURCES_DIR="$RESOURCES_DIR/app"
ENTITLEMENTS="$ROOT_DIR/resources/entitlements.mac.plist"
DEFAULT_IDENTITY="Developer ID Application: LONGBIAO CHEN (HJG65XBC25)"
IDENTITY="${CSC_NAME:-$DEFAULT_IDENTITY}"

swift build --package-path "$PACKAGE_DIR" --scratch-path "$SWIFT_SCRATCH" --cache-path "$SWIFT_CACHE" -c release --arch arm64
# Newer SwiftPM releases moved products out of .build/<triple>/release; ask
# SwiftPM for the real location so a stale binary is never packaged.
BUILD_DIR="$(swift build --package-path "$PACKAGE_DIR" --scratch-path "$SWIFT_SCRATCH" --cache-path "$SWIFT_CACHE" -c release --arch arm64 --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$APP_RESOURCES_DIR/src" "$APP_RESOURCES_DIR/bin"
cp "$BUILD_DIR/DockSwitch" "$MACOS_DIR/DockSwitch"
cp "$BUILD_DIR/DockSwitchGokit5Serial" "$RESOURCES_DIR/DockSwitchGokit5Serial"
cp "$ROOT_DIR/src/config.json" "$APP_RESOURCES_DIR/src/config.json"
cp "$ROOT_DIR/bin/dock-switch-cli.js" "$APP_RESOURCES_DIR/bin/dock-switch-cli.js"
chmod 755 "$APP_RESOURCES_DIR/bin/dock-switch-cli.js"

if [[ -d "$SETTINGS_APP" ]]; then
  cp -R "$SETTINGS_APP" "$RESOURCES_DIR/DockSwitchSettings.app"
fi

if [[ -f "$ROOT_DIR/resources/icon@2x.icns" ]]; then
  cp "$ROOT_DIR/resources/icon@2x.icns" "$RESOURCES_DIR/icon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>DockSwitch</string>
    <key>CFBundleIdentifier</key>
    <string>me.longbiaochen.dock-switch</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>icon</string>
    <key>CFBundleName</key>
    <string>dock-switch</string>
    <key>CFBundleDisplayName</key>
    <string>dock-switch</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>CFBundleShortVersionString</key>
    <string>1.0.1</string>
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
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>dock-switch needs automation permission to show and restore the Dock.</string>
    <key>NSInputMonitoringUsageDescription</key>
    <string>dock-switch listens for the F20 launcher shortcut.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>dock-switch uses Accessibility to read Dock items and place windows.</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if [[ -z "$IDENTITY" ]] || ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "error: required code signing identity not found: $IDENTITY" >&2
  echo "Set CSC_NAME to an installed signing identity, or install the default identity." >&2
  exit 1
fi

SIGNING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dock-switch-sign.XXXXXX")"
SIGNING_APP="$SIGNING_DIR/dock-switch.app"
trap 'rm -rf "$SIGNING_DIR"' EXIT

# File Provider-backed workspaces can reattach Finder metadata between xattr
# cleanup and codesign. Sign outside the workspace, then copy the sealed bundle
# back without resource forks or extended attributes.
/usr/bin/ditto --norsrc --noextattr "$APP_DIR" "$SIGNING_APP"
/usr/bin/xattr -cr "$SIGNING_APP"
if [[ -d "$SIGNING_APP/Contents/Resources/DockSwitchSettings.app" ]]; then
  /usr/bin/codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SIGNING_APP/Contents/Resources/DockSwitchSettings.app"
fi

/usr/bin/codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SIGNING_APP/Contents/Resources/DockSwitchGokit5Serial"
/usr/bin/codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$SIGNING_APP"
/usr/bin/codesign --verify --deep --strict "$SIGNING_APP"

rm -rf "$APP_DIR"
/usr/bin/ditto --norsrc --noextattr "$SIGNING_APP" "$APP_DIR"

echo "$APP_DIR"
