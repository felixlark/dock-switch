import AppKit
import ApplicationServices
import DockSwitchCore

/// The existing Dock Switch process is the sole owner of quiet tool placement.
/// No activation restoration loop: prevent activation at launch instead.
final class ToolWindowRouter {
    private final class Watch {
        let app: NSRunningApplication
        let observer: AXObserver
        var known: [AXUIElement]
        var documents: Set<URL>?
        init(app: NSRunningApplication, observer: AXObserver, known: [AXUIElement], documents: Set<URL>?) {
            self.app = app; self.observer = observer; self.known = known; self.documents = documents
        }
    }
    private struct Managed {
        let pid: pid_t
        let element: AXUIElement
        var result: String
    }
    private var watches: [pid_t: Watch] = [:]
    private var pausedWatches: [Watch] = []
    private var managed: [Managed] = []
    private var tokens: [NSObjectProtocol] = []
    private var lastOpen: [String: Any] = [:]
    private var observationErrors: [pid_t: Int] = [:]
    private var screenToken: NSObjectProtocol?
    private var targetUUID: String? = UserDefaults.standard.string(forKey: "quietToolDisplayUUID")
    private(set) var enabled = UserDefaults.standard.object(forKey: ToolWindowPolicy.enabledKey) as? Bool ?? true
    private let displays = DisplayService()

    func start() {
        guard tokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.watchUtility(app)
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.remove(app.processIdentifier)
        })
        for event in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            tokens.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] n in
                guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.watchUtility(app)
            })
        }
        if enabled { NSWorkspace.shared.runningApplications.forEach(watchUtility) }
        _ = targetDisplay()
        screenToken = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                // Only still-pending windows; handled/user-moved windows stay put.
                for w in Array(self.watches.values) { self.scan(w) }
            }
    }

    func stop() {
        tokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        tokens.removeAll()
        if let screenToken { NotificationCenter.default.removeObserver(screenToken) }
        screenToken = nil
        for pid in Array(watches.keys) { removeWatch(pid) }
    }

    private func removeWatch(_ pid: pid_t) {
        guard let w = watches.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(w.observer), .commonModes)
    }

    private func remove(_ pid: pid_t) {
        removeWatch(pid)
        managed.removeAll { $0.pid == pid }
        pausedWatches.removeAll { $0.app.processIdentifier == pid }
        observationErrors.removeValue(forKey: pid)
    }

    private func watchUtility(_ app: NSRunningApplication) {
        guard enabled, ToolWindowPolicy.utilityBundles.contains(app.bundleIdentifier ?? "") else { return }
        _ = watch(app, baseline: [], documents: nil)
    }

    private func windows(_ app: NSRunningApplication) -> [AXUIElement] {
        value(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    @discardableResult
    private func watch(_ app: NSRunningApplication, baseline: [AXUIElement], documents: Set<URL>?) -> Bool {
        guard enabled, AXIsProcessTrusted(), app.processIdentifier > 0,
              !ToolWindowPolicy.protectedBundles.contains(app.bundleIdentifier ?? "") else { return false }
        if let existing = watches[app.processIdentifier] {
            // Each request contributes its own manual-window baseline. Reusing
            // an observer must never make a later request claim those windows.
            for window in baseline where !existing.known.contains(where: { CFEqual($0, window) }) {
                existing.known.append(window)
                AXObserverAddNotification(existing.observer, window, kAXTitleChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
            if let documents { existing.documents?.formUnion(documents) }
            scan(existing); return true
        }
        var observer: AXObserver?
        guard AXObserverCreate(app.processIdentifier, { _, _, _, context in
            guard let context else { return }
            let owner = Unmanaged<ToolWindowRouter>.fromOpaque(context).takeUnretainedValue()
            // AX callbacks are delivered on the main run loop.
            for w in Array(owner.watches.values) { owner.scan(w) }
        }, &observer) == .success, let observer else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let watch = Watch(app: app, observer: observer, known: baseline, documents: documents)
        watches[app.processIdentifier] = watch
        let results = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification].map {
            AXObserverAddNotification(observer, appElement, $0 as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        guard results.contains(where: { $0 == .success || $0 == .notificationAlreadyRegistered }) else {
            observationErrors[app.processIdentifier] = Int(results[0].rawValue)
            // Existing windows can still be placed even when this application
            // does not publish window notifications. Do not claim observation.
            scan(watch)
            watches.removeValue(forKey: app.processIdentifier); return false
        }
        observationErrors.removeValue(forKey: app.processIdentifier)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        for window in baseline {
            AXObserverAddNotification(observer, window, kAXTitleChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        scan(watch)
        return true
    }

    private func scan(_ watch: Watch) {
        guard enabled else { return }
        if let claims = watch.documents {
            // Opening a file as a tab in an existing manual window consumes
            // the request without taking ownership of that window.
            watch.documents = ToolWindowPolicy.remainingClaims(claims, knownDocuments: Set(watch.known.compactMap(document)))
            if watch.documents?.isEmpty == true { removeWatch(watch.app.processIdentifier); return }
        }
        for window in windows(watch.app) where !watch.known.contains(where: { CFEqual($0, window) }) {
            if let documents = watch.documents {
                guard let raw = value(window, kAXDocumentAttribute) as? String,
                      let url = URL(string: raw), documents.contains(url.standardizedFileURL) else {
                    // Document metadata may become available after AXWindowCreated.
                    AXObserverAddNotification(watch.observer, window, kAXTitleChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
                    continue
                }
            }
            if place(window, pid: watch.app.processIdentifier) {
                watch.known.append(window)
                if watch.documents != nil, let raw = value(window, kAXDocumentAttribute) as? String, let url = URL(string: raw) {
                    watch.documents?.remove(url.standardizedFileURL)
                }
            }
        }
        // A mixed-use app is observed only until this exact document is claimed.
        if watch.documents?.isEmpty == true { removeWatch(watch.app.processIdentifier) }
    }

    @discardableResult
    private func place(_ window: AXUIElement, pid: pid_t) -> Bool {
        guard enabled else { return false }
        if managed.contains(where: { $0.pid == pid && CFEqual($0.element, window) }) { return true }
        guard let app = NSRunningApplication(processIdentifier: pid),
              !ToolWindowPolicy.protectedBundles.contains(app.bundleIdentifier ?? ""),
              ToolWindowPolicy.eligible(role: value(window, kAXRoleAttribute) as? String ?? "",
                                       subrole: value(window, kAXSubroleAttribute) as? String ?? "",
                                       minimized: value(window, kAXMinimizedAttribute) as? Bool ?? false,
                                       fullscreen: value(window, "AXFullScreen") as? Bool ?? false),
              let frame = frame(window), let target = targetDisplay() else { return false }
        // A visible window already on the target is owned, but never raised.
        let inTarget = ToolWindowPolicy.contained(frame, in: target.workArea)
        let placed = inTarget || move(window, to: ToolWindowPolicy.destination(frame: frame, area: target.workArea))
        if placed {
            managed.append(Managed(pid: pid, element: window, result: inTarget ? "already-on-target" : "placed"))
            if (lastOpen["pid"] as? Int) == Int(pid) { lastOpen["state"] = "placed" }
        }
        return placed
    }

    private func move(_ window: AXUIElement, to rect: DSRect) -> Bool {
        var point = CGPoint(x: rect.x, y: rect.y)
        var size = CGSize(width: rect.width, height: rect.height)
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size),
              let current = frame(window) else { return false }
        if abs(current.width - rect.width) > 1 || abs(current.height - rect.height) > 1 {
            guard AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions) == .success else { return false }
        }
        guard AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success,
              let actual = frame(window) else { return false }
        return abs(actual.x - rect.x) < 3 && abs(actual.y - rect.y) < 3
            && abs(actual.width - rect.width) < 3 && abs(actual.height - rect.height) < 3
            && targetDisplay().map { ToolWindowPolicy.contained(actual, in: $0.workArea) } == true
    }

    func command(_ request: [String: Any]) -> [String: Any] {
        switch request["command"] as? String {
        case "tool-status": return status()
        case "tool-routing":
            guard let flag = request["enabled"] as? Bool else { return error("enabled is required") }
            setEnabled(flag); return status()
        case "tool-exempt": exemptFocused(); return status()
        case "tool-recover": recover(); return status()
        case "tool-place":
            guard let pid = request["pid"] as? Int, let id = request["windowID"] as? Int,
                  let app = NSRunningApplication(processIdentifier: pid_t(pid)),
                  let window = exactWindow(app, id: id) else { return error("No unique live window for this PID/window ID") }
            return ["ok": place(window, pid: pid_t(pid)), "status": status()]
        case "tool-open": return open(request)
        default: return error("Unsupported tool command")
        }
    }

    func setEnabled(_ flag: Bool) {
        enabled = flag
        UserDefaults.standard.set(flag, forKey: ToolWindowPolicy.enabledKey)
        if flag {
            let previous = pausedWatches; pausedWatches.removeAll()
            for w in previous where !w.app.isTerminated { watch(w.app, baseline: w.known, documents: w.documents) }
            NSWorkspace.shared.runningApplications.forEach(watchUtility)
        } else {
            pausedWatches = Array(watches.values)
            for pid in Array(watches.keys) { removeWatch(pid) }
        }
    }

    func exemptFocused() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let window = value(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute) else { return }
        guard CFGetTypeID(window) == AXUIElementGetTypeID() else { return }
        let element = window as! AXUIElement
        if let i = managed.firstIndex(where: { CFEqual($0.element, element) }) { managed[i].result = "exempt" }
        else { managed.append(Managed(pid: app.processIdentifier, element: element, result: "exempt")) }
    }

    func recover() {
        let connected = displays.displays()
        guard enabled, let target = ToolWindowPolicy.target(connected) else { return }
        for i in managed.indices where managed[i].result != "exempt" {
            guard let f = frame(managed[i].element), !connected.contains(where: { ToolWindowPolicy.intersects(f, $0.workArea) }) else { continue }
            if move(managed[i].element, to: ToolWindowPolicy.destination(frame: f, area: target.workArea)) { managed[i].result = "recovered" }
        }
    }

    private func open(_ request: [String: Any]) -> [String: Any] {
        guard enabled else { return error("Tool routing is paused") }
        guard AXIsProcessTrusted() else { return error("Dock Switch Accessibility permission is required") }
        guard let path = request["appPath"] as? String, path.hasPrefix("/"),
              let bundle = Bundle(path: path), path.hasSuffix(".app"),
              !ToolWindowPolicy.protectedBundles.contains(bundle.bundleIdentifier ?? "") else { return error("Use an absolute, non-protected app bundle path") }
        let appURL = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let existing = NSWorkspace.shared.runningApplications.first { $0.bundleURL?.resolvingSymlinksInPath() == appURL }
        let baseline = existing.map(windows) ?? []
        let resource: URL?
        if let raw = request["url"] as? String {
            guard let url = URL(string: raw), ["file", "http", "https"].contains(url.scheme?.lowercased() ?? "") else { return error("url must be file/http/https") }
            resource = url
        } else { resource = nil }
        let existingDocuments = Set(baseline.compactMap { document($0) })
        let scope = ToolWindowPolicy.scope(bundleID: bundle.bundleIdentifier ?? "",
            dedicated: request["dedicated"] as? Bool ?? false, resource: resource, existingDocuments: existingDocuments)
        // File document identity is public AX metadata. Web/tab identity is left
        // to the official browser tool, followed by exact tool-place if needed.
        let documents: Set<URL>?
        switch scope {
        case .dedicated: documents = nil
        case .document(let url): documents = [url]
        case .none: documents = []
        }
        let preObserved: Bool
        if let existing, documents?.isEmpty == false { preObserved = watch(existing, baseline: baseline, documents: documents) }
        else { preObserved = false }
        let id = UUID().uuidString
        lastOpen = ["id": id, "state": "requested"]
        if let existing { lastOpen["pid"] = Int(existing.processIdentifier) }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        let completion: (NSRunningApplication?, Error?) -> Void = { [weak self] app, failure in
            DispatchQueue.main.async {
                guard let self else { return }
                if let failure {
                    if let documents, let existing, let watch = self.watches[existing.processIdentifier], watch.documents != nil {
                        watch.documents?.subtract(documents)
                        if watch.documents?.isEmpty == true { self.removeWatch(existing.processIdentifier) }
                    }
                    self.lastOpen = ["id": id, "state": "failed", "error": failure.localizedDescription]; return
                }
                guard let app else { self.lastOpen = ["id": id, "state": "failed"]; return }
                if let watch = self.watches[app.processIdentifier] { self.scan(watch) }
                let observed: Bool
                if scope != .none {
                    // Never recreate a pre-open claim that was already consumed
                    // by an AX event (including an existing-window/tab reuse).
                    if preObserved { observed = self.watches[app.processIdentifier] != nil }
                    else if let documents,
                            ToolWindowPolicy.remainingClaims(documents, knownDocuments: Set(baseline.compactMap(self.document))).isEmpty {
                        observed = false
                    } else { observed = self.watch(app, baseline: baseline, documents: documents) }
                } else {
                    // Temporal coincidence is not evidence of tool ownership.
                    // Browser/non-file windows need an explicit window ID.
                    observed = false
                }
                let placed = self.windows(app).contains { w in
                    !baseline.contains(where: { CFEqual($0, w) }) && self.managed.contains(where: { CFEqual($0.element, w) })
                }
                let reused = resource?.isFileURL == true && baseline.compactMap(self.document).contains(resource!.standardizedFileURL)
                let alreadyManaged = scope == .dedicated && self.windows(app).contains { w in self.managed.contains(where: { CFEqual($0.element, w) }) }
                let state = placed ? "placed" : reused ? "opened-in-existing-window" : alreadyManaged ? "already-managed" : observed ? "waiting-for-window" : scope != .none ? "observation-unavailable" : "opened-without-window-rule"
                self.lastOpen = ["id": id, "state": state,
                                 "pid": Int(app.processIdentifier), "observing": observed,
                                 "newProcess": existing == nil]
            }
        }
        if let url = resource {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config, completionHandler: completion)
        } else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: completion)
        }
        return ["ok": true, "requestID": id, "state": "requested"]
    }

    private func exactWindow(_ app: NSRunningApplication, id: Int) -> AXUIElement? {
        guard let entries = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]],
              let info = entries.first(where: { ($0[kCGWindowNumber as String] as? Int) == id && ($0[kCGWindowOwnerPID as String] as? Int) == Int(app.processIdentifier) }),
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        let matching = windows(app).filter { w in
            guard let f = frame(w) else { return false }
            return abs(f.x - rect.minX) < 2 && abs(f.y - rect.minY) < 2 && abs(f.width - rect.width) < 2 && abs(f.height - rect.height) < 2
        }
        return matching.count == 1 ? matching[0] : nil
    }

    private func status() -> [String: Any] {
        let target = targetDisplay()
        return ["ok": true, "enabled": enabled, "accessibility": AXIsProcessTrusted(),
                "target": target.map { ["id": $0.id, "name": $0.label] as [String: Any] } ?? [:],
                "lastOpen": lastOpen, "watchedProcesses": watches.count,
                "observationErrors": observationErrors.map { ["pid": Int($0.key), "code": $0.value] },
                "windows": managed.compactMap { record -> [String: Any]? in
                    guard let f = frame(record.element) else { return nil }
                    return ["pid": record.pid, "result": record.result,
                            "frame": ["x": f.x, "y": f.y, "width": f.width, "height": f.height]]
                }]
    }

    private func targetDisplay() -> DisplaySnapshot? {
        let connected = displays.displays()
        func uuid(_ display: DisplaySnapshot) -> String? {
            CGDisplayCreateUUIDFromDisplayID(display.id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
        }
        if let targetUUID { return connected.first { !$0.internalDisplay && uuid($0) == targetUUID } }
        guard let target = ToolWindowPolicy.target(connected), let identity = uuid(target) else { return nil }
        targetUUID = identity
        UserDefaults.standard.set(identity, forKey: "quietToolDisplayUUID")
        return target
    }

    private func error(_ message: String) -> [String: Any] { ["ok": false, "error": message] }
    private func document(_ window: AXUIElement) -> URL? {
        (value(window, kAXDocumentAttribute) as? String).flatMap(URL.init(string:))?.standardizedFileURL
    }
    private func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &v) == .success else { return nil }
        return v
    }
    private func frame(_ window: AXUIElement) -> DSRect? {
        guard let p = value(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = value(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
        return DSRect(x: point.x, y: point.y, width: size.width, height: size.height)
    }
}
