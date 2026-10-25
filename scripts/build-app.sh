#!/bin/bash
# Builds Lume.app into ./build (or ./build/<arch> with ARCH set). Requires Xcode command line tools (Swift 5.9+) on macOS 14+.
set -euo pipefail

cd "$(dirname "$0")/.."
# ARCH=arm64 or ARCH=x86_64 builds for that architecture alone, into build/<arch>/Lume.app.
ARCH="${ARCH:-}"
ARCH_FLAGS=()
APP="build/Lume.app"
if [ -n "$ARCH" ]; then
    ARCH_FLAGS=(--arch "$ARCH")
    APP="build/$ARCH/Lume.app"
fi
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}

BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/Lume"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lume"

# App icon: render every size from scripts/make-icon.swift, then pack it with iconutil.
mkdir -p .build/icon
swiftc -O -o .build/icon/make-icon scripts/make-icon.swift
rm -rf .build/icon/Lume.iconset
.build/icon/make-icon .build/icon/Lume.iconset
iconutil -c icns .build/icon/Lume.iconset -o "$APP/Contents/Resources/Lume.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Lume</string>
    <key>CFBundleDisplayName</key><string>Lume</string>
    <key>CFBundleIdentifier</key><string>app.lume.optimiser</string>
    <key>CFBundleExecutable</key><string>Lume</string>
    <key>CFBundleIconFile</key><string>Lume</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Sign with the local "Lume Local" identity when there is one: its signature stays the same across
# builds, so privacy permissions such as Full Disk Access survive a rebuild. It lives in its own
# keychain, whose password is only a lock for this one self-signed certificate, so signing never
# prompts. Otherwise fall back to an ad-hoc signature, which macOS treats as a new app every build.
SIGNING_KEYCHAIN="$HOME/Library/Keychains/lume-signing.keychain-db"
SIGNING_PASSWORD="lume-local-signing"
if [ -f "$SIGNING_KEYCHAIN" ] && security unlock-keychain -p "$SIGNING_PASSWORD" "$SIGNING_KEYCHAIN" 2>/dev/null \
    && security find-identity -p codesigning "$SIGNING_KEYCHAIN" | grep -q "Lume Local"; then
    codesign --force --deep --sign "Lume Local" --keychain "$SIGNING_KEYCHAIN" "$APP"
elif security find-identity -v -p codesigning | grep -q "Lume Local"; then
    codesign --force --deep --sign "Lume Local" "$APP"
else
    codesign --force --deep --sign - "$APP"
    echo "Signed ad-hoc. Create a \"Lume Local\" code-signing identity to keep permissions across builds."
fi

echo "Built $APP"
