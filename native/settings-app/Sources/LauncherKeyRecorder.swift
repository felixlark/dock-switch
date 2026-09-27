import AppKit
import Carbon.HIToolbox
import SwiftUI

enum LauncherKeyCapture: Equatable {
    case key(String)
    case clear
    case cancel
    case unsupported

    // Device-dependent modifier bits (NX_DEVICE*KEYMASK in IOLLEvent.h) tell
    // left and right Shift/Command apart; NSEvent.ModifierFlags does not.
    static let modifierKeys: [UInt16: (key: String, mask: UInt, flag: NSEvent.ModifierFlags)] = [
        UInt16(kVK_Shift): ("LEFT_SHIFT", 0x02, .shift),
        UInt16(kVK_RightShift): ("RIGHT_SHIFT", 0x04, .shift),
        UInt16(kVK_Command): ("COMMAND_LEFT", 0x08, .command),
        UInt16(kVK_RightCommand): ("COMMAND_RIGHT", 0x10, .command)
    ]

    /// Whether a flagsChanged event for `keyCode` is a press rather than a release.
    /// Some synthesized events omit the device bits, so fall back to the generic flag.
    static func isModifierDown(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard let modifier = modifierKeys[keyCode] else { return false }
        if flags.rawValue & deviceModifierMask != 0 {
            return flags.rawValue & modifier.mask != 0
        }
        return flags.contains(modifier.flag)
    }

    static let deviceModifierMask: UInt = 0x02 | 0x04 | 0x08 | 0x10

    private static let functionKeys: [Int: Int] = [
        kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5, kVK_F6: 6,
        kVK_F7: 7, kVK_F8: 8, kVK_F9: 9, kVK_F10: 10, kVK_F11: 11, kVK_F12: 12,
        kVK_F13: 13, kVK_F14: 14, kVK_F15: 15, kVK_F16: 16, kVK_F17: 17,
        kVK_F18: 18, kVK_F19: 19
    ]

    // Keys the launcher consumes itself (F20 opens it; arrows and brackets
    // move windows; Return/Escape close it) cannot be app shortcuts.
    private static let launcherKeys: Set<Int> = [
        kVK_F20, kVK_Return, kVK_ANSI_KeypadEnter,
        kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
        kVK_ANSI_LeftBracket, kVK_ANSI_RightBracket
    ]

    static func forKeyDown(keyCode: UInt16, characters: String) -> LauncherKeyCapture {
        let code = Int(keyCode)
        switch code {
        case kVK_Escape:
            return .cancel
        case kVK_Delete, kVK_ForwardDelete:
            return .clear
        case kVK_Tab:
            return .key("TAB")
        case kVK_Space:
            return .key("SPACE")
        default:
            break
        }
        if launcherKeys.contains(code) { return .unsupported }
        if let number = functionKeys[code] { return .key("F\(number)") }
        let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1,
              let scalar = trimmed.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              !(0xF700...0xF8FF).contains(scalar.value) else {
            return .unsupported
        }
        return .key(normalizeLauncherKey(trimmed))
    }
}

/// Records a single launcher key. Standalone left/right Shift or Command is
/// captured when released without another key, so L⇧/R⇧ can be pressed directly.
final class LauncherKeyRecorderView: NSView {
    var onCapture: ((String) -> Void)?
    var displayKey = "" {
        didSet { refresh() }
    }

    private let label = NSTextField(labelWithString: "")
    private var monitor: Any?
    private var pendingModifier: String?
    private var modifierChordUsed = false
    private var isRecording = false {
        didSet { refresh() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        toolTip = "点击后按下按键（可直接按左/右 Shift）；Delete 清除，Esc 取消"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("快捷键")
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 74, height: 24)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            window?.makeFirstResponder(nil)
        } else {
            window?.makeFirstResponder(self)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        window?.makeFirstResponder(self)
        return true
    }

    override func becomeFirstResponder() -> Bool {
        startRecording()
        return true
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRecording() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        resetModifierState()
        // A local monitor sees keys before the window's key equivalents, so
        // Return, Tab and Command are recorded instead of triggering buttons.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
            guard let self, self.isRecording, event.window === self.window else { return event }
            return self.handle(event)
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        resetModifierState()
        isRecording = false
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            let point = convert(event.locationInWindow, from: nil)
            if !bounds.contains(point) {
                window?.makeFirstResponder(nil)
            }
            return event
        case .flagsChanged:
            handleFlagsChanged(event)
            return nil
        case .keyDown:
            resetModifierState()
            let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? ""
            switch LauncherKeyCapture.forKeyDown(keyCode: event.keyCode, characters: characters) {
            case .key(let key):
                finish(with: key)
            case .clear:
                finish(with: "")
            case .cancel:
                window?.makeFirstResponder(nil)
            case .unsupported:
                NSSound.beep()
            }
            return nil
        default:
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let deviceFlags = event.modifierFlags.rawValue & LauncherKeyCapture.deviceModifierMask
        guard let modifier = LauncherKeyCapture.modifierKeys[event.keyCode] else {
            if pendingModifier != nil { modifierChordUsed = true }
            return
        }
        let isDown = LauncherKeyCapture.isModifierDown(keyCode: event.keyCode, flags: event.modifierFlags)
        if isDown {
            if pendingModifier == nil {
                pendingModifier = modifier.key
            } else {
                modifierChordUsed = true
            }
        } else if pendingModifier == modifier.key, !modifierChordUsed {
            finish(with: modifier.key)
            return
        }
        if deviceFlags == 0, !event.modifierFlags.contains(modifier.flag) { resetModifierState() }
    }

    private func finish(with key: String) {
        onCapture?(key)
        window?.makeFirstResponder(nil)
    }

    private func resetModifierState() {
        pendingModifier = nil
        modifierChordUsed = false
    }

    private func refresh() {
        if isRecording {
            label.stringValue = "按下按键"
            label.textColor = .controlAccentColor
        } else if displayKey.isEmpty {
            label.stringValue = "未设置"
            label.textColor = .tertiaryLabelColor
        } else {
            label.stringValue = displayKey
            label.textColor = .labelColor
        }
        setAccessibilityValue(isRecording ? "按下按键" : displayKey)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            layer?.borderWidth = isRecording ? 2 : 1
        }
    }
}

struct LauncherKeyRecorder: NSViewRepresentable {
    var key: String
    var onChange: (String) -> Void

    func makeNSView(context: Context) -> LauncherKeyRecorderView {
        let view = LauncherKeyRecorderView()
        view.displayKey = key
        view.onCapture = onChange
        return view
    }

    func updateNSView(_ view: LauncherKeyRecorderView, context: Context) {
        view.displayKey = key
        view.onCapture = onChange
    }
}
