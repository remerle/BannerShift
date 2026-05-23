#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/BannerShift.app"

echo "==> swift build (universal release)"
swift build -c release \
    --triple arm64-apple-macos13.0
swift build -c release \
    --triple x86_64-apple-macos13.0

# SwiftPM normalizes the --triple platform-version away, so the on-disk
# directory drops the "13.0" suffix (e.g. arm64-apple-macos, not
# arm64-apple-macos13.0). Match what swift build actually writes.
ARM_BIN="$ROOT/.build/arm64-apple-macos/release/BannerShift"
X86_BIN="$ROOT/.build/x86_64-apple-macos/release/BannerShift"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

lipo -create "$ARM_BIN" "$X86_BIN" -output "$APP/Contents/MacOS/BannerShift"
chmod +x "$APP/Contents/MacOS/BannerShift"
cp "$ROOT/Resources/Info.plist"  "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> ad-hoc signing"
codesign --force --sign - \
    --entitlements "$ROOT/Resources/BannerShift.entitlements" \
    --options runtime \
    "$APP"

echo "==> done: $APP"
