import SwiftUI

struct TrendsView: View {
    @Environment(AppState.self) private var appState

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

        HStack {
            // Hide mode toggle in manual mode (locked to History)
            if isAutoRefresh {
                Picker(l10n["trends.mode"], selection: $state.trendsMode) {
                    Text(l10n["trends.mode.live"]).tag(TrendsMode.live)
                    Text(l10n["trends.mode.history"]).tag(TrendsMode.history)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
            }

            Spacer()

            // History: date filter in middle
            if case .history = appState.trendsMode {
                historyDateFilter

                Spacer()
            }

            // Time Window picker — always right-aligned
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
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
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
                            selectedGroups: $state.trendSelectedGroups,
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
                if appState.trendSelectedGroups.isEmpty, let first = store.knownGroups.first {
                    appState.trendSelectedGroups.append(first)
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

        if history.isLoading {
            ProgressView(l10n["common.loading"])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !history.store.hasEnoughData {
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
                        selectedGroups: $historyBindable.selectedGroups,
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
    }

    @ViewBuilder
    private var historyVisibleWindowPicker: some View {
        let l10n = appState.l10n
        @Bindable var historyBindable = appState.historyState

        Picker(l10n["trends.time.window"], selection: $historyBindable.visibleWindowSeconds) {
            Text("1m").tag(TimeInterval(60))
            Text("5m").tag(TimeInterval(300))
            Text("15m").tag(TimeInterval(900))
            Text("30m").tag(TimeInterval(1800))
            Text("1h").tag(TimeInterval(3600))
            Text("6h").tag(TimeInterval(21600))
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
    }

    // MARK: - Shared Chart Stack

    @ViewBuilder
    private func chartStack(
        store: MetricStore,
        renderingMode: TrendRenderingMode,
        selectedTopics: Binding<[String]>,
        selectedGroups: Binding<[String]>,
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

        // Row 3: Consumer group lag
        ConsumerGroupLagChart(
            store: store,
            l10n: l10n,
            renderingMode: renderingMode,
            selectedGroups: selectedGroups,
        )

        // Row 4: Per-topic lag
        TopicLagChart(
            store: store,
            l10n: l10n,
            renderingMode: renderingMode,
            selectedTopics: selectedTopics,
        )

        // Row 5: Per-partition lag
        PartitionLagChart(
            store: store,
            l10n: l10n,
            renderingMode: renderingMode,
            selectedTopics: selectedTopics,
            partitionOwnerMap: partitionOwnerMap,
        )

        // Row 6: Per-consumer member lag
        ConsumerMemberLagChart(
            store: store,
            l10n: l10n,
            renderingMode: renderingMode,
            selectedGroups: selectedGroups,
            consumerGroups: appState.consumerGroups,
        )

        // Row 7: ISR health
        ISRHealthChart(store: store, l10n: l10n, renderingMode: renderingMode)
    }

    // MARK: - Mode Change

    private func handleModeChange(_ newMode: TrendsMode) {
        guard newMode == .history else { return }
        let history = appState.historyState
        history.enterHistoryMode(timeWindow: appState.effectiveTimeWindow)
        Task.detached {
            await history.loadData(
                database: appState.metricDatabase,
                clusterId: appState.configStore.selectedCluster?.id,
            )
        }
    }
}
