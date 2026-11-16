// Installer lifecycle helper. Exact installed bundle paths; no input or activation.
import AppKit
import Foundation

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
    let deadline = Date(timeIntervalSinceNow: 15)
    while !apps().isEmpty && Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1)) }
    guard apps().isEmpty else { fputs("normal termination incomplete; installation stopped\n", stderr); exit(1) }
    print("stopped")
}
