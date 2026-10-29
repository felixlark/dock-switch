import AppKit
import ApplicationServices
import Carbon
import DockSwitchCore

/// Owns the global shortcut and selected-text flow in the existing app. The
/// previously approved local component owns encoding, backups and append-only
/// persistence. No AppleScript, clipboard, input injection or reload tricks.
final class CustomPhraseController {
    // Foundation can reject opening the running app's primary domain as a suite.
    private let defaults = UserDefaults.standard
    private let component = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/wubi-phrase")
    private var hotKey: EventHotKeyRef?
    private var activeShortcut: CustomPhraseShortcut?
    private var observer: NSObjectProtocol?
    private var recordingObserver: NSObjectProtocol?
    private var settingsExitObserver: NSObjectProtocol?
    private var recording = false
    private var busy = false
    private var tip: NSPanel?
    private var dismissTip: DispatchWorkItem?

    func start() {
        observer = DistributedNotificationCenter.default().addObserver(forName: CustomPhraseShortcut.changed,
            object: nil, queue: .main) { [weak self] _ in self?.configure() }
        recordingObserver = DistributedNotificationCenter.default().addObserver(forName: CustomPhraseShortcut.recordingChanged,
            object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                self.recording = note.object as? String == "begin"
                if self.recording {
                    if let hotKey = self.hotKey { UnregisterEventHotKey(hotKey) }
                    self.hotKey = nil
                } else { self.configure() }
            }
        settingsExitObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.bundleIdentifier == "me.longbiaochen.dock-switch.settings" {
                    self?.recording = false; self?.configure()
                }
            }
        configure()
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        if let recordingObserver { DistributedNotificationCenter.default().removeObserver(recordingObserver) }
        if let settingsExitObserver { NSWorkspace.shared.notificationCenter.removeObserver(settingsExitObserver) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        dismissTip?.cancel()
        tip?.close()
    }

    private func publish(_ text: String) {
        defaults.set(text, forKey: CustomPhraseShortcut.statusKey)
        defaults.synchronize()
        DistributedNotificationCenter.default().postNotificationName(CustomPhraseShortcut.statusChanged,
            object: nil, userInfo: nil, deliverImmediately: true)
    }

    private func configure() {
        guard !recording else { return }
        defaults.synchronize()
        let enabled = defaults.object(forKey: CustomPhraseShortcut.enabledKey) as? Bool ?? true
        guard enabled else {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil; activeShortcut = nil
            publish("已停用")
            return
        }
        guard CustomPhraseShortcut.componentFiles.allSatisfy({ FileManager.default.fileExists(atPath: component.appendingPathComponent($0).path) }) else {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil; activeShortcut = nil
            publish("本机五笔短语组件未就绪，快捷键未启用")
            return
        }
        let requested = CustomPhraseShortcut.load(defaults)
        if requested == activeShortcut, hotKey != nil { publish("已启用：\(requested.display)"); return }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(requested.keyCode, requested.modifiers,
            EventHotKeyID(signature: 0x44533230, id: 2), GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr, let replacement else {
            // A failed edit must not replace the last accepted preference on restart.
            if let activeShortcut, let data = try? JSONEncoder().encode(activeShortcut) {
                defaults.set(data, forKey: CustomPhraseShortcut.preferenceKey)
            }
            let previous = hotKey != nil ? activeShortcut : nil
            publish("注册失败（\(status)），请选择其他组合键。" + (previous.map { "仍使用 \($0.display)" } ?? "当前未启用"))
            return
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        activeShortcut = requested
        retireLegacyServiceShortcut()
        publish("已启用：\(requested.display)")
    }

    private func retireLegacyServiceShortcut() {
        let key = "NSUserKeyEquivalents" as CFString
        guard var equivalents = CFPreferencesCopyValue(key, kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any],
              let old = equivalents["选词加入五笔短语"] as? String,
              ["@$\\~", "@$`", "@^~w"].contains(old) else { return }
        // Retire only this feature's known legacy entry; preserve every other
        // app/service shortcut and keep a reversible backup in app preferences.
        defaults.set(old, forKey: "customPhraseLegacyServiceShortcut")
        defaults.synchronize()
        equivalents.removeValue(forKey: "选词加入五笔短语")
        CFPreferencesSetValue(key, equivalents as CFDictionary, kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        _ = CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    func addSelection() {
        guard !busy else { return }
        defaults.set(defaults.integer(forKey: "customPhraseEventCount") + 1, forKey: "customPhraseEventCount")
        guard AXIsProcessTrusted() else { showTip("请在系统设置 → 隐私与安全性 → 辅助功能中允许 dock-switch"); return }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            showTip("请先选中一个中文词组"); return
        }
        let element = focused as! AXUIElement
        var sourcePID: pid_t = 0
        AXUIElementGetPid(element, &sourcePID)
        defaults.set(Int(sourcePID), forKey: "customPhraseSourcePID")
        var subrole: CFTypeRef?
        let subroleStatus = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        guard CustomPhraseSelectionPolicy.mayRead(subroleStatus: subroleStatus, subrole: subrole as? String) else {
            showTip("无法确认当前输入框的安全属性，未读取短语"); return
        }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let phrase = selected as? String, !phrase.isEmpty else {
            showTip("请先选中一个中文词组；当前应用需支持选中文本读取"); return
        }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let code = try run("encode.py", ["encode", phrase]).trimmingCharacters(in: .whitespacesAndNewlines)
                let checked = try check(phrase, code)
                DispatchQueue.main.async { [self] in
                    if checked == "KNOWN" { finish("已有：\(phrase) → \(code)"); return }
                    if checked == "COLLISION" {
                        let alert = NSAlert()
                        alert.messageText = "五笔码 \(code) 已有其他短语"
                        alert.informativeText = "是否追加“\(phrase)”？已有短语将保留。"
                        alert.addButton(withTitle: "追加"); alert.addButton(withTitle: "取消")
                        guard alert.runModal() == .alertFirstButtonReturn else { busy = false; return }
                    }
                    DispatchQueue.global(qos: .userInitiated).async { [self] in
                        do {
                            var args = [phrase, code, "--apply"]
                            if checked == "COLLISION" { args.append("--allow-collision") }
                            let result = try run("db-candidate/append_phrase.py", args)
                            guard let data = result.data(using: .utf8),
                                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                                  ["ADDED_SQL_ONLY", "KNOWN"].contains(json["status"] as? String ?? "") else {
                                throw PhraseError("入库结果未知，请勿重复添加，先核查词库。")
                            }
                            DispatchQueue.main.async { [self] in
                                finish("\(json["status"] as? String == "KNOWN" ? "已有" : "已入库")：\(phrase) → \(code)\n如未出词，请重开当前应用")
                            }
                        } catch { fail(error) }
                    }
                }
            } catch { fail(error) }
        }
    }

    private func check(_ phrase: String, _ code: String) throws -> String {
        let result = try run("db-candidate/append_phrase.py", [phrase, code])
        guard let data = result.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? String, ["NEW", "KNOWN", "COLLISION"].contains(status) else {
            throw PhraseError("词库检查结果无法识别，未写入。")
        }
        return status
    }

    private func run(_ script: String, _ arguments: [String]) throws -> String {
        let url = component.appendingPathComponent(script)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PhraseError("未安装本机五笔短语组件，请查看“自定义短语”设置。")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [url.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw PhraseError(output.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return output
    }

    private func fail(_ error: Error) { DispatchQueue.main.async { [self] in finish("未添加：\(error.localizedDescription)") } }
    private func finish(_ message: String) { busy = false; showTip(message) }

    private func showTip(_ message: String) {
        dismissTip?.cancel(); tip?.close()
        let size = NSSize(width: 440, height: 86)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(origin: mouse, size: size)
        let frame = NSRect(x: min(max(mouse.x + 16, area.minX), area.maxX - size.width),
            y: min(max(mouse.y - size.height - 16, area.minY), area.maxY - size.height), width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isReleasedWhenClosed = false; panel.ignoresMouseEvents = true
        panel.backgroundColor = .windowBackgroundColor; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let label = NSTextField(wrappingLabelWithString: message)
        label.frame = NSRect(x: 16, y: 12, width: size.width - 32, height: size.height - 24)
        label.font = .systemFont(ofSize: 14); panel.contentView?.addSubview(label)
        panel.orderFrontRegardless(); tip = panel
        let dismiss = DispatchWorkItem { [weak self, weak panel] in panel?.close(); if self?.tip === panel { self?.tip = nil } }
        dismissTip = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: dismiss)
    }
}

private struct PhraseError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
