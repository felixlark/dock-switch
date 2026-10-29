import AppKit
import Carbon
import SwiftUI

struct PhraseShortcutRecorder: NSViewRepresentable {
    var shortcut: CustomPhraseShortcut
    var onChange: (CustomPhraseShortcut) -> Void

    func makeNSView(context: Context) -> PhraseShortcutRecorderView { PhraseShortcutRecorderView() }
    func updateNSView(_ view: PhraseShortcutRecorderView, context: Context) {
        view.shortcut = shortcut
        view.onChange = onChange
        view.refresh()
    }
}

final class PhraseShortcutRecorderView: NSButton {
    var shortcut = CustomPhraseShortcut.default
    var onChange: ((CustomPhraseShortcut) -> Void)?
    private var monitor: Any?
    private var windowObserver: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(record)
        toolTip = "点击后按组合键；Esc 取消。需包含 Command、Option 或 Control。"
        setAccessibilityLabel("自定义短语快捷键")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
    @objc private func record() { window?.makeFirstResponder(self) }
    override func becomeFirstResponder() -> Bool {
        guard monitor == nil else { return true }
        DistributedNotificationCenter.default().postNotificationName(CustomPhraseShortcut.recordingChanged,
            object: "begin", userInfo: nil, deliverImmediately: true)
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
            object: window, queue: .main) { [weak self] _ in self?.window?.makeFirstResponder(nil) }
        title = "请按组合键…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseDown {
                if !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                    self.window?.makeFirstResponder(nil)
                }
                return event
            }
            guard event.window === self.window else { return event }
            if event.keyCode == UInt16(kVK_Escape) { self.window?.makeFirstResponder(nil); return nil }
            var modifiers: UInt32 = 0
            for (flag, carbon) in [(NSEvent.ModifierFlags.command, cmdKey), (.shift, shiftKey), (.option, optionKey), (.control, controlKey)] {
                if event.modifierFlags.contains(flag) { modifiers |= UInt32(carbon) }
            }
            let label = event.keyCode == UInt16(kVK_ANSI_Grave) ? "`"
                : (event.characters(byApplyingModifiers: []) ?? "").uppercased()
            let captured = CustomPhraseShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
            guard captured.isValid, label.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
                self.title = "请加 ⌘ / ⌥ / ⌃"; NSSound.beep(); return nil
            }
            self.onChange?(captured)
            self.window?.makeFirstResponder(nil)
            return nil
        }
        return true
    }
    override func resignFirstResponder() -> Bool { stop(); return true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { stop() } }
    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            DistributedNotificationCenter.default().postNotificationName(CustomPhraseShortcut.recordingChanged,
                object: "end", userInfo: nil, deliverImmediately: true)
        }
        monitor = nil
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
        refresh()
    }
    func refresh() {
        if monitor == nil { title = shortcut.display }
        setAccessibilityValue(title)
    }
}
