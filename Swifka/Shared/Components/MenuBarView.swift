import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let l10n = appState.l10n

        VStack(alignment: .leading, spacing: 0) {
            // Open main window
            MenuBarItem(icon: "macwindow", label: l10n["menubar.show"], shortcut: "⇧⌘ N", keyEquivalent: "n", keyModifiers: [.command, .shift]) {
                showSwifka()
            }

            MenuBarSeparator()

            // Cluster section
            MenuBarSectionHeader(l10n["sidebar.clusters"])

            if appState.configStore.clusters.isEmpty {
                MenuBarItem(
                    icon: "slash.circle",
                    label: l10n["connection.status.disconnected"],
                    enabled: false,
                )
            } else {
                ForEach(appState.configStore.clusters) { cluster in
                    let isSelected = appState.configStore.selectedClusterId == cluster.id
                    let isConnected = isSelected && appState.connectionStatus.isConnected
                    let isConnecting = isSelected && appState.connectionStatus == .connecting

                    MenuBarItem(
                        icon: isSelected ? "checkmark.circle.fill" : "circle",
                        label: cluster.name,
                        iconColor: isConnected ? .green
                            : isConnecting ? .orange
                            : isSelected ? .secondary : .secondary,
                        enabled: !isConnecting && !isConnected,
                    ) {
                        dismiss()
                        Task {
                            if appState.connectionStatus.isConnected {
                                await appState.disconnect()
                            }
                            appState.configStore.selectedClusterId = cluster.id
                            await appState.connect()
                        }
                    }
                }
            }

            MenuBarSeparator()

            MenuBarItem(icon: "gauge.with.dots.needle.33percent", label: l10n["sidebar.dashboard"], shortcut: "⇧⌘ D", keyEquivalent: "d", keyModifiers: [.command, .shift]) {
                navigateTo(.dashboard)
            }
            MenuBarItem(icon: "chart.xyaxis.line", label: l10n["sidebar.trends"], shortcut: "⇧⌘ E", keyEquivalent: "e", keyModifiers: [.command, .shift]) {
                navigateTo(.trends)
            }
            MenuBarItem(icon: "chart.line.downtrend.xyaxis", label: l10n["sidebar.lag"], shortcut: "⇧⌘ L", keyEquivalent: "l", keyModifiers: [.command, .shift]) {
                navigateTo(.lag)
            }
            MenuBarItem(icon: "list.bullet.rectangle", label: l10n["sidebar.topics"], shortcut: "⇧⌘ T", keyEquivalent: "t", keyModifiers: [.command, .shift]) {
                navigateTo(.topics)
            }
            MenuBarItem(icon: "envelope", label: l10n["sidebar.messages"], shortcut: "⇧⌘ M", keyEquivalent: "m", keyModifiers: [.command, .shift]) {
                navigateTo(.messages)
            }
            MenuBarItem(icon: "person.3", label: l10n["sidebar.groups"], shortcut: "⇧⌘ C", keyEquivalent: "c", keyModifiers: [.command, .shift]) {
                navigateTo(.consumerGroups)
            }
            MenuBarItem(icon: "server.rack", label: l10n["sidebar.brokers"], shortcut: "⇧⌘ B", keyEquivalent: "b", keyModifiers: [.command, .shift]) {
                navigateTo(.brokers)
            }

            MenuBarSeparator()

            MenuBarItem(icon: "gear", label: l10n["sidebar.settings"], shortcut: "⌘ ,", keyEquivalent: ",", keyModifiers: .command) {
                navigateTo(.settings)
            }
            MenuBarItem(icon: "xmark", label: l10n["menubar.quit"], shortcut: "⌘ Q", keyEquivalent: "q", keyModifiers: .command) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 5)
        .frame(width: 260)
    }

    private func activateMainWindow() {
        if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
            NSApplication.shared.activate()
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    private func showSwifka() {
        dismiss()
        activateMainWindow()
    }

    private func navigateTo(_ item: SidebarItem) {
        dismiss()
        appState.selectedSidebarItem = item
        activateMainWindow()
    }
}

// MARK: - Components

private struct MenuBarItem: View {
    let icon: String
    let label: String
    var shortcut: String?
    var keyEquivalent: KeyEquivalent?
    var keyModifiers: EventModifiers = []
    var iconColor: Color = .secondary
    var enabled: Bool = true
    var action: (() -> Void)?

    @State private var isHovered = false
    @State private var isActivated = false

    private var highlighted: Bool {
        isHovered || isActivated
    }

    var body: some View {
        buttonView
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.85)
            .onHover { isHovered = enabled ? $0 : false }
            .onAppear { isActivated = false }
            .padding(.horizontal, 5)
    }

    @ViewBuilder
    private var buttonView: some View {
        let button = Button {
            guard !isActivated else { return }
            isActivated = true
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                action?()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(highlighted ? .white : iconColor)
                    .frame(width: 20, alignment: .center)
                Text(label)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(highlighted ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 26)
            .contentShape(Rectangle())
            .background(highlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(highlighted ? .white : .primary)
        }
        .buttonStyle(.plain)

        if let keyEquivalent {
            button.keyboardShortcut(keyEquivalent, modifiers: keyModifiers)
        } else {
            button
        }
    }
}

private struct MenuBarSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 17)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

private struct MenuBarSeparator: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }
}
