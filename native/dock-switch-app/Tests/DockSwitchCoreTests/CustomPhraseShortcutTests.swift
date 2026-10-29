import Carbon
import ApplicationServices
import XCTest
@testable import DockSwitchCore

final class CustomPhraseShortcutTests: XCTestCase {
    func testSubroleFailuresCannotReadSelection() {
        XCTAssertFalse(CustomPhraseSelectionPolicy.mayRead(subroleStatus: .cannotComplete, subrole: nil))
        XCTAssertFalse(CustomPhraseSelectionPolicy.mayRead(subroleStatus: .apiDisabled, subrole: nil))
        XCTAssertFalse(CustomPhraseSelectionPolicy.mayRead(subroleStatus: .success, subrole: nil))
        XCTAssertFalse(CustomPhraseSelectionPolicy.mayRead(subroleStatus: .success, subrole: kAXSecureTextFieldSubrole as String))
        XCTAssertTrue(CustomPhraseSelectionPolicy.mayRead(subroleStatus: .success, subrole: "AXSearchField"))
        XCTAssertTrue(CustomPhraseSelectionPolicy.mayRead(subroleStatus: .attributeUnsupported, subrole: nil))
        XCTAssertTrue(CustomPhraseSelectionPolicy.mayRead(subroleStatus: .noValue, subrole: nil))
    }
    func testDefaultUsesPhysicalGraveWithCommandShift() throws {
        let shortcut = CustomPhraseShortcut.default
        XCTAssertEqual(shortcut.keyCode, 50)
        XCTAssertEqual(shortcut.modifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(shortcut.display, "⇧⌘`")
        XCTAssertTrue(shortcut.isValid)
        XCTAssertEqual(try JSONDecoder().decode(CustomPhraseShortcut.self, from: JSONEncoder().encode(shortcut)), shortcut)
    }

    func testPlainTypingAndLauncherTriggerCannotBeCaptured() {
        XCTAssertFalse(CustomPhraseShortcut(keyCode: 13, modifiers: 0, keyLabel: "W").isValid)
        XCTAssertFalse(CustomPhraseShortcut(keyCode: 13, modifiers: UInt32(shiftKey), keyLabel: "W").isValid)
        XCTAssertFalse(CustomPhraseShortcut(keyCode: UInt32(kVK_F20), modifiers: UInt32(cmdKey), keyLabel: "F20").isValid)
        XCTAssertFalse(CustomPhraseShortcut(keyCode: 999, modifiers: UInt32(cmdKey), keyLabel: "?").isValid)
        XCTAssertTrue(CustomPhraseShortcut(keyCode: 13, modifiers: UInt32(cmdKey | controlKey | optionKey), keyLabel: "W").isValid)
    }

    func testStoredConfigurationRoundTripsWithoutMutatingLauncherPreferences() throws {
        let name = "dock-switch-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "codexWorkspaceAutoExpand")
        let shortcut = CustomPhraseShortcut(keyCode: 13, modifiers: UInt32(cmdKey | optionKey), keyLabel: "W")
        defaults.set(try JSONEncoder().encode(shortcut), forKey: CustomPhraseShortcut.preferenceKey)
        XCTAssertEqual(CustomPhraseShortcut.load(defaults), shortcut)
        XCTAssertFalse(defaults.bool(forKey: "codexWorkspaceAutoExpand"))
        defaults.set(Data("invalid".utf8), forKey: CustomPhraseShortcut.preferenceKey)
        XCTAssertEqual(CustomPhraseShortcut.load(defaults), .default)
    }
}
