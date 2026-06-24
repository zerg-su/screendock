import AppKit
import ApplicationServices
import CoreGraphics

enum DockEdge { case bottom, left, right }

struct DockLocation {
    let screen: NSScreen
    let edge: DockEdge
    /// The Dock's visible tile area in Cocoa (bottom-left) coordinates, when it
    /// can be read via Accessibility. Lets the bar sit flush beside the Dock
    /// instead of guessing. nil if Accessibility is not granted.
    let rect: CGRect?
    /// Configured Dock icon size (points). Tracks the System Settings slider so
    /// the bar's icons scale with the Dock.
    let tileSize: CGFloat
}

/// Finds which display currently hosts the native Dock, its edge, and (via AX)
/// the exact rect of its tile area.
///
/// On modern macOS the Dock's own window (owner "Dock", layer >= 0) spans the
/// FULL screen it lives on — it is not a thin strip. Per-display wallpaper
/// windows are also owned by "Dock" but sit at a deeply negative layer, so a
/// `layer >= 0` filter isolates the real Dock window for screen detection.
enum DockLocator {
    static func current(screens: [NSScreen]) -> DockLocation? {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        var best: (screen: NSScreen, area: CGFloat)?
        for w in raw {
            guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "Dock" else { continue }
            guard let layer = w[kCGWindowLayer as String] as? Int, layer >= 0 else { continue } // skip wallpaper
            guard let rect = Geometry.boundsRect(w), let scr = Geometry.screen(for: rect, screens: screens) else { continue }
            let area = rect.width * rect.height
            if best == nil || area > best!.area { best = (scr, area) }
        }
        guard let best else { return nil }

        var cocoaRect: CGRect?
        if let pid = dockPID(), let cg = dockListRect(pid: pid) {
            let primaryH = Geometry.primaryHeight(screens)
            cocoaRect = CGRect(x: cg.minX, y: primaryH - cg.maxY, width: cg.width, height: cg.height)
        }
        return DockLocation(screen: best.screen, edge: dockEdge(), rect: cocoaRect, tileSize: dockTileSize())
    }

    private static func dockTileSize() -> CGFloat {
        let n = UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "tilesize") as? NSNumber
        return CGFloat(n?.doubleValue ?? 48)
    }

    private static func dockPID() -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.apple.dock" }?
            .processIdentifier
    }

    /// The Dock's visible tile area via Accessibility (the Dock app's `AXList`).
    /// Returns CG (top-left) coordinates. Requires Accessibility; nil otherwise.
    private static func dockListRect(pid: pid_t) -> CGRect? {
        guard Permissions.isTrusted else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        for child in AXUtil.children(of: axApp) where AXUtil.role(of: child) == (kAXListRole as String) {
            if let f = AXUtil.frame(of: child) { return f }
        }
        return nil
    }

    private static func dockEdge() -> DockEdge {
        switch UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") {
        case "left": return .left
        case "right": return .right
        default: return .bottom
        }
    }
}
