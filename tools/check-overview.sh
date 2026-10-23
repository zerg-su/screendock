#!/bin/sh
# Bounded, opt-in UI check. Creates and closes only its own fixture windows.
# Requires this terminal's existing Accessibility grant. Does not grant access.
set -eu
cd "$(dirname "$0")/.."
swift build
BIN_DIR=$(swift build --show-bin-path)
swiftc -D DEBUG -I "$BIN_DIR/Modules" \
    "$BIN_DIR/WindowCore.build/WindowCatalog.swift.o" \
    Sources/screendock/AXUtil.swift Sources/screendock/Permissions.swift \
    Sources/screendock/AccessibleWindows.swift Sources/screendock/WindowOverview.swift \
    tools/check-overview.swift -o "$BIN_DIR/check-overview"
exec "$BIN_DIR/check-overview"
