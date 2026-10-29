import Carbon
import Foundation

/// Physical virtual-key code plus Carbon modifiers; independent of input source
/// and shifted characters (notably the grave/tilde key).
public struct CustomPhraseShortcut: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var keyLabel: String

    public init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    public static let `default` = Self(keyCode: UInt32(kVK_ANSI_Grave),
        modifiers: UInt32(cmdKey | shiftKey), keyLabel: "`")
    public static let preferenceKey = "customPhraseShortcut"
    public static let enabledKey = "customPhraseEnabled"
    public static let statusKey = "customPhraseStatus"
    public static let suiteName = "me.longbiaochen.dock-switch"
    public static let changed = Notification.Name("me.longbiaochen.dock-switch.customPhraseChanged")
    public static let statusChanged = Notification.Name("me.longbiaochen.dock-switch.customPhraseStatusChanged")
    public static let recordingChanged = Notification.Name("me.longbiaochen.dock-switch.customPhraseRecordingChanged")
    public static let previewRequested = Notification.Name("me.longbiaochen.dock-switch.customPhrasePreviewRequested")
    public static let componentFiles = ["encode.py", "wubi86.dict.yaml", "known-phrases.json",
        "db-candidate/append_phrase.py", "db-candidate/schema.json"]

    public var display: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + keyLabel
    }

    public var isValid: Bool {
        let allowed = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        return keyCode < 128 && keyCode != UInt32(kVK_F20)
            && modifiers & allowed == modifiers && modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
            && !keyLabel.isEmpty
    }

    public static func load(_ defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: preferenceKey),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return .default }
        return value
    }
}
