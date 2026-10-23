#!/bin/sh
# Assemble screendock.app from the release build: bundle + Info.plist + icon,
# then ad-hoc sign with the stable identifier so the Accessibility grant sticks.
set -e

APP="screendock.app"
ID="su.zerg.screendock"
NAME="screendock"
EXPERIMENTAL=0
UNIVERSAL=0
for arg in "$@"; do
    case "$arg" in
        --experimental) EXPERIMENTAL=1 ;;
        --universal) UNIVERSAL=1 ;;
        *) echo "Usage: $0 [--experimental] [--universal]" >&2; exit 2 ;;
    esac
done
if [ "$EXPERIMENTAL" = 1 ]; then
    APP="ScreenDock Experimental.app"
    ID="su.zerg.screendock.experimental"
    NAME="ScreenDock Experimental"
    VERSION="${VERSION:-0.1.0}"
else
    VERSION="${VERSION:-0.0.1}"
fi
BUILD_NUMBER="${BUILD_NUMBER:-1}"

set -- -c release
if [ "$UNIVERSAL" = 1 ]; then
    set -- "$@" --arch arm64 --arch x86_64
fi
swift build "$@"
BIN_DIR=$(swift build "$@" --show-bin-path)

# Generate the icon if it is missing.
if [ ! -f AppIcon.icns ]; then
    swift tools/make-icon.swift
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/screendock" "$APP/Contents/MacOS/screendock"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

python3 - "$APP" "$ID" "$NAME" "$VERSION" "$BUILD_NUMBER" <<'PY'
import pathlib, plistlib, sys
app, identifier, name, version, build = sys.argv[1:]
info = {
    "CFBundleName": name, "CFBundleDisplayName": name,
    "CFBundleIdentifier": identifier, "CFBundleExecutable": "screendock",
    "CFBundleIconFile": "AppIcon", "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version, "CFBundleVersion": build,
    "LSMinimumSystemVersion": "13.0", "LSUIElement": True,
    "NSHighResolutionCapable": True,
}
with (pathlib.Path(app) / "Contents/Info.plist").open("wb") as output:
    plistlib.dump(info, output)
PY

codesign --force --deep --sign - --identifier "$ID" "$APP"
echo "Built $APP"
