import AppKit

/// A tile in a bar — an app icon that raises one specific window.
final class TileButton: NSButton {
    var win: WinInfo?

    // Right-click shows the tile's context menu even though the panel is
    // non-activating (NSButton would otherwise swallow the event).
    override func rightMouseDown(with event: NSEvent) {
        if let menu = menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

/// Owns one floating panel per display and keeps it visually matched to the
/// native Dock: same icon size, same band height, same baseline, and a pill
/// background that reaches toward the screen edge the way the Dock's does. The
/// Dock's screen gets the bar flush beside the Dock; other screens get it
/// centred on the Dock's edge.
final class BarController: NSObject {
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var signatures: [CGDirectDisplayID: String] = [:]
    private var statusItem: NSStatusItem?

    private let edgeMargin: CGFloat = 8
    private let gap: CGFloat = 10            // distance between the Dock and our bar
    private let backgroundAlpha: CGFloat = 0.85   // thins the blur toward the Dock's translucency

    /// Sizing derived from the live Dock so the bars look like an extension of it.
    /// The pill is the icon row padded by `bandPad` on every side, plus an extra
    /// `pillExtra` on the screen-edge side so the rounded background reaches the
    /// edge like the Dock's — while the icons stay aligned with the Dock's.
    private struct Metrics {
        let icon: CGFloat       // icon footprint (square tile)
        let bandPad: CGFloat    // icon padding within the Dock band
        let pillExtra: CGFloat  // extra pill extension toward the screen edge
        let spacing: CGFloat    // gap between tiles
        var thickness: CGFloat { icon + 2 * bandPad + pillExtra }
        var corner: CGFloat { thickness * 0.30 }
    }

    func start() {
        setupStatusItem()
        refresh()
    }

    /// Screen layout changed: tear down and let the next refresh rebuild.
    func rebuildScreens() {
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        signatures.removeAll()
        refresh()
    }

    func refresh() {
        let screens = NSScreen.screens

        // Group windows by the display they sit on (max overlap).
        var byDisplay: [CGDirectDisplayID: [WinInfo]] = [:]
        for w in WindowScanner.scan() {
            guard let scr = Geometry.screen(for: w.bounds, screens: screens),
                  let id = displayID(of: scr) else { continue }
            byDisplay[id, default: []].append(w)
        }

        let dock = DockLocator.current(screens: screens)
        let dockDisplayID = dock.flatMap { displayID(of: $0.screen) }
        let edge = dock?.edge ?? .bottom
        let metrics = barMetrics(dock: dock)

        for screen in screens {
            guard let id = displayID(of: screen) else { continue }
            let wins = (byDisplay[id] ?? []).sorted { $0.windowID < $1.windowID }
            if wins.isEmpty { hidePanel(for: id); continue }

            // Show on every non-empty screen, including the Dock's. On the Dock's
            // screen, sit flush beside it (rect via AX); elsewhere centre.
            let placement: Placement
            if id == dockDisplayID, let rect = dock?.rect {
                placement = .besideDock(rect, edge)
            } else {
                placement = .center(edge)
            }
            showPanel(for: id, screen: screen, windows: wins, placement: placement, metrics: metrics)
        }

        // Drop panels for displays that no longer exist.
        let liveIDs = Set(screens.compactMap { displayID(of: $0) })
        for id in Array(panels.keys) where !liveIDs.contains(id) {
            panels[id]?.orderOut(nil)
            panels.removeValue(forKey: id)
            signatures.removeValue(forKey: id)
        }
    }

    // MARK: - Metrics

    private func barMetrics(dock: DockLocation?) -> Metrics {
        let icon = dock?.tileSize ?? 48
        let band = dock?.rect?.height ?? (icon + 14)        // Dock band (AX icon-box) height
        let bandPad = max(2, ((band - icon) / 2).rounded())
        return Metrics(icon: icon, bandPad: bandPad, pillExtra: 0,
                       spacing: max(2, (icon * 0.06).rounded()))
    }

    // MARK: - Panels

    private func showPanel(for id: CGDirectDisplayID, screen: NSScreen, windows: [WinInfo], placement: Placement, metrics: Metrics) {
        let edge = placement.edge
        let panel = panels[id] ?? makePanel()
        panels[id] = panel
        effectView(in: panel)?.layer?.cornerRadius = metrics.corner

        // Rebuild tiles only when the window set, edge, or Dock size changed.
        let signature = windows.map { String($0.windowID) }.joined(separator: ",")
            + "|\(edge)|\(Int(metrics.icon))|\(Int(metrics.thickness))"
        if signatures[id] != signature {
            rebuildTiles(in: panel, windows: windows, edge: edge, metrics: metrics)
            signatures[id] = signature
        }

        position(panel: panel, on: screen, windowCount: windows.count, placement: placement, metrics: metrics)
        if !panel.isVisible { panel.orderFront(nil) }
    }

    private func hidePanel(for id: CGDirectDisplayID) {
        panels[id]?.orderOut(nil)
        signatures.removeValue(forKey: id)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false   // the window shadow renders as a hard black ring on this small pill
        panel.hidesOnDeactivate = false

        // Blur background and icons are siblings, so the blur can be thinned with
        // alpha (closer to the Dock) WITHOUT fading the icons.
        let container = NSView()
        container.wantsLayer = true

        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.alphaValue = backgroundAlpha
        effect.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effect)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effect.topAnchor.constraint(equalTo: container.topAnchor),
            effect.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        panel.contentView = container
        return panel
    }

    private func effectView(in panel: NSPanel) -> NSVisualEffectView? {
        panel.contentView?.subviews.compactMap { $0 as? NSVisualEffectView }.first
    }

    private func rebuildTiles(in panel: NSPanel, windows: [WinInfo], edge: DockEdge, metrics: Metrics) {
        guard let container = panel.contentView else { return }
        container.subviews.filter { $0 is NSStackView }.forEach { $0.removeFromSuperview() }

        let horizontal = (edge == .bottom)
        let stack = NSStackView()
        stack.orientation = horizontal ? .horizontal : .vertical
        stack.spacing = metrics.spacing

        // Pad evenly by bandPad, but extend the screen-edge-facing side by
        // pillExtra so the rounded background reaches the edge like the Dock,
        // without moving the icons off the Dock's baseline.
        let p = metrics.bandPad, e = metrics.pillExtra
        var insets = NSEdgeInsets(top: p, left: p, bottom: p, right: p)
        switch edge {
        case .bottom: insets.bottom = p + e
        case .left:   insets.left = p + e
        case .right:  insets.right = p + e
        }
        stack.edgeInsets = insets
        stack.translatesAutoresizingMaskIntoConstraints = false

        for w in windows {
            let button = TileButton()
            button.win = w
            button.image = w.icon
            button.imageScaling = .scaleProportionallyUpOrDown
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(tileClicked(_:))
            button.toolTip = NSRunningApplication(processIdentifier: w.pid)?.localizedName
            button.menu = contextMenu(for: w)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: metrics.icon).isActive = true
            button.heightAnchor.constraint(equalToConstant: metrics.icon).isActive = true
            stack.addArrangedSubview(button)
        }

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    private enum Placement {
        case center(DockEdge)              // non-Dock screen: centre on the edge
        case besideDock(CGRect, DockEdge)  // Dock screen: Dock rect in Cocoa coords

        var edge: DockEdge {
            switch self {
            case .center(let e): return e
            case .besideDock(_, let e): return e
            }
        }
    }

    private func position(panel: NSPanel, on screen: NSScreen, windowCount: Int, placement: Placement, metrics: Metrics) {
        let edge = placement.edge
        let horizontal = (edge == .bottom)
        let n = CGFloat(max(windowCount, 1))
        let along = n * metrics.icon + (n - 1) * metrics.spacing + metrics.bandPad * 2
        let width = horizontal ? along : metrics.thickness
        let height = horizontal ? metrics.thickness : along

        let frame = screen.frame             // full frame (the Dock lives inside it)
        let vf = screen.visibleFrame         // excludes menu bar / Dock strip
        let extra = metrics.pillExtra
        var x: CGFloat = 0
        var y: CGFloat = 0

        switch placement {
        case .center(let e):
            switch e {
            case .bottom:
                y = vf.minY + edgeMargin
                x = vf.midX - width / 2
            case .left:
                x = vf.minX + edgeMargin
                y = vf.midY - height / 2
            case .right:
                x = vf.maxX - width - edgeMargin
                y = vf.midY - height / 2
            }

        case .besideDock(let dock, let e):
            // Flush beside the Dock; the pill's screen-edge side is offset by
            // `extra` so it reaches the edge while the icons stay on the Dock's
            // baseline. Fall back to "above / past the end" with no room.
            switch e {
            case .bottom:
                // Match the Dock's bottom margin: the Dock occupies a reserved
                // strip (frame.minY .. visibleFrame.minY); seat the bar in it the
                // same way rather than at the taller AX icon-box bottom.
                // Seat the pill in the Dock's reserved strip, 2px down from its top
                // edge so the bottom margin matches the Dock (band height, not bar).
                let reserved = vf.minY - frame.minY
                let bottomMargin = max(2, reserved - dock.height - 2)
                let besideX = dock.maxX + gap
                if besideX + width <= frame.maxX - edgeMargin {
                    x = besideX
                    y = frame.minY + bottomMargin
                } else {
                    x = max(frame.minX + edgeMargin, min(dock.maxX - width, frame.maxX - width - edgeMargin))
                    y = dock.maxY + gap
                }
            case .left:
                let belowY = dock.minY - gap - height
                if belowY >= frame.minY + edgeMargin {
                    x = dock.minX - extra
                    y = belowY
                } else {
                    x = dock.maxX + gap
                    y = dock.midY - height / 2
                }
            case .right:
                let belowY = dock.minY - gap - height
                if belowY >= frame.minY + edgeMargin {
                    x = dock.maxX - width + extra
                    y = belowY
                } else {
                    x = dock.minX - gap - width
                    y = dock.midY - height / 2
                }
            }
        }
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    // MARK: - Actions

    @objc private func tileClicked(_ sender: TileButton) {
        guard let win = sender.win else { return }
        WindowRaiser.raise(win)
    }

    private func contextMenu(for win: WinInfo) -> NSMenu {
        let menu = NSMenu()
        let name = NSRunningApplication(processIdentifier: win.pid)?.localizedName ?? "Application"
        let header = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let raise = NSMenuItem(title: "Bring to Front", action: #selector(menuRaise(_:)), keyEquivalent: "")
        raise.target = self
        raise.representedObject = win
        menu.addItem(raise)

        let hide = NSMenuItem(title: "Hide", action: #selector(menuHide(_:)), keyEquivalent: "")
        hide.target = self
        hide.representedObject = NSNumber(value: win.pid)
        menu.addItem(hide)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(menuQuit(_:)), keyEquivalent: "")
        quit.target = self
        quit.representedObject = NSNumber(value: win.pid)
        menu.addItem(quit)
        return menu
    }

    @objc private func menuRaise(_ sender: NSMenuItem) {
        if let win = sender.representedObject as? WinInfo { WindowRaiser.raise(win) }
    }

    @objc private func menuHide(_ sender: NSMenuItem) {
        if let n = sender.representedObject as? NSNumber {
            NSRunningApplication(processIdentifier: n.int32Value)?.hide()
        }
    }

    @objc private func menuQuit(_ sender: NSMenuItem) {
        if let n = sender.representedObject as? NSNumber {
            NSRunningApplication(processIdentifier: n.int32Value)?.terminate()
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "screendock") {
            img.isTemplate = true
            item.button?.image = img
        } else {
            item.button?.title = "▦"
        }

        let menu = NSMenu()
        let header = NSMenuItem(title: "screendock", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Helpers

    private func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
