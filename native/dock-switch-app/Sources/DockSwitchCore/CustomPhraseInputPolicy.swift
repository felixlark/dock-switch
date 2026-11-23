import Foundation

public enum CustomPhraseInputPolicy {
    /// A replacement shortcut must be a single non-empty token. The phrase itself
    /// may contain spaces, punctuation, newlines and non-Chinese characters.
    public static func normalizedShortcut(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.unicodeScalars.contains(where: {
                  $0.value == 0 || CharacterSet.whitespacesAndNewlines.contains($0)
              }) else { return nil }
        return trimmed
    }

    /// The local Wubi encoder reports these as expected phrase rejections. Other
    /// failures remain operational errors and must not silently open the manual
    /// shortcut path.
    public static func isWubiTextRejection(_ output: String) -> Bool {
        output.contains("请选择一个连续中文词组")
            || output.contains("五笔 86 码表中没有这些字")
    }

    public static func componentNeedsAnyTextUpgrade(_ output: String) -> Bool {
        output.contains("unrecognized arguments: --any-text")
    }
}
