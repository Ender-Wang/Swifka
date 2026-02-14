import SwiftUI

struct TrendsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        let l10n = appState.l10n
        let store = appState.metricStore
        if !appState.connectionStatus.isConnected {
            ContentUnavailableView(
                l10n["trends.not.connected"],
                systemImage: "chart.xyaxis.line",
                description: Text(l10n["trends.not.connected.description"]),
            )
        } else if !store.hasEnoughData {
            ContentUnavailableView(
                l10n["trends.not.enough.data"],
                systemImage: "chart.xyaxis.line",
                description: Text(l10n["trends.not.enough.data.description"]),
            )
        } else {
            let isAutoRefresh = appState.refreshManager.isAutoRefresh
            let tickInterval: TimeInterval = if case let .interval(seconds) = appState.refreshManager.mode {
                TimeInterval(seconds)
            } else {
                86400 // manual: effectively never tick
            }
            TimelineView(.periodic(from: .now, by: tickInterval)) { timeline in
                let now = timeline.date
                let timeDomain = now.addingTimeInterval(-appState.effectiveTimeWindow.seconds) ... now

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        // Time window picker
                        HStack {
                            Spacer()
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

                        // Row 1: Cluster throughput + Ping latency
                        HStack(spacing: 16) {
                            ClusterThroughputChart(store: store, l10n: l10n, timeDomain: timeDomain)
                            PingLatencyChart(store: store, l10n: l10n, timeDomain: timeDomain)
                                .frame(maxWidth: 300)
                        }

                        // Row 2: Per-topic throughput
                        TopicThroughputChart(
                            store: store,
                            l10n: l10n,
                            timeDomain: timeDomain,
                            selectedTopics: $state.trendSelectedTopics,
                        )

                        // Row 3: Consumer group lag
                        ConsumerGroupLagChart(
                            store: store,
                            l10n: l10n,
                            timeDomain: timeDomain,
                            selectedGroups: $state.trendSelectedGroups,
                        )

                        // Row 4: ISR health
                        ISRHealthChart(store: store, l10n: l10n, timeDomain: timeDomain)
                    }
                    .padding()
                }
                .transaction { $0.animation = nil }
            }
            // Manual mode: new data → pingHistory.count changes → id changes → TimelineView
            // recreates with fresh Date(). Auto-refresh: id is stable (0), ticks normally.
            .id(isAutoRefresh ? 0 : store.pingHistory.count)
            .navigationTitle(l10n["trends.title"])
            .onAppear {
                if appState.trendSelectedTopics.isEmpty,
                   let first = store.knownTopics.first(where: { !$0.hasPrefix("__") })
                {
                    appState.trendSelectedTopics.insert(first)
                }
                if appState.trendSelectedGroups.isEmpty, let first = store.knownGroups.first {
                    appState.trendSelectedGroups.insert(first)
                }
            }
        }
    }
}
