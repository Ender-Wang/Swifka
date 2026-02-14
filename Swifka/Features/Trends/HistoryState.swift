import Foundation

@Observable
final class HistoryState {
    /// Dedicated MetricStore for history data — unbounded capacity.
    let store = MetricStore(capacity: .max)

    /// Earliest timestamp available in the database for the current cluster.
    var minTimestamp: Date?

    /// User-selected start of the time range.
    var rangeFrom = Date().addingTimeInterval(-300)

    /// User-selected end of the time range.
    var rangeTo = Date()

    /// Whether a database query is in progress.
    var isLoading = false

    /// Selected topics for history charts (independent from live selections).
    var selectedTopics: [String] = []

    /// Selected groups for history charts (independent from live selections).
    var selectedGroups: [String] = []

    /// Visible window duration for scrollable charts (seconds).
    var visibleWindowSeconds: TimeInterval = 300

    /// Set default time range when entering History mode.
    func enterHistoryMode(timeWindow: ChartTimeWindow) {
        let now = Date()
        rangeTo = now
        rangeFrom = now.addingTimeInterval(-timeWindow.seconds)
    }

    /// Load data from the database for the current time range.
    func loadData(database: MetricDatabase?, clusterId: UUID?) async {
        guard let database, let clusterId else { return }
        isLoading = true

        do {
            if let bounds = try await database.timestampBounds(clusterId: clusterId) {
                minTimestamp = bounds.min
            }

            let snapshots = try await database.loadSnapshots(
                clusterId: clusterId,
                from: rangeFrom,
                to: rangeTo,
            )
            store.loadHistorical(snapshots)

            // Auto-select first topic/group if empty
            if selectedTopics.isEmpty,
               let first = store.knownTopics.first(where: { !$0.hasPrefix("__") })
            {
                selectedTopics.append(first)
            }
            if selectedGroups.isEmpty, let first = store.knownGroups.first {
                selectedGroups.append(first)
            }
        } catch {
            print("Failed to load history data: \(error)")
        }

        isLoading = false
    }
}
