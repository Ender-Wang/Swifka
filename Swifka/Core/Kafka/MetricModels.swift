import Foundation

// MARK: - Metric Snapshot

/// A single point-in-time snapshot captured at the end of each refresh cycle.
nonisolated struct MetricSnapshot: Sendable, Identifiable {
    let id: UUID
    let timestamp: Date

    /// Per-topic: sum of high watermarks across all partitions.
    let topicWatermarks: [String: Int64]

    /// Per-consumer-group: total lag (empty until committed offset fetching is added).
    let consumerGroupLags: [String: Int64]

    /// Cluster-wide aggregates.
    let totalHighWatermark: Int64
    let totalLag: Int64
    let underReplicatedPartitions: Int
    let totalPartitions: Int
    let brokerCount: Int

    /// Ping latency at snapshot time.
    let pingMs: Int?
}

// MARK: - Derived Chart Points

/// Computed from consecutive MetricSnapshots for throughput charts.
/// Uses deterministic ID based on timestamp + topic to avoid SwiftUI/Charts identity churn.
nonisolated struct ThroughputPoint: Sendable, Identifiable {
    let timestamp: Date
    let topic: String
    let messagesPerSecond: Double

    var id: Int {
        var hasher = Hasher()
        hasher.combine(timestamp)
        hasher.combine(topic)
        return hasher.finalize()
    }
}

/// A single lag data point for chart display.
nonisolated struct LagPoint: Sendable, Identifiable {
    let timestamp: Date
    let group: String
    let totalLag: Int64

    var id: Int {
        var hasher = Hasher()
        hasher.combine(timestamp)
        hasher.combine(group)
        return hasher.finalize()
    }
}

/// Ping data point with deterministic ID for chart display.
nonisolated struct PingPoint: Sendable, Identifiable {
    let timestamp: Date
    let ms: Int

    var id: Int {
        var hasher = Hasher()
        hasher.combine(timestamp)
        return hasher.finalize()
    }
}

/// ISR health data point with deterministic ID for chart display.
nonisolated struct ISRHealthPoint: Sendable, Identifiable {
    let timestamp: Date
    let healthyRatio: Double

    var id: Int {
        var hasher = Hasher()
        hasher.combine(timestamp)
        return hasher.finalize()
    }
}
