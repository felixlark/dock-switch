import AppKit
import ApplicationServices

/// Owned by the existing dock-switch app. No helper, key interception, private
/// storage, chat text, or activation. Unknown/localized layouts fail closed.
public final class CodexWorkspaceObserver {
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var pid: pid_t?
    private var subscriptions: [(AXUIElement, String)] = []
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
            "accessibilityTrusted": AXIsProcessTrusted(), "observing": observer != nil,
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
        guard pid != app.processIdentifier else { return }
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
        for name in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification,
                     kAXFocusedUIElementChangedNotification, kAXTitleChangedNotification] {
            subscribe(element, name)
        }
        subscribeWindows()
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        // Seed existing view; enabling/restarting never reopens a manually closed pane.
        if let sample = snapshot() {
            _ = tracker.observe(window: AXIdentity(sample.window), chat: AXIdentity(sample.toolbar), workspaceOpen: sample.open)
        } else {
            tracker.startOutsideChat()
        }
        NSLog("dock-switch: Codex workspace observer attached")
    }

    private func subscribe(_ element: AXUIElement, _ name: String) {
        guard let observer, !subscriptions.contains(where: { CFEqual($0.0, element) && $0.1 == name }) else { return }
        let result = AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        if result == .success { subscriptions.append((element, name)) }
    }

    private func subscribeWindows() {
        guard let application, let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] else { return }
        // Remove stale window subscriptions without retaining every historical window.
        if let observer {
            subscriptions.removeAll { entry in
                guard !CFEqual(entry.0, application), !windows.contains(where: { CFEqual($0, entry.0) }) else { return false }
                AXObserverRemoveNotification(observer, entry.0, entry.1 as CFString)
                return true
            }
        }
        for window in windows { subscribe(window, kAXTitleChangedNotification) }
    }

    private func detach() {
        generation += 1
        pending?.cancel()
        pending = nil
        if let observer {
            for (element, name) in subscriptions { AXObserverRemoveNotification(observer, element, name as CFString) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        subscriptions.removeAll()
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
        guard CodexWorkspacePreference.enabled, AXIsProcessTrusted(), let sample = snapshot() else { return }
        guard tracker.observe(window: AXIdentity(sample.window), chat: AXIdentity(sample.toolbar), workspaceOpen: sample.open),
              let button = sample.newTab else { return }
        // Re-read immediately before AXPress: no cached button on a newly navigated
        // chat/window, no activation, no retries after an unknown action result.
        guard let current = snapshot(), CFEqual(current.window, sample.window),
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

    private func snapshot() -> Sample? {
        guard pid != nil, let application, let window = elementAttribute(application, kAXFocusedWindowAttribute),
              attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              attribute(window, kAXMinimizedAttribute) as? Bool == false,
              (attribute(window, "AXSheets") as? [AXUIElement] ?? []).isEmpty,
              let toolbar = find(in: window, matching: { role, label in role == kAXToolbarRole && label == "Chat toolbar" }),
              let header = elementAttribute(toolbar, kAXParentAttribute) else { return nil }
        let tabs = find(in: header, matching: { role, label in role == kAXTabGroupRole && label == "Chat tabs" })
        let button = find(in: header, matching: { role, label in role == kAXButtonRole && label == "New tab" })
        guard tabs != nil || button != nil else { return nil }
        return Sample(window: window, toolbar: toolbar, open: tabs != nil, newTab: button)
    }

    /// Structural/header traversal only. Never enter the conversation, composer,
    /// sidebar lists, browser web content, or read AXValue/selected text.
    private func find(in root: AXUIElement, matching: (String, String) -> Bool) -> AXUIElement? {
        var queue = [root]
        var visited = Set<AXIdentity>()
        var index = 0
        while index < queue.count {
            let element = queue[index]
            index += 1
            guard visited.insert(AXIdentity(element)).inserted else { continue }
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            guard ![kAXStaticTextRole, kAXTextAreaRole, kAXTextFieldRole].contains(role) else { continue }
            if role == "AXWebArea" {
                guard let url = attribute(element, kAXURLAttribute) as? URL,
                      url.scheme == "app", url.host == "-", url.path == "/index.html" else { continue }
            }
            let label = (attribute(element, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? attribute(element, kAXDescriptionAttribute) as? String ?? ""
            if matching(role, label) { return element }
            if ["Conversation", "Latest response", "Navigation", "App navigation"].contains(label) { continue }
            if [kAXButtonRole, kAXCheckBoxRole, kAXPopUpButtonRole, kAXListRole, "AXOutline", "AXTable", "AXComboBox", "AXLink", kAXTabGroupRole, kAXToolbarRole].contains(role) { continue }
            queue += attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return nil
    }
}

private struct AXIdentity: Hashable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
}

private func elementAttribute(_ element: AXUIElement, _ key: String) -> AXUIElement? {
    guard let value = attribute(element, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
