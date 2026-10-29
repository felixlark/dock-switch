import XCTest
@testable import DockSwitchCore

final class CodexWorkspaceAXPolicyTests: XCTestCase {
    private let nodes = [
        0: CodexWorkspaceScanNode(role: "AXGroup", label: "", children: [1, 2]),
        1: CodexWorkspaceScanNode(role: "AXTabGroup", label: "Chat tabs", children: []),
        2: CodexWorkspaceScanNode(role: "AXButton", label: "New tab", children: [])
    ]

    private func tabs(read: (Int) -> CodexWorkspaceScanNode<Int>?) -> CodexWorkspaceSearchResult<Int> {
        CodexWorkspaceTreeSearch.find(root: 0, read: read, matching: { $0 == "AXTabGroup" && $1 == "Chat tabs" })
    }

    func testExistingTabsAreFound() {
        guard case .found(1) = tabs(read: { nodes[$0] }) else { return XCTFail("existing tabs must suppress opening") }
    }

    func testTabRoleReadFailureIsUnknownEvenWhenNewTabButtonIsReadable() {
        guard case .unknown = tabs(read: { $0 == 1 ? nil : nodes[$0] }) else { return XCTFail("failed AX role read must never mean absent") }
    }

    func testAncestorChildrenReadFailureIsUnknown() {
        let unreadable = CodexWorkspaceScanNode<Int>(role: "AXGroup", label: "", children: nil)
        guard case .unknown = tabs(read: { $0 == 0 ? unreadable : nodes[$0] }) else { return XCTFail("incomplete traversal must not open a tab") }
    }

    func testOnlyCompleteScanProvesTabsAbsent() {
        let closed = CodexWorkspaceScanNode(role: "AXGroup", label: "", children: [2])
        guard case .absent = tabs(read: { $0 == 0 ? closed : nodes[$0] }) else { return XCTFail("known closed layout should be recognized") }
    }

    func testUnnamedHeaderButtonWrappersRemainTraversable() {
        let wrapped = [0: CodexWorkspaceScanNode(role: "AXButton", label: "", children: [1]),
                       1: CodexWorkspaceScanNode(role: "AXButton", label: "New tab", children: [])]
        let result = CodexWorkspaceTreeSearch.find(root: 0, read: { id in
            guard let node = wrapped[id] else { return nil }
            return CodexWorkspaceScanNode(role: node.role, label: node.label,
                children: CodexWorkspaceTreeSearch.prunesChildren(role: node.role, label: node.label) ? [] : node.children)
        }, matching: { $0 == "AXButton" && $1 == "New tab" })
        guard case .found(1) = result else { return XCTFail("must reach the named child of Codex's unnamed button wrapper") }
        XCTAssertTrue(CodexWorkspaceTreeSearch.prunesChildren(role: "AXGroup", label: "Conversation"))
        XCTAssertTrue(CodexWorkspaceTreeSearch.prunesChildren(role: "AXTextArea", label: ""))
    }

    func testHeaderControlsOutsideNestedToolbarWrappers() {
        var inspected: [Int] = []
        let result = CodexWorkspaceHeaderSearch.nearest(startingAt: 1, parent: { $0 + 1 }, inspect: { node -> CodexWorkspaceHeaderState<Int> in
            inspected.append(node)
            return node == 4 ? .closed(99) : .absent
        })
        guard case .closed(99) = result else { return XCTFail("must find outer header controls") }
        XCTAssertEqual(inspected, [1, 2, 3, 4], "do not search beyond the nearest header")
    }

    func testHeaderUnknownBoundaryAndParentCycleFailClosed() {
        var inspected: [Int] = []
        let unknown = CodexWorkspaceHeaderSearch.nearest(startingAt: 1, parent: { $0 + 1 }, inspect: { node -> CodexWorkspaceHeaderState<Int> in
            inspected.append(node)
            return node == 3 ? .unknown : .absent
        })
        guard case .unknown = unknown else { return XCTFail("shell boundary or read failure must stop traversal") }
        XCTAssertEqual(inspected, [1, 2, 3])
        let cycle = CodexWorkspaceHeaderSearch.nearest(startingAt: 1, parent: { $0 }, inspect: { _ -> CodexWorkspaceHeaderState<Int> in .absent })
        guard case .unknown = cycle else { return XCTFail("AX parent cycles must not loop") }
    }

    func testApplicationDialogIsDetectedBehindAnExposedChatToolbar() {
        let modalTree = [
            0: CodexWorkspaceScanNode(role: "AXGroup", label: "", children: [1, 2]),
            1: CodexWorkspaceScanNode(role: "AXToolbar", label: "Chat toolbar", children: []),
            2: CodexWorkspaceScanNode(role: "AXGroup", label: "Rename chat", children: [], subrole: "AXApplicationDialog")
        ]
        let result = CodexWorkspaceTreeSearch.findNode(root: 0, read: { modalTree[$0] }, matching: { $0.subrole == "AXApplicationDialog" })
        guard case .found(2) = result else { return XCTFail("background toolbar must not hide the active Chromium dialog") }
    }

    func testTransientSubscriptionFailureRecoversWithoutRestart() {
        var subscriptions = CodexWorkspaceSubscriptions<Int>()
        var calls = 0
        subscriptions.ensure(element: 1, notification: "AXTitleChanged") { calls += 1; return .retryable(-25204) }
        XCTAssertEqual(subscriptions.activeCount, 0)
        XCTAssertEqual(subscriptions.retryableCount, 1)
        subscriptions.ensure(element: 1, notification: "AXTitleChanged") { calls += 1; return .active }
        XCTAssertEqual(subscriptions.activeCount, 1)
        XCTAssertEqual(subscriptions.retryableCount, 0)
        subscriptions.ensure(element: 1, notification: "AXTitleChanged") { calls += 1; return .active }
        XCTAssertEqual(calls, 2, "registered subscriptions must not be duplicated")
    }

    func testUnsupportedAndStaleSubscriptionsAreReportedAndReleased() {
        var subscriptions = CodexWorkspaceSubscriptions<Int>()
        subscriptions.ensure(element: 1, notification: "unsupported") { .unsupported }
        subscriptions.ensure(element: 1, notification: "unsupported") { XCTFail("unsupported is not transient"); return .active }
        subscriptions.ensure(element: 2, notification: "active") { .active }
        XCTAssertEqual(subscriptions.unsupportedCount, 1)
        var removed: [Int] = []
        subscriptions.remove(where: { _ in true }, unregister: { removed.append($0.element) })
        XCTAssertEqual(removed, [2])
        XCTAssertTrue(subscriptions.outcomes.isEmpty)
    }
}
