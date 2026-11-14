import Foundation

/// Geometry and ownership policy only; no activation, pointer or GUI operations.
public enum ToolWindowPolicy {
    public enum Scope: Equatable { case dedicated, document(URL), none }
    public static let enabledKey = "quietToolWindowsEnabled"
    public static let protectedBundles: Set<String> = [
        "com.openai.codex", "com.webcatalog.juli.x-chat",
        "com.google.Chrome.app.lodlkdfmihgonocnmddehnfgiljnadcf"
    ]
    public static let utilityBundles: Set<String> = [
        "me.longbiaochen.dock-switch.settings", "me.longbiaochen.codex-plus",
        "com.deskvncviewer.desktop"
    ]
    public static func scope(bundleID: String, dedicated: Bool, resource: URL?, existingDocuments: Set<URL>) -> Scope {
        guard !protectedBundles.contains(bundleID) else { return .none }
        if utilityBundles.contains(bundleID) || dedicated { return .dedicated }
        guard let resource, resource.isFileURL else { return .none }
        let normalized = resource.standardizedFileURL
        return existingDocuments.contains(normalized) ? .none : .document(normalized)
    }
    public static func remainingClaims(_ claims: Set<URL>, knownDocuments: Set<URL>) -> Set<URL> {
        claims.subtracting(knownDocuments)
    }

    public static func target(_ displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        displays.filter { !$0.internalDisplay }.max { $0.bounds.centerX < $1.bounds.centerX }
    }

    public static func destination(frame: DSRect, area: DSRect) -> DSRect {
        let width = min(frame.width, area.width)
        let height = min(frame.height, area.height)
        return DSRect(x: area.x + (area.width - width) / 2,
                      y: area.y + (area.height - height) / 2, width: width, height: height)
    }

    public static func eligible(role: String, subrole: String, minimized: Bool, fullscreen: Bool) -> Bool {
        role == "AXWindow" && ["AXStandardWindow", "AXDialog", "AXSystemDialog"].contains(subrole)
            && !minimized && !fullscreen
    }

    public static func intersects(_ frame: DSRect, _ other: DSRect) -> Bool {
        min(frame.maxX, other.maxX) > max(frame.minX, other.minX)
            && min(frame.maxY, other.maxY) > max(frame.minY, other.minY)
    }
    public static func contained(_ frame: DSRect, in area: DSRect) -> Bool {
        frame.minX >= area.minX && frame.minY >= area.minY && frame.maxX <= area.maxX && frame.maxY <= area.maxY
    }
}
