import SwiftUI

struct LagView: View {
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
                l10n["lag.not.connected"],
                systemImage: "chart.line.downtrend.xyaxis",
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

            switch appState.lagMode {
            case .live:
                liveContent
            case .history:
                historyContent
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var lagToolbar: some View {
        @Bindable var state = appState
        let l10n = appState.l10n
        let isAutoRefresh = appState.refreshManager.isAutoRefresh

        HStack {
            // Hide mode toggle in manual mode (locked to History)
            if isAutoRefresh {
                Picker(l10n["trends.mode"], selection: $state.lagMode) {
                    Text(l10n["trends.mode.live"]).tag(TrendsMode.live)
                    Text(l10n["trends.mode.history"]).tag(TrendsMode.history)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
            }

            Spacer()

            // History: date filter in middle
            if case .history = appState.lagMode {
                lagHistoryDateFilter

                Spacer()
            }

            // Time Window picker — always right-aligned
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
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
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
    private var lagHistoryVisibleWindowPicker: some View {
        let l10n = appState.l10n
        @Bindable var historyBindable = appState.lagHistoryState

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

    // MARK: - Lag Chart Stack

    @ViewBuilder
    private func lagChartStack(
        store: MetricStore,
        renderingMode: TrendRenderingMode,
        selectedTopics: Binding<[String]>,
        selectedGroups: Binding<[String]>,
    ) -> some View {
        let l10n = appState.l10n

        // Row 1: Consumer Group Lag + Topic Lag side by side
        HStack(alignment: .top, spacing: 16) {
            ConsumerGroupLagChart(
                store: store,
                l10n: l10n,
                renderingMode: renderingMode,
                selectedGroups: selectedGroups,
            )

            TopicLagChart(
                store: store,
                l10n: l10n,
                renderingMode: renderingMode,
                selectedTopics: selectedTopics,
            )
        }

        // Row 2: Partition Lag (full width)
        PartitionLagChart(
            store: store,
            l10n: l10n,
            renderingMode: renderingMode,
            selectedTopics: selectedTopics,
            partitionOwnerMap: partitionOwnerMap,
        )

        // Row 3: Consumer Member Lag (full width)
        ConsumerMemberLagChart(
            store: store,
            l10n: l10n,
            renderingMode: renderingMode,
            selectedGroups: selectedGroups,
            consumerGroups: appState.consumerGroups,
        )
    }

    // MARK: - Mode Change

    private func handleModeChange(_ newMode: TrendsMode) {
        guard newMode == .history else { return }
        let history = appState.lagHistoryState
        history.enterHistoryMode(timeWindow: appState.effectiveLagTimeWindow)
        Task.detached {
            await history.loadData(
                database: appState.metricDatabase,
                clusterId: appState.configStore.selectedCluster?.id,
            )
        }
    }
}
