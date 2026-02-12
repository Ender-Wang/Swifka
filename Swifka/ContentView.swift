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
                .environment(\.defaultMinListRowHeight, appState.rowDensity.rowHeight)
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

                        Picker(selection: Binding(
                            get: { appState.defaultRefreshMode },
                            set: { newMode in
                                appState.refreshManager.updateMode(newMode)
                                appState.defaultRefreshMode = newMode
                            },
                        )) {
                            ForEach(RefreshMode.presets) { mode in
                                Text(refreshModeLabel(mode, l10n: l10n))
                                    .tag(mode)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.inline)
                    } label: {
                        switch appState.defaultRefreshMode {
                        case .manual:
                            Label(l10n["common.refresh"], systemImage: "hand.raised")
                        case let .interval(seconds):
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.trianglehead.2.clockwise")
                                Text("\(seconds)s")
                                    .font(.caption2)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                // Connection controls
                if appState.connectionStatus.isConnected {
                    Button {
                        Task { await appState.disconnect() }
                    } label: {
                        Label(l10n["connection.disconnect"], systemImage: "power")
                            .foregroundStyle(.green)
                    }
                } else if appState.configStore.selectedCluster != nil {
                    Button {
                        Task { await appState.connect() }
                    } label: {
                        Label(l10n["connection.connect"], systemImage: "power")
                            .foregroundStyle(.red)
                    }
                } else {
                    Label(l10n["connection.connect"], systemImage: "power")
                        .foregroundStyle(.gray)
                }
            }
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

            CompactSidebarFooterView()
        }
        .padding(.top, 8)
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
        .frame(minHeight: 0)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooterView()
        }
    }
}

// MARK: - Sidebar Footer

private struct SidebarFooterView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let l10n = appState.l10n

        VStack(alignment: .leading, spacing: 4) {
            Divider()

            // Connection status row
            HStack(spacing: 6) {
                ConnectionStatusBadge(status: appState.connectionStatus)
                Text(connectionLabel(l10n: l10n))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ProgressView()
                    .controlSize(.mini)
                    .opacity(appState.isLoading ? 1 : 0)
            }

            // Metric chips — always visible, counts animate on change
            MetricChipRow(icon: "server.rack", count: brokerCount,
                          label: l10n[brokerCount == 1 ? "status.broker" : "status.brokers"],
                          color: .blue, connected: connected)
            MetricChipRow(icon: "list.bullet.rectangle", count: topicCount,
                          label: l10n[topicCount == 1 ? "status.topic" : "status.topics"],
                          color: .green, connected: connected)
            MetricChipRow(icon: "square.split.2x2", count: partitionCount,
                          label: l10n[partitionCount == 1 ? "status.partition" : "status.partitions"],
                          color: .orange, connected: connected)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .padding(.top, 2)
    }

    private var connected: Bool {
        appState.connectionStatus.isConnected
    }

    private var brokerCount: Int {
        appState.brokers.count
    }

    private var topicCount: Int {
        appState.topics.count(where: { !$0.isInternal })
    }

    private var partitionCount: Int {
        appState.totalPartitions
    }

    private func connectionLabel(l10n: L10n) -> String {
        switch appState.connectionStatus {
        case .connected:
            appState.configStore.selectedCluster?.name ?? l10n["connection.status.connected"]
        case .connecting:
            l10n["status.connecting"]
        case .disconnected:
            l10n["status.disconnected"]
        case .error:
            l10n["connection.status.error"]
        }
    }
}

private struct MetricChipRow: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color
    var connected: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .frame(width: 14, alignment: .center)
            Text(connected ? "\(count)" : "--")
                .font(.caption.monospacedDigit().bold())
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .opacity(connected ? 1 : 0.35)
        .animation(.default, value: count)
        .animation(.default, value: connected)
    }
}

// MARK: - Compact Sidebar Footer

private struct CompactSidebarFooterView: View {
    @Environment(AppState.self) private var appState

    private var connected: Bool {
        appState.connectionStatus.isConnected
    }

    var body: some View {
        VStack(spacing: 6) {
            Divider()
                .padding(.horizontal, 8)

            ConnectionStatusBadge(status: appState.connectionStatus, size: 6)
                .overlay {
                    if appState.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.5)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: appState.isLoading)
                .padding(.bottom, 2)

            CompactMetricIcon(icon: "server.rack", count: appState.brokers.count, color: .blue, connected: connected)
            CompactMetricIcon(icon: "list.bullet.rectangle", count: appState.topics.count(where: { !$0.isInternal }), color: .green, connected: connected)
            CompactMetricIcon(icon: "square.split.2x2", count: appState.totalPartitions, color: .orange, connected: connected)
        }
        .padding(.bottom, 4)
    }
}

private struct CompactMetricIcon: View {
    let icon: String
    let count: Int
    let color: Color
    var connected: Bool = true

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(connected ? "\(count)" : "-")
                .font(.system(size: 9).monospacedDigit().bold())
                .contentTransition(.numericText())
        }
        .frame(width: 32, height: 24)
        .help("\(count)")
        .opacity(connected ? 1 : 0.35)
        .animation(.default, value: count)
        .animation(.default, value: connected)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
