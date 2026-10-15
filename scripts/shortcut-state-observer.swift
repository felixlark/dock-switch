// Read-only acceptance aid: no input injection, event tap, permission request,
// window titles, typed text, or screenshot capture. GUI actions belong to CUA.
import AppKit
import Carbon

let duration = Double(CommandLine.arguments[1])!
let started = ProcessInfo.processInfo.systemUptime
let installedExecutable = "/Applications/dock-switch.app/Contents/MacOS/DockSwitch"

func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}

func snapshot() -> [String: Any] {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "unknown"
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "me.longbiaochen.dock-switch")
        .filter { $0.executableURL?.path == installedExecutable }
    let pids = Set(apps.map { $0.processIdentifier })
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    let frontmost = NSWorkspace.shared.frontmostApplication
    let frontmostWindows: [[String: Any]] = (windows ?? []).compactMap { window in
        guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
              pid == frontmost?.processIdentifier,
              (window[kCGWindowLayer as String] as? Int) == 0,
              let bounds = window[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return ["pid": pid, "bounds": bounds]
    }
    let hudWindows: [[String: Any]] = (windows ?? []).compactMap { window in
        guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
              pids.contains(pid),
              (window[kCGWindowAlpha as String] as? Double ?? 0) > 0,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              (bounds["Width"] as? Double ?? 0) > 100,
              // OverlayLayoutService uses a 60pt strip (smaller while hiding).
              // The same PID's 132pt mouse ripple must not count as the HUD.
              (bounds["Height"] as? Double ?? 0) > 20,
              (bounds["Height"] as? Double ?? 0) <= 64 else { return nil }
        return ["pid": pid, "bounds": bounds]
    }
    return [
        "inputSourceID": sourceID,
        "installedPIDs": apps.map { $0.processIdentifier }.sorted(),
        "hudVisible": windows == nil ? NSNull() : !hudWindows.isEmpty as Any,
        "hudWindows": hudWindows,
        "windowObservationAvailable": windows != nil,
        "frontmostBundleID": frontmost?.bundleIdentifier ?? "unknown",
        "frontmostWindows": frontmostWindows
    ]
}

var previous: Data?
var count = 0
repeat {
    // Pump workspace notifications without activating or manipulating any app.
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    let state = snapshot()
    let comparable = try! JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
    if comparable != previous {
        emit(["event": "state", "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started,
              "timestamp": ISO8601DateFormatter().string(from: Date()), "state": state])
        previous = comparable
        count += 1
    }
} while ProcessInfo.processInfo.systemUptime - started < duration
emit(["event": "end", "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started, "stateEvents": count])
