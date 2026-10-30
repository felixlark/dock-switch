import XCTest
@testable import DockSwitchCore

final class PhraseRefreshTests: XCTestCase {
    private func exercise(original: String = "wubi", alternate: String? = "english",
                          initial: String = "wubi", pid: Int32 = 42,
                          fails: Set<String> = [], intervenes: (() -> Void)? = nil,
                          userSource: String? = nil, userPID: Int32? = nil) -> (PhraseInputRefresh.Result?, [String]) {
        var current = initial
        var foreground = pid
        var selected: [String] = []
        var result: PhraseInputRefresh.Result?
        PhraseInputRefresh.run(original: original, alternate: alternate, sourcePID: 42,
            current: { current }, foreground: { foreground }, select: {
                selected.append($0)
                guard !fails.contains($0) else { return false }
                current = $0; return true
            }, afterSwitch: { action in
                intervenes?()
                if let userSource { current = userSource }
                if let userPID { foreground = userPID }
                action()
            }, completion: { result = $0 })
        return (result, selected)
    }

    func testWubiEnglishRoundTripRestoresOriginal() {
        let (result, selected) = exercise()
        XCTAssertEqual(result, .refreshed)
        XCTAssertEqual(selected, ["english", "wubi"])
        let reverse = exercise(original: "english", alternate: "wubi", initial: "english")
        XCTAssertEqual(reverse.0, .refreshed)
        XCTAssertEqual(reverse.1, ["wubi", "english"])
    }

    func testChangedClientOrSourceDoesNotStartSwitching() {
        XCTAssertEqual(exercise(pid: 99).0, .contextChanged)
        XCTAssertTrue(exercise(pid: 99).1.isEmpty)
        XCTAssertEqual(exercise(initial: "other").0, .contextChanged)
        XCTAssertTrue(exercise(initial: "other").1.isEmpty)
    }

    func testUnavailablePairDoesNotSwitch() {
        XCTAssertEqual(exercise(alternate: nil).0, .unavailable)
        XCTAssertTrue(exercise(alternate: nil).1.isEmpty)
        XCTAssertEqual(exercise(alternate: "wubi").0, .unavailable)
    }

    func testFailuresDoNotClaimRefreshOrRetry() {
        let failedSwitch = exercise(fails: ["english"])
        XCTAssertEqual(failedSwitch.0, .switchFailed)
        XCTAssertEqual(failedSwitch.1, ["english"])
        let failedRestore = exercise(fails: ["wubi"])
        XCTAssertEqual(failedRestore.0, .restoreFailed)
        XCTAssertEqual(failedRestore.1, ["english", "wubi"])
    }

    func testUserInterventionDuringSwitchIsPreserved() {
        let changedSource = exercise(userSource: "other")
        XCTAssertEqual(changedSource.0, .contextChanged)
        XCTAssertEqual(changedSource.1, ["english"])
        let changedApp = exercise(userPID: 99)
        XCTAssertEqual(changedApp.0, .contextChanged)
        XCTAssertEqual(changedApp.1, ["english"])
    }

    func testTooltipAtBottomCenterOfActiveDisplaysUsableArea() {
        for area in [CGRect(x: 0, y: 70, width: 1512, height: 850),
                     CGRect(x: -1920, y: -1000, width: 1920, height: 1000),
                     CGRect(x: 1512, y: 100, width: 2560, height: 1400)] {
            let frame = PhraseTipPlacement.frame(size: CGSize(width: 360, height: 92), visibleFrame: area)
            XCTAssertEqual(frame.midX, area.midX)
            XCTAssertEqual(frame.minY, area.minY + 24)
            XCTAssertTrue(area.contains(frame))
        }
        let tiny = CGRect(x: -50, y: -20, width: 200, height: 60)
        XCTAssertEqual(PhraseTipPlacement.frame(size: CGSize(width: 360, height: 92), visibleFrame: tiny), tiny)
    }
}
