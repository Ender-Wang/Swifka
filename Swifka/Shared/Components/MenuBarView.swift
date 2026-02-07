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
        Divider()
        Button(l10n["sidebar.topics"]) { navigateTo(.topics) }
        Button(l10n["sidebar.messages"]) { navigateTo(.messages) }
        Divider()
        Button(l10n["sidebar.groups"]) { navigateTo(.consumerGroups) }
        Button(l10n["sidebar.brokers"]) { navigateTo(.brokers) }
        Divider()
        Button(l10n["sidebar.settings"]) { navigateTo(.settings) }

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
