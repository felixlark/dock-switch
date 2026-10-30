import AppKit
import Carbon
import DockSwitchCore

/// Uses only enabled, selectable keyboard sources. Never enables/disables an
/// input method, restarts a client, or injects a keyboard shortcut.
struct PhraseInputSource {
    static let wubiID = "com.apple.inputmethod.SCIM.WBX"

    static func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue() as? T
    }

    static func currentID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return property(source, kTISPropertyInputSourceID)
    }

    static func refresh(original: String?, sourcePID: pid_t, completion: @escaping (String) -> Void) {
        guard let original else { completion("未能读取输入法，请手动切换中英"); return }
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
                      kTISPropertyInputSourceIsEnabled as String: true,
                      kTISPropertyInputSourceIsSelectCapable as String: true] as [String: Any]
        let sources = TISCreateInputSourceList(filter as CFDictionary, false).takeRetainedValue() as! [TISInputSource]
        let englishSources = sources.filter { source in
            let ascii: Bool = property(source, kTISPropertyInputSourceIsASCIICapable) ?? false
            let languages: [String] = property(source, kTISPropertyInputSourceLanguages) ?? []
            return ascii && languages.contains(where: { $0 == "en" || $0.hasPrefix("en-") })
        }.compactMap { property($0, kTISPropertyInputSourceID) as String? }
        // Scope this integration to the configured Apple Wubi and English pair.
        let alternate = original == wubiID ? englishSources.first : englishSources.contains(original) ? wubiID : nil
        let history = PhraseRefreshHistory()
        let sourceCenter = DistributedNotificationCenter.default()
        let appCenter = NSWorkspace.shared.notificationCenter
        let sourceObserver = sourceCenter.addObserver(forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: nil) { _ in history.sourceChanged() }
        let appObserver = appCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: nil) { _ in history.applicationChanged() }
        PhraseInputRefresh.run(original: original,
            alternate: sources.contains(where: { (property($0, kTISPropertyInputSourceID) as String?) == alternate }) ? alternate : nil,
            sourcePID: sourcePID, current: currentID,
            foreground: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            select: { id in
                guard let source = sources.first(where: { (property($0, kTISPropertyInputSourceID) as String?) == id }) else { return false }
                return TISSelectInputSource(source) == noErr
            }, contextUnchanged: { history.unchanged }, afterSwitch: { action in
                // Let the client's run loop observe deselection before restoring.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: action)
            }, completion: { result in
                sourceCenter.removeObserver(sourceObserver)
                appCenter.removeObserver(appObserver)
                switch result {
                case .refreshed: completion("已切换中英并恢复原输入法")
                case .contextChanged: completion("输入状态已变化，未继续切换；可手动切换中英")
                case .unavailable: completion("中英输入法未就绪，请手动切换")
                case .switchFailed: completion("切换输入法失败，请手动切换中英")
                case .restoreFailed: completion("未能恢复原输入法，请手动选择")
                }
            })
    }
}
