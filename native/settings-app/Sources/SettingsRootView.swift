import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        NavigationSplitView {
            List(selection: .constant("launcher")) {
                Label("启动默认值", systemImage: "command")
                    .tag("launcher")
                Label("显示器", systemImage: "display")
                    .foregroundStyle(.secondary)
                Label("高级", systemImage: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 240)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                rows
                Divider()
                footer
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("启动默认值")
                        .font(.largeTitle.weight(.semibold))
                    Text("为 Dock App 设置快捷键、默认屏幕和打开位置。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("刷新") {
                    store.load()
                }
            }
            TextField("搜索 App", text: $store.query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            HeaderRow()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.filteredRows) { row in
                        SettingsRowView(row: row)
                            .environmentObject(store)
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator.opacity(0.45), lineWidth: 1)
        }
        .padding(28)
        .background(.background)
    }

    private var footer: some View {
        HStack {
            Text(store.statusText)
                .foregroundColor(store.errorText.isEmpty ? Color.secondary : Color.red)
            Spacer()
            Button("取消") {
                NSApp.keyWindow?.close()
            }
            Button("保存") {
                store.save()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!store.canSave)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

struct HeaderRow: View {
    var body: some View {
        HStack(spacing: 14) {
            Text("App")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("快捷键")
                .frame(width: 86, alignment: .leading)
            Text("默认屏幕")
                .frame(width: 130, alignment: .leading)
            Text("位置")
                .frame(width: 118, alignment: .leading)
            Text("状态")
                .frame(width: 98, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}

struct SettingsRowView: View {
    @EnvironmentObject private var store: SettingsStore
    let row: SettingsRow

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if row.fallback {
                    Text("不保存时继续使用自动数字键")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if row.readonly {
                    Text(row.displayKey)
                        .font(.headline.monospaced())
                        .frame(width: 52, height: 26)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    LauncherKeyRecorder(key: row.key) { key in
                        store.update(rowID: row.id, key: key)
                    }
                    .frame(width: 74, height: 24)
                }
            }
            .frame(width: 86)

            Group {
                if row.readonly {
                    Text("保留")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("", selection: Binding(
                        get: { row.screen },
                        set: { store.update(rowID: row.id, screen: $0) }
                    )) {
                        ForEach(screenOptions) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 118)
                }
            }
            .frame(width: 130)

            Group {
                if row.readonly {
                    Text("保留")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("", selection: Binding(
                        get: { row.position },
                        set: { store.update(rowID: row.id, position: $0) }
                    )) {
                        ForEach(positionOptions) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 106)
                }
            }
            .frame(width: 118)

            Text(row.status.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.12), in: Capsule())
                .frame(width: 98, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.background.opacity(0.001))
    }

    private var statusColor: Color {
        switch row.status {
        case .configured: return .blue
        case .userAssigned: return .orange
        case .fallback: return .green
        case .reserved: return .purple
        }
    }
}
