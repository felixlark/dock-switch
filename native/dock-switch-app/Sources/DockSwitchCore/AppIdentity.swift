import Foundation

/// Both processes read the main app's preference and notification namespace.
public struct AppIdentity: Equatable {
    public static let publicNamespace = "io.github.felixlark.dock-switch"
    public let dataNamespace: String

    public init(info: [String: Any]) {
        // A neutral fallback supports ordinary SwiftPM tests without an app bundle.
        dataNamespace = (info["DockSwitchDataNamespace"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? Self.publicNamespace
    }

    public static var current: Self { Self(info: Bundle.main.infoDictionary ?? [:]) }

    public func notification(_ suffix: String) -> Notification.Name {
        Notification.Name("\(dataNamespace).\(suffix)")
    }

    public static func settingsBundleIdentifier(in bundle: Bundle) -> String? {
        guard let url = bundle.resourceURL?.appendingPathComponent("DockSwitchSettings.app") else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}
