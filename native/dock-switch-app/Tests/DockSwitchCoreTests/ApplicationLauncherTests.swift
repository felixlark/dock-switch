import XCTest
@testable import DockSwitchCore

final class ApplicationLauncherTests: XCTestCase {
    func testRunningAppsAlwaysReceiveReopenAfterActivation() {
        for name in ["Feishu", "Finder", "Safari", "Calendar", "Google Chrome"] {
            let workspace = RecordingApplicationWorkspace()
            let url = URL(fileURLWithPath: "/Applications/\(name).app")
            workspace.runningApplications = [RunningLauncherApplication(name: name, bundleIdentifier: nil, bundleURL: url)]
            let launcher = ApplicationLauncher(workspace: workspace)
            XCTAssertTrue(launcher.open(name: name))
            XCTAssertEqual(workspace.events, [.activate(url), .openApplication(url)], name)
        }
    }

    func testColdAppsUseTheSameOpenRequest() {
        for name in ["Feishu", "Contacts", "Safari"] {
            let workspace = RecordingApplicationWorkspace()
            let url = URL(fileURLWithPath: "/Applications/\(name).app")
            workspace.namedURLs[name] = url
            XCTAssertTrue(ApplicationLauncher(workspace: workspace).open(name: name))
            XCTAssertEqual(workspace.events, [.activate(url), .openApplication(url)])
        }
    }

    func testFeishuAliasesPreferCanonicalBundleOverAmbiguousNames() {
        for name in ["Feishu", "Lark", "飞书", " LARK.app "] {
            let workspace = RecordingApplicationWorkspace()
            let canonical = URL(fileURLWithPath: "/Applications/Lark.app")
            workspace.bundleURLs["com.electron.lark"] = canonical
            workspace.runningApplications = [RunningLauncherApplication(name: "Feishu", bundleIdentifier: "example.other", bundleURL: URL(fileURLWithPath: "/Applications/Other.app"))]
            XCTAssertTrue(ApplicationLauncher(workspace: workspace).open(name: name))
            XCTAssertEqual(workspace.events.last, .openApplication(canonical))
        }
    }

    func testLocalizedRunningAppResolvesByBundleFilename() {
        let workspace = RecordingApplicationWorkspace()
        let url = URL(fileURLWithPath: "/System/Applications/Mail.app")
        workspace.runningApplications = [RunningLauncherApplication(name: "邮件", bundleIdentifier: "com.apple.mail", bundleURL: url)]
        XCTAssertTrue(ApplicationLauncher(workspace: workspace).open(name: "Mail"))
        XCTAssertEqual(workspace.events.last, .openApplication(url))
    }

    func testPinnedBundleAndWebAppOverrideNameResolution() {
        for path in ["/Applications/Pinned.app", "/Users/test/Applications/Chrome Apps.localized/X.app"] {
            let workspace = RecordingApplicationWorkspace()
            workspace.namedURLs["X"] = URL(fileURLWithPath: "/Applications/Wrong.app")
            let resolved = URL(fileURLWithPath: path)
            let launcher = ApplicationLauncher(workspace: workspace, resolveOpenPath: { _ in resolved.path })
            XCTAssertTrue(launcher.open(name: "X", openPath: "~/configured/target.app"))
            XCTAssertEqual(workspace.events, [.activate(resolved), .openApplication(resolved)])
        }
    }

    func testFilesAndDirectoriesKeepNormalSystemOpen() {
        for path in ["/Users/test/report.pdf", "/Users/test/Documents"] {
            let workspace = RecordingApplicationWorkspace()
            let launcher = ApplicationLauncher(workspace: workspace, resolveOpenPath: { $0 })
            XCTAssertTrue(launcher.open(name: "Ignored", openPath: path))
            XCTAssertEqual(workspace.events, [.openResource(URL(fileURLWithPath: path))])
        }
    }

    func testUnknownAppFailsWithoutOpeningAnything() {
        let workspace = RecordingApplicationWorkspace()
        XCTAssertFalse(ApplicationLauncher(workspace: workspace).open(name: "Missing App", openPath: "  "))
        XCTAssertTrue(workspace.events.isEmpty)
    }
}

private final class RecordingApplicationWorkspace: LauncherApplicationWorkspace {
    enum Event: Equatable {
        case activate(URL)
        case openApplication(URL)
        case openResource(URL)
    }
    var runningApplications: [RunningLauncherApplication] = []
    var namedURLs: [String: URL] = [:]
    var bundleURLs: [String: URL] = [:]
    var events: [Event] = []
    func applicationURL(bundleIdentifier: String) -> URL? { bundleURLs[bundleIdentifier] }
    func applicationURL(name: String) -> URL? { namedURLs[name] }
    func prepareActivation(at url: URL) { events.append(.activate(url)) }
    func openApplication(at url: URL) { events.append(.openApplication(url)) }
    func openResource(at url: URL) { events.append(.openResource(url)) }
}
