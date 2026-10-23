import XCTest
@testable import WindowCore

final class WindowCatalogTests: XCTestCase {
    private func window(_ token: UInt64, app: String = "Keynote", title: String,
                        minimized: Bool = false, hidden: Bool = false,
                        fullScreen: Bool = false) -> WindowEntry {
        WindowEntry(id: WindowID(pid: 42, token: token), appName: app, title: title,
                    isMinimized: minimized, isHidden: hidden, isFullScreen: fullScreen)
    }

    func testSearchMatchesAllWordsAcrossAppAndTitleIgnoringCaseAndAccents() {
        let café = window(1, app: "Pages", title: "Café annual report")
        let other = window(2, app: "Keynote", title: "Annual report")
        XCTAssertEqual(WindowIndex.search([other, café], query: "  CAFE   pages "), [café])
        XCTAssertEqual(WindowIndex.search([café, other], query: "pages missing"), [])
    }

    func testRussianSearchAndWhitespace() {
        let target = window(1, title: "Отчёт за октябрь")
        XCTAssertEqual(WindowIndex.search([target], query: "ОКТЯБРЬ keynote"), [target])
        XCTAssertEqual(WindowIndex.search([target], query: " \n\t "), [target])
    }

    func testIncludesMinimizedHiddenAndFullScreenWindows() {
        let windows = [window(1, title: "A", minimized: true),
                       window(2, title: "B", hidden: true),
                       window(3, title: "C", fullScreen: true)]
        XCTAssertEqual(WindowIndex.search(windows, query: ""), windows)
    }

    func testDeduplicatesIdentityButKeepsDifferentWindowsWithSameTitle() {
        let first = window(1, title: "Untitled")
        let second = window(2, title: "Untitled")
        XCTAssertEqual(WindowIndex.search([first, second, first], query: ""), [first, second])
    }

    func testSortsByApplicationThenDocumentWithStableIdentityTieBreak() {
        let z = window(1, app: "Safari", title: "Z")
        let b = window(4, app: "Keynote", title: "B")
        let a2 = window(3, app: "Keynote", title: "A")
        let a1 = window(2, app: "Keynote", title: "A")
        XCTAssertEqual(WindowIndex.search([z, b, a2, a1], query: ""), [a1, a2, b, z])
    }

    func testSelectionSurvivesRefreshAndFallsBackWhenWindowDisappears() {
        let a = window(1, title: "A"), b = window(2, title: "B")
        XCTAssertEqual(WindowIndex.selection(previous: b.id, in: [a, b]), b.id)
        XCTAssertEqual(WindowIndex.selection(previous: b.id, in: [a]), a.id)
        XCTAssertNil(WindowIndex.selection(previous: b.id, in: []))
    }

    func testRestoresAndFocusesExactMinimizedWindowWithoutTouchingSibling() {
        let sibling = window(1, title: "Untitled", minimized: true)
        let target = window(2, title: "Untitled", minimized: true, hidden: true)
        let backend = Desktop(windows: [sibling, target], hidden: true)
        XCTAssertEqual(WindowActions.activate(target.id, in: [sibling, target], using: backend), .focused)
        XCTAssertFalse(backend.hidden)
        XCTAssertFalse(backend.minimized.contains(target.id))
        XCTAssertTrue(backend.minimized.contains(sibling.id))
        XCTAssertEqual(backend.frontmost, target.id)
    }

    func testMissingWindowAndExitedApplicationDoNotFocusAnotherWindow() {
        let target = window(1, title: "A")
        let backend = Desktop(windows: [target])
        XCTAssertEqual(WindowActions.activate(target.id, in: [], using: backend), .windowGone)
        XCTAssertNil(backend.frontmost)
        backend.running = false
        XCTAssertEqual(WindowActions.activate(target.id, in: [target], using: backend), .appUnavailable)
        XCTAssertNil(backend.frontmost)
    }

    func testRestoreOrFocusFailureIsReportedInsteadOfClaimingSuccess() {
        let target = window(1, title: "A", minimized: true)
        let backend = Desktop(windows: [target])
        backend.canRestore = false
        XCTAssertEqual(WindowActions.activate(target.id, in: [target], using: backend), .restoreFailed)
        XCTAssertNil(backend.frontmost)
        backend.canRestore = true
        backend.canFocus = false
        XCTAssertEqual(WindowActions.activate(target.id, in: [target], using: backend), .focusFailed)
        XCTAssertNil(backend.frontmost)
    }

    func testNormalWindowDoesNotRequireRestorePermission() {
        let target = window(1, title: "A")
        let backend = Desktop(windows: [target])
        backend.canRestore = false
        XCTAssertEqual(WindowActions.activate(target.id, in: [target], using: backend), .focused)
        XCTAssertEqual(backend.frontmost, target.id)
    }

    func testUnhideFailureDoesNotFocusOrRestoreTheHiddenWindow() {
        let target = window(1, title: "A", minimized: true, hidden: true)
        let backend = Desktop(windows: [target], hidden: true)
        backend.canUnhide = false
        XCTAssertEqual(WindowActions.activate(target.id, in: [target], using: backend), .appUnavailable)
        XCTAssertTrue(backend.hidden)
        XCTAssertTrue(backend.minimized.contains(target.id))
        XCTAssertNil(backend.frontmost)
    }

    func testRaiseRetriesTransientSpaceTransitionAndStopsAfterSuccess() {
        var attempts = 0, pauses = 0
        let result = WindowRaiseRetry.run(attempt: {
            attempts += 1
            return attempts < 3 ? .temporarilyBusy : .raised
        }, pause: { pauses += 1 })
        XCTAssertTrue(result)
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(pauses, 2)
    }

    func testRaiseRetryIsBoundedAndDoesNotRetryUnavailableWindows() {
        var attempts = 0, pauses = 0
        XCTAssertFalse(WindowRaiseRetry.run(attempt: {
            attempts += 1
            return .temporarilyBusy
        }, pause: { pauses += 1 }))
        XCTAssertEqual(attempts, 5)
        XCTAssertEqual(pauses, 4)
        attempts = 0
        XCTAssertFalse(WindowRaiseRetry.run(attempt: {
            attempts += 1
            return .unavailable
        }, pause: { XCTFail("Permanent failure must not wait") }))
        XCTAssertEqual(attempts, 1)
    }
}

private final class Desktop: WindowActionBackend {
    var running = true
    var hidden: Bool
    var minimized: Set<WindowID>
    var frontmost: WindowID?
    var canRestore = true
    var canFocus = true
    var canUnhide = true
    private let ids: Set<WindowID>

    init(windows: [WindowEntry], hidden: Bool = false) {
        self.hidden = hidden
        minimized = Set(windows.filter(\.isMinimized).map(\.id))
        ids = Set(windows.map(\.id))
    }

    func isRunning(_ pid: Int32) -> Bool { running }
    func unhide(_ pid: Int32) -> Bool {
        guard canUnhide else { return false }
        hidden = false
        return true
    }
    func restore(_ id: WindowID) -> Bool {
        guard canRestore, ids.contains(id) else { return false }
        minimized.remove(id)
        return true
    }
    func focus(_ id: WindowID) -> Bool {
        guard canFocus, ids.contains(id), !hidden, !minimized.contains(id) else { return false }
        frontmost = id
        return true
    }
}
