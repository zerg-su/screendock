import AppKit
import CoreGraphics

/// One on-screen window.
struct WinInfo {
    let windowID: CGWindowID   // kCGWindowNumber, stable & unique
    let pid: pid_t             // kCGWindowOwnerPID
    let bounds: CGRect         // kCGWindowBounds, global, top-left origin
    let icon: NSImage?         // owning app icon (cached by pid)
}

/// Coordinate helpers shared between the window scanner and the Dock locator.
///
/// CG / Accessibility coordinates: origin at the top-left of the *primary*
/// screen, Y growing downward. `NSScreen.frame`: origin bottom-left, Y growing
/// upward, primary screen anchored at (0, 0).
enum Geometry {
    static func boundsRect(_ window: [String: Any]) -> CGRect? {
        guard let d = window[kCGWindowBounds as String] as? [String: NSNumber],
              let x = d["X"]?.doubleValue, let y = d["Y"]?.doubleValue,
              let w = d["Width"]?.doubleValue, let h = d["Height"]?.doubleValue
        else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    static func primaryHeight(_ screens: [NSScreen]) -> CGFloat {
        let primary = screens.first(where: { $0.frame.origin == .zero }) ?? screens.first
        return primary?.frame.height ?? 0
    }

    /// A screen's frame expressed in CG (top-left origin) coordinates.
    static func cgRect(of screen: NSScreen, primaryHeight: CGFloat) -> CGRect {
        let f = screen.frame
        return CGRect(x: f.minX, y: primaryHeight - f.minY - f.height, width: f.width, height: f.height)
    }

    /// The screen that overlaps `rect` (a CG/top-left rect) the most.
    static func screen(for rect: CGRect, screens: [NSScreen]) -> NSScreen? {
        let primaryH = primaryHeight(screens)
        var best: NSScreen?
        var bestArea: CGFloat = -1
        for screen in screens {
            let cg = cgRect(of: screen, primaryHeight: primaryH)
            let inter = cg.intersection(rect)
            let area = inter.isNull ? 0 : inter.width * inter.height
            if area > bestArea { bestArea = area; best = screen }
        }
        return best
    }
}

enum WindowScanner {
    private static var iconCache: [pid_t: NSImage] = [:]
    private static let ignoredOwners: Set<String> = [
        "Dock", "Window Server", "WindowServer", "Control Center",
        "Notification Center", "Spotlight", "screendock"
    ]

    /// On-screen, normal-layer application windows of the current Space.
    /// `.optionOnScreenOnly` already excludes minimized windows and windows on
    /// other Spaces, so no extra filtering for those is needed.
    static func scan() -> [WinInfo] {
        let myPid = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var result: [WinInfo] = []
        for w in raw {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            let alpha = (w[kCGWindowAlpha as String] as? Double) ?? 1.0
            if alpha <= 0.01 { continue }
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != myPid else { continue }
            if let owner = w[kCGWindowOwnerName as String] as? String, ignoredOwners.contains(owner) { continue }
            guard let id = w[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let rect = Geometry.boundsRect(w), rect.width >= 50, rect.height >= 50 else { continue }

            result.append(WinInfo(windowID: id, pid: pid, bounds: rect, icon: icon(for: pid)))
        }
        return result
    }

    private static func icon(for pid: pid_t) -> NSImage? {
        if let cached = iconCache[pid] { return cached }
        guard let app = NSRunningApplication(processIdentifier: pid), let img = app.icon else { return nil }
        iconCache[pid] = img
        return img
    }
}
