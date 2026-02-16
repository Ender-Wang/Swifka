import Foundation
import SQLite

actor MetricDatabase {
    private let db: Connection

    // MARK: - Table Definition

    private let snapshots = Table("metric_snapshots")
    private let colId = SQLite.Expression<String>("id")
    private let colClusterId = SQLite.Expression<String>("cluster_id")
    private let colTimestamp = SQLite.Expression<Double>("timestamp")
    private let colTopicWatermarks = SQLite.Expression<String>("topic_watermarks")
    private let colConsumerGroupLags = SQLite.Expression<String>("consumer_group_lags")
    private let colTotalHighWatermark = SQLite.Expression<Int64>("total_high_watermark")
    private let colTotalLag = SQLite.Expression<Int64>("total_lag")
    private let colUnderReplicatedPartitions = SQLite.Expression<Int64>("under_replicated_partitions")
    private let colTotalPartitions = SQLite.Expression<Int64>("total_partitions")
    private let colBrokerCount = SQLite.Expression<Int64>("broker_count")
    private let colPingMs = SQLite.Expression<Int64?>("ping_ms")
    private let colGranularity = SQLite.Expression<Double>("granularity")
    private let colTopicLags = SQLite.Expression<String>("topic_lags")
    private let colPartitionLagDetail = SQLite.Expression<String>("partition_lag_detail")

    // MARK: - Init

    init() throws {
        db = try Self.openAndSetup()
    }

    /// Opens the database, enables WAL, and creates the schema.
    /// Static + nonisolated so it runs without actor isolation issues in init.
    private static func openAndSetup() throws -> Connection {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first!
        let dir = appSupport.appendingPathComponent(Constants.configDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dbPath = dir.appendingPathComponent(Constants.metricsDatabaseFileName).path
        let conn = try Connection(dbPath)
        try conn.execute("PRAGMA journal_mode = WAL")

        let table = Table("metric_snapshots")
        let colId = SQLite.Expression<String>("id")
        let colClusterId = SQLite.Expression<String>("cluster_id")
        let colTimestamp = SQLite.Expression<Double>("timestamp")
        let colTopicWatermarks = SQLite.Expression<String>("topic_watermarks")
        let colConsumerGroupLags = SQLite.Expression<String>("consumer_group_lags")
        let colTotalHighWatermark = SQLite.Expression<Int64>("total_high_watermark")
        let colTotalLag = SQLite.Expression<Int64>("total_lag")
        let colUnderReplicatedPartitions = SQLite.Expression<Int64>("under_replicated_partitions")
        let colTotalPartitions = SQLite.Expression<Int64>("total_partitions")
        let colBrokerCount = SQLite.Expression<Int64>("broker_count")
        let colPingMs = SQLite.Expression<Int64?>("ping_ms")
        let colGranularity = SQLite.Expression<Double>("granularity")

        try conn.run(table.create(ifNotExists: true) { t in
            t.column(colId, primaryKey: true)
            t.column(colClusterId)
            t.column(colTimestamp)
            t.column(colTopicWatermarks)
            t.column(colConsumerGroupLags)
            t.column(colTotalHighWatermark)
            t.column(colTotalLag)
            t.column(colUnderReplicatedPartitions)
            t.column(colTotalPartitions)
            t.column(colBrokerCount)
            t.column(colPingMs)
            t.column(colGranularity)
        })

        try conn.run(table.createIndex(
            colClusterId, colTimestamp,
            ifNotExists: true,
        ))

        // Migrations: add columns if they don't already exist
        let existingColumns = try Set(
            conn.prepare("PRAGMA table_info(metric_snapshots)")
                .map { row in row[1] as! String },
        )

        if !existingColumns.contains("topic_lags") {
            try conn.run(table.addColumn(
                SQLite.Expression<String>("topic_lags"), defaultValue: "{}",
            ))
        }

        if !existingColumns.contains("partition_lag_detail") {
            try conn.run(table.addColumn(
                SQLite.Expression<String>("partition_lag_detail"), defaultValue: "{}",
            ))
        }

        return conn
    }

    // MARK: - Insert

    func insert(_ snapshot: MetricSnapshot, clusterId: UUID) throws {
        let watermarksJSON = try String(
            data: JSONEncoder().encode(snapshot.topicWatermarks),
            encoding: .utf8,
        )!
        let lagsJSON = try String(
            data: JSONEncoder().encode(snapshot.consumerGroupLags),
            encoding: .utf8,
        )!
        let topicLagsJSON = try String(
            data: JSONEncoder().encode(snapshot.topicLags),
            encoding: .utf8,
        )!
        let partitionLagDetailJSON = try String(
            data: JSONEncoder().encode(snapshot.partitionLagDetail),
            encoding: .utf8,
        )!

        try db.run(snapshots.insert(
            colId <- snapshot.id.uuidString,
            colClusterId <- clusterId.uuidString,
            colTimestamp <- snapshot.timestamp.timeIntervalSince1970,
            colTopicWatermarks <- watermarksJSON,
            colConsumerGroupLags <- lagsJSON,
            colTopicLags <- topicLagsJSON,
            colPartitionLagDetail <- partitionLagDetailJSON,
            colTotalHighWatermark <- snapshot.totalHighWatermark,
            colTotalLag <- snapshot.totalLag,
            colUnderReplicatedPartitions <- Int64(snapshot.underReplicatedPartitions),
            colTotalPartitions <- Int64(snapshot.totalPartitions),
            colBrokerCount <- Int64(snapshot.brokerCount),
            colPingMs <- snapshot.pingMs.map { Int64($0) },
            colGranularity <- snapshot.granularity,
        ))
    }

    // MARK: - Load

    func loadRecentSnapshots(
        clusterId: UUID,
        limit: Int = Constants.metricStoreCapacity,
    ) throws -> [MetricSnapshot] {
        let query = snapshots
            .filter(colClusterId == clusterId.uuidString)
            .order(colTimestamp.desc)
            .limit(limit)

        var results: [MetricSnapshot] = []
        let decoder = JSONDecoder()

        for row in try db.prepare(query) {
            try results.append(decodeSnapshot(row: row, decoder: decoder))
        }

        // Return in chronological order (oldest first)
        return results.reversed()
    }

    // MARK: - Time-Range Query

    func loadSnapshots(
        clusterId: UUID,
        from startDate: Date,
        to endDate: Date,
    ) throws -> [MetricSnapshot] {
        let query = snapshots
            .filter(colClusterId == clusterId.uuidString)
            .filter(colTimestamp >= startDate.timeIntervalSince1970)
            .filter(colTimestamp <= endDate.timeIntervalSince1970)
            .order(colTimestamp.asc)

        var results: [MetricSnapshot] = []
        let decoder = JSONDecoder()

        for row in try db.prepare(query) {
            try results.append(decodeSnapshot(row: row, decoder: decoder))
        }

        return results
    }

    // MARK: - Downsampled Query

    /// Returns the appropriate bucket size in seconds for a given time range,
    /// or nil if the range is small enough for raw data.
    static func bucketSeconds(forRangeSeconds range: TimeInterval) -> Int? {
        switch range {
        case ...1800: nil // ≤30m: raw data
        case ...3600: 10 // ≤1h: 10s buckets (~360 points)
        case ...21600: 60 // ≤6h: 1-min buckets (~360 points)
        case ...86400: 300 // ≤24h: 5-min buckets (~288 points)
        case ...604_800: 1800 // ≤7d: 30-min buckets (~336 points)
        default: 3600 // >7d: 1h buckets
        }
    }

    /// Loads downsampled snapshots using SQL GROUP BY time buckets.
    /// Scalar columns use AVG/MIN/MAX based on mode. JSON dict columns are
    /// aggregated in Swift (per-key AVG/MIN/MAX across all rows in a bucket).
    func loadDownsampledSnapshots(
        clusterId: UUID,
        from startDate: Date,
        to endDate: Date,
        bucketSeconds: Int,
        mode: AggregationMode,
    ) throws -> [MetricSnapshot] {
        let aggFn = switch mode {
        case .mean: "AVG"
        case .min: "MIN"
        case .max: "MAX"
        }

        // Load all rows with bucket assignment + scalar aggregates via window functions
        let sql = """
        SELECT
            m.id,
            CAST(m.timestamp / \(bucketSeconds) AS INTEGER) * \(bucketSeconds) AS bucket_ts,
            m.topic_watermarks,
            m.consumer_group_lags,
            m.topic_lags,
            m.partition_lag_detail,
            CAST(\(aggFn)(m.total_high_watermark) OVER (PARTITION BY CAST(m.timestamp / \(bucketSeconds) AS INTEGER)) AS INTEGER) AS agg_hwm,
            CAST(\(aggFn)(m.total_lag) OVER (PARTITION BY CAST(m.timestamp / \(bucketSeconds) AS INTEGER)) AS INTEGER) AS agg_lag,
            CAST(\(aggFn)(m.under_replicated_partitions) OVER (PARTITION BY CAST(m.timestamp / \(bucketSeconds) AS INTEGER)) AS INTEGER) AS agg_urp,
            MAX(m.total_partitions) OVER (PARTITION BY CAST(m.timestamp / \(bucketSeconds) AS INTEGER)) AS agg_parts,
            MAX(m.broker_count) OVER (PARTITION BY CAST(m.timestamp / \(bucketSeconds) AS INTEGER)) AS agg_brokers,
            CAST(\(aggFn)(m.ping_ms) OVER (PARTITION BY CAST(m.timestamp / \(bucketSeconds) AS INTEGER)) AS INTEGER) AS agg_ping
        FROM metric_snapshots m
        WHERE m.cluster_id = ? AND m.timestamp >= ? AND m.timestamp <= ?
        ORDER BY bucket_ts ASC, m.timestamp ASC
        """

        let stmt = try db.prepare(
            sql,
            clusterId.uuidString,
            startDate.timeIntervalSince1970,
            endDate.timeIntervalSince1970,
        )

        let decoder = JSONDecoder()

        // Collect rows per bucket for JSON aggregation
        struct BucketRow {
            let id: UUID
            let watermarks: [String: Int64]
            let lags: [String: Int64]
            let topicLags: [String: Int64]
            let partitionLagDetail: [String: Int64]
            let aggHwm: Int64
            let aggLag: Int64
            let aggUrp: Int64
            let aggParts: Int64
            let aggBrokers: Int64
            let aggPing: Int64?
        }

        var buckets: [(ts: Double, rows: [BucketRow])] = []
        var currentBucketTs: Double = -1

        for row in stmt {
            guard let idStr = row[0] as? String,
                  let bucketTs = row[1] as? Double ?? (row[1] as? Int64).map(Double.init),
                  let watermarksStr = row[2] as? String,
                  let lagsStr = row[3] as? String,
                  let topicLagsStr = row[4] as? String,
                  let partLagStr = row[5] as? String
            else { continue }

            let bucketRow = BucketRow(
                id: UUID(uuidString: idStr) ?? UUID(),
                watermarks: (try? decoder.decode([String: Int64].self, from: watermarksStr.data(using: .utf8)!)) ?? [:],
                lags: (try? decoder.decode([String: Int64].self, from: lagsStr.data(using: .utf8)!)) ?? [:],
                topicLags: (try? decoder.decode([String: Int64].self, from: topicLagsStr.data(using: .utf8)!)) ?? [:],
                partitionLagDetail: (try? decoder.decode([String: Int64].self, from: partLagStr.data(using: .utf8)!)) ?? [:],
                aggHwm: (row[6] as? Int64) ?? 0,
                aggLag: (row[7] as? Int64) ?? 0,
                aggUrp: (row[8] as? Int64) ?? 0,
                aggParts: (row[9] as? Int64) ?? 0,
                aggBrokers: (row[10] as? Int64) ?? 0,
                aggPing: row[11] as? Int64,
            )

            if bucketTs != currentBucketTs {
                buckets.append((ts: bucketTs, rows: [bucketRow]))
                currentBucketTs = bucketTs
            } else {
                buckets[buckets.count - 1].rows.append(bucketRow)
            }
        }

        // Aggregate JSON dicts per bucket
        return buckets.map { bucket in
            let rows = bucket.rows
            let first = rows[0]

            return MetricSnapshot(
                id: first.id,
                timestamp: Date(timeIntervalSince1970: bucket.ts),
                granularity: TimeInterval(bucketSeconds),
                topicWatermarks: aggregateDict(rows.map(\.watermarks), mode: mode),
                consumerGroupLags: aggregateDict(rows.map(\.lags), mode: mode),
                topicLags: aggregateDict(rows.map(\.topicLags), mode: mode),
                partitionLagDetail: aggregateDict(rows.map(\.partitionLagDetail), mode: mode),
                totalHighWatermark: first.aggHwm,
                totalLag: first.aggLag,
                underReplicatedPartitions: Int(first.aggUrp),
                totalPartitions: Int(first.aggParts),
                brokerCount: Int(first.aggBrokers),
                pingMs: first.aggPing.map { Int($0) },
            )
        }
    }

    /// Aggregate an array of `[String: Int64]` dicts per key using the given mode.
    private func aggregateDict(_ dicts: [[String: Int64]], mode: AggregationMode) -> [String: Int64] {
        guard !dicts.isEmpty else { return [:] }
        if dicts.count == 1 { return dicts[0] }

        // Collect all keys
        var allKeys = Set<String>()
        for d in dicts {
            allKeys.formUnion(d.keys)
        }

        var result: [String: Int64] = [:]
        for key in allKeys {
            let values = dicts.compactMap { $0[key] }
            guard !values.isEmpty else { continue }
            switch mode {
            case .mean:
                result[key] = values.reduce(0, +) / Int64(values.count)
            case .min:
                result[key] = values.min()!
            case .max:
                result[key] = values.max()!
            }
        }
        return result
    }

    // MARK: - Row Decoding

    private func decodeSnapshot(row: Row, decoder: JSONDecoder) throws -> MetricSnapshot {
        let watermarks = try decoder.decode(
            [String: Int64].self,
            from: row[colTopicWatermarks].data(using: .utf8)!,
        )
        let lags = try decoder.decode(
            [String: Int64].self,
            from: row[colConsumerGroupLags].data(using: .utf8)!,
        )
        let topicLags = try decoder.decode(
            [String: Int64].self,
            from: row[colTopicLags].data(using: .utf8)!,
        )
        let partitionLagDetail = try decoder.decode(
            [String: Int64].self,
            from: row[colPartitionLagDetail].data(using: .utf8)!,
        )

        return MetricSnapshot(
            id: UUID(uuidString: row[colId])!,
            timestamp: Date(timeIntervalSince1970: row[colTimestamp]),
            granularity: row[colGranularity],
            topicWatermarks: watermarks,
            consumerGroupLags: lags,
            topicLags: topicLags,
            partitionLagDetail: partitionLagDetail,
            totalHighWatermark: row[colTotalHighWatermark],
            totalLag: row[colTotalLag],
            underReplicatedPartitions: Int(row[colUnderReplicatedPartitions]),
            totalPartitions: Int(row[colTotalPartitions]),
            brokerCount: Int(row[colBrokerCount]),
            pingMs: row[colPingMs].map { Int($0) },
        )
    }

    // MARK: - Timestamp Bounds

    func timestampBounds(clusterId: UUID) throws -> (min: Date, max: Date)? {
        let query = snapshots
            .filter(colClusterId == clusterId.uuidString)
            .select(colTimestamp.min, colTimestamp.max)

        guard let row = try db.pluck(query) else { return nil }
        guard let minTS = row[colTimestamp.min],
              let maxTS = row[colTimestamp.max] else { return nil }

        return (
            min: Date(timeIntervalSince1970: minTS),
            max: Date(timeIntervalSince1970: maxTS),
        )
    }

    // MARK: - Pruning

    @discardableResult
    func pruneAllClusters(retentionPolicy: DataRetentionPolicy) throws -> Int {
        guard let cutoff = retentionPolicy.cutoffDate else { return 0 }
        let query = snapshots
            .filter(colTimestamp < cutoff.timeIntervalSince1970)
        return try db.run(query.delete())
    }

    func deleteClusterData(clusterId: UUID) throws {
        let query = snapshots
            .filter(colClusterId == clusterId.uuidString)
        try db.run(query.delete())
    }

    @discardableResult
    func deleteAllData() throws -> Int {
        try db.run(snapshots.delete())
    }
}
