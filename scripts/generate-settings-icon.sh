#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICON_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/dock-switch-icon.XXXXXX")"
trap 'rm -rf "$ICON_SCRATCH"' EXIT
mkdir -p "$HOME/Library/Caches/dock-switch/settings-modules" "$ICON_SCRATCH/settings.iconset"
swift -module-cache-path "$HOME/Library/Caches/dock-switch/settings-modules" "$ROOT_DIR/scripts/generate-settings-icon.swift" "$ICON_SCRATCH/png"
for size in 16 32 128 256 512; do
    cp "$ICON_SCRATCH/png/icon_${size}x${size}.png" "$ICON_SCRATCH/settings.iconset/icon_${size}x${size}.png"
    double=$((size * 2))
    cp "$ICON_SCRATCH/png/icon_${double}x${double}.png" "$ICON_SCRATCH/settings.iconset/icon_${size}x${size}@2x.png"
done
cp "$ICON_SCRATCH/png/icon_512x512.png" "$ROOT_DIR/resources/settings.png"
iconutil -c icns "$ICON_SCRATCH/settings.iconset" -o "$ROOT_DIR/resources/settings.icns"
