import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var phraseShortcut = CustomPhraseShortcut.default
    @Published var phraseEnabled = true
    @Published var phraseStatus = ""
    private var phraseObserver: NSObjectProtocol?

    var phraseComponentInstalled: Bool {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/wubi-phrase")
        return CustomPhraseShortcut.componentFiles
            .allSatisfy { FileManager.default.fileExists(atPath: base.appendingPathComponent($0).path) }
    }

    func loadPhraseSettings() {
        let defaults = UserDefaults(suiteName: CustomPhraseShortcut.suiteName)!
        defaults.synchronize()
        phraseShortcut = CustomPhraseShortcut.load(defaults)
        phraseEnabled = defaults.object(forKey: CustomPhraseShortcut.enabledKey) as? Bool ?? true
        phraseStatus = defaults.string(forKey: CustomPhraseShortcut.statusKey) ?? "等待 dock-switch 注册快捷键"
    }

    func savePhraseSettings() {
        let defaults = UserDefaults(suiteName: CustomPhraseShortcut.suiteName)!
        guard phraseShortcut.isValid, let data = try? JSONEncoder().encode(phraseShortcut) else { return }
        defaults.set(data, forKey: CustomPhraseShortcut.preferenceKey)
        defaults.set(phraseEnabled, forKey: CustomPhraseShortcut.enabledKey)
        defaults.synchronize()
        phraseStatus = "正在应用…"
        DistributedNotificationCenter.default().postNotificationName(CustomPhraseShortcut.changed,
            object: nil, userInfo: nil, deliverImmediately: true)
    }
    // Shared with the runtime; kept outside the signed application bundle.
    @Published var codexWorkspaceAutoExpand = UserDefaults(suiteName: "me.longbiaochen.dock-switch")!
        .object(forKey: "codexWorkspaceAutoExpand") as? Bool ?? true {
        didSet {
            let defaults = UserDefaults(suiteName: "me.longbiaochen.dock-switch")!
            defaults.set(codexWorkspaceAutoExpand, forKey: "codexWorkspaceAutoExpand")
            defaults.synchronize()
        }
    }
    @Published var rows: [SettingsRow] = []
    @Published var query = ""
    @Published var statusText = "读取中..."
    @Published var errorText = ""
    @Published var isDirty = false

    private let configPath: String
    private let dockCachePath: String

    init(arguments: [String]) {
        self.configPath = Self.value(after: "--config", in: arguments)
            ?? "/Applications/dock-switch.app/Contents/Resources/app/src/config.json"
        self.dockCachePath = Self.value(after: "--dock-cache", in: arguments)
            ?? "\(NSHomeDirectory())/Library/Application Support/dock-switch/dock-items-cache.json"
        load()
        loadPhraseSettings()
        phraseObserver = DistributedNotificationCenter.default().addObserver(forName: CustomPhraseShortcut.statusChanged,
            object: nil, queue: .main) { [weak self] _ in
                // Preserve the draft controls; only update runtime acknowledgement.
                let defaults = UserDefaults(suiteName: CustomPhraseShortcut.suiteName)!
                defaults.synchronize()
                let status = defaults.string(forKey: CustomPhraseShortcut.statusKey) ?? "等待运行状态"
                Task { @MainActor [weak self] in self?.phraseStatus = status }
            }
    }

    var filteredRows: [SettingsRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rows }
        return rows.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var canSave: Bool {
        validationError() == nil
    }

    func load() {
        do {
            let config = try Self.readJSONObject(path: configPath) as? [String: Any] ?? [:]
            let dockItems = try Self.readJSONObject(path: dockCachePath) as? [[String: Any]] ?? []
            rows = buildRows(dockItems: dockItems, config: config)
            isDirty = false
            errorText = ""
            statusText = "\(rows.count) 个 Dock App"
        } catch {
            errorText = "读取失败：\(error.localizedDescription)"
            statusText = errorText
        }
    }

    func update(rowID: SettingsRow.ID, key: String? = nil, screen: String? = nil, position: String? = nil) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }), !rows[index].readonly else { return }
        if let key {
            rows[index].key = displayLauncherKey(key)
        }
        if let screen {
            rows[index].screen = screen
            rows[index].placement = ""
            if screen.isEmpty {
                rows[index].position = ""
            } else if rows[index].position.isEmpty {
                rows[index].position = "fill"
            }
        }
        if let position {
            rows[index].position = position
            rows[index].placement = ""
            if !position.isEmpty && rows[index].screen.isEmpty {
                rows[index].screen = "1"
            }
        }
        if rows[index].fallback {
            let key = normalizeLauncherKey(rows[index].key)
            let automaticKey = normalizeLauncherKey(rows[index].displayKey)
            let hasUserAssignment = (!key.isEmpty && key != automaticKey)
                || !rows[index].screen.isEmpty
                || !rows[index].position.isEmpty
            rows[index].status = hasUserAssignment ? .userAssigned : .fallback
        }
        isDirty = true
        refreshValidationText()
    }

    func save() {
        if let validation = validationError() {
            errorText = validation
            statusText = validation
            return
        }

        do {
            var config = try Self.readJSONObject(path: configPath) as? [String: Any] ?? [:]
            let dockItems = try Self.readJSONObject(path: dockCachePath) as? [[String: Any]] ?? []
            try applyRows(to: &config, dockItems: dockItems)
            try Self.writeJSONObject(config, path: configPath)
            load()
            statusText = "已保存，快捷键已刷新"
        } catch {
            errorText = "保存失败：\(error.localizedDescription)"
            statusText = errorText
        }
    }

    private func refreshValidationText() {
        if let validation = validationError() {
            errorText = validation
            statusText = validation
        } else {
            errorText = ""
            statusText = isDirty ? "有未保存修改" : "\(rows.count) 个 Dock App"
        }
    }

    private func validationError() -> String? {
        var byKey: [String: [String]] = [:]
        for row in rows where !row.readonly {
            let key = normalizeLauncherKey(row.key)
            if key.isEmpty { continue }
            if isReservedSettingsKey(key, for: row.name) {
                return "\(key) 是系统保留键"
            }
            byKey[key, default: []].append(row.name)
        }
        if let duplicate = byKey.first(where: { $0.value.count > 1 }) {
            return "\(duplicate.key) 被 \(duplicate.value.joined(separator: "、")) 重复使用"
        }
        return nil
    }

    private func buildRows(dockItems: [[String: Any]], config: [String: Any]) -> [SettingsRow] {
        let configItems = config["dock_items"] as? [[String: Any]] ?? []
        let sortedDockItems = visibleDockItems(dockItems)
        var fallbackKey = 1
        var result: [SettingsRow] = []

        for dockItem in sortedDockItems {
            guard let name = dockItem["name"] as? String else { continue }
            let configItem = configItems.first { normalizeAppName($0["name"] as? String ?? "") == normalizeAppName(name) }
            let defaultItem = defaultSettingsItem(for: name)
            if let configItem,
               defaultItem != nil || !(configItem["key"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let configuredKey = configItem["key"] as? String ?? ""
                let placement = configItem["placement"] as? String ?? ""
                let parsedPlacement = parsePlacement(placement)
                let screen = normalizeScreenValue((configItem["screen"] as? String) ?? parsedPlacement.screen)
                result.append(SettingsRow(
                    id: name,
                    name: (configItem["name"] as? String) ?? name,
                    key: displayLauncherKey(configuredKey),
                    displayKey: displayLauncherKey(configuredKey),
                    screen: screen,
                    position: parsedPlacement.position,
                    placement: placement,
                    status: .configured,
                    readonly: false,
                    configured: true,
                    fallback: false
                ))
            } else if let defaultItem {
                result.append(defaultItem)
            } else {
                result.append(SettingsRow(
                    id: name,
                    name: name,
                    key: "\(fallbackKey)",
                    displayKey: "\(fallbackKey)",
                    screen: "",
                    position: "",
                    placement: "",
                    status: .fallback,
                    readonly: false,
                    configured: false,
                    fallback: true
                ))
                fallbackKey += 1
            }
        }
        return result
    }

    private func applyRows(to config: inout [String: Any], dockItems: [[String: Any]]) throws {
        let visibleNames = Set(visibleDockItems(dockItems).compactMap { $0["name"] as? String }.map(normalizeAppName))
        var updates: [String: SettingsRow] = [:]
        for row in rows where !row.readonly && visibleNames.contains(normalizeAppName(row.name)) {
            updates[normalizeAppName(row.name)] = row
        }

        var configItems = config["dock_items"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        for index in configItems.indices {
            let name = configItems[index]["name"] as? String ?? ""
            let normalized = normalizeAppName(name)
            guard let row = updates[normalized] else { continue }
            seen.insert(normalized)
            apply(row: row, to: &configItems[index])
        }

        for (normalized, row) in updates where !seen.contains(normalized) {
            let key = outputKey(for: row)
            let placement = placementFor(screen: row.screen, position: row.position)
            guard !key.isEmpty || !row.screen.isEmpty || !placement.isEmpty else { continue }
            var item: [String: Any] = ["name": row.name]
            if !key.isEmpty { item["key"] = key }
            if !row.screen.isEmpty { item["screen"] = row.screen }
            if !placement.isEmpty { item["placement"] = placement }
            configItems.append(item)
        }
        config["dock_items"] = configItems
    }

    private func apply(row: SettingsRow, to item: inout [String: Any]) {
        let key = outputKey(for: row)
        if key.isEmpty { item.removeValue(forKey: "key") } else { item["key"] = key }
        if row.screen.isEmpty { item.removeValue(forKey: "screen") } else { item["screen"] = row.screen }
        let placement = placementFor(screen: row.screen, position: row.position)
        if placement.isEmpty { item.removeValue(forKey: "placement") } else { item["placement"] = placement }
    }

    private func outputKey(for row: SettingsRow) -> String {
        let key = normalizeLauncherKey(row.key)
        if !row.configured && key == row.displayKey {
            return ""
        }
        return key
    }

    private func isReservedSettingsKey(_ key: String, for appName: String) -> Bool {
        if key == "COMMAND_LEFT", normalizeAppName(appName) == "system settings" {
            return false
        }
        return ["COMMAND_LEFT", "COMMAND_RIGHT"].contains(key)
    }

    private func visibleDockItems(_ dockItems: [[String: Any]]) -> [[String: Any]] {
        var seenNames = Set<String>()
        return dockItems
            .filter {
                guard let name = $0["name"] as? String,
                      name != "Trash",
                      name != "Downloads",
                      let pos = $0["pos"] as? [String: Any],
                      pos["x"] is NSNumber else {
                    return false
                }
                return true
            }
            .sorted {
                let lhs = (($0["pos"] as? [String: Any])?["x"] as? NSNumber)?.doubleValue ?? 0
                let rhs = (($1["pos"] as? [String: Any])?["x"] as? NSNumber)?.doubleValue ?? 0
                return lhs < rhs
            }
            .filter {
                guard let name = $0["name"] as? String else { return false }
                return seenNames.insert(normalizeAppName(name)).inserted
            }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func readJSONObject(path: String) throws -> Any {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func writeJSONObject(_ object: Any, path: String) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path), options: [.atomic])
    }
}
