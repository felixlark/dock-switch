import AppKit
import ApplicationServices
import Carbon
import Foundation

public struct DSRect: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var centerX: Double { x + width / 2 }
    public var centerY: Double { y + height / 2 }

    public func contains(_ point: CGPoint) -> Bool {
        Double(point.x) >= minX && Double(point.x) <= maxX &&
            Double(point.y) >= minY && Double(point.y) <= maxY
    }
}

public struct SubprocessOutput {
    public let terminationStatus: Int32
    public let stdout: Data
}

public enum Subprocess {
    public static func captureOutput(executableURL: URL, arguments: [String]) -> SubprocessOutput? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdout
        guard (try? process.run()) != nil else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return SubprocessOutput(terminationStatus: process.terminationStatus, stdout: data)
    }
}

public struct DisplaySnapshot: Codable, Equatable {
    public var id: UInt32
    public var internalDisplay: Bool
    public var bounds: DSRect
    public var workArea: DSRect
    public var scaleFactor: Double
    public var label: String

    enum CodingKeys: String, CodingKey {
        case id
        case internalDisplay = "internal"
        case bounds
        case workArea
        case scaleFactor
        case label
    }
}

public struct DockItemSnapshot: Codable, Equatable {
    public var name: String
    public var pos: CGPoint
    public var size: CGSize
    public var containerFrame: DSRect?

    public init(name: String, pos: CGPoint, size: CGSize, containerFrame: DSRect? = nil) {
        self.name = name
        self.pos = pos
        self.size = size
        self.containerFrame = containerFrame
    }
}

public struct LauncherConfig: Codable, Equatable {
    public var dockItems: [LauncherConfigItem]

    enum CodingKeys: String, CodingKey {
        case dockItems = "dock_items"
    }

    public static let empty = LauncherConfig(dockItems: [])
}

public struct LauncherConfigItem: Codable, Equatable {
    public var name: String
    public var key: String?
    public var screen: String?
    public var kind: String?
    public var placement: String?
    public var openPath: String?
    public var appURL: String?

    enum CodingKeys: String, CodingKey {
        case name
        case key
        case screen
        case kind
        case placement
        case openPath = "open_path"
        case appURL = "app_url"
    }
}

public struct LauncherItem: Equatable, Identifiable {
    public var id: String { "\(name)-\(key)" }
    public var name: String
    public var key: String
    public var icon: String?
    public var kind: String?
    public var placement: String?
    public var openPath: String?
    public var appURL: String?
    public var dockItem: DockItemSnapshot

    public var displayKey: String {
        icon ?? key
    }

    public init(name: String, key: String, icon: String? = nil, kind: String? = nil, placement: String? = nil, openPath: String? = nil, appURL: String? = nil, dockItem: DockItemSnapshot) {
        self.name = name
        self.key = key
        self.icon = icon
        self.kind = kind
        self.placement = placement
        self.openPath = openPath
        self.appURL = appURL
        self.dockItem = dockItem
    }
}

public struct Gokit5Action: Equatable {
    public var name: String
    public var kind: String?
    public var placement: String?
    public var codexTarget: String?
    public var mouseTarget: String?
    public var openPath: String?
    public var appURL: String?

    public init(name: String = "Mouse", kind: String? = nil, placement: String? = nil, codexTarget: String? = nil, mouseTarget: String? = nil, openPath: String? = nil, appURL: String? = nil) {
        self.name = name
        self.kind = kind
        self.placement = placement
        self.codexTarget = codexTarget
        self.mouseTarget = mouseTarget
        self.openPath = openPath
        self.appURL = appURL
    }
}

public struct OverlayTarget: Equatable, Identifiable {
    public var id: String { item.id }
    public var item: LauncherItem
    public var frame: DSRect
}

public struct OverlayLayout: Equatable {
    public var windowFrameAX: DSRect
    public var dockRect: DSRect
    public var targets: [OverlayTarget]
}

public enum OverlayAnimationPolicy {
    public static let showDuration: TimeInterval = 0
    public static let showUsesFinalFrame = true
    public static let hideDuration: TimeInterval = 0.12
    public static let hideScale: Double = 0.96
}

public enum StatusItemIconPolicy {
    public static let size = CGSize(width: 18, height: 18)
    public static let usesTemplateImage = true
    public static let accessibilityLabel = "dock-switch"
}

public enum LauncherShortcutRules {
    public static func appName(for normalizedKey: String) -> String? {
        switch normalizedKey {
        case "F6":
            return "ChatGPT"
        case "LEFT_SHIFT":
            return "Codex"
        case "RIGHT_SHIFT":
            return "Claude"
        case "F3":
            return "SmartShadow"
        case "COMMAND_LEFT":
            return "System Settings"
        default:
            return nil
        }
    }

    public static func launcherItem(
        for normalizedKey: String,
        config: LauncherConfig = .empty
    ) -> LauncherItem? {
        // A key saved in Settings wins over the built-in default app for that key.
        let configured = config.dockItems.first(where: {
            LauncherRules.normalizeKey($0.key ?? "") == normalizedKey
        })
        let defaultAppName = appName(for: normalizedKey)
        if configured == nil, let defaultAppName, config.dockItems.contains(where: {
            LauncherRules.normalizeAppName($0.name) == LauncherRules.normalizeAppName(defaultAppName) &&
                !LauncherRules.normalizeKey($0.key ?? "").isEmpty
        }) {
            return nil
        }
        guard let appName = configured?.name ?? defaultAppName else { return nil }
        guard let special = LauncherRules.specialItem(for: appName) else {
            return LauncherItem(
                name: configured?.name ?? appName,
                key: normalizedKey,
                icon: nil,
                kind: configured?.kind,
                placement: configured?.placement,
                openPath: configured?.openPath,
                appURL: configured?.appURL,
                dockItem: DockItemSnapshot(name: appName, pos: .zero, size: .zero)
            )
        }
        return LauncherItem(
            name: configured?.name ?? special.name,
            key: normalizedKey,
            icon: LauncherRules.keyIcon(for: normalizedKey) ?? special.icon,
            kind: configured?.kind,
            placement: configured?.placement ?? special.placement,
            openPath: configured?.openPath ?? special.openPath,
            appURL: configured?.appURL,
            dockItem: DockItemSnapshot(name: special.name, pos: .zero, size: .zero)
        )
    }

    public static func isReserved(_ normalizedKey: String) -> Bool {
        ["COMMAND_LEFT", "COMMAND_RIGHT"].contains(normalizedKey)
    }

    public static func windowAction(key: String, code: String = "") -> String? {
        let candidates = [key, code]
        for candidate in candidates {
            switch candidate {
            case "ArrowUp":
                return "up"
            case "ArrowDown":
                return "down"
            case "ArrowLeft":
                return "left"
            case "ArrowRight":
                return "right"
            case "[", "【", "BracketLeft":
                return "current_left"
            case "]", "】", "BracketRight":
                return "current_right"
            default:
                continue
            }
        }
        return nil
    }

    public static func shouldCenterMouse(for action: String) -> Bool {
        ["up", "down", "left", "right", "current_left", "current_right"].contains(action)
    }
}

public enum DisplayGeometry {
    public static func internalDisplay(_ displays: [DisplaySnapshot], primaryDisplay: DisplaySnapshot?) -> DisplaySnapshot? {
        displays.first(where: \.internalDisplay) ?? primaryDisplay ?? displays.first
    }

    public static func externalDisplay(_ displays: [DisplaySnapshot], primaryDisplay: DisplaySnapshot?, currentDisplay: DisplaySnapshot? = nil) -> DisplaySnapshot? {
        guard !displays.isEmpty else { return nil }
        let externals = displays.filter { !$0.internalDisplay }
        if externals.count == 1 { return externals[0] }
        if externals.count > 1 {
            return externals.max { a, b in
                a.workArea.width * a.workArea.height < b.workArea.width * b.workArea.height
            }
        }
        if let currentDisplay {
            return displays.first { $0.id != currentDisplay.id } ?? primaryDisplay ?? displays.first
        }
        if let primaryDisplay {
            return displays.first { $0.id != primaryDisplay.id } ?? primaryDisplay
        }
        return displays.count > 1 ? displays[1] : nil
    }

    public static func sideLeftDisplay(_ displays: [DisplaySnapshot], primaryDisplay: DisplaySnapshot?) -> DisplaySnapshot? {
        sideCandidates(displays, primaryDisplay: primaryDisplay)
            .sorted { $0.bounds.x < $1.bounds.x }
            .first
    }

    public static func sideRightDisplay(_ displays: [DisplaySnapshot], primaryDisplay: DisplaySnapshot?) -> DisplaySnapshot? {
        sideCandidates(displays, primaryDisplay: primaryDisplay)
            .sorted { $0.bounds.x > $1.bounds.x }
            .first
    }

    public static func display(for target: String, displays: [DisplaySnapshot], primaryDisplay: DisplaySnapshot?) -> DisplaySnapshot? {
        switch target {
        case "internal":
            return internalDisplay(displays, primaryDisplay: primaryDisplay)
        case "external":
            return externalDisplay(displays, primaryDisplay: primaryDisplay) ?? internalDisplay(displays, primaryDisplay: primaryDisplay)
        case "side_left":
            return sideLeftDisplay(displays, primaryDisplay: primaryDisplay) ?? internalDisplay(displays, primaryDisplay: primaryDisplay)
        case "side_right":
            return sideRightDisplay(displays, primaryDisplay: primaryDisplay) ?? internalDisplay(displays, primaryDisplay: primaryDisplay)
        default:
            return nil
        }
    }

    public static func display(containing rect: DSRect, displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        guard !displays.isEmpty else { return nil }
        let point = CGPoint(x: rect.centerX, y: rect.centerY)
        if let containing = displays.first(where: { $0.bounds.contains(point) }) {
            return containing
        }
        return displays.min { a, b in
            distanceSquared(from: point, to: a.bounds) < distanceSquared(from: point, to: b.bounds)
        }
    }

    public static func boundsForDisplay(_ display: DisplaySnapshot?) -> DSRect? {
        display?.workArea
    }

    public static func resolveBoundsForAction(action: String, displays: [DisplaySnapshot], primaryDisplay: DisplaySnapshot?, currentDisplay: DisplaySnapshot?) -> DSRect? {
        guard !displays.isEmpty else { return nil }
        if action == "current_left" {
            guard let area = currentDisplay?.workArea else { return nil }
            return leftHalf(area)
        }
        if action == "current_right" {
            guard let area = currentDisplay?.workArea else { return nil }
            return rightHalf(area)
        }
        if action == "fill" {
            return currentDisplay?.bounds ?? currentDisplay?.workArea
        }
        let targetName: String?
        switch action {
        case "up":
            targetName = "external"
        case "down":
            targetName = "internal"
        case "left":
            targetName = "side_left"
        case "right":
            targetName = "side_right"
        default:
            targetName = nil
        }
        guard let targetName else { return nil }
        return boundsForDisplay(display(for: targetName, displays: displays, primaryDisplay: primaryDisplay))
    }

    public static func resolveBoundsForPlacement(_ placement: String, displays: [DisplaySnapshot], primaryDisplay: DisplaySnapshot?) -> DSRect? {
        guard !displays.isEmpty else { return nil }
        if let generic = parseGenericPlacement(placement) {
            guard let display = display(for: generic.target, displays: displays, primaryDisplay: primaryDisplay) else { return nil }
            return bounds(for: generic.mode, display: display)
        }
        if placement == "external_left_half" {
            let target = externalDisplay(displays, primaryDisplay: primaryDisplay) ?? internalDisplay(displays, primaryDisplay: primaryDisplay)
            return target.map { leftHalf($0.workArea) }
        }
        if placement == "external_right_half" {
            let target = externalDisplay(displays, primaryDisplay: primaryDisplay) ?? internalDisplay(displays, primaryDisplay: primaryDisplay)
            return target.map { rightHalf($0.workArea) }
        }
        return nil
    }

    public static func centerPoint(for rect: DSRect) -> CGPoint {
        CGPoint(x: round(rect.centerX), y: round(rect.centerY))
    }

    public static func appKitFrame(fromAX rect: DSRect, inDisplay displayAX: DSRect, appKitDisplayFrame: DSRect) -> DSRect {
        let localTopOffset = rect.y - displayAX.y
        return DSRect(
            x: rect.x,
            y: appKitDisplayFrame.y + appKitDisplayFrame.height - localTopOffset - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func sideCandidates(_ displays: [DisplaySnapshot], primaryDisplay: DisplaySnapshot?) -> [DisplaySnapshot] {
        guard !displays.isEmpty else { return [] }
        let external = externalDisplay(displays, primaryDisplay: primaryDisplay)
        return displays.filter { display in
            !display.internalDisplay && (external == nil || display.id != external?.id)
        }
    }

    private static func parseGenericPlacement(_ placement: String) -> (target: String, mode: String)? {
        let targets = ["internal", "external", "side_left", "side_right"]
        let modes = ["fill", "left_half", "right_half"]
        for target in targets {
            for mode in modes {
                if placement == "\(target)_\(mode)" {
                    return (target, mode)
                }
            }
        }
        return nil
    }

    private static func bounds(for mode: String, display: DisplaySnapshot) -> DSRect? {
        switch mode {
        case "fill":
            return display.workArea
        case "left_half":
            return leftHalf(display.workArea)
        case "right_half":
            return rightHalf(display.workArea)
        default:
            return nil
        }
    }

    private static func leftHalf(_ area: DSRect) -> DSRect {
        let width = floor(area.width / 2)
        return DSRect(x: area.x, y: area.y, width: width, height: area.height)
    }

    private static func rightHalf(_ area: DSRect) -> DSRect {
        let width = floor(area.width / 2)
        return DSRect(x: area.x + width, y: area.y, width: area.width - width, height: area.height)
    }

    private static func distanceSquared(from point: CGPoint, to rect: DSRect) -> Double {
        var dx = 0.0
        if Double(point.x) < rect.minX {
            dx = rect.minX - Double(point.x)
        } else if Double(point.x) > rect.maxX {
            dx = Double(point.x) - rect.maxX
        }
        var dy = 0.0
        if Double(point.y) < rect.minY {
            dy = rect.minY - Double(point.y)
        } else if Double(point.y) > rect.maxY {
            dy = Double(point.y) - rect.maxY
        }
        return dx * dx + dy * dy
    }
}

public enum DockSwitchPaths {
    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/dock-switch", isDirectory: true)
    }

    public static var controlSocket: URL {
        supportDirectory.appendingPathComponent("control.sock")
    }

    public static func bundledConfigURL() -> URL {
        if let resource = Bundle.main.resourceURL {
            return resource
                .appendingPathComponent("app", isDirectory: true)
                .appendingPathComponent("src", isDirectory: true)
                .appendingPathComponent("config.json")
        }
        return URL(fileURLWithPath: "/Applications/dock-switch.app/Contents/Resources/app/src/config.json")
    }

    public static var dockCacheURL: URL {
        supportDirectory.appendingPathComponent("dock-items-cache.json")
    }
}

public final class ConfigStore {
    public private(set) var url: URL

    public init(url: URL = DockSwitchPaths.bundledConfigURL()) {
        self.url = url
    }

    public func load() -> LauncherConfig {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        return (try? JSONDecoder().decode(LauncherConfig.self, from: data)) ?? .empty
    }
}

public enum LauncherRules {
    public static func normalizeAppName(_ name: String) -> String {
        var normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasSuffix(".app") {
            normalized.removeLast(4)
        }
        normalized = normalized.lowercased()
        if normalized == "chrome" { return "google chrome" }
        return normalized
    }

    public static func normalizeKey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let lower = trimmed.lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        if lower == "space" { return "SPACE" }
        if lower == "tab" { return "TAB" }
        if lower == "left_shift" || lower == "shift_left" { return "LEFT_SHIFT" }
        if lower == "right_shift" || lower == "shift_right" { return "RIGHT_SHIFT" }
        if ["cmd", "command", "cmd_left", "left_cmd", "command_left", "left_command", "meta_left", "left_meta"].contains(lower) {
            return "COMMAND_LEFT"
        }
        if ["cmd_right", "right_cmd", "command_right", "right_command", "meta_right", "right_meta"].contains(lower) {
            return "COMMAND_RIGHT"
        }
        if lower.hasPrefix("f"), lower.dropFirst().allSatisfy(\.isNumber) {
            return lower.uppercased()
        }
        if trimmed.count == 1 { return trimmed.uppercased() }
        return trimmed.uppercased()
    }

    public static func normalizeEventKey(characters: String, keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Tab:
            return "TAB"
        case kVK_Shift:
            return "LEFT_SHIFT"
        case kVK_RightShift:
            return "RIGHT_SHIFT"
        case kVK_ANSI_Backslash:
            return "\\"
        default:
            return normalizeKey(characters)
        }
    }

    public static func keyIcon(for key: String) -> String? {
        switch normalizeKey(key) {
        case "TAB":
            return "⇥"
        case "LEFT_SHIFT":
            return "L⇧"
        case "RIGHT_SHIFT":
            return "R⇧"
        case "COMMAND", "COMMAND_LEFT", "COMMAND_RIGHT":
            return "⌘"
        default:
            return nil
        }
    }

    public static func specialItem(for name: String) -> (name: String, key: String, icon: String, placement: String?, openPath: String?)? {
        switch normalizeAppName(name) {
        case "chatgpt":
            return ("ChatGPT", "F6", "F6", "side_right_fill", nil)
        case "codex":
            return ("Codex", "LEFT_SHIFT", "L⇧", "external_fill", nil)
        case "smartshadow":
            return ("SmartShadow", "F3", "F3", "side_left_fill", "/Applications/SmartShadow.app")
        case "claude":
            return ("Claude", "RIGHT_SHIFT", "R⇧", "side_right_fill", "/Applications/Claude.app")
        default:
            return nil
        }
    }

    public static func buildLauncherItems(
        dockItems: [DockItemSnapshot],
        config: LauncherConfig
    ) -> [LauncherItem] {
        let visible = dockItems
            .filter { !$0.name.isEmpty && $0.name != "Trash" && $0.name != "Downloads" }
            .sorted { $0.pos.x < $1.pos.x }
        let userAssignedKeys = Set(config.dockItems.compactMap { item -> String? in
            let key = normalizeKey(item.key ?? "")
            return key.isEmpty ? nil : key
        })
        var fallbackKey = 1
        return visible.map { dockItem in
            let normalizedDockName = normalizeAppName(dockItem.name)
            let configured = config.dockItems.first(where: {
                normalizeAppName($0.name) == normalizedDockName
            })

            if let special = specialItem(for: dockItem.name) {
                if let configured {
                    let configuredKey = configured.key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return LauncherItem(
                        name: configured.name,
                        key: configuredKey,
                        icon: keyIcon(for: configuredKey),
                        kind: configured.kind,
                        placement: configured.placement ?? special.placement,
                        openPath: configured.openPath ?? special.openPath,
                        appURL: configured.appURL,
                        dockItem: dockItem
                    )
                }
                return LauncherItem(
                    name: special.name,
                    key: special.key,
                    icon: special.icon,
                    kind: nil,
                    placement: special.placement,
                    openPath: special.openPath,
                    appURL: nil,
                    dockItem: dockItem
                )
            }

            if let configured, !normalizeKey(configured.key ?? "").isEmpty {
                return LauncherItem(
                    name: configured.name,
                    key: normalizeKey(configured.key ?? ""),
                    icon: keyIcon(for: configured.key ?? ""),
                    kind: configured.kind,
                    placement: configured.placement,
                    openPath: configured.openPath,
                    appURL: configured.appURL,
                    dockItem: dockItem
                )
            }

            while userAssignedKeys.contains("\(fallbackKey)") {
                fallbackKey += 1
            }
            defer { fallbackKey += 1 }
            return LauncherItem(
                name: dockItem.name,
                key: "\(fallbackKey)",
                icon: nil,
                kind: nil,
                placement: nil,
                openPath: nil,
                appURL: nil,
                dockItem: dockItem
            )
        }
    }
}

public final class DisplayService {
    public init() {}

    public func displays() -> [DisplaySnapshot] {
        return NSScreen.screens.map { screen in
            let desc = screen.deviceDescription
            let id = (desc[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let displayBounds = CGDisplayBounds(id)
            let label: String
            if #available(macOS 10.15, *) {
                label = screen.localizedName
            } else {
                label = ""
            }
            return DisplaySnapshot(
                id: id,
                internalDisplay: id != 0 && CGDisplayIsBuiltin(id) != 0,
                bounds: Self.convertDisplayBounds(displayBounds),
                workArea: Self.convertVisibleFrame(screen.visibleFrame, screenFrame: screen.frame, displayBounds: displayBounds),
                scaleFactor: Double(screen.backingScaleFactor),
                label: label
            )
        }
    }

    public static func convertDisplayBounds(_ rect: CGRect) -> DSRect {
        DSRect(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }

    public static func convertVisibleFrame(_ visibleFrame: CGRect, screenFrame: CGRect, displayBounds: CGRect) -> DSRect {
        let leftInset = visibleFrame.minX - screenFrame.minX
        let topInset = screenFrame.maxY - visibleFrame.maxY
        return DSRect(
            x: Double(displayBounds.minX + leftInset),
            y: Double(displayBounds.minY + topInset),
            width: Double(visibleFrame.width),
            height: Double(visibleFrame.height)
        )
    }
}

public final class DockVisibilityService {
    public init() {}

    public func showDock() {}

    public func restoreDock() {}
}

public final class DockSnapshotService {
    public init() {}

    public func queryDockItems() throws -> [DockItemSnapshot] {
        guard AXIsProcessTrusted() else {
            throw NSError(domain: "DockSnapshotService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Accessibility permission is required"])
        }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            throw NSError(domain: "DockSnapshotService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Dock is not running"])
        }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        var items: [DockItemSnapshot] = []
        collectDockItems(root, depth: 0, containerFrame: nil, into: &items)
        var seen = Set<String>()
        return items.filter { item in
            let key = "\(item.name)|\(Int(item.pos.x))|\(Int(item.pos.y))"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
        .sorted { $0.pos.x == $1.pos.x ? $0.pos.y < $1.pos.y : $0.pos.x < $1.pos.x }
    }

    public func writeCache(_ items: [DockItemSnapshot], to url: URL = DockSwitchPaths.dockCacheURL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoded = items.map { item -> [String: Any] in
                [
                    "name": item.name,
                    "pos": ["x": item.pos.x, "y": item.pos.y],
                    "size": ["w": item.size.width, "h": item.size.height]
                ]
            }
            let data = try JSONSerialization.data(withJSONObject: encoded, options: [.prettyPrinted])
            try data.write(to: url)
        } catch {
            NSLog("dock-switch: failed to write Dock cache: \(error.localizedDescription)")
        }
    }

    private func collectDockItems(_ element: AXUIElement, depth: Int, containerFrame: DSRect?, into items: inout [DockItemSnapshot]) {
        guard depth <= 6 else { return }
        let role = axString(element, kAXRoleAttribute as CFString) ?? ""
        let nextContainerFrame: DSRect?
        if role == kAXListRole as String,
           let point = axPoint(element, kAXPositionAttribute as CFString),
           let size = axSize(element, kAXSizeAttribute as CFString) {
            nextContainerFrame = DSRect(x: Double(point.x), y: Double(point.y), width: Double(size.width), height: Double(size.height))
        } else {
            nextContainerFrame = containerFrame
        }
        if let point = axPoint(element, kAXPositionAttribute as CFString) {
            let name = axString(element, kAXTitleAttribute as CFString)
                ?? axString(element, kAXDescriptionAttribute as CFString)
                ?? ""
            if !name.isEmpty, name != "missing value", name != "Dock" {
                let size = axSize(element, kAXSizeAttribute as CFString) ?? CGSize(width: 52, height: 52)
                items.append(DockItemSnapshot(name: name, pos: point, size: size, containerFrame: nextContainerFrame))
            }
        }
        guard let children = axChildren(element) else { return }
        for child in children {
            collectDockItems(child, depth: depth + 1, containerFrame: nextContainerFrame, into: &items)
        }
    }
}

public final class OverlayLayoutService {
    public init() {}

    public func resolve(
        launcherItems: [LauncherItem],
        displays: [DisplaySnapshot],
        gap: Double = 0,
        targetSize: CGSize = CGSize(width: 42, height: 34)
    ) -> OverlayLayout? {
        guard !launcherItems.isEmpty else { return nil }
        let rects = launcherItems.map { item in
            DSRect(x: Double(item.dockItem.pos.x), y: Double(item.dockItem.pos.y), width: Double(item.dockItem.size.width), height: Double(item.dockItem.size.height))
        }
        guard let left = rects.map(\.minX).min(),
              let top = rects.map(\.minY).min(),
              let right = rects.map(\.maxX).max(),
              let bottom = rects.map(\.maxY).max() else {
            return nil
        }
        let itemBounds = DSRect(x: left, y: top, width: right - left, height: bottom - top)
        let dockRect = launcherItems.first?.dockItem.containerFrame ?? itemBounds
        let last = launcherItems[launcherItems.count - 1].dockItem
        let positionYs = launcherItems.map { Double($0.dockItem.pos.y) }
        let minY = positionYs.min() ?? top
        let maxY = positionYs.max() ?? top
        let overlayHeight = 60.0
        let x = dockRect.x
        let width = max(120.0, Double(last.pos.x) - x + 60.0)
        let centerY = round((minY + maxY) / 2)
        let targetDisplay = displayForDockOverlay(x: x, y: centerY, displays: displays)
        let displayBounds = targetDisplay?.bounds
        let dockItemsOriginY = displayBounds.map {
            dockCoordinateOriginY(centerY: centerY, displayBounds: $0)
        } ?? 0
        let localDockCenterY = centerY - dockItemsOriginY
        let displayMidY = displayBounds.map { floor($0.height / 2) } ?? centerY
        let isBottomDock = localDockCenterY >= displayMidY
        let localMinY = minY - dockItemsOriginY
        let localMaxY = maxY - dockItemsOriginY
        let localDockRectMinY = dockRect.minY - dockItemsOriginY
        let unclampedLocalY: Double
        if isBottomDock {
            let workAreaMaxY = targetDisplay.map { $0.workArea.maxY - $0.bounds.y }
            let safeDockTop = [localMinY, localDockRectMinY, workAreaMaxY]
                .compactMap { $0 }
                .min() ?? localMinY
            unclampedLocalY = safeDockTop - overlayHeight - gap
        } else {
            unclampedLocalY = localMaxY + 52.0 + gap
        }
        let localWindowY: Double
        if let displayBounds {
            localWindowY = clamp(unclampedLocalY, 0, displayBounds.height - overlayHeight)
        } else {
            localWindowY = unclampedLocalY
        }
        let y = localWindowY + (displayBounds?.y ?? 0)
        let window = DSRect(x: x, y: y, width: width, height: overlayHeight)

        let targets = launcherItems.map { item -> OverlayTarget in
            let center = Double(item.dockItem.pos.x) + Double(item.dockItem.size.width) / 2
            let targetX = clamp(center - Double(targetSize.width) / 2 - window.x, 4, window.width - Double(targetSize.width) - 4)
            let frame = DSRect(
                x: targetX,
                y: (window.height - Double(targetSize.height)) / 2,
                width: Double(targetSize.width),
                height: Double(targetSize.height)
            )
            return OverlayTarget(item: item, frame: frame)
        }
        return OverlayLayout(windowFrameAX: window, dockRect: dockRect, targets: targets)
    }

    private func dockCoordinateOriginY(centerY: Double, displayBounds: DSRect) -> Double {
        let localY = centerY
        let globalY = centerY - displayBounds.y
        let localDistance = distanceToNearestVerticalEdge(localY, height: displayBounds.height)
        let globalDistance = distanceToNearestVerticalEdge(globalY, height: displayBounds.height)

        if globalDistance < localDistance {
            return displayBounds.y
        }
        return 0
    }

    private func distanceToNearestVerticalEdge(_ y: Double, height: Double) -> Double {
        guard y >= 0, y <= height else { return .infinity }
        return min(y, height - y)
    }

    private func displayForDockOverlay(x: Double, y: Double, displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        if let localMatch = displays.first(where: { display in
            guard display.bounds.y > 0 else { return false }
            return x >= display.bounds.minX && x <= display.bounds.maxX &&
                y >= 0 && y <= display.bounds.height
        }) {
            return localMatch
        }
        return DisplayGeometry.display(
            containing: DSRect(x: x, y: y, width: 1, height: 1),
            displays: displays
        )
    }
}

public enum WebAppRuntime {
    private static var knownWebAppDirectories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Applications/Chrome Apps.localized",
            "\(home)/Applications/Chromium Apps.localized",
            "/Applications/Chrome Apps.localized",
            "/Applications/Chromium Apps.localized"
        ]
    }

    public static func resolveOpenPath(_ rawPath: String) -> String {
        let candidates = openPathCandidates(rawPath)
        guard !candidates.isEmpty else { return "" }
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
    }

    public static func findAppProcessPID(openPath: String?) -> pid_t? {
        guard let openPath,
              !openPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let bundlePath = resolveOpenPath(openPath)
        guard !bundlePath.isEmpty else { return nil }
        let executablePrefix = URL(fileURLWithPath: bundlePath)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .path + "/"
        return processTable()
            .filter { $0.command.hasPrefix(executablePrefix) }
            .sorted { $0.pid > $1.pid }
            .first?
            .pid
    }

    public static func findChromeAppProcessPID(appURL: String?) -> pid_t? {
        guard let appURL = appURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !appURL.isEmpty else {
            return nil
        }
        return processTable()
            .filter { isChromeBrowserCommand($0.command) }
            .filter { !$0.command.contains("--type=") }
            .filter { !$0.command.contains("crashpad_handler") }
            .filter { commandContainsAppURL($0.command, appURL: appURL) }
            .sorted { $0.pid > $1.pid }
            .first?
            .pid
    }

    private static func openPathCandidates(_ rawPath: String) -> [String] {
        let expanded = NSString(string: rawPath.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath
        guard !expanded.isEmpty else { return [] }
        var candidates = [expanded]
        if expanded.contains("/Chrome Apps.localized/") {
            candidates.append(expanded.replacingOccurrences(of: "/Chrome Apps.localized/", with: "/Chromium Apps.localized/"))
        }
        if expanded.contains("/Chromium Apps.localized/") {
            candidates.append(expanded.replacingOccurrences(of: "/Chromium Apps.localized/", with: "/Chrome Apps.localized/"))
        }
        let bundleName = URL(fileURLWithPath: expanded).lastPathComponent
        if !bundleName.isEmpty {
            candidates.append(contentsOf: knownWebAppDirectories.map { "\($0)/\(bundleName)" })
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func processTable() -> [(pid: pid_t, command: String)] {
        guard let output = Subprocess.captureOutput(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["ax", "-o", "pid=,command="]
        ), output.terminationStatus == 0 else { return [] }
        let data = output.stdout
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let firstSpace = trimmed.firstIndex(where: \.isWhitespace),
                  let pid = Int32(trimmed[..<firstSpace].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            let command = trimmed[firstSpace...].trimmingCharacters(in: .whitespacesAndNewlines)
            return (pid_t(pid), command)
        }
    }

    private static func isChromeBrowserCommand(_ command: String) -> Bool {
        command.contains("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome ") ||
            command.hasSuffix("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome") ||
            command.contains("/Applications/Chromium.app/Contents/MacOS/Chromium ") ||
            command.hasSuffix("/Applications/Chromium.app/Contents/MacOS/Chromium")
    }

    private static func commandContainsAppURL(_ command: String, appURL: String) -> Bool {
        let marker = "--app=\(appURL)"
        guard let range = command.range(of: marker) else { return false }
        if range.upperBound == command.endIndex { return true }
        return command[range.upperBound].isWhitespace
    }
}

public final class LauncherService {
    private let windowPlacement: any LauncherWindowPlacement
    private let placeRetryDeadline: TimeInterval
    private let placeRetryDelay: TimeInterval
    private let showMouseFeedback: (CGPoint) -> Void
    private let openItem: (LauncherItem) -> Void

    public init(
        windowPlacement: any LauncherWindowPlacement = WindowPlacementService(),
        placeRetryDeadline: TimeInterval = 1.6,
        placeRetryDelay: TimeInterval = 0.08,
        showMouseFeedback: @escaping (CGPoint) -> Void = { _ in },
        openItem: ((LauncherItem) -> Void)? = nil
    ) {
        self.windowPlacement = windowPlacement
        self.placeRetryDeadline = placeRetryDeadline
        self.placeRetryDelay = placeRetryDelay
        self.showMouseFeedback = showMouseFeedback
        self.openItem = openItem ?? Self.open
    }

    public func activate(_ item: LauncherItem) {
        let placement = item.placement ?? (item.kind == "web_app" ? "internal_fill" : nil)
        openItem(item)
        if let placement {
            retryPlace(item: item, placement: placement, until: Date().addingTimeInterval(placeRetryDeadline))
        } else {
            retryMoveMouseToApplicationWindowCenter(appName: item.name, until: Date().addingTimeInterval(placeRetryDeadline))
        }
    }

    public func activate(_ action: Gokit5Action) {
        let item = LauncherItem(
            name: action.name,
            key: "",
            kind: action.kind,
            placement: action.placement,
            openPath: action.openPath,
            appURL: action.appURL,
            dockItem: DockItemSnapshot(name: action.name, pos: .zero, size: .zero)
        )
        activate(item)
    }

    private static func open(_ item: LauncherItem) {
        if let raw = item.openPath, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = WebAppRuntime.resolveOpenPath(raw)
            NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
            return
        }
        NSWorkspace.shared.launchApplication(item.name)
    }

    private func retryPlace(item: LauncherItem, placement: String, until deadline: Date) {
        DispatchQueue.main.asyncAfter(deadline: .now() + placeRetryDelay) {
            if let pid = WebAppRuntime.findAppProcessPID(openPath: item.openPath),
               self.showFeedbackIfSuccessful(self.windowPlacement.placePID(pid, placement: placement)) {
                return
            }
            if let pid = WebAppRuntime.findChromeAppProcessPID(appURL: item.appURL),
               self.showFeedbackIfSuccessful(self.windowPlacement.placePID(pid, placement: placement)) {
                return
            }
            if self.showFeedbackIfSuccessful(self.windowPlacement.placeProcess(name: item.name, placement: placement)) {
                return
            }
            if Date() < deadline {
                self.retryPlace(item: item, placement: placement, until: deadline)
            }
        }
    }

    private func retryMoveMouseToApplicationWindowCenter(appName: String, until deadline: Date) {
        DispatchQueue.main.asyncAfter(deadline: .now() + placeRetryDelay) {
            if self.showFeedbackIfSuccessful(self.windowPlacement.moveMouseToApplicationWindowCenter(name: appName)) {
                return
            }
            if Date() < deadline {
                self.retryMoveMouseToApplicationWindowCenter(appName: appName, until: deadline)
            }
        }
    }

    @discardableResult
    private func showFeedbackIfSuccessful(_ result: WindowActionResult) -> Bool {
        guard result.ok,
              let point = result.feedbackPoint,
              point.x.isFinite,
              point.y.isFinite else {
            return false
        }
        showMouseFeedback(point)
        return true
    }
}

public struct WindowActionResult: Equatable {
    public var ok: Bool
    public var feedbackPoint: CGPoint?

    public init(ok: Bool, feedbackPoint: CGPoint? = nil) {
        self.ok = ok
        self.feedbackPoint = feedbackPoint
    }
}

public protocol LauncherWindowPlacement {
    func placePID(_ pid: pid_t, placement: String) -> WindowActionResult
    func placeProcess(name: String, placement: String) -> WindowActionResult
    func moveMouseToPIDWindowCenter(_ pid: pid_t) -> WindowActionResult
    func moveMouseToApplicationWindowCenter(name: String) -> WindowActionResult
}

public final class WindowPlacementService {
    private let displayService = DisplayService()

    public init() {}

    @discardableResult
    public func placeProcess(name: String, placement: String) -> WindowActionResult {
        guard let bounds = resolveBounds(placement: placement) else { return WindowActionResult(ok: false) }
        for candidate in runtimeNameCandidates(name) {
            if moveFirstWindow(appName: candidate, bounds: bounds) { return follow(bounds: bounds) }
        }
        return WindowActionResult(ok: false)
    }

    public func placePID(_ pid: pid_t, placement: String) -> WindowActionResult {
        guard let bounds = resolveBounds(placement: placement),
              moveFirstWindow(pid: pid, bounds: bounds) else {
            return WindowActionResult(ok: false)
        }
        return follow(bounds: bounds)
    }

    public func moveProcess(name: String, bounds: DSRect) -> WindowActionResult {
        for candidate in runtimeNameCandidates(name) {
            if moveFirstWindow(appName: candidate, bounds: bounds) { return follow(bounds: bounds) }
        }
        return WindowActionResult(ok: false)
    }

    public func movePID(_ pid: pid_t, bounds: DSRect) -> WindowActionResult {
        guard moveFirstWindow(pid: pid, bounds: bounds) else { return WindowActionResult(ok: false) }
        return follow(bounds: bounds)
    }

    public func moveMouseToDisplayTarget(_ target: String) -> WindowActionResult {
        let displays = displayService.displays()
        guard !displays.isEmpty else { return WindowActionResult(ok: false) }
        let primary = displays.first(where: \.internalDisplay) ?? displays[0]
        guard let display = DisplayGeometry.display(for: target, displays: displays, primaryDisplay: primary) else {
            return WindowActionResult(ok: false)
        }
        let point = DisplayGeometry.centerPoint(for: display.workArea)
        moveMouse(to: point)
        clickMouse(at: point)
        return WindowActionResult(ok: true, feedbackPoint: point)
    }

    public func placeWindowByAction(_ action: String, preferredPID: pid_t? = nil) -> WindowActionResult {
        let displays = displayService.displays()
        guard !displays.isEmpty else { return WindowActionResult(ok: false) }
        let primary = displays.first(where: \.internalDisplay) ?? displays[0]
        guard let selection = selectedWindow(preferredPID: preferredPID),
              let current = DisplayGeometry.display(containing: selection.bounds, displays: displays),
              let target = DisplayGeometry.resolveBoundsForAction(
                  action: action,
                  displays: displays,
                  primaryDisplay: primary,
                  currentDisplay: current
              ) else {
            return WindowActionResult(ok: false)
        }
        guard moveWindow(selection.window, bounds: target) else { return WindowActionResult(ok: false) }
        return follow(bounds: target)
    }

    public func moveMouseToApplicationWindowCenter(name: String) -> WindowActionResult {
        for candidate in runtimeNameCandidates(name) {
            guard let app = copyApplication(named: candidate),
                  let window = firstWindow(in: app),
                  let bounds = windowBounds(window) else {
                continue
            }
            return follow(bounds: bounds)
        }
        return WindowActionResult(ok: false)
    }

    public func moveMouseToPIDWindowCenter(_ pid: pid_t) -> WindowActionResult {
        guard pid > 0 else { return WindowActionResult(ok: false) }
        let app = AXUIElementCreateApplication(pid)
        guard let window = firstWindow(in: app),
              let bounds = windowBounds(window) else {
            return WindowActionResult(ok: false)
        }
        return follow(bounds: bounds)
    }

    private func runtimeNameCandidates(_ name: String) -> [String] {
        name == "微信" ? ["微信", "WeChat"] : [name]
    }

    private func resolveBounds(placement: String) -> DSRect? {
        let displays = displayService.displays()
        guard !displays.isEmpty else { return nil }
        let primary = displays.first(where: \.internalDisplay) ?? displays[0]
        return DisplayGeometry.resolveBoundsForPlacement(placement, displays: displays, primaryDisplay: primary)
    }

    private func follow(bounds: DSRect) -> WindowActionResult {
        let point = DisplayGeometry.centerPoint(for: bounds)
        moveMouse(to: point)
        return WindowActionResult(ok: true, feedbackPoint: point)
    }

    private func selectedWindow(preferredPID: pid_t?) -> (window: AXUIElement, bounds: DSRect)? {
        if let preferredPID, preferredPID > 0 {
            let app = AXUIElementCreateApplication(preferredPID)
            if let window = firstWindow(in: app), let bounds = windowBounds(window) {
                return (window, bounds)
            }
        }
        guard let app = frontmostApplicationAXElement(),
              let window = firstWindow(in: app),
              let bounds = windowBounds(window) else {
            return nil
        }
        return (window, bounds)
    }
}

extension WindowPlacementService: LauncherWindowPlacement {}

public enum Gokit5Serial {
    public static let defaultSerialNumber = "94:A9:90:10:E5:F4"
    public static let hostButtonPrefix = "GOKIT5_HOST_BUTTON:"
    public static let diagnosticPrefix = "GOKIT5_"

    public static func normalizeButton(_ button: String) -> String {
        let key = button.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        return key
    }

    public static func action(for button: String) -> Gokit5Action? {
        switch normalizeButton(button) {
        case "minus":
            return Gokit5Action(
                mouseTarget: "side_left"
            )
        case "voice":
            return Gokit5Action(
                mouseTarget: "external"
            )
        case "switch":
            return Gokit5Action(
                mouseTarget: "side_right"
            )
        case "green":
            return Gokit5Action(
                mouseTarget: "side_right"
            )
        case "plus":
            return Gokit5Action(
                mouseTarget: "internal"
            )
        default:
            return nil
        }
    }

    public static func parseButtonLine(_ line: String) -> String {
        guard let range = line.range(of: hostButtonPrefix) else { return "" }
        let raw = line[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init) ?? ""
        let cleaned = String(raw.prefix { char in
            char.isLetter || char.isNumber || char == "_" || char == "-" || char == "+"
        })
        let button = normalizeButton(cleaned)
        return action(for: button) == nil ? "" : button
    }

    public static func isDiagnosticLine(_ line: String) -> Bool {
        line.contains(diagnosticPrefix)
    }

    public static func extractPortPaths(from text: String, serialNumber: String = defaultSerialNumber) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var ports: [String] = []
        for index in lines.indices where lines[index].contains("USB JTAG_serial debug unit") || lines[index].contains("USB JTAG/serial debug unit") {
            let block = lines[index..<min(lines.count, index + 220)].joined(separator: "\n")
            guard block.contains("\"idVendor\" = 12346"),
                  block.contains("\"idProduct\" = 4097"),
                  serialNumber.isEmpty || block.contains("\"\(serialNumber)\"") else {
                continue
            }
            let pattern = #""IOTTYSuffix"\s*=\s*"([^"]+)""#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsRange = NSRange(block.startIndex..<block.endIndex, in: block)
                for match in regex.matches(in: block, range: nsRange) {
                    guard let range = Range(match.range(at: 1), in: block) else { continue }
                    ports.append("/dev/cu.usbmodem\(block[range])")
                }
            }
        }
        return Array(NSOrderedSet(array: ports)) as? [String] ?? ports
    }
}

public struct Gokit5Status {
    public var enabled: Bool
    public var status: String
    public var portPath: String
    public var running: Bool
    public var updatedAt: String
    public var error: String?
    public var lastButton: String? = nil
    public var lastTarget: String? = nil
    public var lastLine: String? = nil
    public var lastEventAt: String? = nil
    public var lastSerialLine: String? = nil
    public var lastSerialLineAt: String? = nil
    public var serialLineCount: Int = 0
    public var helperStdoutChunkCount: Int = 0
    public var helperStdoutByteCount: Int = 0
    public var helperStdoutLfCount: Int = 0
    public var helperStdoutPreview: String? = nil
    public var recentLines: [String] = []
    public var readPollCount: Int = 0
    public var debounceDropCount: Int = 0
    public var lastDebouncedButton: String? = nil
    public var lastDebouncedAt: String? = nil
    public var lastReadErrno: Int32? = nil
    public var resetInfo: String? = nil

    public mutating func clearConnectionTelemetry() {
        lastButton = nil
        lastTarget = nil
        lastLine = nil
        lastEventAt = nil
        lastSerialLine = nil
        lastSerialLineAt = nil
        serialLineCount = 0
        helperStdoutChunkCount = 0
        helperStdoutByteCount = 0
        helperStdoutLfCount = 0
        helperStdoutPreview = nil
        recentLines = []
        readPollCount = 0
        debounceDropCount = 0
        lastDebouncedButton = nil
        lastDebouncedAt = nil
        lastReadErrno = nil
        resetInfo = nil
    }

    public func json() -> [String: Any] {
        var payload: [String: Any] = [
            "enabled": enabled,
            "status": status,
            "portPath": portPath,
            "running": running,
            "updatedAt": updatedAt
        ]
        if let error { payload["error"] = error }
        if let lastButton { payload["lastButton"] = lastButton }
        if let lastTarget { payload["lastTarget"] = lastTarget }
        if let lastLine { payload["lastLine"] = lastLine }
        if let lastEventAt { payload["lastEventAt"] = lastEventAt }
        if let lastSerialLine { payload["lastSerialLine"] = lastSerialLine }
        if let lastSerialLineAt { payload["lastSerialLineAt"] = lastSerialLineAt }
        payload["serialLineCount"] = serialLineCount
        payload["helperStdoutChunkCount"] = helperStdoutChunkCount
        payload["helperStdoutByteCount"] = helperStdoutByteCount
        payload["helperStdoutLfCount"] = helperStdoutLfCount
        if let helperStdoutPreview { payload["helperStdoutPreview"] = helperStdoutPreview }
        if !recentLines.isEmpty { payload["recentLines"] = recentLines }
        payload["readPollCount"] = readPollCount
        payload["debounceDropCount"] = debounceDropCount
        if let lastDebouncedButton { payload["lastDebouncedButton"] = lastDebouncedButton }
        if let lastDebouncedAt { payload["lastDebouncedAt"] = lastDebouncedAt }
        if let lastReadErrno { payload["lastReadErrno"] = lastReadErrno }
        if let resetInfo { payload["resetInfo"] = resetInfo }
        return payload
    }
}

public final class Gokit5SerialListener {
    private let queue = DispatchQueue(label: "dock-switch.gokit5-serial")
    private let debounceMs: Int
    private let reconnectMs: Int
    private let onAction: (Gokit5Action, String, String) -> Void
    private var serialFD: Int32 = -1
    private var helperProcess: Process?
    private var helperPipe: Pipe?
    private var reconnectWorkItem: DispatchWorkItem?
    private var lineBuffer = Data()
    private var lastDispatchByButton: [String: Date] = [:]
    private var status = Gokit5Status(enabled: true, status: "starting", portPath: "", running: false, updatedAt: isoNow(), error: nil)
    private var readLoopGeneration = 0

    public init(debounceMs: Int = 0, reconnectMs: Int = 2000, onAction: @escaping (Gokit5Action, String, String) -> Void) {
        self.debounceMs = debounceMs
        self.reconnectMs = reconnectMs
        self.onAction = onAction
    }

    public func start() {
        queue.async {
            guard self.status.enabled else { return }
            self.status.running = true
            self.connect()
        }
    }

    public func stop() {
        queue.sync {
            self.status.running = false
            self.reconnectWorkItem?.cancel()
            self.reconnectWorkItem = nil
            self.closeHandle()
        }
    }

    public func snapshot() -> Gokit5Status {
        queue.sync { status }
    }

    private func connect() {
        guard status.running, serialFD < 0, helperProcess == nil else { return }
        let port = findPort()
        guard !port.isEmpty else {
            updateStatus("not_found", portPath: "")
            scheduleReconnect()
            return
        }
        if startHelper(port: port) {
            return
        }
        let fd = Darwin.open(port, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            updateStatus("open_failed", portPath: port, error: "Failed to open serial port: \(String(cString: strerror(errno)))")
            scheduleReconnect()
            return
        }
        guard configure(port: port) else {
            Darwin.close(fd)
            updateStatus("open_failed", portPath: port, error: "Failed to configure serial port")
            scheduleReconnect()
            return
        }
        serialFD = fd
        lineBuffer = Data()
        status.clearConnectionTelemetry()
        updateStatus("connected", portPath: port)
        readLoopGeneration += 1
        startReadLoop(portPath: port, generation: readLoopGeneration)
        resetUsbSerial(fd: fd)
        primeReadAfterReset(portPath: port)
    }

    private func startHelper(port: String) -> Bool {
        let helperURL = Bundle.main.resourceURL?.appendingPathComponent("DockSwitchGokit5Serial")
        guard let helperURL, FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            return false
        }
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = helperURL
        process.arguments = [port]
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { [weak self] process in
            self?.queue.async {
                self?.handleHelperEnded(portPath: port, pid: process.processIdentifier, status: "closed")
            }
        }
        do {
            try process.run()
        } catch {
            status.error = "Failed to start serial helper: \(error.localizedDescription)"
            return false
        }
        helperProcess = process
        helperPipe = stdout
        status.clearConnectionTelemetry()
        updateStatus("connected", portPath: port)
        startHelperPipeReadLoop(pipe: stdout, portPath: port, pid: process.processIdentifier)
        startHelperErrorReadLoop(pipe: stderr)
        return true
    }

    private func startHelperPipeReadLoop(pipe: Pipe, portPath: String, pid: Int32) {
        let fd = pipe.fileHandleForReading.fileDescriptor
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count > 0 {
                    let data = Data(buffer.prefix(count))
                    self?.queue.async {
                        self?.status.helperStdoutChunkCount += 1
                        self?.status.helperStdoutByteCount += count
                        self?.status.helperStdoutLfCount += data.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
                        self?.status.helperStdoutPreview = String(decoding: data.prefix(240), as: UTF8.self)
                        self?.handle(data: data, portPath: portPath)
                    }
                    continue
                }
                if count == 0 {
                    self?.queue.async {
                        self?.handleHelperEnded(portPath: portPath, pid: pid, status: "closed")
                    }
                    return
                }
                if errno == EINTR {
                    continue
                }
                let readError = String(cString: strerror(errno))
                self?.queue.async {
                    self?.handleHelperEnded(portPath: portPath, pid: pid, status: "error", error: readError)
                }
                return
            }
        }
    }

    private func handleHelperEnded(portPath: String, pid: Int32, status nextStatus: String, error: String? = nil) {
        guard status.running, helperProcess?.processIdentifier == pid else { return }
        updateStatus(nextStatus, portPath: portPath, error: error)
        closeHandle()
        scheduleReconnect()
    }

    private func startHelperErrorReadLoop(pipe: Pipe) {
        let fd = pipe.fileHandleForReading.fileDescriptor
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count > 0, let text = String(data: Data(buffer.prefix(count)), encoding: .utf8) {
                    self?.queue.async {
                        self?.status.error = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    continue
                }
                if count == 0 || (count < 0 && errno != EINTR) {
                    return
                }
            }
        }
    }

    private func startReadLoop(portPath: String, generation: Int) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                var shouldContinue = false
                self?.queue.sync {
                    shouldContinue = self?.status.running == true &&
                        self?.serialFD ?? -1 >= 0 &&
                        self?.readLoopGeneration == generation
                }
                if !shouldContinue {
                    return
                }
                self?.queue.async {
                    guard self?.readLoopGeneration == generation else { return }
                    self?.readAvailable(portPath: portPath)
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }

    private func readAvailable(portPath: String) {
        guard serialFD >= 0 else { return }
        status.readPollCount += 1
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(serialFD, &buffer, buffer.count)
            if count > 0 {
                handle(data: Data(buffer.prefix(count)), portPath: portPath)
                continue
            }
            if count == 0 {
                updateStatus("closed", portPath: portPath)
                closeHandle()
                scheduleReconnect()
                return
            }
            if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                status.lastReadErrno = errno
                return
            }
            status.lastReadErrno = errno
            updateStatus("error", portPath: portPath, error: String(cString: strerror(errno)))
            closeHandle()
            scheduleReconnect()
            return
        }
    }

    private func primeReadAfterReset(portPath: String) {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline, serialFD >= 0 {
            readAvailable(portPath: portPath)
            usleep(50_000)
        }
    }

    private func handle(data: Data, portPath: String) {
        lineBuffer.append(data)
        while let newlineIndex = lineBuffer.firstIndex(of: 10) {
            let lineData = lineBuffer[..<newlineIndex]
            lineBuffer.removeSubrange(...newlineIndex)
            let line = String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            status.serialLineCount += 1
            status.lastSerialLine = line
            status.lastSerialLineAt = Self.isoNow()
            if Gokit5Serial.isDiagnosticLine(line) {
                status.recentLines.append(line)
                if status.recentLines.count > 50 {
                    status.recentLines.removeFirst(status.recentLines.count - 50)
                }
            }
            let button = Gokit5Serial.parseButtonLine(line)
            guard !button.isEmpty, shouldDispatch(button) else { continue }
            guard let action = Gokit5Serial.action(for: button) else { continue }
            status.lastButton = button
            status.lastTarget = action.placement
            status.lastLine = line
            status.lastEventAt = Self.isoNow()
            onAction(action, button, line)
        }
    }

    private func shouldDispatch(_ button: String) -> Bool {
        let now = Date()
        if debounceMs > 0,
           let last = lastDispatchByButton[button],
           now.timeIntervalSince(last) * 1000 < Double(debounceMs) {
            status.debounceDropCount += 1
            status.lastDebouncedButton = button
            status.lastDebouncedAt = Self.isoNow()
            return false
        }
        lastDispatchByButton[button] = now
        return true
    }

    private func closeHandle() {
        helperPipe = nil
        if helperProcess?.isRunning == true {
            helperProcess?.terminate()
        }
        helperProcess = nil
        if serialFD >= 0 {
            Darwin.close(serialFD)
            serialFD = -1
        }
        readLoopGeneration += 1
    }

    private func scheduleReconnect() {
        guard status.running, reconnectWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWorkItem = nil
            self.connect()
        }
        reconnectWorkItem = item
        queue.asyncAfter(deadline: .now() + .milliseconds(reconnectMs), execute: item)
    }

    private func updateStatus(_ next: String, portPath: String, error: String? = nil) {
        if next != "connected" {
            status.clearConnectionTelemetry()
        }
        status.status = next
        status.portPath = portPath
        status.updatedAt = Self.isoNow()
        status.error = error
    }

    private func findPort() -> String {
        let envPort = ProcessInfo.processInfo.environment["GOKIT5_SERIAL_PORT"] ?? ""
        if !envPort.isEmpty, FileManager.default.fileExists(atPath: envPort) {
            return envPort
        }

        let dev = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return dev.filter { $0.hasPrefix("cu.usbmodem") }.sorted().first.map { "/dev/\($0)" } ?? ""
    }

    private func resetUsbSerial(fd: Int32) {
        // ESP32-S3 USB-Serial/JTAG exposes boot logs only after a DTR/RTS reset
        // sequence, matching the behavior of pyserial/idf_monitor.
        let tiocmbis = UInt(2_147_775_596)
        let tiocmbic = UInt(2_147_775_595)
        var modemBits: Int32 = 0
        guard ioctl(fd, UInt(TIOCMGET), &modemBits) == 0 else {
            status.resetInfo = "get_failed:\(errno)"
            return
        }
        let original = modemBits
        var results: [String] = ["get:\(original)"]
        let sequence: [(Bool, Bool)] = [
            (false, false),
            (true, true),
            (false, true),
            (true, false),
            (false, false),
        ]
        for (dtr, rts) in sequence {
            var dtrBit: Int32 = TIOCM_DTR
            var rtsBit: Int32 = TIOCM_RTS
            let dtrResult = ioctl(fd, dtr ? tiocmbis : tiocmbic, &dtrBit)
            let dtrErrno = errno
            let rtsResult = ioctl(fd, rts ? tiocmbis : tiocmbic, &rtsBit)
            let rtsErrno = errno
            results.append("\(dtr ? 1 : 0)\(rts ? 1 : 0):\(dtrResult):\(dtrErrno):\(rtsResult):\(rtsErrno)")
            usleep(200_000)
        }
        status.resetInfo = results.joined(separator: ",")
    }

    private func configure(port: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/stty")
        process.arguments = ["-f", port, "115200", "raw", "-echo", "-icanon", "min", "1", "time", "0", "clocal", "-hupcl"]
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

public final class CodexDisplaySelectionService {
    private struct CodexWindowRef {
        var element: AXUIElement
        var bounds: DSRect

        var identity: String {
            [
                round(bounds.x),
                round(bounds.y),
                round(bounds.width),
                round(bounds.height)
            ].map { String(Int($0)) }.joined(separator: ":")
        }
    }

    private let displayService: DisplayService
    private let showMouseFeedback: (CGPoint) -> Void

    public init(
        displayService: DisplayService = DisplayService(),
        showMouseFeedback: @escaping (CGPoint) -> Void = { _ in }
    ) {
        self.displayService = displayService
        self.showMouseFeedback = showMouseFeedback
    }

    public func select(target rawTarget: String, appName: String = "Codex", source: String = "") -> [String: Any] {
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        guard AXIsProcessTrusted() else {
            return ["ok": false, "error": "Accessibility permission is required"]
        }
        let target = normalizeTarget(rawTarget)
        guard !target.isEmpty else {
            return ["ok": false, "error": "target must be side_left, external, side_right, or internal"]
        }
        let displays = displayService.displays()
        guard let targetDisplay = display(for: target, displays: displays) else {
            return ["ok": false, "target": target, "error": "No display found for \(target)"]
        }

        let point = CGPoint(x: targetDisplay.workArea.centerX, y: targetDisplay.workArea.centerY)
        let actualPoint = moveMouse(to: point, display: targetDisplay)
        clickMouse(at: actualPoint)

        let existingWindows = codexWindows(appName: appName)
        var window = existingWindows.filter { ref in
            sameDisplay(self.display(containing: ref.bounds, displays: displays), targetDisplay)
        }
        .sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
        .first
        let reusedExistingTargetWindow = window != nil
        var createdNewWindow = false
        var moved = false

        if window == nil {
            let created = createCodexWindowOnTarget(
                appName: appName,
                targetDisplay: targetDisplay,
                displays: displays,
                existingWindows: existingWindows
            )
            window = created.window
            createdNewWindow = created.window != nil
            moved = created.moved
        }

        if let window {
            focus(appName: appName, source: source, window: window)
        }
        showMouseFeedback(actualPoint)

        return [
            "ok": true,
            "target": target,
            "placement": placement(for: target),
            "appName": appName,
            "source": source,
            "display": [
                "id": targetDisplay.id,
                "label": targetDisplay.label,
                "bounds": rectJSON(targetDisplay.bounds),
                "workArea": rectJSON(targetDisplay.workArea)
            ],
            "selectedWindow": window.map { rectJSON($0.bounds) } as Any,
            "reusedExistingTargetWindow": reusedExistingTargetWindow,
            "createdNewWindow": createdNewWindow,
            "moved": moved,
            "focused": window != nil,
            "mouseMoved": true,
            "mouseClicked": true,
            "feedbackPoint": ["x": round(actualPoint.x), "y": round(actualPoint.y)]
        ]
    }

    private func normalizeTarget(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "-", with: "_") {
        case "left", "side", "side_left":
            return "side_left"
        case "up", "top", "external":
            return "external"
        case "right", "side_right":
            return "side_right"
        case "down", "bottom", "internal":
            return "internal"
        default:
            return ""
        }
    }

    private func placement(for target: String) -> String {
        "\(target)_fill"
    }

    private func display(for target: String, displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        guard !displays.isEmpty else { return nil }
        let primary = displays.first(where: \.internalDisplay) ?? displays[0]
        let externals = displays.filter { !$0.internalDisplay }
        let largestExternal = externals.max { a, b in
            a.workArea.width * a.workArea.height < b.workArea.width * b.workArea.height
        }
        let sideCandidates = externals.filter { external in
            guard let largestExternal else { return true }
            return external.id != largestExternal.id
        }
        switch target {
        case "internal":
            return primary
        case "external":
            return largestExternal ?? primary
        case "side_left":
            return sideCandidates.min { $0.bounds.x < $1.bounds.x } ?? primary
        case "side_right":
            return sideCandidates.max { $0.bounds.x < $1.bounds.x } ?? primary
        default:
            return nil
        }
    }

    private func display(containing rect: DSRect, displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        displays.first { $0.bounds.contains(CGPoint(x: rect.centerX, y: rect.centerY)) }
    }

    private func sameDisplay(_ a: DisplaySnapshot?, _ b: DisplaySnapshot?) -> Bool {
        guard let a, let b else { return false }
        return a.id == b.id || (!a.label.isEmpty && a.label == b.label)
    }

    private func codexWindows(appName: String) -> [CodexWindowRef] {
        let normalized = LauncherRules.normalizeAppName(appName)
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            LauncherRules.normalizeAppName($0.localizedName ?? "") == normalized
        }) else { return [] }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.compactMap { window -> CodexWindowRef? in
            guard let point = axPoint(window, kAXPositionAttribute as CFString),
                  let size = axSize(window, kAXSizeAttribute as CFString),
                  size.width > 0,
                  size.height > 0 else { return nil }
            return CodexWindowRef(
                element: window,
                bounds: DSRect(x: point.x, y: point.y, width: size.width, height: size.height)
            )
        }
    }

    private func focus(appName: String, source: String, window: CodexWindowRef) {
        let normalized = LauncherRules.normalizeAppName(appName)
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            LauncherRules.normalizeAppName($0.localizedName ?? "") == normalized
        }) else { return }
        app.activate(options: [.activateIgnoringOtherApps])
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }

    private func createCodexWindowOnTarget(
        appName: String,
        targetDisplay: DisplaySnapshot,
        displays: [DisplaySnapshot],
        existingWindows: [CodexWindowRef]
    ) -> (window: CodexWindowRef?, moved: Bool) {
        let existingIdentities = Set(existingWindows.map(\.identity))
        requestNewCodexWindow(appName: appName, targetDisplay: targetDisplay)
        let deadline = Date().addingTimeInterval(1.6)
        let newInstanceDeadline = Date().addingTimeInterval(0.45)
        var requestedNewInstance = false
        var latestWindows: [CodexWindowRef] = []
        repeat {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.06))
            latestWindows = codexWindows(appName: appName)
            if let targetWindow = latestWindows.first(where: { ref in
                !existingIdentities.contains(ref.identity) &&
                    sameDisplay(display(containing: ref.bounds, displays: displays), targetDisplay)
            }) {
                return (targetWindow, false)
            }
            if let newWindow = latestWindows.first(where: { !existingIdentities.contains($0.identity) }) {
                let alreadyOnTarget = sameDisplay(display(containing: newWindow.bounds, displays: displays), targetDisplay)
                let moved = alreadyOnTarget ? false : moveWindow(newWindow.element, bounds: targetDisplay.workArea)
                let refreshed = windowBounds(newWindow.element)
                    .map { CodexWindowRef(element: newWindow.element, bounds: $0) } ?? newWindow
                return (refreshed, moved)
            }
            if !requestedNewInstance && Date() >= newInstanceDeadline {
                openNewCodexInstance(appName: appName)
                requestedNewInstance = true
            }
        } while Date() < deadline

        let targetWindow = latestWindows.first { ref in
            sameDisplay(display(containing: ref.bounds, displays: displays), targetDisplay)
        }
        return (targetWindow, false)
    }

    private func requestNewCodexWindow(appName: String, targetDisplay: DisplaySnapshot) {
        if createCodexWindowWithScripting(appName: appName, bounds: targetDisplay.workArea) {
            return
        }
        let normalized = LauncherRules.normalizeAppName(appName)
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            LauncherRules.normalizeAppName($0.localizedName ?? "") == normalized
        }) {
            app.activate(options: [.activateIgnoringOtherApps])
            postCommandN()
            return
        }
        openCodexApplication(appName: appName)
    }

    private func createCodexWindowWithScripting(appName: String, bounds: DSRect) -> Bool {
        let escapedName = appName.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let left = Int(round(bounds.x))
        let top = Int(round(bounds.y))
        let right = Int(round(bounds.x + bounds.width))
        let bottom = Int(round(bounds.y + bounds.height))
        let source = """
        tell application "\(escapedName)" to make new window with properties {bounds:{\(left), \(top), \(right), \(bottom)}}
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        script.executeAndReturnError(&error)
        if let error {
            NSLog("dock-switch: failed to create \(appName) window via scripting: \(error)")
            return false
        }
        return true
    }

    private func openCodexApplication(appName: String) {
        let candidates = [
            "/Applications/\(appName).app",
            "\(NSHomeDirectory())/Applications/\(appName).app"
        ]
        let path = candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "/Applications/\(appName).app"
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func openNewCodexInstance(appName: String) {
        let candidates = [
            "/Applications/\(appName).app",
            "\(NSHomeDirectory())/Applications/\(appName).app"
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration) { _, error in
            if let error {
                NSLog("dock-switch: failed to open new \(appName) instance: \(error.localizedDescription)")
            }
        }
    }

    private func postCommandN() {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_N), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_N), keyDown: false) else {
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func moveMouse(to point: CGPoint, display: DisplaySnapshot? = nil) -> CGPoint {
        if let display, display.id != 0 {
            let localPoint = CGPoint(
                x: point.x - display.bounds.x,
                y: point.y - display.bounds.y
            )
            if CGDisplayMoveCursorToPoint(CGDirectDisplayID(display.id), localPoint) == .success {
                CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
                return currentMouseLocation() ?? point
            }
        }
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        return currentMouseLocation() ?? point
    }

    private func currentMouseLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    private func clickMouse(at point: CGPoint) {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

public final class ControlServer {
    private var listenFD: Int32 = -1
    private var running = false
    private let queue = DispatchQueue(label: "dock-switch.control-server")
    private let connectionQueue = DispatchQueue(label: "dock-switch.control-server.connections", attributes: .concurrent)
    private let displayService: DisplayService
    private let windowPlacement: WindowPlacementService
    private let showLauncher: () -> Bool
    private let hideLauncher: () -> Bool
    private let showMouseFeedback: (CGPoint) -> Void
    private let getGokit5Status: () -> [String: Any]
    private let selectCodexDisplay: ([String: Any]) -> [String: Any]

    public init(
        displayService: DisplayService,
        windowPlacement: WindowPlacementService,
        showLauncher: @escaping () -> Bool,
        hideLauncher: @escaping () -> Bool,
        showMouseFeedback: @escaping (CGPoint) -> Void = { _ in },
        getGokit5Status: @escaping () -> [String: Any] = { ["enabled": false, "status": "unavailable", "running": false] },
        selectCodexDisplay: @escaping ([String: Any]) -> [String: Any] = { _ in ["ok": false, "error": "select-codex-display is unavailable"] }
    ) {
        self.displayService = displayService
        self.windowPlacement = windowPlacement
        self.showLauncher = showLauncher
        self.hideLauncher = hideLauncher
        self.showMouseFeedback = showMouseFeedback
        self.getGokit5Status = getGokit5Status
        self.selectCodexDisplay = selectCodexDisplay
    }

    deinit {
        stop()
    }

    public func start(path: String = DockSwitchPaths.controlSocket.path) {
        stop()
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        unlink(path)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            path.withCString { cstr in
                strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cstr, maxLen - 1)
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0, listen(listenFD, 16) == 0 else {
            stop()
            return
        }
        running = true
        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    public func stop() {
        running = false
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        unlink(DockSwitchPaths.controlSocket.path)
    }

    private func acceptLoop() {
        while running {
            let fd = accept(listenFD, nil, nil)
            if fd < 0 { continue }
            connectionQueue.async { [weak self] in
                self?.handle(fd: fd)
            }
        }
    }

    private func handle(fd: Int32) {
        defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: 8192)
        let count = read(fd, &buffer, buffer.count)
        guard count > 0 else { return }
        let data = Data(buffer.prefix(count))
        let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let command = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]) ?? [:]
        let response = handle(command)
        let responseData = ((try? JSONSerialization.data(withJSONObject: response)) ?? Data("{\"ok\":false}\n".utf8)) + Data("\n".utf8)
        _ = responseData.withUnsafeBytes { write(fd, $0.baseAddress, responseData.count) }
    }

    private func handle(_ command: [String: Any]) -> [String: Any] {
        switch command["command"] as? String {
        case "debug-displays":
            let displays = displayService.displays().map { display -> [String: Any] in
                [
                    "id": display.id,
                    "internal": display.internalDisplay,
                    "bounds": rectJSON(display.bounds),
                    "workArea": rectJSON(display.workArea),
                    "scaleFactor": display.scaleFactor,
                    "label": display.label
                ]
            }
            return ["ok": true, "displays": displays]
        case "show-launcher":
            return showLauncher() ? ["ok": true] : ["ok": false, "error": "Failed to show launcher"]
        case "hide-launcher":
            return hideLauncher() ? ["ok": true] : ["ok": false, "error": "Failed to hide launcher"]
        case "gokit5-status":
            return ["ok": true, "gokit5": getGokit5Status()]
        case "select-codex-display":
            return selectCodexDisplay(command)
        case "place-app":
            guard let appName = command["appName"] as? String,
                  let placement = command["placement"] as? String else {
                return ["ok": false, "error": "appName and placement are required"]
            }
            NSWorkspace.shared.launchApplication(appName)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                _ = self.showFeedbackIfSuccessful(self.windowPlacement.placeProcess(name: appName, placement: placement))
            }
            return ["ok": true]
        case "place-pid":
            guard let pid = number(command["pid"]),
                  let placement = command["placement"] as? String else {
                return ["ok": false, "error": "pid and placement are required"]
            }
            return json(for: showFeedbackIfSuccessful(windowPlacement.placePID(pid_t(pid), placement: placement)))
        case "move-app":
            guard let appName = command["appName"] as? String,
                  let rect = rectFrom(command) else {
                return ["ok": false, "error": "appName and x/y/w/h are required"]
            }
            return json(for: showFeedbackIfSuccessful(windowPlacement.moveProcess(name: appName, bounds: rect)))
        case "move-pid":
            guard let pid = number(command["pid"]),
                  let rect = rectFrom(command) else {
                return ["ok": false, "error": "pid and x/y/w/h are required"]
            }
            return json(for: showFeedbackIfSuccessful(windowPlacement.movePID(pid_t(pid), bounds: rect)))
        default:
            return ["ok": false, "error": "Unsupported command"]
        }
    }

    @discardableResult
    private func showFeedbackIfSuccessful(_ result: WindowActionResult) -> WindowActionResult {
        if result.ok, let point = result.feedbackPoint {
            showMouseFeedback(point)
        }
        return result
    }

    private func json(for result: WindowActionResult) -> [String: Any] {
        var response: [String: Any] = ["ok": result.ok]
        if let point = result.feedbackPoint {
            response["feedbackPoint"] = ["x": round(point.x), "y": round(point.y)]
        }
        return response
    }
}

private func rectJSON(_ rect: DSRect) -> [String: Any] {
    ["x": rect.x, "y": rect.y, "width": rect.width, "height": rect.height]
}

private func number(_ value: Any?) -> Int? {
    if let int = value as? Int { return int }
    if let double = value as? Double { return Int(double) }
    if let string = value as? String { return Int(string) }
    return nil
}

private func rectFrom(_ command: [String: Any]) -> DSRect? {
    guard let x = number(command["x"]),
          let y = number(command["y"]),
          let w = number(command["w"]),
          let h = number(command["h"]),
          w > 0,
          h > 0 else { return nil }
    return DSRect(x: Double(x), y: Double(y), width: Double(w), height: Double(h))
}

private func axString(_ element: AXUIElement, _ attr: CFString) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr, &value) == .success else { return nil }
    return value as? String
}

private func axPoint(_ element: AXUIElement, _ attr: CFString) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr, &value) == .success,
          let ax = value,
          CFGetTypeID(ax) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue((ax as! AXValue), .cgPoint, &point) else { return nil }
    return point
}

private func axSize(_ element: AXUIElement, _ attr: CFString) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr, &value) == .success,
          let ax = value,
          CFGetTypeID(ax) == AXValueGetTypeID() else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue((ax as! AXValue), .cgSize, &size) else { return nil }
    return size
}

private func axChildren(_ element: AXUIElement) -> [AXUIElement]? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
          let array = value as? [AXUIElement] else { return nil }
    return array
}

private func copyApplication(named name: String) -> AXUIElement? {
    let normalized = LauncherRules.normalizeAppName(name)
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
        LauncherRules.normalizeAppName($0.localizedName ?? "") == normalized
    }) else { return nil }
    return AXUIElementCreateApplication(app.processIdentifier)
}

private func frontmostApplicationAXElement() -> AXUIElement? {
    guard let app = NSWorkspace.shared.frontmostApplication,
          LauncherRules.normalizeAppName(app.localizedName ?? "") != "dock-switch" else {
        return nil
    }
    return AXUIElementCreateApplication(app.processIdentifier)
}

private func firstWindow(in app: AXUIElement) -> AXUIElement? {
    if let focused = usableWindowFromAppAttribute(app, kAXFocusedWindowAttribute as CFString) {
        return focused
    }
    if let main = usableWindowFromAppAttribute(app, kAXMainWindowAttribute as CFString) {
        return main
    }
    return allUsableWindows(in: app)
        .sorted { (windowBounds($0)?.width ?? 0) * (windowBounds($0)?.height ?? 0) > (windowBounds($1)?.width ?? 0) * (windowBounds($1)?.height ?? 0) }
        .first
}

private func usableWindowFromAppAttribute(_ app: AXUIElement, _ attr: CFString) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, attr, &value) == .success,
          let window = value,
          CFGetTypeID(window) == AXUIElementGetTypeID() else {
        return nil
    }
    let element = (window as! AXUIElement)
    return isUsableWindow(element) ? element : nil
}

private func allUsableWindows(in app: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement] else { return [] }
    return windows.filter(isUsableWindow)
}

private func isUsableWindow(_ window: AXUIElement) -> Bool {
    guard let bounds = windowBounds(window),
          bounds.width > 0,
          bounds.height > 0 else {
        return false
    }
    let subrole = axString(window, kAXSubroleAttribute as CFString) ?? ""
    if subrole.isEmpty { return true }
    return subrole == kAXStandardWindowSubrole as String || subrole == kAXDialogSubrole as String
}

private func windowBounds(_ window: AXUIElement) -> DSRect? {
    guard let point = axPoint(window, kAXPositionAttribute as CFString),
          let size = axSize(window, kAXSizeAttribute as CFString),
          size.width > 0,
          size.height > 0 else {
        return nil
    }
    return DSRect(x: point.x, y: point.y, width: size.width, height: size.height)
}

private func moveFirstWindow(appName: String, bounds: DSRect) -> Bool {
    guard let app = copyApplication(named: appName) else { return false }
    return moveFirstWindow(app: app, bounds: bounds)
}

private func moveFirstWindow(pid: pid_t, bounds: DSRect) -> Bool {
    let app = AXUIElementCreateApplication(pid)
    return moveFirstWindow(app: app, bounds: bounds)
}

private func moveFirstWindow(app: AXUIElement, bounds: DSRect) -> Bool {
    guard AXIsProcessTrusted(), let win = firstWindow(in: app) else { return false }
    return moveWindow(win, bounds: bounds)
}

private func moveWindow(_ win: AXUIElement, bounds: DSRect) -> Bool {
    guard AXIsProcessTrusted() else { return false }
    clearAXBoolIfTrueAndSettable(win, attr: "AXFullScreen" as CFString)
    let moved = applyWindowBoundsPrecisely(win, bounds: bounds)
    if moved {
        AXUIElementPerformAction(win, kAXRaiseAction as CFString)
    }
    return moved
}

private func applyWindowBoundsPrecisely(_ win: AXUIElement, bounds: DSRect) -> Bool {
    var point = CGPoint(x: bounds.x, y: bounds.y)
    var size = CGSize(width: bounds.width, height: bounds.height)
    guard let pointValue = AXValueCreate(.cgPoint, &point),
          let sizeValue = AXValueCreate(.cgSize, &size) else { return false }

    let app = applicationElement(for: win)
    var restoredEnhancedUI = false
    if let app,
       axBool(app, "AXEnhancedUserInterface" as CFString) == true,
       setAXBoolIfSettable(app, attr: "AXEnhancedUserInterface" as CFString, value: false) {
        restoredEnhancedUI = true
    }
    defer {
        if restoredEnhancedUI, let app {
            _ = setAXBoolIfSettable(app, attr: "AXEnhancedUserInterface" as CFString, value: true)
        }
    }

    func applyOnce() {
        _ = AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sizeValue)
        _ = AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, pointValue)
        _ = AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sizeValue)
        Thread.sleep(forTimeInterval: 0.012)
    }

    applyOnce()
    if windowBounds(win)?.isNear(bounds, tolerance: 2) == true {
        return true
    }
    applyOnce()
    return windowBounds(win)?.isNear(bounds, tolerance: 2) == true
}

private func applicationElement(for window: AXUIElement) -> AXUIElement? {
    var pid = pid_t()
    guard AXUIElementGetPid(window, &pid) == .success, pid > 0 else { return nil }
    return AXUIElementCreateApplication(pid)
}

private func clearAXBoolIfTrueAndSettable(_ element: AXUIElement, attr: CFString) {
    guard axBool(element, attr) == true else { return }
    _ = setAXBoolIfSettable(element, attr: attr, value: false)
}

private func setAXBoolIfSettable(_ element: AXUIElement, attr: CFString, value: Bool) -> Bool {
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(element, attr, &settable) == .success, settable.boolValue else {
        return false
    }
    return AXUIElementSetAttributeValue(element, attr, value as CFBoolean) == .success
}

private func axBool(_ element: AXUIElement, _ attr: CFString) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr, &value) == .success,
          let boolValue = value as? Bool else {
        return nil
    }
    return boolValue
}

private extension DSRect {
    func isNear(_ other: DSRect, tolerance: Double) -> Bool {
        abs(x - other.x) <= tolerance &&
            abs(y - other.y) <= tolerance &&
            abs(width - other.width) <= tolerance &&
            abs(height - other.height) <= tolerance
    }
}

private func moveMouse(to point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
}

private func clickMouse(at point: CGPoint) {
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
        return
    }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

private func clamp(_ value: Double, _ minValue: Double, _ maxValue: Double) -> Double {
    guard maxValue >= minValue else { return minValue }
    return max(minValue, min(value, maxValue))
}
