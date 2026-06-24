#!/bin/sh
# Assemble screendock.app from the release build: bundle + Info.plist + icon,
# then ad-hoc sign with the stable identifier so the Accessibility grant sticks.
set -e

APP="screendock.app"
ID="su.zerg.screendock"

swift build -c release

# Generate the icon if it is missing.
if [ ! -f AppIcon.icns ]; then
    swift tools/make-icon.swift
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/screendock "$APP/Contents/MacOS/screendock"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>screendock</string>
    <key>CFBundleDisplayName</key><string>screendock</string>
    <key>CFBundleIdentifier</key><string>su.zerg.screendock</string>
    <key>CFBundleExecutable</key><string>screendock</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - --identifier "$ID" "$APP"
echo "Built $APP"
