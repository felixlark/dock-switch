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
        XCTAssertEqual(identity.notification("customPhraseChanged").rawValue,
            "org.example.launcher.customPhraseChanged")
        XCTAssertEqual(identity.notification("customPhraseStatusChanged").rawValue,
            "org.example.launcher.customPhraseStatusChanged")
        XCTAssertEqual(identity.notification("customPhraseRecordingChanged").rawValue,
            "org.example.launcher.customPhraseRecordingChanged")
        XCTAssertEqual(identity.notification("customPhrasePreviewRequested").rawValue,
            "org.example.launcher.customPhrasePreviewRequested")
    }
}
