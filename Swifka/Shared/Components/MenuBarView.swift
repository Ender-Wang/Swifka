import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let l10n = appState.l10n

        VStack(alignment: .leading, spacing: 0) {
            // Open main window
            MenuBarItem(icon: "macwindow", label: l10n["menubar.show"], appIcon: true, shortcut: "⇧⌘ N", keyEquivalent: "n", keyModifiers: [.command, .shift]) {
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
                let duplicateNames = Set(
                    Dictionary(grouping: appState.configStore.clusters, by: \.name)
                        .filter { $0.value.count > 1 }.keys,
                )

                ForEach(appState.configStore.clusters) { cluster in
                    let isSelected = appState.configStore.selectedClusterId == cluster.id
                    let isConnected = isSelected && appState.connectionStatus.isConnected
                    let isConnecting = isSelected && appState.connectionStatus == .connecting
                    let isDuplicate = duplicateNames.contains(cluster.name)

                    MenuBarItem(
                        icon: isConnected ? "power"
                            : isConnecting ? "arrow.triangle.2.circlepath"
                            : "circle",
                        label: cluster.name,
                        suffix: isDuplicate ? String(cluster.id.uuidString.prefix(8)) : nil,
                        hoverIcon: isConnected ? "power" : nil,
                        hoverIconColor: isConnected ? .red : nil,
                        iconColor: isConnected ? .green
                            : isConnecting ? .orange
                            : .secondary,
                        enabled: !isConnecting,
                    ) {
                        dismiss()
                        Task {
                            if isConnected {
                                await appState.disconnect()
                            } else {
                                if appState.connectionStatus.isConnected {
                                    await appState.disconnect()
                                }
                                appState.configStore.selectedClusterId = cluster.id
                                await appState.connect()
                            }
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
    var suffix: String?
    var appIcon: Bool = false
    var hoverIcon: String?
    var hoverIconColor: Color?
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
                let showHoverIcon = isHovered && hoverIcon != nil
                if appIcon {
                    Image("MenuBarIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .frame(width: 20, alignment: .center)
                } else {
                    let iconForeground: Color = if showHoverIcon {
                        hoverIconColor ?? (highlighted ? .white : iconColor)
                    } else {
                        highlighted ? .white : iconColor
                    }
                    Image(systemName: showHoverIcon ? hoverIcon! : icon)
                        .font(.system(size: 14))
                        .foregroundStyle(iconForeground)
                        .frame(width: 20, alignment: .center)
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.easeInOut(duration: 0.15), value: showHoverIcon)
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(label)
                        .lineLimit(1)
                    if let suffix {
                        Text(suffix)
                            .font(.system(size: 10))
                            .monospaced()
                            .foregroundStyle(highlighted ? Color.white.opacity(0.5) : Color.secondary.opacity(0.6))
                    }
                }
                Spacer(minLength: 12)
                if let shortcut {
                    shortcutView(shortcut)
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

    private func shortcutView(_ shortcut: String) -> some View {
        let symbolSize: CGFloat = 10
        let keySize: CGFloat = 11
        let cellWidth: CGFloat = 14

        return HStack(spacing: 0) {
            // Pad leading space so all shortcuts right-align at the same width
            // Longest shortcut has 2 modifiers + key = 3 cells
            let parts = shortcut.split(separator: " ")
            let modifiers = parts.count > 1 ? String(parts[0]) : ""
            let key = parts.count > 1 ? String(parts[1]) : String(parts[0])
            let hasShift = modifiers.contains("⇧")
            let hasCommand = modifiers.contains("⌘")

            // Shift slot (empty if no shift)
            Image(systemName: "shift")
                .font(.system(size: symbolSize, weight: .medium))
                .frame(width: cellWidth)
                .opacity(hasShift ? 1 : 0)

            // Command slot
            Image(systemName: "command")
                .font(.system(size: symbolSize, weight: .medium))
                .frame(width: cellWidth)
                .opacity(hasCommand ? 1 : 0)

            // Key letter
            Text(key)
                .font(.system(size: keySize, weight: .medium))
                .frame(width: cellWidth)
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
