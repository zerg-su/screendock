import Foundation

public struct WindowID: Hashable {
    public let pid: Int32
    public let token: UInt64

    public init(pid: Int32, token: UInt64) {
        self.pid = pid
        self.token = token
    }
}

public struct WindowEntry: Hashable {
    public let id: WindowID
    public let appName: String
    public let title: String
    public let isMinimized: Bool
    public let isHidden: Bool
    public let isFullScreen: Bool

    public init(id: WindowID, appName: String, title: String,
                isMinimized: Bool = false, isHidden: Bool = false, isFullScreen: Bool = false) {
        self.id = id
        self.appName = appName
        self.title = title
        self.isMinimized = isMinimized
        self.isHidden = isHidden
        self.isFullScreen = isFullScreen
    }
}

public enum WindowIndex {
    public static func search(_ entries: [WindowEntry], query: String) -> [WindowEntry] {
        func normalized(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive],
                         locale: Locale(identifier: "en_US_POSIX"))
        }
        let words = normalized(query).split(whereSeparator: \.isWhitespace)
        var seen = Set<WindowID>()
        return entries.filter { entry in
            guard seen.insert(entry.id).inserted else { return false }
            let text = normalized(entry.appName + " " + entry.title)
            return words.allSatisfy { text.contains($0) }
        }.sorted { a, b in
            let appOrder = a.appName.localizedStandardCompare(b.appName)
            if appOrder != .orderedSame { return appOrder == .orderedAscending }
            let titleOrder = a.title.localizedStandardCompare(b.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            if a.id.pid != b.id.pid { return a.id.pid < b.id.pid }
            return a.id.token < b.id.token
        }
    }

    public static func selection(previous: WindowID?, in entries: [WindowEntry]) -> WindowID? {
        previous.flatMap { id in entries.first(where: { $0.id == id })?.id } ?? entries.first?.id
    }
}

public protocol WindowActionBackend {
    func isRunning(_ pid: Int32) -> Bool
    func unhide(_ pid: Int32) -> Bool
    func restore(_ id: WindowID) -> Bool
    func focus(_ id: WindowID) -> Bool
}

public enum WindowActivationResult: Equatable {
    case focused, windowGone, appUnavailable, restoreFailed, focusFailed
}

public enum WindowRaiseStatus { case raised, temporarilyBusy, unavailable }

public enum WindowRaiseRetry {
    public static func run(attempt: () -> WindowRaiseStatus, pause: () -> Void) -> Bool {
        for index in 0..<5 {
            switch attempt() {
            case .raised: return true
            case .unavailable: return false
            case .temporarilyBusy:
                if index < 4 { pause() }
            }
        }
        return false
    }
}

public enum WindowActions {
    public static func activate(_ id: WindowID, in entries: [WindowEntry],
                                using backend: WindowActionBackend) -> WindowActivationResult {
        guard let entry = entries.first(where: { $0.id == id }) else { return .windowGone }
        guard backend.isRunning(id.pid) else { return .appUnavailable }
        if entry.isHidden && !backend.unhide(id.pid) { return .appUnavailable }
        if entry.isMinimized && !backend.restore(id) { return .restoreFailed }
        return backend.focus(id) ? .focused : .focusFailed
    }
}
