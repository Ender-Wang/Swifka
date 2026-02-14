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

    /// Incremented on clear/loadHistorical to force chart recreation (resets scroll state).
    private(set) var dataEpoch: Int = 0

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
            let excess = snapshots.count - capacity
            snapshots.removeFirst(excess)
        }
        rebuildCaches()
    }

    /// Bulk-load historical snapshots from database.
    func loadHistorical(_ historical: [MetricSnapshot]) {
        snapshots = historical
        if snapshots.count > capacity {
            snapshots = Array(snapshots.suffix(capacity))
        }
        dataEpoch += 1
        rebuildCaches()
    }

    func clear() {
        snapshots.removeAll()
        dataEpoch += 1
        rebuildCaches()
    }

    // MARK: - Per-Key Accessors

    func throughputSeries(for topic: String) -> [ThroughputPoint] {
        topicThroughputCache[topic] ?? []
    }

    func lagSeries(for group: String) -> [LagPoint] {
        groupLagCache[group] ?? []
    }

    // MARK: - Granularity

    /// Granularity of the most recent snapshot, used for chart visible domain.
    var currentGranularity: TimeInterval {
        snapshots.last?.granularity ?? 0
    }

    // MARK: - Cache Rebuild

    private func rebuildCaches() {
        hasEnoughData = snapshots.count >= 2

        // Compute segments from granularity and timestamps.
        // Two consecutive points connect if the actual gap ≤ expected interval × tolerance.
        // A break increments the segment counter.
        var segments: [Int] = []
        if !snapshots.isEmpty {
            segments.append(0)
            var currentSegment = 0
            for i in 1 ..< snapshots.count {
                let gap = snapshots[i].timestamp.timeIntervalSince(snapshots[i - 1].timestamp)
                let prevG = snapshots[i - 1].granularity
                let currG = snapshots[i].granularity

                // Use the earlier point's granularity if auto-refresh, else the later's.
                // If both are manual (0), any positive gap > 0 × 2 = 0 → always breaks.
                let effectiveGranularity: TimeInterval = if prevG > 0 {
                    prevG
                } else {
                    currG
                }

                if gap > effectiveGranularity * Constants.gapToleranceFactor {
                    currentSegment += 1
                }
                segments.append(currentSegment)
            }
        }

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
        pingHistory = zip(segments, snapshots).compactMap { seg, snap in
            guard let ms = snap.pingMs else { return nil }
            return PingPoint(timestamp: snap.timestamp, ms: ms, segment: seg)
        }

        // ISR health
        isrHealthSeries = zip(segments, snapshots).map { seg, snap in
            let ratio = snap.totalPartitions > 0
                ? Double(snap.totalPartitions - snap.underReplicatedPartitions) / Double(snap.totalPartitions)
                : 1.0
            return ISRHealthPoint(timestamp: snap.timestamp, healthyRatio: ratio, segment: seg)
        }

        // Cluster lag
        clusterLagSeries = zip(segments, snapshots).map { seg, snap in
            LagPoint(timestamp: snap.timestamp, group: "__cluster__", totalLag: snap.totalLag, segment: seg)
        }

        guard snapshots.count >= 2 else {
            clusterThroughput = []
            topicThroughputCache = [:]
            groupLagCache = [:]
            return
        }

        // Cluster throughput — skip pairs that cross segment boundaries
        var clusterPoints: [ThroughputPoint] = []
        for i in 1 ..< snapshots.count {
            guard segments[i] == segments[i - 1] else { continue }
            let prev = snapshots[i - 1]
            let curr = snapshots[i]
            let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
            guard dt > 0 else { continue }
            let delta = max(0, curr.totalHighWatermark - prev.totalHighWatermark)
            clusterPoints.append(ThroughputPoint(
                timestamp: curr.timestamp,
                topic: "__cluster__",
                messagesPerSecond: Double(delta) / dt,
                segment: segments[i],
            ))
        }
        clusterThroughput = clusterPoints

        // Per-topic throughput
        var newTopicCache: [String: [ThroughputPoint]] = [:]
        for topic in allTopics {
            var points: [ThroughputPoint] = []
            for i in 1 ..< snapshots.count {
                guard segments[i] == segments[i - 1] else { continue }
                let prev = snapshots[i - 1]
                let curr = snapshots[i]
                let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
                guard dt > 0 else { continue }
                let prevWM = prev.topicWatermarks[topic] ?? 0
                let currWM = curr.topicWatermarks[topic] ?? 0
                let delta = max(0, currWM - prevWM)
                points.append(ThroughputPoint(
                    timestamp: curr.timestamp,
                    topic: topic,
                    messagesPerSecond: Double(delta) / dt,
                    segment: segments[i],
                ))
            }
            newTopicCache[topic] = points
        }
        topicThroughputCache = newTopicCache

        // Per-group lag
        var newGroupCache: [String: [LagPoint]] = [:]
        for group in allGroups {
            newGroupCache[group] = zip(segments, snapshots).compactMap { seg, snap in
                guard let lag = snap.consumerGroupLags[group] else { return nil }
                return LagPoint(timestamp: snap.timestamp, group: group, totalLag: lag, segment: seg)
            }
        }
        groupLagCache = newGroupCache
    }
}
