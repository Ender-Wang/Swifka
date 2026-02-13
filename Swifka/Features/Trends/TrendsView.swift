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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    // Row 1: Cluster throughput + Ping latency
                    HStack(spacing: 16) {
                        ClusterThroughputChart(store: store, l10n: l10n)
                        PingLatencyChart(store: store, l10n: l10n)
                            .frame(maxWidth: 300)
                    }

                    // Row 2: Per-topic throughput
                    TopicThroughputChart(
                        store: store,
                        l10n: l10n,
                        selectedTopics: $state.trendSelectedTopics,
                    )

                    // Row 3: Consumer group lag
                    ConsumerGroupLagChart(
                        store: store,
                        l10n: l10n,
                        selectedGroups: $state.trendSelectedGroups,
                    )

                    // Row 4: ISR health
                    ISRHealthChart(store: store, l10n: l10n)
                }
                .padding()
            }
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
