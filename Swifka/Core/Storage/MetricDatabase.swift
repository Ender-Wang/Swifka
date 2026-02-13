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
        })

        try conn.run(table.createIndex(
            colClusterId, colTimestamp,
            ifNotExists: true,
        ))

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

        try db.run(snapshots.insert(
            colId <- snapshot.id.uuidString,
            colClusterId <- clusterId.uuidString,
            colTimestamp <- snapshot.timestamp.timeIntervalSince1970,
            colTopicWatermarks <- watermarksJSON,
            colConsumerGroupLags <- lagsJSON,
            colTotalHighWatermark <- snapshot.totalHighWatermark,
            colTotalLag <- snapshot.totalLag,
            colUnderReplicatedPartitions <- Int64(snapshot.underReplicatedPartitions),
            colTotalPartitions <- Int64(snapshot.totalPartitions),
            colBrokerCount <- Int64(snapshot.brokerCount),
            colPingMs <- snapshot.pingMs.map { Int64($0) },
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
            let watermarks = try decoder.decode(
                [String: Int64].self,
                from: row[colTopicWatermarks].data(using: .utf8)!,
            )
            let lags = try decoder.decode(
                [String: Int64].self,
                from: row[colConsumerGroupLags].data(using: .utf8)!,
            )

            results.append(MetricSnapshot(
                id: UUID(uuidString: row[colId])!,
                timestamp: Date(timeIntervalSince1970: row[colTimestamp]),
                topicWatermarks: watermarks,
                consumerGroupLags: lags,
                totalHighWatermark: row[colTotalHighWatermark],
                totalLag: row[colTotalLag],
                underReplicatedPartitions: Int(row[colUnderReplicatedPartitions]),
                totalPartitions: Int(row[colTotalPartitions]),
                brokerCount: Int(row[colBrokerCount]),
                pingMs: row[colPingMs].map { Int($0) },
            ))
        }

        // Return in chronological order (oldest first)
        return results.reversed()
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
