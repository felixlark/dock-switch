import Carbon
import XCTest
@testable import DockSwitchCore

final class DockSwitchCoreTests: XCTestCase {
    private final class FakeLauncherWindowPlacement: LauncherWindowPlacement {
        var placeProcessResult = WindowActionResult(ok: false)
        var moveMouseResult = WindowActionResult(ok: false)
        var placedProcesses: [(name: String, placement: String)] = []
        var movedApps: [String] = []

        func placePID(_ pid: pid_t, placement: String) -> WindowActionResult {
            WindowActionResult(ok: false)
        }

        func placeProcess(name: String, placement: String) -> WindowActionResult {
            placedProcesses.append((name, placement))
            return placeProcessResult
        }

        func moveMouseToPIDWindowCenter(_ pid: pid_t) -> WindowActionResult {
            WindowActionResult(ok: false)
        }

        func moveMouseToApplicationWindowCenter(name: String) -> WindowActionResult {
            movedApps.append(name)
            return moveMouseResult
        }
    }

    private func display(
        id: UInt32,
        label: String,
        internalDisplay: Bool,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        workArea: DSRect? = nil
    ) -> DisplaySnapshot {
        DisplaySnapshot(
            id: id,
            internalDisplay: internalDisplay,
            bounds: DSRect(x: x, y: y, width: width, height: height),
            workArea: workArea ?? DSRect(x: x, y: y, width: width, height: height),
            scaleFactor: 2,
            label: label
        )
    }

    private func fourDisplayLayout() -> [DisplaySnapshot] {
        [
            display(
                id: 1,
                label: "Internal Display",
                internalDisplay: true,
                x: 0,
                y: 0,
                width: 1512,
                height: 982,
                workArea: DSRect(x: 0, y: 33, width: 1512, height: 875)
            ),
            display(
                id: 2,
                label: "Left Side Display",
                internalDisplay: false,
                x: -2444,
                y: -1080,
                width: 1920,
                height: 1080,
                workArea: DSRect(x: -2444, y: -1050, width: 1920, height: 1050)
            ),
            display(
                id: 3,
                label: "Right Side Display",
                internalDisplay: false,
                x: 2036,
                y: -1080,
                width: 1920,
                height: 1080,
                workArea: DSRect(x: 2036, y: -1050, width: 1920, height: 1050)
            ),
            display(
                id: 5,
                label: "External Display",
                internalDisplay: false,
                x: -524,
                y: -1440,
                width: 2560,
                height: 1440,
                workArea: DSRect(x: -524, y: -1410, width: 2560, height: 1410)
            )
        ]
    }

    func testLauncherItemsPreserveConfiguredAndReservedKeys() {
        let dockItems = [
            DockItemSnapshot(name: "Finder", pos: CGPoint(x: 10, y: 900), size: CGSize(width: 50, height: 66)),
            DockItemSnapshot(name: "ChatGPT", pos: CGPoint(x: 60, y: 900), size: CGSize(width: 50, height: 66)),
            DockItemSnapshot(name: "Codex", pos: CGPoint(x: 110, y: 900), size: CGSize(width: 50, height: 66)),
            DockItemSnapshot(name: "System Settings", pos: CGPoint(x: 160, y: 900), size: CGSize(width: 50, height: 66)),
            DockItemSnapshot(name: "SmartShadow", pos: CGPoint(x: 210, y: 900), size: CGSize(width: 50, height: 66)),
            DockItemSnapshot(name: "Claude", pos: CGPoint(x: 260, y: 900), size: CGSize(width: 50, height: 66)),
            DockItemSnapshot(name: "Terminal", pos: CGPoint(x: 310, y: 900), size: CGSize(width: 50, height: 66)),
            DockItemSnapshot(name: "Temporary", pos: CGPoint(x: 360, y: 900), size: CGSize(width: 50, height: 66))
        ]
        let config = LauncherConfig(dockItems: [
            LauncherConfigItem(name: "Finder", key: "D", screen: nil, kind: nil, placement: nil, openPath: nil, appURL: nil),
            LauncherConfigItem(name: "System Settings", key: "COMMAND_LEFT", screen: nil, kind: nil, placement: nil, openPath: nil, appURL: nil),
            LauncherConfigItem(name: "SmartShadow", key: "F3", screen: "0", kind: nil, placement: "external_fill", openPath: nil, appURL: nil),
            LauncherConfigItem(name: "Terminal", key: "\\", screen: nil, kind: nil, placement: nil, openPath: nil, appURL: nil)
        ])

        let items = LauncherRules.buildLauncherItems(dockItems: dockItems, config: config)

        XCTAssertEqual(items.map(\.key), ["D", "F6", "LEFT_SHIFT", "COMMAND_LEFT", "F3", "RIGHT_SHIFT", "\\", "1"])
        XCTAssertEqual(items.map(\.displayKey), ["D", "F6", "L⇧", "⌘", "F3", "R⇧", "\\", "1"])
        XCTAssertEqual(items.first { $0.name == "ChatGPT" }?.placement, "side_right_fill")
        XCTAssertEqual(items.first { $0.name == "Codex" }?.placement, "external_fill")
        XCTAssertEqual(items.first { $0.name == "SmartShadow" }?.placement, "external_fill")
        XCTAssertEqual(items.first { $0.name == "Claude" }?.placement, "side_right_fill")
        XCTAssertEqual(items.first { $0.name == "SmartShadow" }?.openPath, "/Applications/SmartShadow.app")
        XCTAssertEqual(items.first { $0.name == "Claude" }?.openPath, "/Applications/Claude.app")
    }

    func testUserAssignedNumericKeysTakePriorityOverAutomaticFallbackKeys() {
        let dockItems = [
            DockItemSnapshot(name: "Automatic App", pos: CGPoint(x: 10, y: 900), size: CGSize(width: 50, height: 66)),
            DockItemSnapshot(name: "User App", pos: CGPoint(x: 60, y: 900), size: CGSize(width: 50, height: 66))
        ]
        let config = LauncherConfig(dockItems: [
            LauncherConfigItem(name: "User App", key: "1", screen: nil, kind: nil, placement: nil, openPath: nil, appURL: nil)
        ])

        let items = LauncherRules.buildLauncherItems(dockItems: dockItems, config: config)

        XCTAssertEqual(items.map(\.key), ["2", "1"])
        XCTAssertEqual(items.first { $0.key == "1" }?.name, "User App")
    }

    func testBottomDockOverlaySitsAboveDock() {
        let display = DisplaySnapshot(
            id: 1,
            internalDisplay: true,
            bounds: DSRect(x: 0, y: 0, width: 1512, height: 982),
            workArea: DSRect(x: 0, y: 33, width: 1512, height: 949),
            scaleFactor: 2,
            label: "Built-in Retina Display"
        )
        let dockItems = [
            DockItemSnapshot(name: "Finder", pos: CGPoint(x: 480, y: 906), size: CGSize(width: 50, height: 66)),
            DockItemSnapshot(name: "Safari", pos: CGPoint(x: 540, y: 906), size: CGSize(width: 50, height: 66))
        ]
        let launcherItems = LauncherRules.buildLauncherItems(dockItems: dockItems, config: .empty)
        let layout = OverlayLayoutService().resolve(launcherItems: launcherItems, displays: [display])

        XCTAssertNotNil(layout)
        XCTAssertEqual(layout!.windowFrameAX, DSRect(x: 480, y: 846, width: 120, height: 60))
        XCTAssertEqual(layout!.targets.count, 2)
    }

    func testBottomDockOverlayAlignsWithDockWindowLeftEdge() {
        let display = DisplaySnapshot(
            id: 1,
            internalDisplay: true,
            bounds: DSRect(x: 0, y: 0, width: 1512, height: 982),
            workArea: DSRect(x: 0, y: 33, width: 1512, height: 875),
            scaleFactor: 2,
            label: "Built-in Retina Display"
        )
        let dockFrame = DSRect(x: 112, y: 904, width: 1288, height: 68)
        let dockItems = [
            DockItemSnapshot(name: "Finder", pos: CGPoint(x: 120, y: 904), size: CGSize(width: 52, height: 68), containerFrame: dockFrame),
            DockItemSnapshot(name: "Safari", pos: CGPoint(x: 172, y: 904), size: CGSize(width: 52, height: 68), containerFrame: dockFrame),
            DockItemSnapshot(name: "Google Chrome", pos: CGPoint(x: 224, y: 904), size: CGSize(width: 52, height: 68), containerFrame: dockFrame)
        ]
        let launcherItems = LauncherRules.buildLauncherItems(dockItems: dockItems, config: .empty)
        let layout = OverlayLayoutService().resolve(launcherItems: launcherItems, displays: [display])

        XCTAssertNotNil(layout)
        XCTAssertEqual(layout!.dockRect, dockFrame)
        XCTAssertEqual(layout!.windowFrameAX, DSRect(x: 112, y: 844, width: 172, height: 60))
    }

    func testTopDockOverlayUsesHistoricalBelowDockOffset() {
        let display = DisplaySnapshot(
            id: 1,
            internalDisplay: true,
            bounds: DSRect(x: 0, y: 0, width: 1512, height: 982),
            workArea: DSRect(x: 0, y: 33, width: 1512, height: 949),
            scaleFactor: 2,
            label: "Built-in Retina Display"
        )
        let dockItems = [
            DockItemSnapshot(name: "Finder", pos: CGPoint(x: 480, y: 30), size: CGSize(width: 50, height: 66)),
            DockItemSnapshot(name: "Safari", pos: CGPoint(x: 540, y: 30), size: CGSize(width: 50, height: 66))
        ]
        let launcherItems = LauncherRules.buildLauncherItems(dockItems: dockItems, config: .empty)
        let layout = OverlayLayoutService().resolve(launcherItems: launcherItems, displays: [display])

        XCTAssertNotNil(layout)
        XCTAssertEqual(layout!.windowFrameAX, DSRect(x: 480, y: 82, width: 120, height: 60))
    }

    func testBottomDockOverlayAccountsForPositiveDisplayOrigin() {
        let display = DisplaySnapshot(
            id: 1,
            internalDisplay: true,
            bounds: DSRect(x: 0, y: 458, width: 1512, height: 982),
            workArea: DSRect(x: 0, y: 491, width: 1512, height: 875),
            scaleFactor: 2,
            label: "Built-in Retina Display"
        )
        let externalDisplay = DisplaySnapshot(
            id: 4,
            internalDisplay: false,
            bounds: DSRect(x: 0, y: -374, width: 2560, height: 1440),
            workArea: DSRect(x: 0, y: -344, width: 2560, height: 1410),
            scaleFactor: 2,
            label: "DELL U3219Q"
        )
        let dockItems = [
            DockItemSnapshot(name: "Finder", pos: CGPoint(x: 172, y: 904), size: CGSize(width: 52, height: 68)),
            DockItemSnapshot(name: "Safari", pos: CGPoint(x: 224, y: 904), size: CGSize(width: 52, height: 68))
        ]
        let launcherItems = LauncherRules.buildLauncherItems(dockItems: dockItems, config: .empty)
        let layout = OverlayLayoutService().resolve(launcherItems: launcherItems, displays: [display, externalDisplay])

        XCTAssertNotNil(layout)
        XCTAssertEqual(layout!.windowFrameAX, DSRect(x: 172, y: 1302, width: 120, height: 60))
    }

    func testBottomDockOverlayDoesNotDoubleApplyPositiveDisplayOriginWhenDockCoordinatesAreGlobal() {
        let externalMainDisplay = DisplaySnapshot(
            id: 4,
            internalDisplay: false,
            bounds: DSRect(x: 0, y: 0, width: 2560, height: 1440),
            workArea: DSRect(x: 0, y: 30, width: 2560, height: 1410),
            scaleFactor: 2,
            label: "DELL U3219Q"
        )
        let internalDisplay = DisplaySnapshot(
            id: 1,
            internalDisplay: true,
            bounds: DSRect(x: 535, y: 1440, width: 1512, height: 982),
            workArea: DSRect(x: 535, y: 1473, width: 1512, height: 875),
            scaleFactor: 2,
            label: "Built-in Retina Display"
        )
        let dockFrame = DSRect(x: 595, y: 2348, width: 1265, height: 74)
        let dockItems = [
            DockItemSnapshot(name: "Finder", pos: CGPoint(x: 603, y: 2362), size: CGSize(width: 52, height: 52), containerFrame: dockFrame),
            DockItemSnapshot(name: "Safari", pos: CGPoint(x: 663, y: 2362), size: CGSize(width: 52, height: 52), containerFrame: dockFrame)
        ]
        let launcherItems = LauncherRules.buildLauncherItems(dockItems: dockItems, config: .empty)
        let layout = OverlayLayoutService().resolve(
            launcherItems: launcherItems,
            displays: [externalMainDisplay, internalDisplay]
        )

        XCTAssertNotNil(layout)
        XCTAssertEqual(layout!.windowFrameAX, DSRect(x: 595, y: 2288, width: 128, height: 60))
        XCTAssertLessThanOrEqual(layout!.windowFrameAX.maxY, internalDisplay.workArea.maxY)
    }

    func testOverlayUsesDisplayContainingDockItems() {
        let internalDisplay = DisplaySnapshot(
            id: 1,
            internalDisplay: true,
            bounds: DSRect(x: 0, y: 0, width: 1512, height: 982),
            workArea: DSRect(x: 0, y: 33, width: 1512, height: 949),
            scaleFactor: 2,
            label: "Internal"
        )
        let externalDisplay = DisplaySnapshot(
            id: 2,
            internalDisplay: false,
            bounds: DSRect(x: -579, y: -1410, width: 2560, height: 1410),
            workArea: DSRect(x: -579, y: -1410, width: 2560, height: 1378),
            scaleFactor: 2,
            label: "External"
        )
        let dockItems = [
            DockItemSnapshot(name: "Finder", pos: CGPoint(x: -120, y: -92), size: CGSize(width: 50, height: 66)),
            DockItemSnapshot(name: "Safari", pos: CGPoint(x: -60, y: -92), size: CGSize(width: 50, height: 66))
        ]
        let launcherItems = LauncherRules.buildLauncherItems(dockItems: dockItems, config: .empty)
        let layout = OverlayLayoutService().resolve(launcherItems: launcherItems, displays: [internalDisplay, externalDisplay])

        XCTAssertNotNil(layout)
        XCTAssertEqual(layout!.windowFrameAX, DSRect(x: -120, y: -152, width: 120, height: 60))
    }

    func testKeyNormalization() {
        XCTAssertEqual(LauncherRules.normalizeKey("tab"), "TAB")
        XCTAssertEqual(LauncherRules.normalizeKey("f20"), "F20")
        XCTAssertEqual(LauncherRules.normalizeKey("d"), "D")
        XCTAssertEqual(LauncherRules.normalizeKey("left_shift"), "LEFT_SHIFT")
        XCTAssertEqual(LauncherRules.normalizeKey("right-shift"), "RIGHT_SHIFT")
        XCTAssertEqual(LauncherRules.keyIcon(for: "LEFT_SHIFT"), "L⇧")
        XCTAssertEqual(LauncherRules.keyIcon(for: "RIGHT_SHIFT"), "R⇧")
        XCTAssertEqual(LauncherRules.normalizeKey("cmd_left"), "COMMAND_LEFT")
        XCTAssertEqual(LauncherRules.normalizeKey("left_cmd"), "COMMAND_LEFT")
        XCTAssertEqual(LauncherRules.normalizeKey("cmd-right"), "COMMAND_RIGHT")
        XCTAssertEqual(LauncherRules.keyIcon(for: "COMMAND_LEFT"), "⌘")
    }

    func testEventKeyNormalizationUsesHardwareBackslash() {
        XCTAssertEqual(LauncherRules.normalizeEventKey(characters: "", keyCode: UInt16(kVK_ANSI_Backslash)), "\\")
        XCTAssertEqual(LauncherRules.normalizeEventKey(characters: "¥", keyCode: UInt16(kVK_ANSI_Backslash)), "\\")
        XCTAssertEqual(LauncherRules.normalizeEventKey(characters: "", keyCode: UInt16(kVK_Tab)), "TAB")
        XCTAssertEqual(LauncherRules.normalizeEventKey(characters: "", keyCode: UInt16(kVK_Shift)), "LEFT_SHIFT")
        XCTAssertEqual(LauncherRules.normalizeEventKey(characters: "", keyCode: UInt16(kVK_RightShift)), "RIGHT_SHIFT")
    }

    func testShortcutRulesMapReservedAppsAndWindowActions() {
        XCTAssertEqual(LauncherShortcutRules.appName(for: "F6"), "ChatGPT")
        XCTAssertEqual(LauncherShortcutRules.appName(for: "LEFT_SHIFT"), "Codex")
        XCTAssertEqual(LauncherShortcutRules.appName(for: "RIGHT_SHIFT"), "Claude")
        XCTAssertEqual(LauncherShortcutRules.appName(for: "F3"), "SmartShadow")
        XCTAssertEqual(LauncherShortcutRules.appName(for: "COMMAND_LEFT"), "System Settings")
        XCTAssertNil(LauncherShortcutRules.appName(for: "TAB"))
        XCTAssertNil(LauncherShortcutRules.appName(for: "COMMAND_RIGHT"))
        XCTAssertTrue(LauncherShortcutRules.isReserved("COMMAND_RIGHT"))
        XCTAssertFalse(LauncherShortcutRules.isReserved("LEFT_SHIFT"))
        XCTAssertFalse(LauncherShortcutRules.isReserved("RIGHT_SHIFT"))
        XCTAssertFalse(LauncherShortcutRules.isReserved("F3"))
        XCTAssertFalse(LauncherShortcutRules.isReserved("F6"))
        XCTAssertFalse(LauncherShortcutRules.isReserved("TAB"))
        XCTAssertEqual(LauncherShortcutRules.windowAction(key: "ArrowUp"), "up")
        XCTAssertEqual(LauncherShortcutRules.windowAction(key: "【"), "current_left")
        XCTAssertEqual(LauncherShortcutRules.windowAction(key: "]"), "current_right")
        XCTAssertNil(LauncherShortcutRules.windowAction(key: "\\"))
        XCTAssertTrue(LauncherShortcutRules.shouldCenterMouse(for: "right"))
        XCTAssertTrue(LauncherShortcutRules.shouldCenterMouse(for: "current_right"))
    }

    func testShortcutRulesResolveReservedAppsToPlacedLauncherItems() {
        let smartShadow = LauncherShortcutRules.launcherItem(for: "F3")
        XCTAssertEqual(smartShadow?.name, "SmartShadow")
        XCTAssertEqual(smartShadow?.key, "F3")
        XCTAssertEqual(smartShadow?.placement, "side_left_fill")
        XCTAssertEqual(smartShadow?.openPath, "/Applications/SmartShadow.app")

        let codex = LauncherShortcutRules.launcherItem(for: "LEFT_SHIFT")
        XCTAssertEqual(codex?.name, "Codex")
        XCTAssertEqual(codex?.key, "LEFT_SHIFT")
        XCTAssertEqual(codex?.placement, "external_fill")

        let claude = LauncherShortcutRules.launcherItem(for: "RIGHT_SHIFT")
        XCTAssertEqual(claude?.name, "Claude")
        XCTAssertEqual(claude?.key, "RIGHT_SHIFT")
        XCTAssertEqual(claude?.placement, "side_right_fill")
        XCTAssertEqual(claude?.openPath, "/Applications/Claude.app")
        XCTAssertNil(LauncherShortcutRules.launcherItem(for: "COMMAND_RIGHT"))
    }

    func testDirectModifierShortcutUsesConfiguredPlacementWithoutOpeningLauncher() {
        let config = LauncherConfig(dockItems: [
            LauncherConfigItem(
                name: "Claude",
                key: "RIGHT_SHIFT",
                screen: "side_right",
                kind: nil,
                placement: "side_right_fill",
                openPath: nil,
                appURL: nil
            )
        ])

        let claude = LauncherShortcutRules.launcherItem(for: "RIGHT_SHIFT", config: config)

        XCTAssertEqual(claude?.name, "Claude")
        XCTAssertEqual(claude?.key, "RIGHT_SHIFT")
        XCTAssertEqual(claude?.placement, "side_right_fill")
        XCTAssertEqual(claude?.openPath, "/Applications/Claude.app")
    }

    func testDirectModifierShortcutFollowsReassignedKeys() {
        func item(_ name: String, _ key: String, _ placement: String) -> LauncherConfigItem {
            LauncherConfigItem(name: name, key: key, screen: nil, kind: nil, placement: placement, openPath: nil, appURL: nil)
        }
        let config = LauncherConfig(dockItems: [
            item("Claude", "LEFT_SHIFT", "external_fill"),
            item("ChatGPT", "RIGHT_SHIFT", "side_right_fill")
        ])

        let chatGPT = LauncherShortcutRules.launcherItem(for: "RIGHT_SHIFT", config: config)
        XCTAssertEqual(chatGPT?.name, "ChatGPT")
        XCTAssertEqual(chatGPT?.key, "RIGHT_SHIFT")
        XCTAssertEqual(chatGPT?.icon, "R⇧")
        XCTAssertEqual(chatGPT?.placement, "side_right_fill")

        let claude = LauncherShortcutRules.launcherItem(for: "LEFT_SHIFT", config: config)
        XCTAssertEqual(claude?.name, "Claude")
        XCTAssertEqual(claude?.placement, "external_fill")
        XCTAssertEqual(claude?.openPath, "/Applications/Claude.app")

        // A default app that was moved to another key no longer answers its old key.
        let moved = LauncherConfig(dockItems: [item("Claude", "LEFT_SHIFT", "external_fill")])
        XCTAssertNil(LauncherShortcutRules.launcherItem(for: "RIGHT_SHIFT", config: moved))
    }

    func testLauncherServiceShowsMouseFeedbackAfterPlacedAppMouseMove() {
        let placement = FakeLauncherWindowPlacement()
        placement.placeProcessResult = WindowActionResult(ok: true, feedbackPoint: CGPoint(x: 420, y: 240))
        var feedbackPoints: [CGPoint] = []
        let expectation = expectation(description: "feedback shown")
        let service = LauncherService(
            windowPlacement: placement,
            placeRetryDeadline: 0.1,
            placeRetryDelay: 0,
            showMouseFeedback: { point in
                feedbackPoints.append(point)
                expectation.fulfill()
            },
            openItem: { _ in }
        )

        service.activate(LauncherItem(
            name: "Claude",
            key: "F6",
            placement: "external_fill",
            dockItem: DockItemSnapshot(name: "Claude", pos: .zero, size: .zero)
        ))

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(placement.placedProcesses.map(\.name), ["Claude"])
        XCTAssertEqual(placement.placedProcesses.map(\.placement), ["external_fill"])
        XCTAssertEqual(placement.movedApps, [])
        XCTAssertEqual(feedbackPoints, [CGPoint(x: 420, y: 240)])
    }

    func testLauncherServiceShowsMouseFeedbackAfterUnplacedAppMouseMove() {
        let placement = FakeLauncherWindowPlacement()
        placement.moveMouseResult = WindowActionResult(ok: true, feedbackPoint: CGPoint(x: -100, y: 50))
        var feedbackPoints: [CGPoint] = []
        let expectation = expectation(description: "feedback shown")
        let service = LauncherService(
            windowPlacement: placement,
            placeRetryDeadline: 0.1,
            placeRetryDelay: 0,
            showMouseFeedback: { point in
                feedbackPoints.append(point)
                expectation.fulfill()
            },
            openItem: { _ in }
        )

        service.activate(LauncherItem(
            name: "Finder",
            key: "D",
            dockItem: DockItemSnapshot(name: "Finder", pos: .zero, size: .zero)
        ))

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(placement.placedProcesses.count, 0)
        XCTAssertEqual(placement.movedApps, ["Finder"])
        XCTAssertEqual(feedbackPoints, [CGPoint(x: -100, y: 50)])
    }

    func testOverlayAnimationPolicyShowsInstantlyAndHidesSwiftly() {
        XCTAssertEqual(OverlayAnimationPolicy.showDuration, 0)
        XCTAssertTrue(OverlayAnimationPolicy.showUsesFinalFrame)
        XCTAssertGreaterThan(OverlayAnimationPolicy.hideDuration, 0)
        XCTAssertLessThanOrEqual(OverlayAnimationPolicy.hideDuration, 0.14)
        XCTAssertGreaterThan(OverlayAnimationPolicy.hideScale, 0.92)
        XCTAssertLessThan(OverlayAnimationPolicy.hideScale, 1)
    }

    func testStatusItemIconPolicyUsesTemplateImagesForSystemAppearance() {
        XCTAssertEqual(StatusItemIconPolicy.size, CGSize(width: 18, height: 18))
        XCTAssertTrue(StatusItemIconPolicy.usesTemplateImage)
        XCTAssertEqual(StatusItemIconPolicy.accessibilityLabel, "dock-switch")
    }

    func testSubprocessCaptureDrainsLargeStdoutBeforeWaiting() throws {
        let startedAt = Date()
        let output = try XCTUnwrap(Subprocess.captureOutput(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "/usr/bin/yes 012345678901234567890123456789 | /usr/bin/head -n 20000"]
        ))

        XCTAssertEqual(output.terminationStatus, 0)
        XCTAssertGreaterThan(output.stdout.count, 128 * 1024)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 5)
    }

    func testDisplayGeometryRoutesArrowsToPhysicalDisplays() {
        let displays = fourDisplayLayout()
        let primary = displays[0]

        XCTAssertEqual(DisplayGeometry.resolveBoundsForAction(action: "up", displays: displays, primaryDisplay: primary, currentDisplay: primary), displays[3].workArea)
        XCTAssertEqual(DisplayGeometry.resolveBoundsForAction(action: "down", displays: displays, primaryDisplay: primary, currentDisplay: displays[3]), displays[0].workArea)
        XCTAssertEqual(DisplayGeometry.resolveBoundsForAction(action: "left", displays: displays, primaryDisplay: primary, currentDisplay: primary), displays[1].workArea)
        XCTAssertEqual(DisplayGeometry.resolveBoundsForAction(action: "right", displays: displays, primaryDisplay: primary, currentDisplay: primary), displays[2].workArea)
    }

    func testDisplayGeometryTilesCurrentDisplayAndFillsCurrentBounds() {
        let displays = fourDisplayLayout()
        let current = displays[3]

        XCTAssertEqual(
            DisplayGeometry.resolveBoundsForAction(action: "current_left", displays: displays, primaryDisplay: displays[0], currentDisplay: current),
            DSRect(x: -524, y: -1410, width: 1280, height: 1410)
        )
        XCTAssertEqual(
            DisplayGeometry.resolveBoundsForAction(action: "current_right", displays: displays, primaryDisplay: displays[0], currentDisplay: current),
            DSRect(x: 756, y: -1410, width: 1280, height: 1410)
        )
        XCTAssertEqual(
            DisplayGeometry.resolveBoundsForAction(action: "fill", displays: displays, primaryDisplay: displays[0], currentDisplay: current),
            current.bounds
        )
    }

    func testDisplayGeometrySupportsSidePlacementsAndFallbacks() {
        let displays = fourDisplayLayout()
        let primary = displays[0]

        XCTAssertNil(DisplayGeometry.resolveBoundsForPlacement("side_fill", displays: displays, primaryDisplay: primary))
        XCTAssertEqual(DisplayGeometry.resolveBoundsForPlacement("side_left_fill", displays: displays, primaryDisplay: primary), displays[1].workArea)
        XCTAssertEqual(DisplayGeometry.resolveBoundsForPlacement("side_right_fill", displays: displays, primaryDisplay: primary), displays[2].workArea)
        XCTAssertEqual(
            DisplayGeometry.resolveBoundsForPlacement("side_right_right_half", displays: displays, primaryDisplay: primary),
            DSRect(x: 2996, y: -1050, width: 960, height: 1050)
        )

        let twoDisplays = [displays[0], displays[3]]
        XCTAssertEqual(DisplayGeometry.resolveBoundsForPlacement("side_left_fill", displays: twoDisplays, primaryDisplay: displays[0]), displays[0].workArea)
        XCTAssertEqual(DisplayGeometry.resolveBoundsForPlacement("side_right_fill", displays: twoDisplays, primaryDisplay: displays[0]), displays[0].workArea)
        XCTAssertEqual(
            DisplayGeometry.resolveBoundsForPlacement("external_right_half", displays: [displays[0]], primaryDisplay: displays[0]),
            DSRect(x: 756, y: 33, width: 756, height: 875)
        )
    }

    func testDisplayGeometryFindsContainingOrNearestDisplay() {
        let displays = fourDisplayLayout()

        XCTAssertEqual(
            DisplayGeometry.display(containing: DSRect(x: 2100, y: -900, width: 400, height: 300), displays: displays)?.id,
            3
        )
        XCTAssertEqual(
            DisplayGeometry.display(containing: DSRect(x: 3800, y: -900, width: 400, height: 300), displays: displays)?.id,
            3
        )
    }

    func testDisplayGeometryConvertsAXFrameOnNonInternalDisplayToAppKitFrame() {
        let displayAX = DSRect(x: 0, y: -1270, width: 2560, height: 1440)
        let displayAppKit = DSRect(x: 0, y: 0, width: 2560, height: 1440)
        let overlayAX = DSRect(x: 170, y: 82, width: 1200, height: 48)

        let appKit = DisplayGeometry.appKitFrame(
            fromAX: overlayAX,
            inDisplay: displayAX,
            appKitDisplayFrame: displayAppKit
        )

        XCTAssertEqual(appKit, DSRect(x: 170, y: 40, width: 1200, height: 48))
    }

    func testDisplayServiceConvertsInternalScreenWithoutMainScreenHeightDrift() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = CGRect(x: 0, y: 74, width: 1512, height: 875)
        let displayBounds = CGRect(x: 0, y: 0, width: 1512, height: 982)

        XCTAssertEqual(
            DisplayService.convertDisplayBounds(displayBounds),
            DSRect(x: 0, y: 0, width: 1512, height: 982)
        )
        XCTAssertEqual(
            DisplayService.convertVisibleFrame(visibleFrame, screenFrame: screenFrame, displayBounds: displayBounds),
            DSRect(x: 0, y: 33, width: 1512, height: 875)
        )
    }

    func testGokit5ButtonParsingAndTargetMapping() {
        XCTAssertEqual(Gokit5Serial.parseButtonLine("GOKIT5_HOST_BUTTON:minus"), "minus")
        XCTAssertEqual(Gokit5Serial.parseButtonLine("I (123) Gokit5: GOKIT5_HOST_BUTTON:voice"), "voice")
        XCTAssertEqual(Gokit5Serial.parseButtonLine("GOKIT5_HOST_BUTTON:plus extra"), "plus")
        XCTAssertEqual(Gokit5Serial.parseButtonLine("GOKIT5_HOST_BUTTON:green"), "green")
        XCTAssertEqual(Gokit5Serial.parseButtonLine("GOKIT5_HOST_BUTTON:switch"), "switch")
        XCTAssertEqual(Gokit5Serial.parseButtonLine("GOKIT5_HOST_BUTTON:+"), "")
        XCTAssertEqual(Gokit5Serial.parseButtonLine("GOKIT5_HOST_BUTTON:add"), "")
        XCTAssertEqual(Gokit5Serial.parseButtonLine("GOKIT5_HOST_BUTTON:volume-up"), "")
        XCTAssertEqual(Gokit5Serial.parseButtonLine("GOKIT5_HOST_BUTTON:volume+"), "")
        XCTAssertEqual(Gokit5Serial.parseButtonLine("I (123) VolcRTCApp: Heap Info"), "")

        let minus = Gokit5Serial.action(for: "minus")
        XCTAssertEqual(minus?.mouseTarget, "side_left")
        XCTAssertNil(minus?.codexTarget)
        XCTAssertNil(minus?.placement)
        XCTAssertNil(minus?.openPath)

        let voice = Gokit5Serial.action(for: "voice")
        XCTAssertEqual(voice?.mouseTarget, "external")
        XCTAssertNil(voice?.codexTarget)
        XCTAssertNil(voice?.placement)

        let switchAction = Gokit5Serial.action(for: "switch")
        XCTAssertEqual(switchAction?.mouseTarget, "side_right")
        XCTAssertNil(switchAction?.codexTarget)
        XCTAssertNil(switchAction?.placement)
        XCTAssertNil(switchAction?.openPath)

        let green = Gokit5Serial.action(for: "green")
        XCTAssertEqual(green?.mouseTarget, "side_right")
        XCTAssertNil(green?.codexTarget)
        XCTAssertNil(green?.placement)
        XCTAssertNil(green?.kind)
        XCTAssertNil(green?.openPath)
        XCTAssertNil(green?.appURL)

        let plus = Gokit5Serial.action(for: "plus")
        XCTAssertEqual(plus?.mouseTarget, "internal")
        XCTAssertNil(plus?.codexTarget)
        XCTAssertNil(plus?.placement)
        XCTAssertNil(plus?.kind)
        XCTAssertNil(plus?.openPath)
        XCTAssertNil(plus?.appURL)
        XCTAssertNil(Gokit5Serial.action(for: "+"))
        XCTAssertNil(Gokit5Serial.action(for: "add"))
        XCTAssertNil(Gokit5Serial.action(for: "volume-up"))
        XCTAssertNil(Gokit5Serial.action(for: "volume+"))

        XCTAssertEqual(Gokit5Serial.inputPhrase(for: "voice"), "/goal")
        XCTAssertEqual(Gokit5Serial.inputPhrase(for: "plus"), "/plan")
        XCTAssertEqual(Gokit5Serial.inputPhrase(for: "green"), "side chat")
        XCTAssertEqual(Gokit5Serial.inputPhrase(for: "switch"), "side chat")
        XCTAssertEqual(Gokit5Serial.inputPhrase(for: "minus"), "continue")
        XCTAssertNil(Gokit5Serial.inputPhrase(for: "unknown"))
    }

    func testKeyboardShortcutInputCreatesUnicodeTextWithoutCommandOrReturn() {
        let events = KeyboardShortcutInput.makeTextEvents("/goal")
        XCTAssertEqual(events?.count, 2)
        XCTAssertEqual(events?.first?.type, .keyDown)
        XCTAssertEqual(events?.last?.type, .keyUp)
        XCTAssertEqual(events?.first?.flags, [])
        XCTAssertEqual(events?.last?.flags, [])
        XCTAssertEqual(events?.first?.getIntegerValueField(.keyboardEventKeycode), 0)
        XCTAssertNotEqual(events?.first?.getIntegerValueField(.keyboardEventKeycode), Int64(kVK_Return))

        var actualLength = 0
        var characters = [UniChar](repeating: 0, count: 16)
        characters.withUnsafeMutableBufferPointer { buffer in
            events?.first?.keyboardGetUnicodeString(
                maxStringLength: buffer.count,
                actualStringLength: &actualLength,
                unicodeString: buffer.baseAddress
            )
        }
        XCTAssertEqual(String(utf16CodeUnits: characters, count: actualLength), "/goal")
    }

    func testGokit5DiagnosticLineDetection() {
        XCTAssertTrue(Gokit5Serial.isDiagnosticLine("GOKIT5_ADC_PROBE:8:603"))
        XCTAssertTrue(Gokit5Serial.isDiagnosticLine("I (123) Gokit5: GOKIT5_HOST_BUTTON:switch"))
        XCTAssertFalse(Gokit5Serial.isDiagnosticLine("I (123) WifiBoard: Free internal"))
    }

    func testGokit5StatusClearsStaleConnectionTelemetry() {
        var status = Gokit5Status(enabled: true, status: "connected", portPath: "/dev/cu.usbmodem13101", running: true, updatedAt: "now", error: nil)
        status.lastButton = "switch"
        status.lastTarget = "side_right_fill"
        status.lastLine = "GOKIT5_HOST_BUTTON:switch"
        status.lastEventAt = "event-time"
        status.lastSerialLine = "GOKIT5_HOST_BUTTON:switch"
        status.lastSerialLineAt = "serial-time"
        status.serialLineCount = 12
        status.helperStdoutChunkCount = 3
        status.helperStdoutByteCount = 120
        status.helperStdoutLfCount = 12
        status.helperStdoutPreview = "GOKIT5_HOST_BUTTON:switch"
        status.recentLines = ["GOKIT5_HOST_BUTTON:switch"]
        status.readPollCount = 4
        status.lastReadErrno = 35
        status.resetInfo = "get:0"

        status.clearConnectionTelemetry()

        XCTAssertNil(status.lastButton)
        XCTAssertNil(status.lastTarget)
        XCTAssertNil(status.lastLine)
        XCTAssertNil(status.lastEventAt)
        XCTAssertNil(status.lastSerialLine)
        XCTAssertNil(status.lastSerialLineAt)
        XCTAssertEqual(status.serialLineCount, 0)
        XCTAssertEqual(status.helperStdoutChunkCount, 0)
        XCTAssertEqual(status.helperStdoutByteCount, 0)
        XCTAssertEqual(status.helperStdoutLfCount, 0)
        XCTAssertNil(status.helperStdoutPreview)
        XCTAssertTrue(status.recentLines.isEmpty)
        XCTAssertEqual(status.readPollCount, 0)
        XCTAssertNil(status.lastReadErrno)
        XCTAssertNil(status.resetInfo)
    }

    func testGokit5PortExtractionFindsEspressifSerialSuffix() {
        let sample = """
        +-o USB JTAG/serial debug unit@00131000  <class IOUSBHostDevice>
          |   "idProduct" = 4097
          |   "USB Product Name" = "USB JTAG_serial debug unit"
          |   "kUSBSerialNumberString" = "94:A9:90:10:E5:F4"
          |   "USB Vendor Name" = "Espressif"
          |   "idVendor" = 12346
          +-o AppleUSBACMData
            |   "IOTTYSuffix" = "13101"
        """

        XCTAssertEqual(Gokit5Serial.extractPortPaths(from: sample), ["/dev/cu.usbmodem13101"])
    }
}
