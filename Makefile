BINARY = .build/debug/screendock
IDENTIFIER = su.zerg.screendock

.PHONY: build sign run release clean

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

clean:
	swift package clean
