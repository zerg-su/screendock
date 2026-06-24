import AppKit
import ApplicationServices

/// Brings a specific window to the front. Accessibility is touched ONLY here
/// (on click) — never on the periodic scan — so a busy/unresponsive app can
/// never freeze the bars.
enum WindowRaiser {
    static func raise(_ win: WinInfo) {
        let runningApp = NSRunningApplication(processIdentifier: win.pid)
        if #available(macOS 14.0, *) {
            runningApp?.activate()
        } else {
            runningApp?.activate(options: [])
        }

        // Without Accessibility we can only bring the app forward (its frontmost
        // window), not the specific target window.
        guard Permissions.isTrusted else { return }

        let axApp = AXUIElementCreateApplication(win.pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25) // guard against blocking on a busy app

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }

        // Match the CGWindow to an AX window by position/size. At click time the
        // coordinates coincide exactly, so the closest match is the right one.
        var matched: AXUIElement?
        var bestDelta = CGFloat.greatestFiniteMagnitude
        for axWin in windows {
            guard let frame = AXUtil.frame(of: axWin) else { continue }
            let dx: CGFloat = abs(frame.minX - win.bounds.minX)
            let dy: CGFloat = abs(frame.minY - win.bounds.minY)
            let dw: CGFloat = abs(frame.width - win.bounds.width)
            let dh: CGFloat = abs(frame.height - win.bounds.height)
            let delta = dx + dy + dw + dh
            if delta < bestDelta { bestDelta = delta; matched = axWin }
        }

        guard let target = matched, bestDelta < 20 else { return }
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
}
