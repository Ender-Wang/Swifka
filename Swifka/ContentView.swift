import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showingAddClusterSheet = false
    @State private var detailOpacity: Double = 1
    @State private var detailOffset: CGFloat = 0
    @State private var showAlertHistory = false
    @State private var alertHistory: [AlertRecord] = []

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
                    case .trends:
                        TrendsView()
                    case .lag:
                        LagView()
                    case .topics:
                        TopicListView()
                    case .messages:
                        MessageBrowserView()
                    case .schemaRegistry:
                        SchemaRegistryView()
                    case .consumerGroups:
                        ConsumerGroupsView()
                    case .brokers:
                        BrokersView()
                    case .clusters:
                        ClustersView()
                    case .settings:
                        SettingsView()
                    case .none:
                        DashboardView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(detailOpacity)
                .offset(y: detailOffset)
                .onChange(of: appState.selectedSidebarItem) {
                    detailOpacity = 0
                    detailOffset = 6
                    withAnimation(.easeOut(duration: 0.2)) {
                        detailOpacity = 1
                        detailOffset = 0
                    }
                }
                .environment(\.defaultMinListRowHeight, appState.rowDensity.rowHeight)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Image(systemName: sidebarIcon(for: appState.selectedSidebarItem))
                    .foregroundStyle(.secondary)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                // Alert bell — Dashboard only (cluster health overview)
                if appState.selectedSidebarItem == .dashboard
                    || appState.selectedSidebarItem == .none
                {
                    let activeCount = alertHistory.count(where: { $0.resolvedAt == nil })
                    Button {
                        showAlertHistory.toggle()
                    } label: {
                        Label(l10n["toolbar.alerts"], systemImage: "bell")
                            .foregroundStyle(activeCount > 0 ? .orange : .secondary)
                            .symbolEffect(.bounce, value: activeCount)
                    }
                    .overlay(alignment: .topTrailing) {
                        if activeCount > 0 {
                            Text("\(activeCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .frame(minWidth: 15, minHeight: 15)
                                .background(.orange, in: Circle())
                                .offset(x: 6, y: -6)
                                .allowsHitTesting(false)
                        }
                    }
                    .help(l10n["toolbar.alerts"])
                    .popover(isPresented: $showAlertHistory) {
                        AlertHistoryPopover(appState: appState, history: alertHistory)
                    }
                }

                // Refresh controls — connected data pages
                if appState.connectionStatus.isConnected,
                   appState.selectedSidebarItem != .clusters,
                   appState.selectedSidebarItem != .settings,
                   appState.selectedSidebarItem != .schemaRegistry
                {
                    Menu {
                        Button(l10n["common.refresh"]) {
                            Task { await appState.refreshAll() }
                        }
                        .keyboardShortcut("r")
                        .disabled(appState.refreshManager.isAutoRefresh)

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
                    .help(l10n["settings.refresh.mode"])
                }

                // Add cluster — Clusters page only
                if appState.selectedSidebarItem == .clusters {
                    Button {
                        showingAddClusterSheet = true
                    } label: {
                        Label(l10n["cluster.add"], systemImage: "plus")
                    }
                    .help(l10n["cluster.add"])
                    .keyboardShortcut("n", modifiers: .command)
                }

                // Power button — all pages except Clusters
                if appState.selectedSidebarItem != .clusters {
                    let isConnected = appState.connectionStatus.isConnected
                    let hasCluster = appState.configStore.selectedCluster != nil
                    if isConnected || hasCluster {
                        Button {
                            Task {
                                if isConnected {
                                    await appState.disconnect()
                                } else {
                                    await appState.connect()
                                }
                            }
                        } label: {
                            Label(
                                isConnected ? l10n["connection.disconnect"] : l10n["connection.connect"],
                                systemImage: "power",
                            )
                            .foregroundStyle(isConnected ? .green : .red)
                        }
                        .help(isConnected ? l10n["connection.disconnect"] : l10n["connection.connect"])
                    }
                }
            }
        }
        .onChange(of: appState.activeAlerts.count) {
            Task { await loadAlertHistory() }
        }
        .onChange(of: showAlertHistory) {
            if showAlertHistory { Task { await loadAlertHistory() } }
        }
        .sheet(isPresented: $showingAddClusterSheet) {
            ClusterFormView(mode: .add) { cluster, password in
                appState.configStore.addCluster(cluster)
                if let password, cluster.authType == .sasl {
                    try? KeychainManager.save(password: password, for: cluster.id)
                }
            }
            .environment(appState)
        }
        .task {
            // Auto-connect on launch if a cluster is selected
            if appState.configStore.selectedCluster != nil {
                await appState.connect()
            }
        }
        .task(id: appState.connectionStatus.isConnected) {
            guard appState.connectionStatus.isConnected else { return }
            while !Task.isCancelled {
                let ms = await appState.ping()
                withAnimation { appState.pingMs = ms }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshModeLabel(_ mode: RefreshMode, l10n: L10n) -> String {
        switch mode {
        case .manual: l10n["settings.refresh.manual"]
        case let .interval(seconds): l10n.t("settings.refresh.interval.seconds", "\(seconds)")
        }
    }

    private func sidebarIcon(for item: SidebarItem?) -> String {
        switch item {
        case .dashboard, .none: "gauge.with.dots.needle.33percent"
        case .trends: "chart.xyaxis.line"
        case .lag: "chart.line.downtrend.xyaxis"
        case .topics: "list.bullet.rectangle"
        case .messages: "envelope"
        case .schemaRegistry: "doc.text.magnifyingglass"
        case .consumerGroups: "person.2"
        case .brokers: "server.rack"
        case .clusters: "square.stack.3d.up"
        case .settings: "gear"
        }
    }

    private func loadAlertHistory() async {
        guard let db = appState.metricDatabase,
              let clusterId = appState.configStore.selectedCluster?.id
        else {
            alertHistory = []
            return
        }
        alertHistory = await (try? db.loadRecentAlerts(clusterId: clusterId, limit: 50)) ?? []
    }
}

// MARK: - Compact Sidebar

private struct CompactSidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(AppState.self) private var appState
    @State private var hoveredItem: SidebarItem?

    private struct IconGroup {
        let items: [(SidebarItem, String)]
    }

    private let groups: [IconGroup] = [
        IconGroup(items: [
            (.dashboard, "gauge.with.dots.needle.33percent"),
            (.trends, "chart.xyaxis.line"),
            (.lag, "chart.line.downtrend.xyaxis"),
        ]),
        IconGroup(items: [
            (.topics, "list.bullet.rectangle"),
            (.messages, "envelope"),
            (.schemaRegistry, "doc.text.magnifyingglass"),
        ]),
        IconGroup(items: [
            (.consumerGroups, "person.2"),
            (.brokers, "server.rack"),
        ]),
        IconGroup(items: [
            (.clusters, "square.stack.3d.up"),
            (.settings, "gear"),
        ]),
    ]

    var body: some View {
        let l10n = appState.l10n

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
                            : hoveredItem == item
                            ? AnyShapeStyle(.quaternary)
                            : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6),
                    )
                    .onHover { isHovered in
                        hoveredItem = isHovered ? item : nil
                    }
                    .help(sidebarLabel(for: item, l10n: l10n))
                }
            }

            Spacer()

            CompactSidebarFooterView()
        }
        .padding(.top, 8)
        .padding(.horizontal, 4)
        .frame(width: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .trailing) { Divider() }
    }

    private func sidebarLabel(for item: SidebarItem, l10n: L10n) -> String {
        switch item {
        case .dashboard: l10n["sidebar.dashboard"]
        case .trends: l10n["sidebar.trends"]
        case .lag: l10n["sidebar.lag"]
        case .topics: l10n["sidebar.topics"]
        case .messages: l10n["sidebar.messages"]
        case .schemaRegistry: l10n["sidebar.schemas"]
        case .consumerGroups: l10n["sidebar.groups"]
        case .brokers: l10n["sidebar.brokers"]
        case .clusters: l10n["sidebar.clusters"]
        case .settings: l10n["sidebar.settings"]
        }
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
                Label(l10n["sidebar.trends"], systemImage: "chart.xyaxis.line")
                    .tag(SidebarItem.trends)
                Label(l10n["sidebar.lag"], systemImage: "chart.line.downtrend.xyaxis")
                    .tag(SidebarItem.lag)
            }

            Section(l10n["sidebar.section.browse"]) {
                Label(l10n["sidebar.topics"], systemImage: "list.bullet.rectangle")
                    .tag(SidebarItem.topics)
                Label(l10n["sidebar.messages"], systemImage: "envelope")
                    .tag(SidebarItem.messages)
                Label(l10n["sidebar.schemas"], systemImage: "doc.text.magnifyingglass")
                    .tag(SidebarItem.schemaRegistry)
            }

            Section(l10n["sidebar.section.monitor"]) {
                Label(l10n["sidebar.groups"], systemImage: "person.2")
                    .tag(SidebarItem.consumerGroups)
                Label(l10n["sidebar.brokers"], systemImage: "server.rack")
                    .tag(SidebarItem.brokers)
            }

            Section(l10n["sidebar.section.system"]) {
                Label(l10n["sidebar.clusters"], systemImage: "square.stack.3d.up")
                    .tag(SidebarItem.clusters)
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

                if connected, let ping = appState.pingMs {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(ping)ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView()
                    .controlSize(.mini)
                    .opacity(appState.isLoading ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: appState.isLoading)
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
        .padding(.bottom, 12)
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
            l10n["connection.status.connected"]
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
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.5)
                        .opacity(appState.isLoading ? 1 : 0)
                        .animation(.easeInOut(duration: 0.25), value: appState.isLoading)
                }

            if connected, let ping = appState.pingMs {
                Text("\(ping)ms")
                    .font(.system(size: 9).monospacedDigit().bold())
                    .foregroundStyle(.green)
            }

            CompactMetricIcon(icon: "server.rack", count: appState.brokers.count, color: .blue, connected: connected)
            CompactMetricIcon(icon: "list.bullet.rectangle", count: appState.topics.count(where: { !$0.isInternal }), color: .green, connected: connected)
            CompactMetricIcon(icon: "square.split.2x2", count: appState.totalPartitions, color: .orange, connected: connected)
        }
        .padding(.bottom, 8)
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

// MARK: - Alert History Popover

private enum AlertTab: String, CaseIterable {
    case current
    case history
}

private struct AlertHistoryPopover: View {
    let appState: AppState
    let history: [AlertRecord]
    @State private var selectedRecord: AlertRecord?
    @State private var selectedTab: AlertTab = .current

    private let contentHeight: CGFloat = 320

    private func isActive(_ record: AlertRecord) -> Bool {
        appState.activeAlerts.contains(where: { $0.type == record.type })
    }

    private var currentAlerts: [AlertRecord] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return history.filter { $0.timestamp >= startOfDay || $0.resolvedAt == nil }
    }

    private var pastAlerts: [AlertRecord] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return history.filter { $0.timestamp < startOfDay && $0.resolvedAt != nil }
    }

    private var displayedAlerts: [AlertRecord] {
        selectedTab == .current ? currentAlerts : pastAlerts
    }

    var body: some View {
        let l10n = appState.l10n

        // Fixed-width popover: detail (left 220) + stream (right 380) = 600px always
        HStack(spacing: 0) {
            // Detail area — always 220px, content fades in/out
            ZStack {
                if let record = selectedRecord {
                    ScrollView {
                        alertDetailPanel(record, l10n: l10n)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "bell")
                            .font(.system(size: 24))
                            .foregroundStyle(.quaternary)
                        Text(l10n["alerts.select.detail"])
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: 220)
            .frame(maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.15), value: selectedRecord?.id)

            Divider()

            // Stream panel — always 380px, never moves
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Picker("", selection: $selectedTab) {
                        Text(l10n["alerts.tab.current"]).tag(AlertTab.current)
                        Text(l10n["alerts.tab.history"]).tag(AlertTab.history)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider()

                if displayedAlerts.isEmpty {
                    Text(selectedTab == .current
                        ? l10n["alerts.current.empty"]
                        : l10n["alerts.history.empty"])
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(displayedAlerts) { record in
                                alertRow(record, l10n: l10n)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if selectedRecord?.id == record.id {
                                            selectedRecord = nil
                                        } else {
                                            selectedRecord = record
                                        }
                                    }
                                    .background(selectedRecord?.id == record.id
                                        ? Color.accentColor.opacity(0.1)
                                        : Color.clear)

                                if record.id != displayedAlerts.last?.id {
                                    Divider()
                                        .padding(.leading, 44)
                                }
                            }
                        }
                    }
                    .frame(height: contentHeight)
                }
            }
            .frame(width: 380, alignment: .top)
        }
        .onChange(of: selectedTab) {
            selectedRecord = nil
        }
        .onChange(of: history) {
            if let sel = selectedRecord, !history.contains(where: { $0.id == sel.id }) {
                selectedRecord = nil
            }
        }
    }

    // MARK: - Row

    private func alertRow(_ record: AlertRecord, l10n: L10n) -> some View {
        HStack(spacing: 10) {
            Image(systemName: record.severity == .critical
                ? "exclamationmark.octagon.fill"
                : "exclamationmark.triangle.fill")
                .foregroundStyle(record.severity == .critical ? .red : .orange)
                .font(.system(size: 13))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(record.title)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if record.resolvedAt == nil, isActive(record) {
                        Text(l10n["alerts.badge.active"])
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 3))
                    } else if record.resolvedAt != nil {
                        Text(l10n["alerts.badge.resolved"])
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.green, in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(record.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(record.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Detail Panel (left side, vertical)

    private func alertDetailPanel(_ record: AlertRecord, l10n: L10n) -> some View {
        let color: Color = record.severity == .critical ? .red : .orange
        let active = record.resolvedAt == nil && isActive(record)

        return VStack(alignment: .leading, spacing: 10) {
            // Severity + Status
            HStack(spacing: 8) {
                Image(systemName: record.severity == .critical
                    ? "exclamationmark.octagon.fill"
                    : "exclamationmark.triangle.fill")
                    .foregroundStyle(color)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.severity == .critical
                        ? l10n["alerts.severity.critical"]
                        : l10n["alerts.severity.warning"])
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(color)
                    Text(active ? l10n["alerts.status.active"] : l10n["alerts.status.resolved"])
                        .font(.caption2)
                        .foregroundStyle(active ? .orange : .green)
                }
            }

            Text(record.title)
                .font(.headline)

            Text(record.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Triggered
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n["alerts.detail.triggered"])
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(record.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                    .font(.caption.monospacedDigit())
            }

            // Resolved
            if let resolvedAt = record.resolvedAt {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n["alerts.detail.resolved"])
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(resolvedAt, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.green)
                }

                let duration = resolvedAt.timeIntervalSince(record.timestamp)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n["alerts.detail.duration"])
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(formatDuration(duration))
                        .font(.caption.monospacedDigit())
                }
            }

            // Type
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n["alerts.detail.type"])
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(record.type.rawValue)
                    .font(.caption)
                    .monospaced()
            }
        }
        .padding(12)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            let m = Int(seconds) / 60
            let s = Int(seconds) % 60
            return "\(m)m \(s)s"
        } else {
            let h = Int(seconds) / 3600
            let m = (Int(seconds) % 3600) / 60
            return "\(h)h \(m)m"
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
