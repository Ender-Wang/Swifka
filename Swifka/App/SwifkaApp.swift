import SwiftUI

@main
struct SwifkaApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
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
                Button(appState.l10n["menubar.show"]) {
                    activateMainWindow()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button(appState.l10n["sidebar.toggle"]) {
                    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandMenu(appState.l10n["sidebar.section.overview"]) {
                Button(appState.l10n["sidebar.dashboard"]) {
                    navigateTo(.dashboard)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                Button(appState.l10n["sidebar.trends"]) {
                    navigateTo(.trends)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandMenu(appState.l10n["sidebar.section.browse"]) {
                Button(appState.l10n["sidebar.topics"]) {
                    navigateTo(.topics)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                Button(appState.l10n["sidebar.messages"]) {
                    navigateTo(.messages)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
            CommandMenu(appState.l10n["sidebar.section.monitor"]) {
                Button(appState.l10n["sidebar.groups"]) {
                    navigateTo(.consumerGroups)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                Button(appState.l10n["sidebar.brokers"]) {
                    navigateTo(.brokers)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            CommandMenu(appState.l10n["sidebar.section.system"]) {
                Button(appState.l10n["sidebar.clusters"]) {
                    navigateTo(.clusters)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button(appState.l10n["sidebar.settings"]) {
                    navigateTo(.settings)
                }
                .keyboardShortcut(",")
            }
        }

        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)
    }

    private func activateMainWindow() {
        if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
            NSApplication.shared.activate()
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    private func navigateTo(_ item: SidebarItem) {
        appState.selectedSidebarItem = item
        activateMainWindow()
    }
}
