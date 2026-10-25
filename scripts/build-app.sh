#!/bin/bash
# Builds Lume.app into ./build. Requires Xcode command line tools (Swift 5.9+) on macOS 14+.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release

BIN="$(swift build -c release --show-bin-path)/Lume"
APP="build/Lume.app"

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

# Ad-hoc signature so Gatekeeper lets it run locally.
codesign --force --deep --sign - "$APP"

echo "Built $APP"
