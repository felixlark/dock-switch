import SwiftUI

@main
struct SettingsStoreChecks {
    @MainActor static func main() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let configURL = dir.appendingPathComponent("config.json")
        let dockURL = dir.appendingPathComponent("dock.json")
        try Data(#"{"dock_items":[{"name":"Other","key":"1"}]}"#.utf8).write(to: configURL)
        try Data(#"[{"name":"WorkBuddy","pos":{"x":10}},{"name":"Other","pos":{"x":20}}]"#.utf8).write(to: dockURL)
        let store = SettingsStore(arguments: ["--config", configURL.path, "--dock-cache", dockURL.path])
        precondition(store.rows[0].key == "2")
        store.update(rowID: "WorkBuddy", screen: "side_right", position: "right_half")
        precondition(store.canSave)
        store.save()
        precondition(store.errorText.isEmpty)
        precondition(store.rows[0].screen == "side_right" && store.rows[0].position == "right_half")
        precondition(store.rows[0].fallback && store.rows[0].key == "2")
        store.save()
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        let item = (json["dock_items"] as! [[String: Any]]).first { $0["name"] as? String == "WorkBuddy" }!
        precondition(item["key"] == nil && item["placement"] as? String == "side_right_right_half")
        store.update(rowID: "WorkBuddy", key: "Q")
        store.save()
        store.update(rowID: "WorkBuddy", key: "")
        store.save()
        precondition(store.rows[0].key == "2" && store.rows[0].screen == "side_right")
        print("Settings save/reload/re-save, clear key, numeric collision passed")
    }
}
