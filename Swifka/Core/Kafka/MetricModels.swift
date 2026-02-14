import Foundation

// MARK: - Chart Time Window

nonisolated enum ChartTimeWindow: String, CaseIterable, Identifiable, Sendable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"

    var id: String {
        rawValue
    }

    var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .thirtyMinutes: 1800
        }
    }
}

// MARK: - Metric Snapshot

/// A single point-in-time snapshot captured at the end of each refresh cycle.
nonisolated struct MetricSnapshot: Sendable, Identifiable {
    let id: UUID
    let timestamp: Date

    /// The polling interval (seconds) when this snapshot was recorded.
    /// Auto-refresh: the interval setting (1, 3, 5, …). Manual: 0.
    /// Used for gap detection — lines break when the actual time gap exceeds the expected granularity.
    let granularity: TimeInterval

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
    /// Segment index for gap detection — lines break between different segments.
    let segment: Int

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
    let segment: Int

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
    let segment: Int

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
    let segment: Int

    var id: Int {
        var hasher = Hasher()
        hasher.combine(timestamp)
        return hasher.finalize()
    }
}

// MARK: - Trends Mode

nonisolated enum TrendsMode: String, CaseIterable, Identifiable, Sendable {
    case live
    case history

    var id: String {
        rawValue
    }
}

// MARK: - Trend Rendering Mode

nonisolated enum TrendRenderingMode: Sendable {
    /// Live: fixed X domain, sliding window, no scrolling.
    case live(timeDomain: ClosedRange<Date>)
    /// History: scrollable chart, visible window of N seconds.
    case history(visibleSeconds: TimeInterval)
}
