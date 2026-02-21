import SwiftUI

struct LagView: View {
    @Environment(AppState.self) private var appState
    @State private var toolbarContentWidth: CGFloat = 0
    @State private var toolbarOverflow = false

    /// Reverse lookup: "topic:partition" → owner info from all consumer group member assignments.
    private var partitionOwnerMap: [String: PartitionOwner] {
        var map: [String: PartitionOwner] = [:]
        for group in appState.consumerGroups {
            for member in group.members {
                for assignment in member.assignments {
                    for partition in assignment.partitions {
                        map["\(assignment.topic):\(partition)"] = PartitionOwner(
                            clientId: member.clientId,
                            memberId: member.memberId,
                        )
                    }
                }
            }
        }
        return map
    }

    var body: some View {
        let l10n = appState.l10n
        if !appState.connectionStatus.isConnected {
            ContentUnavailableView(
                l10n["lag.not.connected"],
                systemImage: "network.slash",
                description: Text(l10n["lag.not.connected.description"]),
            )
        } else {
            lagContent
                .navigationTitle(l10n["lag.title"])
                .onAppear {
                    // Manual mode: default to History and lock there
                    if !appState.refreshManager.isAutoRefresh, appState.lagMode == .live {
                        appState.lagMode = .history
                    }
                }
                .onChange(of: appState.lagMode) { _, newMode in
                    handleModeChange(newMode)
                }
        }
    }

    // MARK: - Content

    private var lagContent: some View {
        VStack(spacing: 0) {
            lagToolbar
            Divider()

            Group {
                switch appState.lagMode {
                case .live:
                    liveContent
                        .transition(.opacity)
                case .history:
                    historyContent
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: appState.lagMode)
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var lagToolbar: some View {
        @Bindable var state = appState
        let l10n = appState.l10n
        let isAutoRefresh = appState.refreshManager.isAutoRefresh

        HStack(spacing: 12) {
            // Scrollable left section: mode picker + date filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if isAutoRefresh {
                        Picker(l10n["trends.mode"], selection: $state.lagMode) {
                            Text(l10n["trends.mode.live"]).tag(TrendsMode.live)
                            Text(l10n["trends.mode.history"]).tag(TrendsMode.history)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }

                    if case .history = appState.lagMode {
                        lagHistoryDateFilter
                    }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { contentWidth in
                    toolbarContentWidth = contentWidth
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { viewportWidth in
                toolbarOverflow = toolbarContentWidth > viewportWidth
            }
            .overlay(alignment: .trailing) {
                LinearGradient(
                    colors: [.clear, Color(nsColor: .windowBackgroundColor)],
                    startPoint: .leading,
                    endPoint: .trailing,
                )
                .frame(width: 40)
                .allowsHitTesting(false)
                .opacity(toolbarOverflow ? 1 : 0)
            }

            // Pinned right: time window + aggregation pickers
            switch appState.lagMode {
            case .live:
                if isAutoRefresh {
                    Picker(l10n["trends.time.window"], selection: Binding(
                        get: { appState.effectiveLagTimeWindow },
                        set: { appState.lagTimeWindow = $0 },
                    )) {
                        ForEach(ChartTimeWindow.allCases) { window in
                            Text(window.rawValue).tag(window)
                        }
                    }
                    .fixedSize()
                }
            case .history:
                lagHistoryVisibleWindowPicker
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Live Content

    @ViewBuilder
    private var liveContent: some View {
        @Bindable var state = appState
        let l10n = appState.l10n
        let store = appState.metricStore

        if !appState.refreshManager.isAutoRefresh {
            ContentUnavailableView(
                l10n["lag.manual.mode"],
                systemImage: "chart.line.downtrend.xyaxis",
                description: Text(l10n["lag.manual.mode.description"]),
            )
        } else if !store.hasEnoughData {
            ContentUnavailableView(
                l10n["lag.not.enough.data"],
                systemImage: "chart.line.downtrend.xyaxis",
                description: Text(l10n["lag.not.enough.data.description"]),
            )
        } else {
            let tickInterval: TimeInterval = if case let .interval(seconds) = appState.refreshManager.mode {
                TimeInterval(seconds)
            } else {
                1
            }
            TimelineView(.periodic(from: .now, by: tickInterval)) { timeline in
                let now = timeline.date
                let timeDomain = now.addingTimeInterval(-appState.effectiveLagTimeWindow.seconds) ... now
                let mode = TrendRenderingMode.live(timeDomain: timeDomain)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        lagChartStack(
                            store: store,
                            renderingMode: mode,
                            selectedTopics: $state.lagSelectedTopics,
                            selectedGroups: $state.lagSelectedGroups,
                            historyRange: nil,
                        )
                    }
                    .padding()
                }
                .transaction { $0.animation = nil }
            }
            .onAppear {
                if appState.lagSelectedTopics.isEmpty,
                   let first = store.knownTopics.first(where: { !$0.hasPrefix("__") })
                {
                    appState.lagSelectedTopics.append(first)
                }
                if appState.lagSelectedGroups.isEmpty, let first = store.knownGroups.first {
                    appState.lagSelectedGroups.append(first)
                }
                // Pre-fetch history data in background so first switch is instant
                prefetchHistoryData()
            }
        }
    }

    // MARK: - History Content

    @ViewBuilder
    private var historyContent: some View {
        let l10n = appState.l10n
        let history = appState.lagHistoryState
        @Bindable var historyBindable = history

        if history.isLoading, !history.store.hasEnoughData {
            ProgressView(l10n["common.loading"])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !history.isLoading, !history.store.hasEnoughData {
            ContentUnavailableView(
                l10n["lag.history.no.data"],
                systemImage: "clock.arrow.circlepath",
                description: Text(l10n["lag.history.no.data.description"]),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let mode = TrendRenderingMode.history(
                visibleSeconds: history.visibleWindowSeconds,
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    lagChartStack(
                        store: history.store,
                        renderingMode: mode,
                        selectedTopics: $historyBindable.selectedTopics,
                        selectedGroups: $historyBindable.selectedGroups,
                        historyRange: (from: history.rangeFrom, to: history.rangeTo),
                    )
                }
                .padding()
            }
        }
    }

    // MARK: - History Controls

    @ViewBuilder
    private var lagHistoryDateFilter: some View {
        let history = appState.lagHistoryState
        @Bindable var historyBindable = history
        let l10n = appState.l10n

        HStack(spacing: 12) {
            DatePicker(
                l10n["trends.history.from"],
                selection: $historyBindable.rangeFrom,
                in: (history.minTimestamp ?? .distantPast) ... history.rangeTo,
                displayedComponents: [.date, .hourAndMinute],
            )
            .labelsHidden()

            Text("–")
                .foregroundStyle(.secondary)

            DatePicker(
                l10n["trends.history.to"],
                selection: $historyBindable.rangeTo,
                in: history.rangeFrom...,
                displayedComponents: [.date, .hourAndMinute],
            )
            .labelsHidden()

            Button(l10n["trends.history.apply"]) {
                history.applyRange()
                Task {
                    await history.loadData(
                        database: appState.metricDatabase,
                        clusterId: appState.configStore.selectedCluster?.id,
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .fixedSize()
    }

    @ViewBuilder
    private var lagHistoryVisibleWindowPicker: some View {
        let l10n = appState.l10n
        let history = appState.lagHistoryState
        @Bindable var historyBindable = history

        HStack(spacing: 12) {
            Picker(l10n["trends.time.window"], selection: $historyBindable.visibleWindowSeconds) {
                ForEach(history.validTimeWindowOptions, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            }
            .fixedSize()

            if history.visibleWindowSeconds > 1800 {
                Picker(l10n["trends.aggregation"], selection: $historyBindable.aggregationMode) {
                    Text(l10n["trends.aggregation.mean"]).tag(AggregationMode.mean)
                    Text(l10n["trends.aggregation.min"]).tag(AggregationMode.min)
                    Text(l10n["trends.aggregation.max"]).tag(AggregationMode.max)
                }
                .fixedSize()
            }
        }
        .onChange(of: history.visibleWindowSeconds) {
            history.expandRangeIfNeeded()
            Task {
                await history.loadData(
                    database: appState.metricDatabase,
                    clusterId: appState.configStore.selectedCluster?.id,
                )
            }
        }
        .onChange(of: history.aggregationMode) {
            Task {
                await history.loadData(
                    database: appState.metricDatabase,
                    clusterId: appState.configStore.selectedCluster?.id,
                )
            }
        }
    }

    // MARK: - Lag Chart Stack

    @ViewBuilder
    private func lagChartStack(
        store: MetricStore,
        renderingMode: TrendRenderingMode,
        selectedTopics: Binding<[String]>,
        selectedGroups: Binding<[String]>,
        historyRange: (from: Date, to: Date)?,
    ) -> some View {
        let l10n = appState.l10n
        let clusterName = appState.configStore.selectedCluster?.name ?? "Unknown"
        let database = appState.metricDatabase
        let clusterId = appState.configStore.selectedCluster?.id

        // Row 1: Consumer Group Lag + Topic Lag side by side
        HStack(alignment: .top, spacing: 16) {
            ConsumerGroupLagChart(
                store: store, l10n: l10n, renderingMode: renderingMode,
                selectedGroups: selectedGroups,
                clusterName: clusterName, database: database, clusterId: clusterId, historyRange: historyRange,
            )

            TopicLagChart(
                store: store, l10n: l10n, renderingMode: renderingMode,
                selectedTopics: selectedTopics,
                clusterName: clusterName, database: database, clusterId: clusterId, historyRange: historyRange,
            )
        }

        // Row 2: Partition Lag (full width)
        PartitionLagChart(
            store: store, l10n: l10n, renderingMode: renderingMode,
            selectedTopics: selectedTopics,
            partitionOwnerMap: partitionOwnerMap,
            clusterName: clusterName, database: database, clusterId: clusterId, historyRange: historyRange,
        )

        // Row 3: Consumer Member Lag (full width)
        ConsumerMemberLagChart(
            store: store, l10n: l10n, renderingMode: renderingMode,
            selectedGroups: selectedGroups,
            consumerGroups: appState.consumerGroups,
            clusterName: clusterName, database: database, clusterId: clusterId, historyRange: historyRange,
        )
    }

    // MARK: - Mode Change

    private func handleModeChange(_ newMode: TrendsMode) {
        guard newMode == .history else { return }
        let history = appState.lagHistoryState
        if !history.store.hasEnoughData {
            history.enterHistoryMode(timeWindow: appState.effectiveLagTimeWindow)
        }
        Task.detached {
            await history.loadData(
                database: appState.metricDatabase,
                clusterId: appState.configStore.selectedCluster?.id,
            )
        }
    }

    /// Pre-fetch history data in background so the first Live → History switch is instant.
    private func prefetchHistoryData() {
        let history = appState.lagHistoryState
        guard !history.store.hasEnoughData else { return }
        history.enterHistoryMode(timeWindow: appState.effectiveLagTimeWindow)
        Task.detached(priority: .low) {
            await history.loadData(
                database: appState.metricDatabase,
                clusterId: appState.configStore.selectedCluster?.id,
            )
        }
    }
}
