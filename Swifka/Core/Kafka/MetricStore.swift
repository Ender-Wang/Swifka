import Foundation

@Observable
final class MetricStore {
    private let capacity: Int

    /// Raw snapshots — not directly observed by views.
    @ObservationIgnored
    private var snapshots: [MetricSnapshot] = []

    /// Cached derived data — views observe these.
    private(set) var clusterThroughput: [ThroughputPoint] = []
    private(set) var pingHistory: [PingPoint] = []
    private(set) var isrHealthSeries: [ISRHealthPoint] = []
    private(set) var clusterLagSeries: [LagPoint] = []
    private(set) var knownTopics: [String] = []
    private(set) var knownGroups: [String] = []
    private(set) var hasEnoughData = false

    /// Per-topic throughput cache.
    private var topicThroughputCache: [String: [ThroughputPoint]] = [:]

    /// Per-group lag cache.
    private var groupLagCache: [String: [LagPoint]] = [:]

    init(capacity: Int = Constants.metricStoreCapacity) {
        self.capacity = capacity
    }

    // MARK: - Ingestion

    func record(_ snapshot: MetricSnapshot) {
        snapshots.append(snapshot)
        if snapshots.count > capacity {
            snapshots.removeFirst(snapshots.count - capacity)
        }
        rebuildCaches()
    }

    /// Bulk-load historical snapshots from database.
    /// Replaces current snapshots and rebuilds caches once.
    func loadHistorical(_ historical: [MetricSnapshot]) {
        snapshots = historical
        if snapshots.count > capacity {
            snapshots = Array(snapshots.suffix(capacity))
        }
        rebuildCaches()
    }

    func clear() {
        snapshots.removeAll()
        rebuildCaches()
    }

    // MARK: - Per-Key Accessors

    func throughputSeries(for topic: String) -> [ThroughputPoint] {
        topicThroughputCache[topic] ?? []
    }

    func lagSeries(for group: String) -> [LagPoint] {
        groupLagCache[group] ?? []
    }

    // MARK: - Cache Rebuild

    private func rebuildCaches() {
        hasEnoughData = snapshots.count >= 2
        let displayLimit = Constants.metricDisplayLimit

        // Only derive from the most recent snapshots for chart display
        let recentSnapshots = Array(snapshots.suffix(displayLimit + 1))

        // Compute time-gap segments: increment segment when gap > threshold
        let gapThreshold = Constants.chartGapThreshold
        var segments = [0]
        for i in 1 ..< recentSnapshots.count {
            let dt = recentSnapshots[i].timestamp.timeIntervalSince(recentSnapshots[i - 1].timestamp)
            segments.append(dt > gapThreshold ? segments[i - 1] + 1 : segments[i - 1])
        }

        // Only display data from the most recent continuous segment.
        // This prevents X-axis compression when historical data (hours ago) and
        // new live data are both present — the chart focuses on the current session.
        let lastSegment = segments.last ?? 0
        let displayStart = segments.firstIndex(of: lastSegment) ?? 0
        let displaySnapshots = Array(recentSnapshots[displayStart...])
        let displaySegments = Array(segments[displayStart...])

        // Known topics / groups (scan all snapshots for picker completeness)
        var allTopics = Set<String>()
        var allGroups = Set<String>()
        for snap in snapshots {
            allTopics.formUnion(snap.topicWatermarks.keys)
            allGroups.formUnion(snap.consumerGroupLags.keys)
        }
        knownTopics = allTopics.sorted()
        knownGroups = allGroups.sorted()

        // Ping history
        pingHistory = zip(displaySegments, displaySnapshots).compactMap { seg, snap in
            guard let ms = snap.pingMs else { return nil }
            return PingPoint(timestamp: snap.timestamp, ms: ms, segment: seg)
        }

        // ISR health
        isrHealthSeries = zip(displaySegments, displaySnapshots).map { seg, snap in
            let ratio = snap.totalPartitions > 0
                ? Double(snap.totalPartitions - snap.underReplicatedPartitions) / Double(snap.totalPartitions)
                : 1.0
            return ISRHealthPoint(timestamp: snap.timestamp, healthyRatio: ratio, segment: seg)
        }

        // Cluster lag
        clusterLagSeries = zip(displaySegments, displaySnapshots).map { seg, snap in
            LagPoint(timestamp: snap.timestamp, group: "__cluster__", totalLag: snap.totalLag, segment: seg)
        }

        guard displaySnapshots.count >= 2 else {
            clusterThroughput = []
            topicThroughputCache = [:]
            groupLagCache = [:]
            return
        }

        // Cluster throughput (all display pairs are within the same segment — no gap skipping needed)
        var clusterPoints: [ThroughputPoint] = []
        for i in 1 ..< displaySnapshots.count {
            let prev = displaySnapshots[i - 1]
            let curr = displaySnapshots[i]
            let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
            guard dt > 0 else { continue }
            let delta = max(0, curr.totalHighWatermark - prev.totalHighWatermark)
            clusterPoints.append(ThroughputPoint(
                timestamp: curr.timestamp,
                topic: "__cluster__",
                messagesPerSecond: Double(delta) / dt,
                segment: lastSegment,
            ))
        }
        clusterThroughput = clusterPoints

        // Per-topic throughput
        var newTopicCache: [String: [ThroughputPoint]] = [:]
        for topic in allTopics {
            var points: [ThroughputPoint] = []
            for i in 1 ..< displaySnapshots.count {
                let prev = displaySnapshots[i - 1]
                let curr = displaySnapshots[i]
                let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
                guard dt > 0 else { continue }
                let prevWM = prev.topicWatermarks[topic] ?? 0
                let currWM = curr.topicWatermarks[topic] ?? 0
                let delta = max(0, currWM - prevWM)
                points.append(ThroughputPoint(
                    timestamp: curr.timestamp,
                    topic: topic,
                    messagesPerSecond: Double(delta) / dt,
                    segment: lastSegment,
                ))
            }
            newTopicCache[topic] = points
        }
        topicThroughputCache = newTopicCache

        // Per-group lag
        var newGroupCache: [String: [LagPoint]] = [:]
        for group in allGroups {
            newGroupCache[group] = zip(displaySegments, displaySnapshots).compactMap { seg, snap in
                guard let lag = snap.consumerGroupLags[group] else { return nil }
                return LagPoint(timestamp: snap.timestamp, group: group, totalLag: lag, segment: seg)
            }
        }
        groupLagCache = newGroupCache
    }
}
