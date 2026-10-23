import AppKit
import ApplicationServices
import WindowCore

struct WindowApplication {
    let pid: pid_t
    let name: String
    let isHidden: Bool
}

struct WindowSnapshot {
    let entries: [WindowEntry]
    let needsPermission: Bool
    let unavailableApps: Int
}

/// AXWindows includes windows on other Spaces and minimized windows. All AX
/// traffic runs on one worker queue, with per-call and whole-scan bounds.
/// The old per-display bars retain their cheap, permission-free CG scan.
final class AccessibleWindows: WindowActionBackend {
    private let queue = DispatchQueue(label: "su.zerg.screendock.window-catalog", qos: .userInitiated)
    private var references: [WindowID: AXUIElement] = [:]
    private var entries: [WindowEntry] = []
    private var nextToken: UInt64 = 0

    static func applications() -> [WindowApplication] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, !app.isTerminated,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
            return WindowApplication(pid: app.processIdentifier,
                                     name: app.localizedName ?? "Приложение",
                                     isHidden: app.isHidden)
        }.sorted { $0.pid < $1.pid }
    }

    func refresh(completion: @escaping (WindowSnapshot) -> Void) {
        let apps = Self.applications()
        queue.async {
            let snapshot = self.scan(applications: apps)
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    // Internal synchronous seam for the bounded live adapter check. Call on a
    // worker while the main run loop is running, as refresh() does.
    func scan(applications: [WindowApplication]) -> WindowSnapshot {
        guard Permissions.isTrusted else {
            entries = []
            references = [:]
            return WindowSnapshot(entries: [], needsPermission: true, unavailableApps: 0)
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 6
        var updated: [WindowEntry] = []
        var handles: [WindowID: AXUIElement] = [:]
        var unavailable = 0

        func retainPrevious(_ pid: pid_t) {
            for entry in entries where entry.id.pid == pid {
                if let handle = references[entry.id] {
                    updated.append(entry)
                    handles[entry.id] = handle
                }
            }
        }

        for app in applications {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                unavailable += 1
                retainPrevious(app.pid)
                continue
            }
            let axApp = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(axApp, 0.15)
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
            guard error == .success, let windows = value as? [AXUIElement] else {
                if error != .attributeUnsupported && error != .noValue {
                    unavailable += 1
                    retainPrevious(app.pid)
                }
                continue
            }
            for (index, window) in windows.enumerated() {
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    unavailable += 1
                    // Keep the previous handles for this app on a partial scan.
                    retainPrevious(app.pid)
                    break
                }
                AXUIElementSetMessagingTimeout(window, 0.15)
                guard AXUtil.role(of: window) == (kAXWindowRole as String) else { continue }
                let previous = references.first { $0.key.pid == app.pid && CFEqual($0.value, window) }?.key
                let id: WindowID
                if let previous { id = previous } else {
                    nextToken += 1
                    id = WindowID(pid: app.pid, token: nextToken)
                }
                let title = Self.title(of: window, fallback: "Окно без названия \(index + 1)")
                let entry = WindowEntry(id: id, appName: app.name, title: title,
                                        isMinimized: Self.flag(kAXMinimizedAttribute, of: window),
                                        isHidden: app.isHidden,
                                        isFullScreen: Self.flag("AXFullScreen", of: window))
                updated.append(entry)
                handles[id] = window
            }
            // AppKit can omit fullscreen windows on another Space from
            // AXWindows. Retain only known, still-valid fullscreen elements.
            // Ordinary closed windows are never kept through this fallback.
            for old in entries where old.id.pid == app.pid && old.isFullScreen && handles[old.id] == nil {
                guard ProcessInfo.processInfo.systemUptime < deadline,
                      let window = references[old.id],
                      AXUtil.role(of: window) == (kAXWindowRole as String),
                      Self.flag("AXFullScreen", of: window) else { continue }
                updated.append(WindowEntry(id: old.id, appName: app.name,
                                           title: Self.title(of: window, fallback: old.title),
                                           isMinimized: Self.flag(kAXMinimizedAttribute, of: window),
                                           isHidden: app.isHidden, isFullScreen: true))
                handles[old.id] = window
            }
        }
        entries = WindowIndex.search(updated, query: "")
        references = handles
        return WindowSnapshot(entries: entries, needsPermission: false, unavailableApps: unavailable)
    }

    private static func string(_ attribute: String, of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func title(of window: AXUIElement, fallback: String) -> String {
        if let title = string(kAXTitleAttribute, of: window) { return title }
        if let document = string(kAXDocumentAttribute, of: window),
           let url = URL(string: document), !url.lastPathComponent.isEmpty {
            return url.lastPathComponent
        }
        return fallback
    }

    private static func flag(_ attribute: String, of window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success else { return false }
        return (value as? NSNumber)?.boolValue ?? false
    }

    func activate(_ id: WindowID, completion: @escaping (WindowActivationResult) -> Void) {
        queue.async {
            let result = WindowActions.activate(id, in: self.entries, using: self)
            DispatchQueue.main.async { completion(result) }
        }
    }

    func isRunning(_ pid: Int32) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return !app.isTerminated
    }

    func unhide(_ pid: Int32) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        if !app.isHidden || app.unhide() { return true }
        // Some apps reject the NSRunningApplication request while still
        // exposing the writable public AXHidden attribute.
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.15)
        return AXUIElementSetAttributeValue(element, kAXHiddenAttribute as CFString, kCFBooleanFalse) == .success
    }

    func restore(_ id: WindowID) -> Bool {
        guard let window = references[id] else { return false }
        return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success
    }

    func focus(_ id: WindowID) -> Bool {
        guard let window = references[id],
              let app = NSRunningApplication(processIdentifier: id.pid) else { return false }
        if app.isHidden && !unhide(id.pid) { return false }
        // Refresh the state: a user may minimize a window after our last scan.
        if Self.flag(kAXMinimizedAttribute, of: window) && !restore(id) { return false }
        let axApp = AXUIElementCreateApplication(id.pid)
        AXUIElementSetMessagingTimeout(axApp, 0.15)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, window)
        let activated: Bool = DispatchQueue.main.sync {
            if #available(macOS 14.0, *) {
                NSApp.yieldActivation(to: app)
                return app.activate(from: .current, options: [])
            }
            return app.activate(options: [])
        }
        // AXRaise can return cannotComplete while macOS animates a Space
        // transition after activation/unminimizing. Retry only that transient
        // result, on the worker, with five 150 ms calls and four 50 ms pauses.
        let raised = WindowRaiseRetry.run(attempt: {
            switch AXUIElementPerformAction(window, kAXRaiseAction as CFString) {
            case .success: return .raised
            case .cannotComplete: return .temporarilyBusy
            default: return .unavailable
            }
        }, pause: { Thread.sleep(forTimeInterval: 0.05) })
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        return activated && raised
    }
}
