import SwiftUI

struct TrendsView: View {
    @Environment(AppState.self) private var appState
    @State private var toolbarContentWidth: CGFloat = 0
    @State private var toolbarOverflow = false

    var body: some View {
        let l10n = appState.l10n
        if !appState.connectionStatus.isConnected {
            ContentUnavailableView(
                l10n["trends.not.connected"],
                systemImage: "chart.xyaxis.line",
                description: Text(l10n["trends.not.connected.description"]),
            )
        } else {
            trendsContent
                .navigationTitle(l10n["trends.title"])
                .onAppear {
                    // Manual mode: default to History and lock there
                    if !appState.refreshManager.isAutoRefresh, appState.trendsMode == .live {
                        appState.trendsMode = .history
                    }
                }
                .onChange(of: appState.trendsMode) { _, newMode in
                    handleModeChange(newMode)
                }
        }
    }

    // MARK: - Content

    private var trendsContent: some View {
        VStack(spacing: 0) {
            trendsToolbar
            Divider()

            switch appState.trendsMode {
            case .live:
                liveContent
            case .history:
                historyContent
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var trendsToolbar: some View {
        @Bindable var state = appState
        let l10n = appState.l10n
        let isAutoRefresh = appState.refreshManager.isAutoRefresh

        HStack(spacing: 12) {
            // Scrollable left section: mode picker + date filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if isAutoRefresh {
                        Picker(l10n["trends.mode"], selection: $state.trendsMode) {
                            Text(l10n["trends.mode.live"]).tag(TrendsMode.live)
                            Text(l10n["trends.mode.history"]).tag(TrendsMode.history)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }

                    if case .history = appState.trendsMode {
                        historyDateFilter
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
            switch appState.trendsMode {
            case .live:
                if isAutoRefresh {
                    Picker(l10n["trends.time.window"], selection: Binding(
                        get: { appState.effectiveTimeWindow },
                        set: { appState.trendTimeWindow = $0 },
                    )) {
                        ForEach(ChartTimeWindow.allCases) { window in
                            Text(window.rawValue).tag(window)
                        }
                    }
                    .fixedSize()
                }
            case .history:
                historyVisibleWindowPicker
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
                l10n["trends.manual.mode"],
                systemImage: "chart.xyaxis.line",
                description: Text(l10n["trends.manual.mode.description"]),
            )
        } else if !store.hasEnoughData {
            ContentUnavailableView(
                l10n["trends.not.enough.data"],
                systemImage: "chart.xyaxis.line",
                description: Text(l10n["trends.not.enough.data.description"]),
            )
        } else {
            let tickInterval: TimeInterval = if case let .interval(seconds) = appState.refreshManager.mode {
                TimeInterval(seconds)
            } else {
                1
            }
            TimelineView(.periodic(from: .now, by: tickInterval)) { timeline in
                let now = timeline.date
                let timeDomain = now.addingTimeInterval(-appState.effectiveTimeWindow.seconds) ... now
                let mode = TrendRenderingMode.live(timeDomain: timeDomain)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        chartStack(
                            store: store,
                            renderingMode: mode,
                            selectedTopics: $state.trendSelectedTopics,
                        )
                    }
                    .padding()
                }
                .transaction { $0.animation = nil }
            }
            .onAppear {
                if appState.trendSelectedTopics.isEmpty,
                   let first = store.knownTopics.first(where: { !$0.hasPrefix("__") })
                {
                    appState.trendSelectedTopics.append(first)
                }
            }
        }
    }

    // MARK: - History Content

    @ViewBuilder
    private var historyContent: some View {
        let l10n = appState.l10n
        let history = appState.historyState
        @Bindable var historyBindable = history

        if history.isLoading, !history.store.hasEnoughData {
            // Only show full-screen spinner when there's no previous data.
            // If the store already has data, keep showing charts while loading updates in background.
            ProgressView(l10n["common.loading"])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !history.isLoading, !history.store.hasEnoughData {
            ContentUnavailableView(
                l10n["trends.history.no.data"],
                systemImage: "clock.arrow.circlepath",
                description: Text(l10n["trends.history.no.data.description"]),
            )
        } else {
            let mode = TrendRenderingMode.history(
                visibleSeconds: history.visibleWindowSeconds,
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    chartStack(
                        store: history.store,
                        renderingMode: mode,
                        selectedTopics: $historyBindable.selectedTopics,
                    )
                }
                .padding()
            }
        }
    }

    // MARK: - History Controls

    @ViewBuilder
    private var historyDateFilter: some View {
        let history = appState.historyState
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
    private var historyVisibleWindowPicker: some View {
        let l10n = appState.l10n
        let history = appState.historyState
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

    // MARK: - Shared Chart Stack

    @ViewBuilder
    private func chartStack(
        store: MetricStore,
        renderingMode: TrendRenderingMode,
        selectedTopics: Binding<[String]>,
    ) -> some View {
        let l10n = appState.l10n

        // Row 1: Cluster throughput + Ping latency
        HStack(spacing: 16) {
            ClusterThroughputChart(store: store, l10n: l10n, renderingMode: renderingMode)
            PingLatencyChart(store: store, l10n: l10n, renderingMode: renderingMode)
                .frame(maxWidth: 300)
        }

        // Row 2: Per-topic throughput
        TopicThroughputChart(
            store: store,
            l10n: l10n,
            renderingMode: renderingMode,
            selectedTopics: selectedTopics,
        )

        // Row 3: ISR health
        ISRHealthChart(store: store, l10n: l10n, renderingMode: renderingMode)
    }

    // MARK: - Mode Change

    private func handleModeChange(_ newMode: TrendsMode) {
        guard newMode == .history else { return }
        let history = appState.historyState
        if !history.store.hasEnoughData {
            history.enterHistoryMode(timeWindow: appState.effectiveTimeWindow)
        }
        Task.detached {
            await history.loadData(
                database: appState.metricDatabase,
                clusterId: appState.configStore.selectedCluster?.id,
            )
        }
    }
}
