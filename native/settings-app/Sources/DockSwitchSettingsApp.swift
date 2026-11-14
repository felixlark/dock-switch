import SwiftUI

@main
struct DockSwitchSettingsApp: App {
    @StateObject private var store = SettingsStore(arguments: CommandLine.arguments)

    var body: some Scene {
        Window("Dock Switch Settings", id: "settings") {
            SettingsRootView()
                .environmentObject(store)
                .frame(minWidth: 840, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Reload") {
                    store.load()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
