import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    private var sidebarHidden: Bool {
        columnVisibility == .detailOnly
    }

    var body: some View {
        @Bindable var state = appState
        let l10n = appState.l10n

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: Constants.sidebarMinWidth, ideal: 220)
        } detail: {
            HStack(spacing: 0) {
                if sidebarHidden {
                    CompactSidebarView(selection: $state.selectedSidebarItem)
                }

                Group {
                    switch appState.selectedSidebarItem {
                    case .dashboard:
                        DashboardView()
                    case .topics:
                        TopicListView()
                    case .messages:
                        MessageBrowserView()
                    case .consumerGroups:
                        ConsumerGroupsView()
                    case .brokers:
                        BrokersView()
                    case .settings:
                        SettingsView()
                    case .none:
                        DashboardView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Refresh controls
                if appState.connectionStatus.isConnected {
                    Menu {
                        Button(l10n["common.refresh"]) {
                            Task { await appState.refreshAll() }
                        }
                        .keyboardShortcut("r")

                        Divider()

                        ForEach(RefreshMode.presets) { mode in
                            Button {
                                appState.refreshManager.updateMode(mode)
                                appState.defaultRefreshMode = mode
                            } label: {
                                HStack {
                                    Text(refreshModeLabel(mode, l10n: l10n))
                                    if mode == appState.defaultRefreshMode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(l10n["common.refresh"], systemImage: "arrow.clockwise")
                    }
                }

                // Connection controls
                if appState.connectionStatus.isConnected {
                    Button {
                        Task { await appState.disconnect() }
                    } label: {
                        Label(l10n["connection.disconnect"], systemImage: "bolt.slash")
                    }
                } else if appState.configStore.selectedCluster != nil {
                    Button {
                        Task { await appState.connect() }
                    } label: {
                        Label(l10n["connection.connect"], systemImage: "bolt")
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            StatusBarView()
        }
        .task {
            // Auto-connect on launch if a cluster is selected
            if appState.configStore.selectedCluster != nil {
                await appState.connect()
            }
        }
    }

    private func refreshModeLabel(_ mode: RefreshMode, l10n: L10n) -> String {
        switch mode {
        case .manual: l10n["settings.refresh.manual"]
        case let .interval(seconds): l10n.t("settings.refresh.interval.seconds", "\(seconds)")
        }
    }
}

// MARK: - Compact Sidebar

private struct CompactSidebarView: View {
    @Binding var selection: SidebarItem?

    private struct IconGroup {
        let items: [(SidebarItem, String)]
    }

    private let groups: [IconGroup] = [
        IconGroup(items: [
            (.dashboard, "gauge.with.dots.needle.33percent"),
        ]),
        IconGroup(items: [
            (.topics, "list.bullet.rectangle"),
            (.messages, "envelope"),
        ]),
        IconGroup(items: [
            (.consumerGroups, "person.3"),
            (.brokers, "server.rack"),
        ]),
        IconGroup(items: [
            (.settings, "gear"),
        ]),
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Divider()
                        .padding(.horizontal, 8)
                }

                ForEach(group.items, id: \.0) { item, icon in
                    Button {
                        selection = item
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .frame(width: 32, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == item ? .accent : .secondary)
                    .background(
                        selection == item
                            ? AnyShapeStyle(.selection)
                            : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6),
                    )
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(width: 44)
        .overlay(alignment: .trailing) { Divider() }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        let l10n = appState.l10n

        List(selection: $state.selectedSidebarItem) {
            // Cluster picker at top
            Section {
                ClusterPickerView()
            }

            Section(l10n["sidebar.section.overview"]) {
                Label(l10n["sidebar.dashboard"], systemImage: "gauge.with.dots.needle.33percent")
                    .tag(SidebarItem.dashboard)
            }

            Section(l10n["sidebar.section.browse"]) {
                Label(l10n["sidebar.topics"], systemImage: "list.bullet.rectangle")
                    .tag(SidebarItem.topics)
                Label(l10n["sidebar.messages"], systemImage: "envelope")
                    .tag(SidebarItem.messages)
            }

            Section(l10n["sidebar.section.monitor"]) {
                Label(l10n["sidebar.groups"], systemImage: "person.3")
                    .tag(SidebarItem.consumerGroups)
                Label(l10n["sidebar.brokers"], systemImage: "server.rack")
                    .tag(SidebarItem.brokers)
            }

            Section(l10n["sidebar.section.system"]) {
                Label(l10n["sidebar.settings"], systemImage: "gear")
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            ConnectionStatusBadge(status: appState.connectionStatus)
            Text(appState.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if appState.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
