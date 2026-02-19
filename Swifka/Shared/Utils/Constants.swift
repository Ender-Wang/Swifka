import Foundation

nonisolated enum Constants {
    static let defaultWindowWidth: CGFloat = 1100
    static let defaultWindowHeight: CGFloat = 700
    static let minWindowWidth: CGFloat = 756
    static let minWindowHeight: CGFloat = 420 // 472 - 52 (toolbar height)
    static let sidebarMinWidth: CGFloat = 200

    static let kafkaTimeout: Int32 = 10000 // 10 seconds
    static let defaultMaxMessages: Int = 100
    static let defaultFetchTimeout: Int32 = 1000 // 1 second

    static let configDirectory = "Swifka"
    static let configFileName = "clusters.json"

    static let keychainService = "io.github.ender-wang.Swifka"

    static let metricStoreCapacity = 300
    static let metricsDatabaseFileName = "metrics.sqlite3"
    static let protosDirectory = "protos"
    static let protoIndexFileName = "proto_index.json"

    /// Max ratio of total data range to visible window in scrollable charts.
    /// Exceeding this causes Metal texture allocation failures (width > 16384px).
    /// At 8×, a 1200pt-wide chart produces ~9600px content — well under the limit.
    static let maxChartScrollRatio: Double = 8.0

    /// Multiplier for gap detection: break chart lines when actual gap > granularity × this factor.
    /// At 2×, a single slow refresh still connects; two missed refreshes cause a break.
    /// When both points are manual (granularity=0), any positive gap > 0 → always breaks.
    static let gapToleranceFactor: Double = 2.0
}
