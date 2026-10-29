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

    func testIdentityNotTitleHandlesUnchangedViewAndSameNameChats() {
        var tracker = CodexWorkspaceSwitchTracker<String>()
        _ = tracker.observe(window: "w", chat: "toolbar-a", workspaceOpen: false)
        // Title noise with an unchanged view must not trigger a press.
        XCTAssertFalse(tracker.observe(window: "w", chat: "toolbar-a", workspaceOpen: false))
        // Different views can have identical human-readable titles.
        XCTAssertTrue(tracker.observe(window: "w", chat: "toolbar-b", workspaceOpen: false))
    }

    func testDialogCompletionReseedsReplacedToolbarBeforeNextRealSwitch() {
        var tracker = CodexWorkspaceSwitchTracker<String>()
        _ = tracker.observe(window: "w", chat: "before-dialog", workspaceOpen: false)
        tracker.reset() // Public dialog detected; unknown reads leave this state intact.
        // Saving Rename permanently remounts the same chat's toolbar.
        XCTAssertFalse(tracker.observe(window: "w", chat: "after-save", workspaceOpen: false))
        XCTAssertFalse(tracker.observe(window: "w", chat: "after-save", workspaceOpen: false))
        XCTAssertTrue(tracker.observe(window: "w", chat: "other-chat", workspaceOpen: false))
        tracker.reset()
        // Cancel may restore the same toolbar; it also seeds without opening.
        XCTAssertFalse(tracker.observe(window: "w", chat: "other-chat", workspaceOpen: false))
        XCTAssertTrue(tracker.observe(window: "w", chat: "after-save", workspaceOpen: false))
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
