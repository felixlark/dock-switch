import AppKit
import Foundation

struct RunningLauncherApplication {
    var name: String
    var bundleIdentifier: String?
    var bundleURL: URL
}

/// Separate system effects from routing so tests never launch or activate apps.
protocol LauncherApplicationWorkspace {
    var runningApplications: [RunningLauncherApplication] { get }
    func applicationURL(bundleIdentifier: String) -> URL?
    func applicationURL(name: String) -> URL?
    func prepareActivation(at url: URL)
    func openApplication(at url: URL)
    func openResource(at url: URL)
}

struct ApplicationLauncher {
    var workspace: any LauncherApplicationWorkspace = SystemLauncherApplicationWorkspace()
    var resolveOpenPath: (String) -> String = WebAppRuntime.resolveOpenPath

    @discardableResult
    func open(name: String, openPath: String? = nil) -> Bool {
        let url: URL
        if let path = openPath, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            url = URL(fileURLWithPath: resolveOpenPath(path))
            if url.pathExtension.lowercased() != "app" {
                workspace.openResource(at: url)
                return true
            }
        } else {
            let canonicalURL = LauncherRules.normalizeAppName(name) == "feishu"
                ? workspace.applicationURL(bundleIdentifier: "com.electron.lark") : nil
            let runningURL = workspace.runningApplications.first {
                LauncherRules.matchesApplication(name: name, localizedName: $0.name, bundleIdentifier: $0.bundleIdentifier) ||
                    LauncherRules.normalizeAppName(name) == LauncherRules.normalizeAppName($0.bundleURL.lastPathComponent)
            }?.bundleURL
            guard let resolved = canonicalURL ?? runningURL ?? workspace.applicationURL(name: name) else {
                NSLog("dock-switch: application not found name=%@", name)
                return false
            }
            url = resolved
        }

        workspace.prepareActivation(at: url)
        // Always send the normal open/reopen request, including when activation
        // succeeds: a running process may have no visible windows.
        workspace.openApplication(at: url)
        return true
    }
}

private struct SystemLauncherApplicationWorkspace: LauncherApplicationWorkspace {
    var runningApplications: [RunningLauncherApplication] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let url = app.bundleURL, app.activationPolicy == .regular else { return nil }
            return RunningLauncherApplication(name: app.localizedName ?? "", bundleIdentifier: app.bundleIdentifier, bundleURL: url)
        }
    }

    func applicationURL(bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func applicationURL(name: String) -> URL? {
        var candidates = [name.trimmingCharacters(in: .whitespacesAndNewlines)]
        if LauncherRules.normalizeAppName(name) == "feishu" { candidates += ["Feishu", "Lark", "飞书"] }
        if LauncherRules.normalizeAppName(name) == "google chrome" { candidates.append("Google Chrome") }
        // Keep LaunchServices name lookup for existing name-only configuration.
        // Actual opening uses openApplication, never the deprecated launch API.
        for candidate in candidates {
            if let path = NSWorkspace.shared.fullPath(forApplication: candidate) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    func prepareActivation(at url: URL) {
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
        }) {
            let accepted: Bool
            if #available(macOS 14.0, *) {
                NSApplication.shared.yieldActivation(to: app)
                accepted = app.activate(from: .current, options: [])
            } else {
                accepted = app.activate(options: [.activateIgnoringOtherApps])
            }
            NSLog("dock-switch: activation bundle=%@ pid=%d accepted=%d", app.bundleIdentifier ?? "unknown", app.processIdentifier, accepted ? 1 : 0)
        } else if #available(macOS 14.0, *), let identifier = Bundle(url: url)?.bundleIdentifier {
            NSApplication.shared.yieldActivation(toApplicationWithBundleIdentifier: identifier)
        }
    }

    func openApplication(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            NSLog("dock-switch: open app=%@ pid=%d error=%@", url.lastPathComponent, app?.processIdentifier ?? -1, error?.localizedDescription ?? "none")
        }
    }

    func openResource(at url: URL) {
        if !NSWorkspace.shared.open(url) {
            NSLog("dock-switch: open resource failed path=%@", url.path)
        }
    }
}
