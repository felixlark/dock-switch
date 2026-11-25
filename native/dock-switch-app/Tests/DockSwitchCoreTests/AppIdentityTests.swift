import XCTest
@testable import DockSwitchCore

final class AppIdentityTests: XCTestCase {
    func testUnbundledDevelopmentUsesNeutralNamespace() {
        XCTAssertEqual(AppIdentity(info: [:]).dataNamespace, "io.github.felixlark.dock-switch")
    }

    func testSettingsIDDoesNotBecomePreferenceDomain() {
        let identity = AppIdentity(info: ["CFBundleIdentifier": "org.example.preferences",
            "DockSwitchDataNamespace": "org.example.launcher"])
        XCTAssertEqual(identity.dataNamespace, "org.example.launcher")
        XCTAssertEqual(identity.notification("settingsChanged").rawValue,
            "org.example.launcher.settingsChanged")
    }
}
