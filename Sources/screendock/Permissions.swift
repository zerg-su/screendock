import AppKit
import ApplicationServices

enum Permissions {
    /// The global window overview and exact-window activation need Accessibility.
    /// The original per-display icon bars still appear without it.
    static func ensureAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if !trusted {
            let msg = """
            [screendock] Accessibility permission is required for the all-windows overview.
            Grant it: System Settings -> Privacy & Security -> Accessibility
            Add the app you launched, then return to its overview and click Refresh.
            Screen Recording is not required.

            """
            FileHandle.standardError.write(Data(msg.utf8))
        }
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }
}
