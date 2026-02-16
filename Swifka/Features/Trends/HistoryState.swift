import Foundation

@Observable
final class HistoryState {
    /// Dedicated MetricStore for history data — unbounded capacity.
    let store = MetricStore(capacity: .max)

    /// Earliest timestamp available in the database for the current cluster.
    var minTimestamp: Date?

    /// User-selected start of the time range (live editing via DatePicker).
    var rangeFrom = Date().addingTimeInterval(-300)

    /// User-selected end of the time range (live editing via DatePicker).
    var rangeTo = Date()

    /// Whether a database query is in progress.
    var isLoading = false

    /// Selected topics for history charts (independent from live selections).
    var selectedTopics: [String] = []

    /// Selected groups for history charts (independent from live selections).
    var selectedGroups: [String] = []

    /// Visible window duration for scrollable charts (seconds).
    var visibleWindowSeconds: TimeInterval = 300

    /// Aggregation mode for downsampled data (Mean / Min / Max).
    var aggregationMode: AggregationMode = .mean

    /// The total range (seconds) of the last applied date filter.
    /// Time Window constraints use this so they don't change while editing dates.
    var appliedRangeSeconds: TimeInterval = 300

    /// Standard time window options (seconds) for the picker.
    static let timeWindowOptions: [(label: String, seconds: TimeInterval)] = [
        ("1m", 60), ("5m", 300), ("15m", 900), ("30m", 1800),
        ("1h", 3600), ("2h", 7200), ("3h", 10800), ("4h", 14400), ("5h", 18000),
        ("6h", 21600), ("12h", 43200), ("24h", 86400), ("2d", 172_800),
        ("3d", 259_200), ("5d", 432_000), ("7d", 604_800),
    ]

    /// Total date range in seconds (live, from DatePicker bindings).
    var totalRangeSeconds: TimeInterval {
        rangeTo.timeIntervalSince(rangeFrom)
    }

    /// Minimum visible window based on the applied range and Metal texture limits.
    var minVisibleWindowSeconds: TimeInterval {
        appliedRangeSeconds / Constants.maxChartScrollRatio
    }

    /// Maximum visible window — smallest standard option >= applied range.
    var maxVisibleWindowSeconds: TimeInterval {
        Self.timeWindowOptions.first(where: { $0.seconds >= appliedRangeSeconds })?.seconds
            ?? appliedRangeSeconds
    }

    /// Valid time window options for the applied date range.
    var validTimeWindowOptions: [(label: String, seconds: TimeInterval)] {
        let minWindow = minVisibleWindowSeconds
        let maxWindow = maxVisibleWindowSeconds
        return Self.timeWindowOptions.filter { $0.seconds >= minWindow && $0.seconds <= maxWindow }
    }

    /// Set default time range when entering History mode.
    func enterHistoryMode(timeWindow: ChartTimeWindow) {
        let now = Date()
        rangeTo = now
        rangeFrom = now.addingTimeInterval(-timeWindow.seconds)
        applyRange()
    }

    /// Commit the current date range and clamp the visible window.
    /// Called when Apply is pressed or on first entry.
    func applyRange() {
        appliedRangeSeconds = totalRangeSeconds
        clampVisibleWindow()
    }

    /// Expand date range to cover the visible window if needed.
    func expandRangeIfNeeded() {
        let currentRange = rangeTo.timeIntervalSince(rangeFrom)
        if currentRange < visibleWindowSeconds {
            rangeFrom = rangeTo.addingTimeInterval(-visibleWindowSeconds)
        }
    }

    /// Ensure visibleWindowSeconds is within [min, max] for the applied range.
    /// Snaps to the nearest valid standard option.
    func clampVisibleWindow() {
        let minWindow = minVisibleWindowSeconds
        let maxWindow = maxVisibleWindowSeconds
        if visibleWindowSeconds < minWindow {
            visibleWindowSeconds = Self.timeWindowOptions
                .first(where: { $0.seconds >= minWindow })?.seconds ?? minWindow
        } else if visibleWindowSeconds > maxWindow {
            visibleWindowSeconds = maxWindow
        }
    }

    /// Load data from the database for the current time range.
    /// Automatically chooses raw or downsampled query based on range span.
    func loadData(database: MetricDatabase?, clusterId: UUID?) async {
        guard let database, let clusterId else { return }
        isLoading = true

        do {
            if let bounds = try await database.timestampBounds(clusterId: clusterId) {
                minTimestamp = bounds.min
            }

            let rangeSeconds = rangeTo.timeIntervalSince(rangeFrom)
            let snapshots: [MetricSnapshot] = if let bucket = MetricDatabase.bucketSeconds(forRangeSeconds: rangeSeconds) {
                try await database.loadDownsampledSnapshots(
                    clusterId: clusterId,
                    from: rangeFrom,
                    to: rangeTo,
                    bucketSeconds: bucket,
                    mode: aggregationMode,
                )
            } else {
                try await database.loadSnapshots(
                    clusterId: clusterId,
                    from: rangeFrom,
                    to: rangeTo,
                )
            }

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
