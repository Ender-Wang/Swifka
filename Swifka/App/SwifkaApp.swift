import SwiftUI

@main
struct SwifkaApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(
                    minWidth: Constants.minWindowWidth,
                    minHeight: Constants.minWindowHeight,
                )
                .onChange(of: appState.appearanceMode, initial: true) {
                    NSApp.appearance = appState.appearanceMode.nsAppearance
                }
        }
        .defaultSize(
            width: Constants.defaultWindowWidth,
            height: Constants.defaultWindowHeight,
        )
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(before: .sidebar) {
                Button(appState.l10n["sidebar.toggle"]) {
                    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandMenu(appState.l10n["sidebar.section.overview"]) {
                Button(appState.l10n["sidebar.dashboard"]) {
                    appState.selectedSidebarItem = .dashboard
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            CommandMenu(appState.l10n["sidebar.section.browse"]) {
                Button(appState.l10n["sidebar.topics"]) {
                    appState.selectedSidebarItem = .topics
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                Button(appState.l10n["sidebar.messages"]) {
                    appState.selectedSidebarItem = .messages
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
            CommandMenu(appState.l10n["sidebar.section.monitor"]) {
                Button(appState.l10n["sidebar.groups"]) {
                    appState.selectedSidebarItem = .consumerGroups
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                Button(appState.l10n["sidebar.brokers"]) {
                    appState.selectedSidebarItem = .brokers
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            CommandMenu(appState.l10n["sidebar.section.system"]) {
                Button(appState.l10n["sidebar.clusters"]) {
                    appState.selectedSidebarItem = .clusters
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button(appState.l10n["sidebar.settings"]) {
                    appState.selectedSidebarItem = .settings
                }
                .keyboardShortcut(",")
            }
        }

        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.menu)
    }
}
