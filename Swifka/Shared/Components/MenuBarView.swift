import SwiftUI

struct MenuBarView: View {
    let appState: AppState

    var body: some View {
        let l10n = appState.l10n

        // Connection status
        switch appState.connectionStatus {
        case .connected:
            if let cluster = appState.configStore.selectedCluster {
                Text("\(l10n["connection.status.connected"]) — \(cluster.name)")
            } else {
                Text(l10n["connection.status.connected"])
            }
        case .connecting:
            Text(l10n["connection.status.connecting"])
        case .disconnected:
            Text(l10n["connection.status.disconnected"])
        case .error:
            Text(l10n["connection.status.error"])
        }

        Divider()

        Button(l10n["sidebar.dashboard"]) { navigateTo(.dashboard) }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        Divider()
        Button(l10n["sidebar.topics"]) { navigateTo(.topics) }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        Button(l10n["sidebar.messages"]) { navigateTo(.messages) }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        Divider()
        Button(l10n["sidebar.groups"]) { navigateTo(.consumerGroups) }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        Button(l10n["sidebar.brokers"]) { navigateTo(.brokers) }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        Divider()
        Button(l10n["sidebar.settings"]) { navigateTo(.settings) }
            .keyboardShortcut(",")

        Divider()

        Button(l10n["menubar.quit"]) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func navigateTo(_ item: SidebarItem) {
        appState.selectedSidebarItem = item
        NSApplication.shared.activate()
        if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
