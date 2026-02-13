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
        pingHistory = recentSnapshots.compactMap { snap in
            guard let ms = snap.pingMs else { return nil }
            return PingPoint(timestamp: snap.timestamp, ms: ms)
        }

        // ISR health
        isrHealthSeries = recentSnapshots.map { snap in
            let ratio = snap.totalPartitions > 0
                ? Double(snap.totalPartitions - snap.underReplicatedPartitions) / Double(snap.totalPartitions)
                : 1.0
            return ISRHealthPoint(timestamp: snap.timestamp, healthyRatio: ratio)
        }

        // Cluster lag
        clusterLagSeries = recentSnapshots.map { snap in
            LagPoint(timestamp: snap.timestamp, group: "__cluster__", totalLag: snap.totalLag)
        }

        guard recentSnapshots.count >= 2 else {
            clusterThroughput = []
            topicThroughputCache = [:]
            groupLagCache = [:]
            return
        }

        // Cluster throughput
        var clusterPoints: [ThroughputPoint] = []
        for i in 1 ..< recentSnapshots.count {
            let prev = recentSnapshots[i - 1]
            let curr = recentSnapshots[i]
            let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
            guard dt > 0 else { continue }
            let delta = max(0, curr.totalHighWatermark - prev.totalHighWatermark)
            clusterPoints.append(ThroughputPoint(
                timestamp: curr.timestamp,
                topic: "__cluster__",
                messagesPerSecond: Double(delta) / dt,
            ))
        }
        clusterThroughput = clusterPoints

        // Per-topic throughput
        var newTopicCache: [String: [ThroughputPoint]] = [:]
        for topic in allTopics {
            var points: [ThroughputPoint] = []
            for i in 1 ..< recentSnapshots.count {
                let prev = recentSnapshots[i - 1]
                let curr = recentSnapshots[i]
                let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
                guard dt > 0 else { continue }
                let prevWM = prev.topicWatermarks[topic] ?? 0
                let currWM = curr.topicWatermarks[topic] ?? 0
                let delta = max(0, currWM - prevWM)
                points.append(ThroughputPoint(
                    timestamp: curr.timestamp,
                    topic: topic,
                    messagesPerSecond: Double(delta) / dt,
                ))
            }
            newTopicCache[topic] = points
        }
        topicThroughputCache = newTopicCache

        // Per-group lag
        var newGroupCache: [String: [LagPoint]] = [:]
        for group in allGroups {
            newGroupCache[group] = recentSnapshots.compactMap { snap in
                guard let lag = snap.consumerGroupLags[group] else { return nil }
                return LagPoint(timestamp: snap.timestamp, group: group, totalLag: lag)
            }
        }
        groupLagCache = newGroupCache
    }
}
