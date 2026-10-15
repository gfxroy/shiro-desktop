#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_MODE="${BUILD_MODE:-release}"
swift build -c "$BUILD_MODE" --product Shiro --jobs 2
SHIRO_BIN_DIR="$(swift build -c "$BUILD_MODE" --show-bin-path)"
SHIRO_APP_DIR="$PWD/dist/Shiro.app"
mkdir -p "$SHIRO_APP_DIR/Contents/MacOS" "$SHIRO_APP_DIR/Contents/Resources"
cp "$SHIRO_BIN_DIR/Shiro" "$SHIRO_APP_DIR/Contents/MacOS/Shiro"
ditto "$SHIRO_BIN_DIR/Shiro_Shiro.bundle" "$SHIRO_APP_DIR/Contents/Resources/Shiro_Shiro.bundle"
cp scripts/Info.plist "$SHIRO_APP_DIR/Contents/Info.plist"
# Ship a source snapshot so installed copies can prepare isolated, reviewable repairs.
SHIRO_REPAIR_DIR="$SHIRO_APP_DIR/Contents/Resources/RepairSource"
rm -rf "$SHIRO_REPAIR_DIR"
mkdir -p "$SHIRO_REPAIR_DIR/scripts"
cp Package.swift "$SHIRO_REPAIR_DIR/Package.swift"
ditto Sources "$SHIRO_REPAIR_DIR/Sources"
ditto Tests "$SHIRO_REPAIR_DIR/Tests"
cp scripts/test_guest.py "$SHIRO_REPAIR_DIR/scripts/test_guest.py"
swift scripts/make_icon.swift "$PWD/dist"
iconutil -c icns "$PWD/dist/Shiro.iconset" -o "$SHIRO_APP_DIR/Contents/Resources/Shiro.icns"
codesign --force --sign - "$SHIRO_APP_DIR"
codesign --verify --strict "$SHIRO_APP_DIR"
printf 'Built %s\n' "$SHIRO_APP_DIR"
if [[ "${1:-}" == "--install" ]]; then
    if [[ -e /Applications/Shiro.app ]]; then
        printf 'Shiro.app already exists. Replace it manually after closing it. New build: %s\n' "$SHIRO_APP_DIR"
        exit 0
    fi
    ditto "$SHIRO_APP_DIR" /Applications/Shiro.app
    printf 'Installed /Applications/Shiro.app\n'
fi
