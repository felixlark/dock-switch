// Installer lifecycle helper. Exact installed bundle paths; no input or activation.
import AppKit
import Foundation

let timeout: TimeInterval?
if let configured = ProcessInfo.processInfo.environment["DOCK_SWITCH_STOP_TIMEOUT_SECONDS"] {
    guard let value = Double(configured), value.isFinite, value > 0 else {
        fputs("stop timeout must be positive when explicitly configured\n", stderr); exit(1)
    }
    timeout = value
} else { timeout = nil }

let mainURL = URL(fileURLWithPath: "/Applications/dock-switch.app")
let paths = Set([mainURL.path, mainURL.appendingPathComponent("Contents/Resources/DockSwitchSettings.app").path])
func apps() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter { paths.contains($0.bundleURL?.path ?? "") }
}
if CommandLine.arguments.last == "status" {
    print(apps().contains { $0.bundleURL == mainURL } ? "running" : "stopped")
} else {
    // Settings keeps unsaved rows in memory. Never discard another writer's draft.
    let active = apps()
    guard !active.contains(where: { $0.bundleURL != mainURL }) else {
        fputs("Settings is running; preserve its draft and close it before installing\n", stderr)
        exit(1)
    }
    if CommandLine.arguments.last == "check" { print("safe"); exit(0) }
    for app in active.filter({ $0.bundleURL == mainURL }) { guard app.terminate() else { fputs("normal termination refused\n", stderr); exit(1) } }
    let deadline = timeout.map { Date(timeIntervalSinceNow: $0) }
    while !apps().isEmpty {
        guard !apps().contains(where: { $0.bundleURL != mainURL }) else {
            fputs("Settings appeared; installation stopped without closing it\n", stderr); exit(1)
        }
        if let deadline, Date() >= deadline {
            fputs("configured normal termination timeout reached; installation stopped\n", stderr); exit(1)
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }
    print("stopped")
}
