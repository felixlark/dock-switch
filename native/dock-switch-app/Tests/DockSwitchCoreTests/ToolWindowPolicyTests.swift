import XCTest
@testable import DockSwitchCore

final class ToolWindowPolicyTests: XCTestCase {
    func testOwnershipDoesNotExpandFromOpeningAProcessOrFromTemporalCoincidence() {
        let resource = URL(fileURLWithPath: "/tmp/tool.txt")
        for bundle in ["com.apple.Terminal", "com.microsoft.VSCode", "com.google.Chrome", "unknown.app"] {
            XCTAssertEqual(ToolWindowPolicy.scope(bundleID: bundle, dedicated: false, resource: nil, existingDocuments: []), .none)
            XCTAssertEqual(ToolWindowPolicy.scope(bundleID: bundle, dedicated: false, resource: URL(string: "https://example.com")!, existingDocuments: []), .none)
            XCTAssertEqual(ToolWindowPolicy.scope(bundleID: bundle, dedicated: false, resource: resource, existingDocuments: []), .document(resource))
            XCTAssertEqual(ToolWindowPolicy.scope(bundleID: bundle, dedicated: false, resource: resource, existingDocuments: [resource]), .none)
        }
        XCTAssertEqual(ToolWindowPolicy.scope(bundleID: "my.generated.tool", dedicated: true, resource: nil, existingDocuments: []), .dedicated)
        XCTAssertEqual(ToolWindowPolicy.scope(bundleID: "com.openai.codex", dedicated: true, resource: nil, existingDocuments: []), .none)
    }
    func testReusingAManualWindowConsumesTheFileClaimBeforeLaterReopen() {
        let a = URL(fileURLWithPath: "/tmp/tool-a.txt")
        let b = URL(fileURLWithPath: "/tmp/manual-b.txt")
        let initial = ToolWindowPolicy.remainingClaims([a], knownDocuments: [b])
        XCTAssertEqual(initial, [a])
        let reusedAsTab = ToolWindowPolicy.remainingClaims(initial, knownDocuments: [a])
        XCTAssertTrue(reusedAsTab.isEmpty)
        XCTAssertTrue(ToolWindowPolicy.remainingClaims(reusedAsTab, knownDocuments: []).isEmpty)
    }
    private func display(_ id: UInt32, x: Double, internalDisplay: Bool = false) -> DisplaySnapshot {
        let rect = DSRect(x: x, y: -900, width: 1200, height: 900)
        return DisplaySnapshot(id: id, internalDisplay: internalDisplay, bounds: rect, workArea: rect, scaleFactor: 2, label: "Same model")
    }

    func testNoExternalTargetDoesNotFallBackOntoChatScreen() {
        XCTAssertNil(ToolWindowPolicy.target([]))
        XCTAssertNil(ToolWindowPolicy.target([display(1, x: 0, internalDisplay: true)]))
        XCTAssertEqual(ToolWindowPolicy.target([display(2, x: -1200), display(1, x: 0, internalDisplay: true), display(3, x: 1200)])?.id, 3)
    }

    func testFitPreservesSmallToolsAndContainsOversizeToolsInWorkArea() {
        let area = DSRect(x: 2000, y: -1100, width: 2000, height: 1100)
        let small = ToolWindowPolicy.destination(frame: DSRect(x: -900, y: 33, width: 600, height: 400), area: area)
        XCTAssertEqual(small, DSRect(x: 2700, y: -750, width: 600, height: 400))
        XCTAssertEqual(ToolWindowPolicy.destination(frame: DSRect(x: 0, y: 0, width: 2400, height: 1400), area: area), area)
        XCTAssertFalse(ToolWindowPolicy.contained(DSRect(x: 1900, y: -1100, width: 1900, height: 1000), in: area))
        XCTAssertTrue(ToolWindowPolicy.contained(small, in: area))
    }

    func testSheetsMenusFullscreenAndMinimizedWindowsStayWithTheirOwner() {
        XCTAssertTrue(ToolWindowPolicy.eligible(role: "AXWindow", subrole: "AXStandardWindow", minimized: false, fullscreen: false))
        for (role, subrole, minimized, fullscreen) in [
            ("AXSheet", "", false, false), ("AXMenu", "", false, false),
            ("AXWindow", "AXStandardWindow", true, false), ("AXWindow", "AXStandardWindow", false, true)
        ] {
            XCTAssertFalse(ToolWindowPolicy.eligible(role: role, subrole: subrole, minimized: minimized, fullscreen: fullscreen))
        }
        XCTAssertTrue(ToolWindowPolicy.protectedBundles.contains("com.openai.codex"))
        XCTAssertFalse(ToolWindowPolicy.utilityBundles.contains("com.apple.TextEdit"))
        XCTAssertFalse(ToolWindowPolicy.utilityBundles.contains("com.google.Chrome"))
    }
}
