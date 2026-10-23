# screendock

> **Experimental branch:** `experimental/window-overview`. Includes a searchable
> all-windows overview in addition to the original per-display bars. Build the
> separate app with `sh build-app.sh --experimental --universal`.
> See [the Russian install guide](docs/EXPERIMENTAL.ru.md).

A tiny per-monitor "dock of just the open windows" for macOS multi-monitor
setups.

On every display that has windows, `screendock` draws a compact floating bar
with one tile per window physically on that screen. Click a tile to bring
exactly that window forward. On the display that currently hosts the native
Dock, the bar sits flush beside the Dock (so it reads as an extension of it);
other displays get a centered bar; empty displays get none. The bar follows the
Dock as it migrates between displays, and matches the Dock's icon size, height,
and baseline — tracking it as you resize the Dock.

## Features

- **All windows:** click the menu-bar icon or press **Control–Option–Space**.
  Search by document title and application name, then press Enter or double-click
  a row. Includes minimized windows, hidden apps and other Spaces/fullscreen.
- The overview uses **Accessibility**, not Screen Recording. It restores the
  selected window and targets its Accessibility identity, including windows
  with identical names or bounds. Slow apps are queried off the main thread.
- One tile per **window** (not per app) on each screen; left-click raises that
  exact window.
- **Right-click** a tile for a context menu: Bring to Front / Hide / Quit.
- Visually matched to the native Dock and **scales with it** when you change the
  Dock size.
- Background app with no Dock icon. Left-click the menu-bar icon for the
  overview; right-click for its menu and **Quit**.

## How it works

- **Window list:** `CGWindowListCopyWindowInfo` (`.optionOnScreenOnly`). Fast,
  non-blocking, needs no permission, and naturally returns only the current
  Space's on-screen windows. Each window is mapped to a display by maximum
  overlap area.
- **Global overview:** `AXWindows` for running regular applications, including
  other Spaces, minimized windows and hidden applications. Titles come from
  `AXTitle`, with `AXDocument` as a fallback. Scans run on a serial worker with
  a 150 ms per-call timeout and a six-second scan budget. Refreshes run only
  while the overview is open. Unresponsive apps are reported as an incomplete
  list; their last known entries remain available.
- **Click to raise:** Accessibility API (`AXRaise`), touched only on click — so
  a busy/unresponsive app can never freeze the bars.
- **Dock tracking:** the full-screen `Dock`-owned window at `layer >= 0`
  (wallpaper windows sit at a deeply negative layer) identifies the Dock's
  display; its edge comes from `com.apple.dock` `orientation`; its tile rect
  (via the Dock's `AXList`) lets the bar seat itself flush beside the Dock and
  copy its icon size / band height / baseline.
- Runs as an `accessory` app (no Dock icon); a menu-bar item provides **Quit**.

## Requirements

- macOS 13+
- **Accessibility** permission for the global overview and exact-window
  activation. The original bars still appear without it. Screen Recording is
  **not** required; titles are read through Accessibility.

## Install (prebuilt)

A built `screendock.app` is attached to each [Release](../../releases), produced
on a GitHub-hosted macOS runner.

1. Download `screendock-*.zip` from the latest release and unzip.
2. Move `screendock.app` to `/Applications`.
3. The build is ad-hoc-signed (no paid Apple Developer ID), so macOS quarantines
   it. Clear the flag once:
   ```sh
   xattr -dr com.apple.quarantine /Applications/screendock.app
   ```
4. Launch it, then grant **Accessibility**: System Settings → Privacy & Security
   → Accessibility → add `/Applications/screendock.app`.
5. Optional autostart: System Settings → General → Login Items → add
   `screendock.app`.

Quit from the menu-bar icon.

## Build from source

```sh
make run     # debug build + ad-hoc codesign (stable identity) + launch
make app     # assemble a distributable screendock.app
make icon    # regenerate AppIcon.icns from tools/make-icon.swift
```

Experimental, universal app (Intel and Apple Silicon):

```sh
sh build-app.sh --experimental --universal
```

This produces `ScreenDock Experimental.app`, bundle identifier
`su.zerg.screendock.experimental`, alongside the normal app.

Verification:

```sh
swift test
sh tools/check-overview.sh
```

The second command requires the terminal's existing Accessibility grant. It
creates its own temporary windows, including a fullscreen Space, checks exact
window activation/restoration and hidden-app recovery, renders the overview,
then closes its fixture process. It never changes the existing permission list.

On first `make run`, grant Accessibility to `.build/debug/screendock`.

> The ad-hoc `codesign` uses a **stable identifier** (`su.zerg.screendock`) so
> the Accessibility grant survives rebuilds — an unsigned binary changes its
> cdhash on every `swift build` and macOS would drop the permission each time.

Tunables live in `Sources/screendock/BarController.swift`
(`backgroundAlpha` — blur translucency — and the effect material).

## Known limitations

- **Dock auto-hide:** the Dock window may be absent, so its display can't be
  detected; the bar then falls back to centered bars on all non-empty screens.
- **Stage Manager:** its left strip is also owned by `Dock` and may confuse the
  detection.
- The original bars still show only current-Space windows and app icons. Use
  the overview for document titles and windows on other Spaces.
- Browser **tabs** are not separate OS windows. The overview lists browser
  windows by their current title, not every tab inside each window.
- Apps that do not expose windows/titles through Accessibility can be missing
  or show a generic title. macOS and the target app control Space transitions;
  an unsupported activation reports an error rather than moving windows.
- AppKit can omit fullscreen windows on other Spaces from `AXWindows`.
  Previously seen, still-fullscreen AX identities are retained. On a cold
  start, an omitted fullscreen window may require showing its app once.
- No thumbnail previews or automatic window tiling in this experiment.
- The global shortcut can be unavailable if another app already registered it;
  the menu-bar icon remains usable.

## Roadmap

- Badge/label to disambiguate multiple windows of one app; highlight the active
  window.
- Hover window previews (needs Screen Recording).
- Developer-ID signing + notarization to drop the Gatekeeper quarantine step.
- Config: bar side, icon size, app blacklist, "tile = app" mode.

## License

Licensed under the Apache License, Version 2.0 — see [LICENSE](LICENSE).

Copyright 2026 Zak Fein.
