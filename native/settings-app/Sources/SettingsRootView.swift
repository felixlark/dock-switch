import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var store: SettingsStore
    @State private var selectedPage: String? = "launcher"

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                Label("启动默认值", systemImage: "command")
                    .tag("launcher")
                Label("自定义短语", systemImage: "text.badge.plus")
                    .tag("phrases")
                Label("显示器", systemImage: "display")
                    .foregroundStyle(.secondary)
                Label("高级", systemImage: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 240)
        } detail: {
            if selectedPage == "phrases" {
                phrasePage
            } else {
            VStack(spacing: 0) {
                header
                Divider()
                rows
                Divider()
                footer
            }
            }
        }
    }

    private var phrasePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("自定义短语").font(.largeTitle.weight(.semibold))
            Text("选中中文词组，按快捷键自动计算五笔码并加入文本替换。")
                .foregroundStyle(.secondary)
            Divider()
            Toggle("启用选词加入短语", isOn: $store.phraseEnabled)
            HStack {
                Text("全局快捷键")
                Spacer()
                PhraseShortcutRecorder(shortcut: store.phraseShortcut) { store.phraseShortcut = $0 }
                    .frame(width: 180, height: 32)
                Button("恢复默认") { store.phraseShortcut = .default }
            }
            Text("点击快捷键后按下新的组合键，再点“应用”。默认 ⌘⇧`（数字 1 左侧的反引号键）。")
                .font(.callout).foregroundStyle(.secondary)
            Text(store.phraseStatus).accessibilityIdentifier("customPhraseStatus")
            Divider()
            Label(store.phraseComponentInstalled ? "本机五笔短语组件已就绪" : "尚未安装本机五笔短语组件",
                systemImage: store.phraseComponentInstalled ? "checkmark.circle" : "exclamationmark.triangle")
            Text("写入前自动备份，保留已有短语；同码词需确认后追加。成功后显示浮层提示。若新增短语暂未出词，请重开使用它的应用。")
                .foregroundStyle(.secondary)
            if !store.phraseComponentInstalled {
                Text("此功能需要本机已配置的五笔编码与短语备份组件。安装位置：~/Library/Application Support/wubi-phrase。")
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            HStack {
                Button("刷新状态") { store.loadPhraseSettings() }
                Menu("预览提示") {
                    Button("入库成功") { previewTip("added") }
                    Button("已有短语") { previewTip("known") }
                    Button("错误提示") { previewTip("error") }
                    Divider()
                    Button("浅色外观") { previewTip("light") }
                    Button("深色外观") { previewTip("dark") }
                }
                .fixedSize()
                Spacer()
                Button("应用") { store.savePhraseSettings() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
    }

    private func previewTip(_ variant: String) {
        DistributedNotificationCenter.default().postNotificationName(CustomPhraseShortcut.previewRequested,
            object: variant, userInfo: nil, deliverImmediately: true)
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
            Toggle("Codex 切换聊天时展开已关闭的工作区", isOn: $store.codexWorkspaceAutoExpand)
            Text("立即生效。使用现有辅助功能授权；已展开时不新增标签，⌘T 保持 New tab。")
                .font(.caption)
                .foregroundStyle(.secondary)
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
