import AppKit
import Carbon
import DockSwitchCore
import QuartzCore
import SwiftUI

@main
final class DockSwitchApp: NSObject, NSApplicationDelegate {
    private static var sharedDelegate: DockSwitchApp?
    private let configStore = ConfigStore()
    private let displayService = DisplayService()
    private let dockSnapshotService = DockSnapshotService()
    private let dockVisibilityService = DockVisibilityService()
    private let overlayLayoutService = OverlayLayoutService()
    private let windowPlacementService = WindowPlacementService()
    private let mouseFeedbackPresenter = MouseFeedbackPresenter()
    private lazy var codexDisplaySelectionService = CodexDisplaySelectionService(
        showMouseFeedback: { [weak self] point in
            self?.mouseFeedbackPresenter.show(at: point)
        }
    )
    private lazy var launcherService = LauncherService(
        windowPlacement: windowPlacementService,
        showMouseFeedback: { [weak self] point in
            self?.mouseFeedbackPresenter.show(at: point)
        }
    )
    private var controlServer: ControlServer?
    private var gokit5SerialListener: Gokit5SerialListener?
    private var statusItem: NSStatusItem?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var overlayPanel: OverlayPanel?
    private var keyMonitor: Any?
    private var currentTargets: [OverlayTarget] = []
    private var previousWindowOwnerPID: pid_t?
    private var lastModifierShortcut: (key: String, time: Date)?

    static func main() {
        let app = NSApplication.shared
        let delegate = DockSwitchApp()
        sharedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("dock-switch runs a global launcher hotkey and control socket")
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        registerHotKey()
        startControlServer()
        startGokit5SerialListener()
        _ = ensureAccessibilityPermission(prompt: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hideLauncher()
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        gokit5SerialListener?.stop()
        controlServer?.stop()
        mouseFeedbackPresenter.close()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let iconURL = Bundle.main.url(forResource: "icon", withExtension: "icns"),
           let image = NSImage(contentsOf: iconURL) {
            image.size = StatusItemIconPolicy.size
            image.isTemplate = StatusItemIconPolicy.usesTemplateImage
            statusItem?.button?.image = image
            statusItem?.button?.imagePosition = .imageOnly
            statusItem?.button?.toolTip = StatusItemIconPolicy.accessibilityLabel
            statusItem?.button?.setAccessibilityLabel(StatusItemIconPolicy.accessibilityLabel)
        } else {
            statusItem?.button?.title = "DS"
            statusItem?.button?.toolTip = StatusItemIconPolicy.accessibilityLabel
            statusItem?.button?.setAccessibilityLabel(StatusItemIconPolicy.accessibilityLabel)
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Launcher", action: #selector(showLauncherMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func showLauncherMenu() {
        _ = showLauncher()
    }

    @objc private func openSettings() {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("DockSwitchSettings.app"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Resources/DockSwitchSettings.app"),
            URL(fileURLWithPath: "/Applications/dock-switch.app/Contents/Resources/DockSwitchSettings.app")
        ].compactMap { $0 }
        if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { NSLog("dock-switch: failed to open settings: \(error.localizedDescription)") }
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func startControlServer() {
        controlServer = ControlServer(
            displayService: displayService,
            windowPlacement: windowPlacementService,
            showLauncher: { [weak self] in
                guard let self else { return false }
                return self.runOnMain { self.showLauncher() }
            },
            hideLauncher: { [weak self] in
                guard let self else { return false }
                return self.runOnMain {
                    self.hideLauncher()
                    return true
                }
            },
            showMouseFeedback: { [weak self] point in
                guard let self else { return }
                self.runOnMain {
                    self.mouseFeedbackPresenter.show(at: point)
                }
            },
            getGokit5Status: { [weak self] in
                guard let self, let listener = self.gokit5SerialListener else {
                    return ["enabled": false, "status": "disabled", "running": false, "portPath": ""]
                }
                return listener.snapshot().json()
            },
            selectCodexDisplay: { [weak self] command in
                guard let self else { return ["ok": false, "error": "dock-switch runtime is not ready"] }
                let target = command["target"] as? String ?? ""
                let appName = command["appName"] as? String ?? "Codex"
                let source = command["source"] as? String ?? ""
                return self.runOnMain {
                    self.codexDisplaySelectionService.select(target: target, appName: appName, source: source)
                }
            }
        )
        controlServer?.start()
    }

    private func startGokit5SerialListener() {
        if ProcessInfo.processInfo.environment["DOCK_SWITCH_GOKIT5"] == "0" {
            return
        }
        let listener = Gokit5SerialListener { [weak self] action, button, _ in
            guard let self else { return }
            let inputPhrase = KeyboardShortcutInput.isCommandPressed()
                ? Gokit5Serial.inputPhrase(for: button)
                : nil
            DispatchQueue.main.async {
                if let phrase = inputPhrase {
                    _ = KeyboardShortcutInput.insertText(phrase)
                    return
                }
                if let target = action.mouseTarget {
                    let result = self.windowPlacementService.moveMouseToDisplayTarget(target)
                    if result.ok, let point = result.feedbackPoint {
                        self.mouseFeedbackPresenter.show(at: point)
                    }
                } else if let target = action.codexTarget {
                    _ = self.codexDisplaySelectionService.select(
                        target: target,
                        appName: action.name,
                        source: "gokit5"
                    )
                } else {
                    self.launcherService.activate(action)
                }
            }
        }
        gokit5SerialListener = listener
        listener.start()
    }

    private func runOnMain<T>(_ work: @escaping () -> T) -> T {
        if Thread.isMainThread { return work() }
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        DispatchQueue.main.async {
            result = work()
            semaphore.signal()
        }
        semaphore.wait()
        return result!
    }

    private func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        return false
    }

    private func registerHotKey() {
        let hotKeyID = EventHotKeyID(signature: fourCharCode("DS20"), id: 1)
        RegisterEventHotKey(UInt32(kVK_F20), 0, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }
            let app = Unmanaged<DockSwitchApp>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if hotKeyID.id == 1 {
                DispatchQueue.main.async {
                    app.toggleLauncher()
                }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    private func toggleLauncher() {
        if overlayPanel?.isVisible == true {
            hideLauncher()
        } else {
            _ = showLauncher()
        }
    }

    @discardableResult
    private func showLauncher() -> Bool {
        guard ensureAccessibilityPermission(prompt: true) else {
            NSLog("dock-switch: Accessibility permission is required to show launcher")
            return false
        }
        previousWindowOwnerPID = currentFrontmostPID()
        dockVisibilityService.showDock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.showLauncherAfterDockSettles()
        }
        return true
    }

    private func showLauncherAfterDockSettles() {
        let items = (try? dockSnapshotService.queryDockItems()) ?? []
        guard !items.isEmpty else {
            NSLog("dock-switch: no Dock items available for launcher")
            return
        }
        dockSnapshotService.writeCache(items)
        let config = configStore.load()
        let launcherItems = LauncherRules.buildLauncherItems(dockItems: items, config: config)
        guard let layout = overlayLayoutService.resolve(
            launcherItems: launcherItems,
            displays: displayService.displays()
        ) else {
            NSLog("dock-switch: failed to resolve launcher overlay layout")
            return
        }
        currentTargets = layout.targets
        showOverlay(layout)
    }

    private func showOverlay(_ layout: OverlayLayout) {
        let frame = appKitFrame(fromAX: layout.windowFrameAX)
        let panel = overlayPanel ?? OverlayPanel()
        overlayPanel = panel
        let view = LauncherOverlayView(
            targets: layout.targets,
            onSelect: { [weak self] item in
                self?.activate(item)
            }
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.alphaValue = 1
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        startKeyMonitor()
    }

    private func hideLauncher() {
        stopKeyMonitor()
        currentTargets = []
        guard let panel = overlayPanel else {
            dockVisibilityService.restoreDock()
            return
        }
        let frame = panel.frame
        let scale = CGFloat(OverlayAnimationPolicy.hideScale)
        let hiddenFrame = NSRect(
            x: frame.midX - frame.width * scale / 2,
            y: frame.midY - frame.height * scale / 2,
            width: frame.width * scale,
            height: frame.height * scale
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlayAnimationPolicy.hideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(hiddenFrame, display: true)
        } completionHandler: { [weak self, weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
            self?.dockVisibilityService.restoreDock()
        }
    }

    private func activate(_ item: LauncherItem) {
        hideLauncher()
        launcherService.activate(item)
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                return self.handleFlagsChanged(event)
            }
            if event.keyCode == UInt16(kVK_Escape) {
                self.hideLauncher()
                return nil
            }
            if let action = self.windowAction(for: event) {
                self.runWindowAction(action)
                return nil
            }
            if self.handleAppShortcut(for: event) {
                return nil
            }
            if let item = self.item(for: event) {
                self.activate(item)
                return nil
            }
            return event
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func item(for event: NSEvent) -> LauncherItem? {
        let text = LauncherRules.normalizeEventKey(
            characters: event.charactersIgnoringModifiers ?? event.characters ?? "",
            keyCode: event.keyCode
        )
        return item(forNormalizedKey: text)
    }

    private func item(forNormalizedKey text: String) -> LauncherItem? {
        return currentTargets.first { target in
            target.item.key.uppercased() == text || target.item.displayKey.uppercased() == text
        }?.item
    }

    private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == UInt16(kVK_Shift), event.modifierFlags.contains(.shift) {
            activateShortcut("LEFT_SHIFT")
            return nil
        }
        if event.keyCode == UInt16(kVK_RightShift), event.modifierFlags.contains(.shift) {
            activateShortcut("RIGHT_SHIFT")
            return nil
        }
        if event.keyCode == UInt16(kVK_Command), event.modifierFlags.contains(.command) {
            activateShortcut("COMMAND_LEFT")
            return nil
        }
        if event.keyCode == UInt16(kVK_RightCommand), event.modifierFlags.contains(.command) {
            activateShortcut("COMMAND_RIGHT")
            return nil
        }
        return event
    }

    private func handleAppShortcut(for event: NSEvent) -> Bool {
        let normalized = LauncherRules.normalizeEventKey(
            characters: event.charactersIgnoringModifiers ?? event.characters ?? "",
            keyCode: event.keyCode
        )
        guard LauncherShortcutRules.isReserved(normalized) else { return false }
        activateShortcut(normalized)
        return true
    }

    private func activateShortcut(_ normalizedKey: String) {
        if let lastModifierShortcut,
           lastModifierShortcut.key == normalizedKey,
           Date().timeIntervalSince(lastModifierShortcut.time) < 0.25 {
            return
        }
        lastModifierShortcut = (normalizedKey, Date())
        // Resolve before hiding: hideLauncher() clears currentTargets.
        let target = item(forNormalizedKey: normalizedKey)
        hideLauncher()
        if let item = target {
            launcherService.activate(item)
            return
        }
        guard let item = LauncherShortcutRules.launcherItem(
            for: normalizedKey,
            config: configStore.load()
        ) else {
            return
        }
        launcherService.activate(item)
    }

    private func windowAction(for event: NSEvent) -> String? {
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            return "up"
        case kVK_DownArrow:
            return "down"
        case kVK_LeftArrow:
            return "left"
        case kVK_RightArrow:
            return "right"
        case kVK_ANSI_LeftBracket:
            return "current_left"
        case kVK_ANSI_RightBracket:
            return "current_right"
        default:
            let text = event.charactersIgnoringModifiers ?? event.characters ?? ""
            return LauncherShortcutRules.windowAction(key: text)
        }
    }

    private func runWindowAction(_ action: String) {
        let preferredPID = previousWindowOwnerPID
        hideLauncher()
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
            guard let self else { return }
            var result = self.windowPlacementService.placeWindowByAction(action, preferredPID: preferredPID)
            if !result.ok {
                result = self.windowPlacementService.placeWindowByAction(action)
            }
            if result.ok, let point = result.feedbackPoint {
                self.mouseFeedbackPresenter.show(at: point)
            }
        }
    }

    private func currentFrontmostPID() -> pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              LauncherRules.normalizeAppName(app.localizedName ?? "") != "dock-switch" else {
            return previousWindowOwnerPID
        }
        return ApplicationProcessIdentity.resolvedPID(for: app)
    }

    private func appKitFrame(fromAX rect: DSRect) -> NSRect {
        let displays = displayService.displays()
        let targetDisplay = DisplayGeometry.display(containing: rect, displays: displays)
        if let targetDisplay,
           let screen = NSScreen.screens.first(where: { screen in
               let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
               return id == targetDisplay.id
           }) {
            let converted = DisplayGeometry.appKitFrame(
                fromAX: rect,
                inDisplay: targetDisplay.bounds,
                appKitDisplayFrame: DSRect(
                    x: Double(screen.frame.origin.x),
                    y: Double(screen.frame.origin.y),
                    width: Double(screen.frame.width),
                    height: Double(screen.frame.height)
                )
            )
            return NSRect(x: converted.x, y: converted.y, width: converted.width, height: converted.height)
        }
        let mainHeight = NSScreen.main?.frame.height ?? 0
        return NSRect(x: rect.x, y: Double(mainHeight) - rect.y - rect.height, width: rect.width, height: rect.height)
    }
}

private final class MouseFeedbackPresenter {
    private let size = CGSize(width: 132, height: 132)
    private let hideDelay: TimeInterval = MouseFeedbackView.pulseDuration + 0.04
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(at quartzPoint: CGPoint) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.show(at: quartzPoint)
            }
            return
        }
        guard quartzPoint.x.isFinite, quartzPoint.y.isFinite else { return }

        let origin = Self.appKitWindowOrigin(forQuartzPoint: quartzPoint, windowSize: size)
        let panel = feedbackPanel()
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        panel.orderFrontRegardless()
        pulse(in: panel)
        scheduleHide()
    }

    func close() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        (panel?.contentView as? MouseFeedbackView)?.stopPulse()
        panel?.close()
        panel = nil
    }

    private func feedbackPanel() -> NSPanel {
        if let panel {
            return panel
        }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.canHide = false
        panel.hidesOnDeactivate = false
        panel.sharingType = .readOnly
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        panel.contentView = MouseFeedbackView(frame: NSRect(origin: .zero, size: size))
        self.panel = panel
        return panel
    }

    private func pulse(in panel: NSPanel) {
        (panel.contentView as? MouseFeedbackView)?.startPulse()
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: item)
    }

    private static func appKitWindowOrigin(forQuartzPoint point: CGPoint, windowSize: CGSize) -> CGPoint {
        for screen in NSScreen.screens {
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            guard id != 0 else { continue }
            let quartzBounds = CGDisplayBounds(CGDirectDisplayID(id))
            guard quartzBounds.contains(point) else { continue }
            let localX = point.x - quartzBounds.minX
            let localY = point.y - quartzBounds.minY
            return CGPoint(
                x: screen.frame.minX + localX - windowSize.width / 2,
                y: screen.frame.maxY - localY - windowSize.height / 2
            )
        }
        let mouseLocation = NSEvent.mouseLocation
        return CGPoint(
            x: mouseLocation.x - windowSize.width / 2,
            y: mouseLocation.y - windowSize.height / 2
        )
    }
}

private final class MouseFeedbackView: NSView {
    static let pulseDuration: TimeInterval = 0.56
    private let rings: [(layer: CAShapeLayer, diameter: CGFloat, lineWidth: CGFloat, alpha: Float)] = [
        (CAShapeLayer(), 54, 3, 0.95),
        (CAShapeLayer(), 62, 4, 0.52),
        (CAShapeLayer(), 72, 8, 0.28)
    ]

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        for ring in rings {
            ring.layer.fillColor = NSColor.clear.cgColor
            ring.layer.strokeColor = NSColor.controlAccentColor.usingColorSpace(.deviceRGB)?.cgColor ?? NSColor.systemBlue.cgColor
            ring.layer.lineCap = .round
            ring.layer.lineJoin = .round
            ring.layer.lineWidth = ring.lineWidth
            ring.layer.opacity = 0
            layer?.addSublayer(ring.layer)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateRingPaths()
    }

    func startPulse() {
        updateRingPaths()
        let duration = MouseFeedbackView.pulseDuration
        for (index, ring) in rings.enumerated() {
            ring.layer.removeAllAnimations()
            ring.layer.opacity = 0
            ring.layer.transform = CATransform3DIdentity

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, ring.alpha, ring.alpha * 0.82, 0]
            opacity.keyTimes = [0, 0.14, 0.46, 1]

            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.72, 0.94, 1.22, 1.54]
            scale.keyTimes = [0, 0.18, 0.58, 1]

            let group = CAAnimationGroup()
            group.animations = [opacity, scale]
            group.duration = duration
            group.beginTime = CACurrentMediaTime() + Double(index) * 0.018
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.isRemovedOnCompletion = true
            ring.layer.add(group, forKey: "dock-switch-mouse-feedback")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.stopPulse()
        }
    }

    func stopPulse() {
        for ring in rings {
            ring.layer.removeAllAnimations()
            ring.layer.opacity = 0
            ring.layer.transform = CATransform3DIdentity
        }
    }

    private func updateRingPaths() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for ring in rings {
            let diameter = ring.diameter
            let rect = CGRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            ring.layer.frame = bounds
            ring.layer.path = CGPath(ellipseIn: rect, transform: nil)
        }
    }
}

final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct LauncherOverlayView: View {
    let targets: [OverlayTarget]
    let onSelect: (LauncherItem) -> Void
    @State private var focusedItem: LauncherItem?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.24), lineWidth: 1)
                }
            ForEach(targets) { target in
                Text(target.item.displayKey)
                    .font(.system(size: target.item.displayKey.count > 1 ? 18 : 21, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: target.frame.width, height: target.frame.height)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color(red: 0.03, green: 0.48, blue: 0.62).opacity(0.96))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(.white.opacity(0.38), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
                    .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .onTapGesture {
                        onSelect(target.item)
                    }
                .position(x: target.frame.x + target.frame.width / 2, y: target.frame.y + target.frame.height / 2)
                .onHover { hovering in
                    focusedItem = hovering ? target.item : focusedItem
                }
                .accessibilityLabel(Text(target.item.name))
                .accessibilityAddTraits(.isButton)
            }
            if let item = focusedItem {
                HStack(spacing: 7) {
                    Text(item.displayKey)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Capsule().fill(Color(red: 0.03, green: 0.48, blue: 0.62)))
                    Text(item.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(.black.opacity(0.42)))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.top, -30)
            }
        }
        .padding(0)
    }
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}
