import XCTest
@testable import DockSwitchCore

final class CodexWorkspacePolicyTests: XCTestCase {
    func testStartupAndDuplicateNotificationsDoNotOpenPane() {
        var tracker = CodexWorkspaceSwitchTracker<String>()
        XCTAssertFalse(tracker.observe(window: "w1", chat: "a", workspaceOpen: false))
        for _ in 0..<4 { XCTAssertFalse(tracker.observe(window: "w1", chat: "a", workspaceOpen: false)) }
        XCTAssertTrue(tracker.observe(window: "w1", chat: "b", workspaceOpen: false))
        for _ in 0..<4 { XCTAssertFalse(tracker.observe(window: "w1", chat: "b", workspaceOpen: false)) }
    }

    func testOpenWorkspaceNeverAddsTabAndManualCloseStaysClosed() {
        var tracker = CodexWorkspaceSwitchTracker<Int>()
        XCTAssertFalse(tracker.observe(window: 1, chat: 10, workspaceOpen: true))
        XCTAssertFalse(tracker.observe(window: 1, chat: 20, workspaceOpen: true))
        XCTAssertFalse(tracker.observe(window: 1, chat: 20, workspaceOpen: false))
        XCTAssertTrue(tracker.observe(window: 1, chat: 10, workspaceOpen: false))
    }

    func testIdentityNotTitleHandlesRenameAndSameNameChats() {
        var tracker = CodexWorkspaceSwitchTracker<String>()
        _ = tracker.observe(window: "w", chat: "toolbar-a", workspaceOpen: false)
        // Rename/streaming title noise does not replace the view identity.
        XCTAssertFalse(tracker.observe(window: "w", chat: "toolbar-a", workspaceOpen: false))
        // Different views can have identical human-readable titles.
        XCTAssertTrue(tracker.observe(window: "w", chat: "toolbar-b", workspaceOpen: false))
    }

    func testFirstOpenAfterStartingOutsideChat() {
        var tracker = CodexWorkspaceSwitchTracker<Int>()
        tracker.startOutsideChat()
        XCTAssertTrue(tracker.observe(window: 1, chat: 10, workspaceOpen: false))
        XCTAssertFalse(tracker.observe(window: 1, chat: 10, workspaceOpen: false))
        tracker.reset()
        tracker.startOutsideChat()
        XCTAssertFalse(tracker.observe(window: 1, chat: 20, workspaceOpen: true))
    }

    func testWindowSwitchAndRestartBaseline() {
        var tracker = CodexWorkspaceSwitchTracker<Int>()
        _ = tracker.observe(window: 1, chat: 10, workspaceOpen: false)
        XCTAssertTrue(tracker.observe(window: 2, chat: 20, workspaceOpen: false))
        XCTAssertTrue(tracker.observe(window: 1, chat: 10, workspaceOpen: false))
        tracker.reset()
        XCTAssertFalse(tracker.observe(window: 1, chat: 10, workspaceOpen: false))
        XCTAssertTrue(tracker.observe(window: 1, chat: 30, workspaceOpen: false))
    }
}
