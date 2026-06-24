BINARY = .build/debug/screendock
IDENTIFIER = su.zerg.screendock

.PHONY: build sign run release icon app clean

build:
	swift build

# Ad-hoc sign with a STABLE identifier so the Accessibility (TCC) grant
# survives rebuilds — otherwise every `swift build` changes the cdhash and
# macOS drops the permission.
sign: build
	codesign --force --sign - --identifier $(IDENTIFIER) $(BINARY)

run: sign
	$(BINARY)

release:
	swift build -c release
	codesign --force --sign - --identifier $(IDENTIFIER) .build/release/screendock

# Regenerate the app icon (AppIcon.icns) from tools/make-icon.swift.
icon:
	swift tools/make-icon.swift
	iconutil -c icns AppIcon.iconset -o AppIcon.icns

# Build the distributable screendock.app bundle.
app:
	sh build-app.sh

clean:
	swift package clean
	rm -rf screendock.app AppIcon.iconset
