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
                           contextUnchanged: @escaping () -> Bool = { true },
                           afterSwitch: (@escaping () -> Void) -> Void,
                           completion: @escaping (Result) -> Void) {
        guard contextUnchanged(), foreground() == sourcePID, current() == original else { completion(.contextChanged); return }
        guard let alternate, alternate != original else { completion(.unavailable); return }
        guard select(alternate), current() == alternate else { completion(.switchFailed); return }
        afterSwitch {
            // Never overwrite a source/app change made by the user while the
            // input client was processing the switch notification.
            guard contextUnchanged(), foreground() == sourcePID, current() == alternate else { completion(.contextChanged); return }
            guard select(original), current() == original else { completion(.restoreFailed); return }
            completion(.refreshed)
        }
    }
}

/// Notification history survives a user leaving and returning to the same state.
/// The first source notification belongs to our one expected programmatic switch;
/// any further source notification or application activation cancels restoration.
public final class PhraseRefreshHistory {
    private let lock = NSLock()
    private var sourceChanges = 0
    private var invalidated = false
    public init() {}
    public func sourceChanged() {
        lock.lock(); defer { lock.unlock() }
        sourceChanges += 1
        if sourceChanges > 1 { invalidated = true }
    }
    public func applicationChanged() {
        lock.lock(); defer { lock.unlock() }
        invalidated = true
    }
    public var unchanged: Bool {
        lock.lock(); defer { lock.unlock() }
        return !invalidated
    }
}
