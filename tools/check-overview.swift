import AppKit
import ApplicationServices
import WindowCore

private var fixtureWindows: [NSWindow] = []
private var fixtureApp: NSRunningApplication?
private var fixtureTimer: Timer?

@main
struct OverviewCheck {
    static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--fixture") {
            app.setActivationPolicy(.regular)
            DispatchQueue.main.async { makeFixtures() }
            app.run()
            return
        }
        guard Permissions.isTrusted else {
            print("SKIP: the terminal needs its existing Accessibility grant for this live check.")
            exit(77)
        }
        app.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("screendock-overview-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let bundle = output.appendingPathComponent("ScreenDock Fixture.app")
        let executable = bundle.appendingPathComponent("Contents/MacOS/check-overview")
        try! FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! FileManager.default.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[0]), to: executable)
        let info: [String: Any] = ["CFBundleIdentifier": "su.zerg.screendock.fixture",
                                   "CFBundleName": "ScreenDock Fixture", "CFBundleExecutable": "check-overview",
                                   "CFBundlePackageType": "APPL", "LSUIElement": false]
        let plist = try! PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try! plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--deep", "--sign", "-", "--identifier", "su.zerg.screendock.fixture", bundle.path]
        try! sign.run()
        sign.waitUntilExit()
        guard sign.terminationStatus == 0 else { print("FAIL: fixture signing"); exit(1) }
        // Always reclaim only the process created by this check, including a timeout.
        DispatchQueue.main.asyncAfter(deadline: .now() + 35) {
            fixtureApp?.terminate()
            print("FAIL: live check timed out")
            exit(1)
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = ["--fixture", output.appendingPathComponent("ready.json").path]
        NSWorkspace.shared.openApplication(at: bundle, configuration: config) { child, error in
            guard let child else { print("FAIL: fixture launch: \(String(describing: error))"); exit(1) }
            fixtureApp = child
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try check(child: child, output: output)
                    DispatchQueue.main.async {
                        child.terminate()
                        print("PASS: live overview check. Evidence: \(output.path)")
                        exit(0)
                    }
                } catch {
                    DispatchQueue.main.async {
                        child.terminate()
                        print("FAIL: \(error)")
                        exit(1)
                    }
                }
            }
        }
        app.run()
    }

    private static func makeFixtures() {
        let hideRequest = URL(fileURLWithPath: CommandLine.arguments.last!).deletingLastPathComponent().appendingPathComponent("hide")
        fixtureTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if FileManager.default.fileExists(atPath: hideRequest.path) {
                try? FileManager.default.removeItem(at: hideRequest)
                NSApp.hide(nil) // Same operation as the fixture user's Command-H.
            }
        }
        for (index, name) in ["Alpha — свёрнутая презентация", "Beta — нужная презентация", "Normal — документ", "Fullscreen — отдельное пространство"].enumerated() {
            let window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 680, height: 440),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "ScreenDock Fixture \(name)"
            window.collectionBehavior = [.fullScreenPrimary]
            let label = NSTextField(labelWithString: "Временное тестовое окно ScreenDock. Закроется автоматически.")
            label.frame = NSRect(x: 24, y: 200, width: 620, height: 32)
            window.contentView?.addSubview(label)
            window.makeKeyAndOrderFront(nil)
            fixtureWindows.append(window)
            if index < 2 { window.miniaturize(nil) }
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            fixtureWindows.last?.toggleFullScreen(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let ids = Dictionary(uniqueKeysWithValues: fixtureWindows.map { ($0.title, $0.windowNumber) })
            let data = try! JSONSerialization.data(withJSONObject: ids, options: [.sortedKeys])
            try! data.write(to: URL(fileURLWithPath: CommandLine.arguments.last!))
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw NSError(domain: "OverviewCheck", code: 1,
                                               userInfo: [NSLocalizedDescriptionKey: message]) }
        print("PASS:", message)
    }

    private static func check(child: NSRunningApplication, output: URL) throws {
        let ready = output.appendingPathComponent("ready.json")
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: ready.path) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        let ids = try JSONSerialization.jsonObject(with: Data(contentsOf: ready)) as! [String: Int]
        let catalog = AccessibleWindows()
        let runningApps = DispatchQueue.main.sync { AccessibleWindows.applications() }
        try require(runningApps.contains { $0.pid == child.processIdentifier }, "fixture is a discoverable regular app")
        let app = runningApps.first { $0.pid == child.processIdentifier }!
        let snapshot = catalog.scan(applications: [app])
        try require(!snapshot.needsPermission && snapshot.entries.count == 4, "AX lists all four fixture windows")
        let alpha = snapshot.entries.first { $0.title.contains("Alpha") }!
        let beta = snapshot.entries.first { $0.title.contains("Beta") }!
        let full = snapshot.entries.first { $0.title.contains("Fullscreen") }!
        try require(alpha.isMinimized && beta.isMinimized, "minimized windows are included")
        try require(full.isFullScreen, "fullscreen window is included")
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let visibleIDs = Set(onScreen.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue })
        let normalID = ids.first { $0.key.contains("Normal") }!.value
        let fullscreenID = ids.first { $0.key.contains("Fullscreen") }!.value
        try require(visibleIDs.contains(fullscreenID) && !visibleIDs.contains(normalID),
                    "AX includes normal window on a different Space from the visible fullscreen")
        let again = catalog.scan(applications: [app])
        try require(Set(snapshot.entries.map(\.id)) == Set(again.entries.map(\.id)), "window identities survive refresh")
        let betaResult = WindowActions.activate(beta.id, in: again.entries, using: catalog)
        try require(betaResult == .focused,
                    "activates exact minimized window from fullscreen Space")
        Thread.sleep(forTimeInterval: 0.8)
        try require(focusedTitle(pid: child.processIdentifier) == beta.title, "Beta is the focused window")
        let restored = catalog.scan(applications: [app])
        try require(restored.entries.first { $0.id == beta.id }?.isMinimized == false,
                    "Beta is restored")
        try require(restored.entries.first { $0.id == alpha.id }?.isMinimized == true,
                    "Alpha remains minimized")
        try Data().write(to: output.appendingPathComponent("hide"))
        let hideDeadline = Date().addingTimeInterval(2)
        while !child.isHidden && Date() < hideDeadline { Thread.sleep(forTimeInterval: 0.1) }
        try require(child.isHidden, "fixture app hides itself as with Command-H")
        let hiddenSnapshot = catalog.scan(applications: [WindowApplication(pid: child.processIdentifier,
                                                                           name: app.name, isHidden: true)])
        try require(hiddenSnapshot.entries.count == 4, "hidden app windows remain in the overview")
        let alphaResult = WindowActions.activate(alpha.id, in: hiddenSnapshot.entries, using: catalog)
        try require(alphaResult == .focused,
                    "unhides app and restores selected Alpha")
        Thread.sleep(forTimeInterval: 0.5)
        try require(focusedTitle(pid: child.processIdentifier) == alpha.title, "Alpha is the focused window")
        DispatchQueue.main.sync {
            do {
                try WindowOverview().renderPreview(entries: snapshot.entries,
                                                   to: output.appendingPathComponent("overview.png"))
            } catch { print("FAIL: UI render: \(error)") }
        }
        try require(FileManager.default.fileExists(atPath: output.appendingPathComponent("overview.png").path),
                    "overview UI renders fixture rows")
        let evidence = "AX windows=4; minimized=2; fullscreen=1; off-Space normal=1; exact restore/focus=PASS; hidden restore=PASS\n"
        try evidence.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }

    private static func focusedTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXTitleAttribute as CFString, &title)
        return title as? String
    }

}
