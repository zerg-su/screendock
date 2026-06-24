import AppKit
import ApplicationServices

enum Permissions {
    /// Prompts for Accessibility once. Non-blocking: window enumeration via
    /// CGWindowList needs no permission, so bars appear regardless; only the
    /// click-to-raise action needs Accessibility.
    static func ensureAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if !trusted {
            let msg = """
            [screendock] Accessibility permission is required to focus a window on click.
            Grant it: System Settings -> Privacy & Security -> Accessibility
            Add the binary: .build/debug/screendock
            Bars still appear without it, but clicking a tile only brings the app
            forward (not the specific window) until the permission is granted.

            """
            FileHandle.standardError.write(Data(msg.utf8))
        }
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }
}
