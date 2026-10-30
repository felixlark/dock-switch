import Foundation

/// A single input-source round trip. Dependencies permit regression tests without
/// changing the test host's real input source or foreground application.
public enum PhraseInputRefresh {
    public enum Result: Equatable {
        case refreshed, contextChanged, unavailable, switchFailed, restoreFailed
    }

    public static func run(original: String, alternate: String?, sourcePID: Int32,
                           current: @escaping () -> String?, foreground: @escaping () -> Int32?,
                           select: @escaping (String) -> Bool,
                           afterSwitch: (@escaping () -> Void) -> Void,
                           completion: @escaping (Result) -> Void) {
        guard foreground() == sourcePID, current() == original else { completion(.contextChanged); return }
        guard let alternate, alternate != original else { completion(.unavailable); return }
        guard select(alternate), current() == alternate else { completion(.switchFailed); return }
        afterSwitch {
            // Never overwrite a source/app change made by the user while the
            // input client was processing the switch notification.
            guard foreground() == sourcePID, current() == alternate else { completion(.contextChanged); return }
            guard select(original), current() == original else { completion(.restoreFailed); return }
            completion(.refreshed)
        }
    }
}
