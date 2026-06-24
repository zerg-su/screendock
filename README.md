# screendock

A tiny per-monitor "dock of open windows" for macOS multi-monitor setups.

On every display that does **not** currently host the native Dock, `screendock`
draws a compact floating bar with one tile per window physically on that screen.
Click a tile to bring exactly that window forward. The bar follows the native
Dock: when the Dock migrates to another display, the bar there disappears and
reappears on the display the Dock left (if it has windows). Empty screens get no
bar.

## How it works

- **Window list:** `CGWindowListCopyWindowInfo` (`.optionOnScreenOnly`). Fast,
  non-blocking, needs no permission, and naturally returns only the current
  Space's on-screen windows. Each window is mapped to a display by maximum
  overlap area.
- **Click to raise:** Accessibility API (`AXRaise`), touched only on click — so
  a busy/unresponsive app can never freeze the bars. **Right-click** a tile for a
  context menu (Bring to Front / Hide / Quit).
- **Dock location:** the full-screen `Dock`-owned window at `layer >= 0` (wallpaper
  windows sit at a deeply negative layer) identifies the Dock's display; the edge
  comes from `com.apple.dock` `orientation`.
- **Visual match:** the bar derives its icon size (`tilesize`), band height, and
  baseline from the live Dock (via the Dock's `AXList` rect) and seats itself in
  the Dock's reserved strip — so it tracks the Dock as you resize it. Tunables in
  `BarController`: `backgroundAlpha` (blur translucency) and the effect material.
- Runs as an `accessory` app (no Dock icon); a menu-bar item provides **Quit**.

## Requirements

- macOS 13+
- **Accessibility** permission (only for click-to-raise; bars appear without it).
  Screen Recording is **not** required (tiles are app icons, not titles).

## Build & run

```sh
make run     # swift build + ad-hoc codesign (stable identity) + launch
```

On first launch, grant Accessibility: System Settings → Privacy & Security →
Accessibility → add `.build/debug/screendock`, then `make run` again.

> The ad-hoc `codesign` in the Makefile uses a **stable identifier**
> (`su.zerg.screendock`) so the Accessibility grant survives rebuilds —
> an unsigned binary changes its cdhash on every `swift build` and macOS would
> drop the permission each time.

Quit from the menu-bar `▦` item (or Ctrl-C in the terminal).

## Known limitations (prototype)

- **Dock auto-hide:** the strip window may be absent, so the Dock display can't
  be detected; the bar then shows on all non-empty screens (brief duplication
  with the hidden Dock is acceptable). This is the most fragile part — verify
  it first.
- **Stage Manager:** its left strip is also owned by `Dock` and may confuse the
  edge detection.
- **No window titles** (would need Screen Recording). Multiple windows of one
  app show identical icons, distinguished only by position/hover.
- Fullscreen windows (separate Space) are not handled specially in v1.

## Possible next steps

- Badge/label to disambiguate multiple windows of one app; highlight the active
  window.
- Hover window previews (needs Screen Recording).
- Package as a signed `.app` + LaunchAgent for autostart and a stable TCC grant.
- Config: bar side, icon size, app blacklist, "tile = app" mode.

## License

Licensed under the Apache License, Version 2.0 — see [LICENSE](LICENSE).

Copyright 2026 Zak Fein.
