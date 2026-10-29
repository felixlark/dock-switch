import AppKit
import ApplicationServices

/// Owned by the existing dock-switch app. No helper, key interception, private
/// storage, chat text, or activation. Unknown/localized layouts fail closed.
public final class CodexWorkspaceObserver {
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var pid: pid_t?
    private var subscriptions = CodexWorkspaceSubscriptions<AXIdentity>()
    private var workspaceTokens: [NSObjectProtocol] = []
    private var maintenance: Timer?
    private var pending: DispatchWorkItem?
    private var generation = 0
    private var eventCount = 0
    private var pressCount = 0
    private var lastPressResult: Int32?
    private var tracker = CodexWorkspaceSwitchTracker<AXIdentity>()

    public init() {}
    deinit { stop() }

    public func status() -> [String: Any] {
        var result: [String: Any] = ["enabled": CodexWorkspacePreference.enabled,
            "accessibilityTrusted": AXIsProcessTrusted(), "observing": observer != nil && subscriptions.activeCount > 0,
            "activeSubscriptions": subscriptions.activeCount,
            "unsupportedSubscriptions": subscriptions.unsupportedCount,
            "retryableSubscriptions": subscriptions.retryableCount,
            "events": eventCount, "pressCount": pressCount]
        if let pid { result["targetPID"] = pid }
        if let lastPressResult { result["lastPressResult"] = lastPressResult }
        return result
    }

    public func start() {
        guard maintenance == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reconcile()
            })
        }
        // Only preference/trust/process discovery is polled, never the AX tree.
        maintenance = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.reconcile() }
        reconcile()
    }

    public func stop() {
        maintenance?.invalidate()
        maintenance = nil
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens.removeAll()
        detach()
    }

    private func reconcile() {
        guard CodexWorkspacePreference.enabled, AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first,
              !app.isTerminated else { detach(); return }
        if pid == app.processIdentifier {
            subscribeApplication()
            subscribeWindows()
            return
        }
        detach()
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var created: AXObserver?
        let result = AXObserverCreate(app.processIdentifier, { _, element, notification, context in
            guard let context else { return }
            Unmanaged<CodexWorkspaceObserver>.fromOpaque(context).takeUnretainedValue()
                .received(element, notification as String)
        }, &created)
        guard result == .success, let created else {
            NSLog("dock-switch: Codex AX observer unavailable (%d)", result.rawValue)
            return
        }
        pid = app.processIdentifier
        application = element
        observer = created
        subscribeApplication()
        subscribeWindows()
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        // Seed existing view; enabling/restarting never reopens a manually closed pane.
        switch snapshot() {
        case .chat(let sample):
            _ = tracker.observe(window: AXIdentity(sample.window), chat: AXIdentity(sample.toolbar), workspaceOpen: sample.open)
        case .outside: tracker.startOutsideChat()
        case .unknown: tracker.reset()
        }
        NSLog("dock-switch: Codex workspace observer attached")
    }

    private func subscribeApplication() {
        guard let application else { return }
        for name in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification,
                     kAXFocusedUIElementChangedNotification, kAXTitleChangedNotification] {
            subscribe(application, name)
        }
    }

    private func subscribe(_ element: AXUIElement, _ name: String) {
        guard let observer else { return }
        subscriptions.ensure(element: AXIdentity(element), notification: name) {
            let result = AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
            switch result {
            case .success, .notificationAlreadyRegistered: return .active
            case .notificationUnsupported: return .unsupported
            default: return .retryable(result.rawValue)
            }
        }
    }

    private func subscribeWindows() {
        guard let application, let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement],
              let observer else { return }
        // A failed window-list read preserves subscriptions for the next maintenance tick.
        subscriptions.remove(where: { entry in
            !CFEqual(entry.element.element, application) && !windows.contains(where: { CFEqual($0, entry.element.element) })
        }, unregister: { entry in
            AXObserverRemoveNotification(observer, entry.element.element, entry.notification as CFString)
        })
        for window in windows { subscribe(window, kAXTitleChangedNotification) }
    }

    private func detach() {
        generation += 1
        pending?.cancel()
        pending = nil
        if let observer {
            subscriptions.remove(where: { _ in true }, unregister: { entry in
                AXObserverRemoveNotification(observer, entry.element.element, entry.notification as CFString)
            })
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        subscriptions = CodexWorkspaceSubscriptions()
        observer = nil
        application = nil
        pid = nil
        tracker.reset()
    }

    private func received(_ element: AXUIElement, _ name: String) {
        if name == kAXTitleChangedNotification {
            guard attribute(element, kAXRoleAttribute) as? String == kAXWindowRole else { return }
        }
        if name == kAXWindowCreatedNotification || name == kAXFocusedWindowChangedNotification { subscribeWindows() }
        eventCount += 1
        // Coalesce Chromium's duplicate top-level events and allow view mounting.
        // Focus changes also cover navigation between identically named chats.
        pending?.cancel()
        generation += 1
        let expectedGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expectedGeneration else { return }
            self.inspect()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func inspect() {
        guard CodexWorkspacePreference.enabled, AXIsProcessTrusted(), case .chat(let sample) = snapshot() else { return }
        guard tracker.observe(window: AXIdentity(sample.window), chat: AXIdentity(sample.toolbar), workspaceOpen: sample.open),
              let button = sample.newTab else { return }
        // Re-read immediately before AXPress: no cached button on a newly navigated
        // chat/window, no activation, no retries after an unknown action result.
        guard case .chat(let current) = snapshot(), CFEqual(current.window, sample.window),
              CFEqual(current.toolbar, sample.toolbar), !current.open,
              let currentButton = current.newTab, CFEqual(currentButton, button),
              attribute(currentButton, kAXEnabledAttribute) as? Bool == true,
              CodexWorkspacePreference.enabled, AXIsProcessTrusted() else { return }
        let result = AXUIElementPerformAction(currentButton, kAXPressAction as CFString)
        pressCount += 1
        lastPressResult = result.rawValue
        NSLog("dock-switch: Codex workspace AXPress result=%d", result.rawValue)
    }

    private struct Sample {
        let window: AXUIElement
        let toolbar: AXUIElement
        let open: Bool
        let newTab: AXUIElement?
    }

    private enum Snapshot {
        case chat(Sample)
        case outside
        case unknown
    }

    private func snapshot() -> Snapshot {
        guard pid != nil, let application, let window = elementAttribute(application, kAXFocusedWindowAttribute),
              attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              attribute(window, kAXMinimizedAttribute) as? Bool == false else { return .unknown }
        switch readAttribute(window, "AXSheets") {
        case .value(let value):
            guard let sheets = value as? [AXUIElement], sheets.isEmpty else { return .unknown }
        case .absent: break
        case .failed: return .unknown
        }
        // Chromium modal dialogs can replace the exposed toolbar identity while
        // retaining the same chat. Do not seed/update the switch tracker through one.
        switch CodexWorkspaceTreeSearch.findNode(root: AXIdentity(window), read: readNode, matching: {
            $0.subrole == "AXApplicationDialog" || ["AXDialog", "AXSheet"].contains($0.role)
        }) {
        case .absent: break
        case .found, .unknown: return .unknown
        }
        let toolbar: AXUIElement
        switch find(in: window, matching: { role, label in role == kAXToolbarRole && label == "Chat toolbar" }) {
        case .found(let element): toolbar = element
        case .absent: return .outside
        case .unknown: return .unknown
        }
        guard let header = elementAttribute(toolbar, kAXParentAttribute) else { return .unknown }
        let state = CodexWorkspaceHeaderSearch.nearest(startingAt: AXIdentity(header), parent: { identity in
            elementAttribute(identity.element, kAXParentAttribute).map(AXIdentity.init)
        }, inspect: { identity -> CodexWorkspaceHeaderState<AXIdentity> in
            let group = identity.element
            // Do not ascend into the shell/web content or cross a failed role read.
            guard attribute(group, kAXRoleAttribute) as? String == kAXGroupRole else { return .unknown }
            switch find(in: group, matching: { role, label in role == kAXTabGroupRole && label == "Chat tabs" }) {
            case .found: return .open
            case .unknown: return .unknown
            case .absent:
                switch find(in: group, matching: { role, label in role == kAXButtonRole && label == "New tab" }) {
                case .found(let button): return .closed(AXIdentity(button))
                case .absent: return .absent
                case .unknown: return .unknown
                }
            }
        })
        switch state {
        case .open: return .chat(Sample(window: window, toolbar: toolbar, open: true, newTab: nil))
        case .closed(let button): return .chat(Sample(window: window, toolbar: toolbar, open: false, newTab: button.element))
        case .absent, .unknown: return .unknown
        }
    }

    /// Structural/header traversal only. Never enter the conversation, composer,
    /// sidebar lists, browser web content, or read AXValue/selected text.
    private func find(in root: AXUIElement, matching: (String, String) -> Bool) -> CodexWorkspaceSearchResult<AXUIElement> {
        let result = CodexWorkspaceTreeSearch.find(root: AXIdentity(root), read: readNode, matching: matching)
        switch result {
        case .found(let identity): return .found(identity.element)
        case .absent: return .absent
        case .unknown: return .unknown
        }
    }

    private func readNode(_ identity: AXIdentity) -> CodexWorkspaceScanNode<AXIdentity>? {
        let element = identity.element
        guard let role = attribute(element, kAXRoleAttribute) as? String else { return nil }
        if [kAXStaticTextRole, kAXTextAreaRole, kAXTextFieldRole].contains(role) {
            return CodexWorkspaceScanNode(role: role, label: "", children: [])
        }
        if role == "AXWebArea" {
            guard let url = attribute(element, kAXURLAttribute) as? URL else { return nil }
            if url.scheme != "app" || url.host != "-" || url.path != "/index.html" {
                return CodexWorkspaceScanNode(role: role, label: "", children: [])
            }
        }
        let subrole: String
        switch readAttribute(element, kAXSubroleAttribute) {
        case .value(let value):
            guard let text = value as? String else { return nil }
            subrole = text
        case .absent: subrole = ""
        case .failed: return nil
        }
        var label = ""
        for key in [kAXTitleAttribute, kAXDescriptionAttribute] {
            switch readAttribute(element, key) {
            case .value(let value):
                guard let text = value as? String else { return nil }
                if !text.isEmpty { label = text }
            case .absent: break
            case .failed: return nil
            }
            if !label.isEmpty { break }
        }
        if CodexWorkspaceTreeSearch.prunesChildren(role: role, label: label) {
            return CodexWorkspaceScanNode(role: role, label: label, children: [], subrole: subrole)
        }
        let children: [AXIdentity]?
        switch readAttribute(element, kAXChildrenAttribute) {
        case .value(let value): children = (value as? [AXUIElement])?.map(AXIdentity.init)
        case .absent: children = []
        case .failed: children = nil
        }
        return CodexWorkspaceScanNode(role: role, label: label, children: children, subrole: subrole)
    }

}

private struct AXIdentity: Hashable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

private enum AXAttributeRead {
    case value(CFTypeRef)
    case absent
    case failed
}

private func readAttribute(_ element: AXUIElement, _ key: String) -> AXAttributeRead {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
    switch result {
    case .success:
        return value.map(AXAttributeRead.value) ?? .failed
    case .attributeUnsupported, .noValue: return .absent
    default: return .failed
    }
}

private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    guard case .value(let value) = readAttribute(element, key) else { return nil }
    return value
}

private func elementAttribute(_ element: AXUIElement, _ key: String) -> AXUIElement? {
    guard let value = attribute(element, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
