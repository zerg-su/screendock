import AppKit

// Entry point. Top-level executable code lives only in this file.
// Accessory policy: no Dock icon, and our own windows are excluded from the
// regular-app scan in WindowScanner.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = BarController()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Permissions.ensureAccessibility()
        controller.start()

        // Periodic refresh: there is no public notification for "window moved /
        // resized" or "Dock migrated to another display", so we poll.
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.controller.refresh()
        }
        timer?.tolerance = 0.2

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            ws.addObserver(self, selector: #selector(refreshNow), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func refreshNow() { controller.refresh() }
    @objc private func screensChanged() { controller.rebuildScreens() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
