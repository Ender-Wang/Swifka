import Foundation
import OSLog

/// Handles full data backup export (ZIP) and import for Swifka.
enum BackupManager {
    /// The Swifka data directory: ~/Library/Application Support/Swifka/
    private static var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Constants.configDirectory)
    }

    /// Parsed contents of a backup ZIP, ready for smart import.
    struct BackupContents {
        let clusters: [ClusterConfig]
        let protoFiles: [ProtoFileInfo]
        let deserializerConfigs: [TopicDeserializerConfig]
        let hasMetricsDB: Bool
    }

    /// Matches the on-disk proto_index.json format (metadata only, no filePath/content).
    private struct ProtoIndexEntry: Codable {
        let id: UUID
        let clusterID: UUID
        let fileName: String
        let messageTypes: [String]
        let importedAt: Date
    }

    // MARK: - Export

    /// Export all Swifka data as a ZIP archive.
    static func exportBackup(metricDatabase: MetricDatabase?) async throws -> Data {
        // Checkpoint the metrics DB to merge WAL into the main file
        if let db = metricDatabase {
            try await db.checkpoint()
        }

        var files: [(path: String, data: Data)] = []
        let dir = dataDirectory
        let fm = FileManager.default

        // clusters.json
        let clustersFile = dir.appendingPathComponent(Constants.configFileName)
        if let data = fm.contents(atPath: clustersFile.path) {
            files.append((Constants.configFileName, data))
        }

        // metrics.sqlite3
        let metricsFile = dir.appendingPathComponent(Constants.metricsDatabaseFileName)
        if let data = fm.contents(atPath: metricsFile.path) {
            files.append((Constants.metricsDatabaseFileName, data))
        }

        // proto_index.json
        let protoIndex = dir.appendingPathComponent(Constants.protoIndexFileName)
        if let data = fm.contents(atPath: protoIndex.path) {
            files.append((Constants.protoIndexFileName, data))
        }

        // protos/*.proto
        let protosDir = dir.appendingPathComponent(Constants.protosDirectory)
        if let protoFiles = try? fm.contentsOfDirectory(atPath: protosDir.path) {
            for filename in protoFiles where filename.hasSuffix(".proto") {
                let filePath = protosDir.appendingPathComponent(filename)
                if let data = fm.contents(atPath: filePath.path) {
                    files.append(("\(Constants.protosDirectory)/\(filename)", data))
                }
            }
        }

        // deserializer_configs.json (from UserDefaults)
        if let data = UserDefaults.standard.data(forKey: "topic_deserializer_configs") {
            files.append(("deserializer_configs.json", data))
        }

        Log.storage.info("[BackupManager] export: \(files.count) files archived")
        return MiniZIP.archive(files)
    }

    // MARK: - Import

    /// Parse a backup ZIP and return its contents for smart import.
    /// Also replaces the metrics database on disk (requires restart).
    static func importBackup(from data: Data) throws -> BackupContents {
        let files = try MiniZIP.extract(data)
        let dir = dataDirectory
        let fm = FileManager.default

        // Ensure data directory exists
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        var clusters: [ClusterConfig] = []
        var protoFiles: [ProtoFileInfo] = []
        var deserializerConfigs: [TopicDeserializerConfig] = []
        var hasMetricsDB = false

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for (path, fileData) in files {
            switch path {
            case Constants.configFileName:
                // Parse clusters — don't write to disk, let ConfigStore handle it
                clusters = (try? decoder.decode([ClusterConfig].self, from: fileData)) ?? []

            case Constants.metricsDatabaseFileName:
                // Replace metrics DB on disk (requires restart to take effect)
                hasMetricsDB = true
                Log.storage.info("[BackupManager] import: metrics database replaced on disk")
                let walFile = dir.appendingPathComponent(Constants.metricsDatabaseFileName + "-wal")
                let shmFile = dir.appendingPathComponent(Constants.metricsDatabaseFileName + "-shm")
                try? fm.removeItem(at: walFile)
                try? fm.removeItem(at: shmFile)
                let dest = dir.appendingPathComponent(path)
                try fileData.write(to: dest, options: .atomic)

            case Constants.protoIndexFileName:
                // Parse proto index metadata — proto_index.json stores metadata-only entries
                // (no filePath or content), so decode as ProtoIndexEntry, not ProtoFileInfo.
                if let index = try? decoder.decode([ProtoIndexEntry].self, from: fileData) {
                    // Build lookup from ZIP proto file paths to their content
                    let protoFileContents = Dictionary(
                        uniqueKeysWithValues: files
                            .filter { $0.path.hasPrefix("\(Constants.protosDirectory)/") }
                            .map { ($0.path, $0.data) },
                    )
                    protoFiles = index.compactMap { meta in
                        // Proto files are stored as <uuid>_<fileName> in the protos/ directory
                        let expectedFileName = "\(meta.id.uuidString)_\(meta.fileName)"
                        let zipPath = "\(Constants.protosDirectory)/\(expectedFileName)"
                        guard let content = protoFileContents[zipPath],
                              let contentStr = String(data: content, encoding: .utf8)
                        else { return nil }
                        return ProtoFileInfo(
                            id: meta.id,
                            clusterID: meta.clusterID,
                            fileName: meta.fileName,
                            filePath: zipPath,
                            content: contentStr,
                            messageTypes: meta.messageTypes,
                            importedAt: meta.importedAt,
                        )
                    }
                }

            case "deserializer_configs.json":
                deserializerConfigs = (try? JSONDecoder().decode(
                    [TopicDeserializerConfig].self, from: fileData,
                )) ?? []

            default:
                // Proto files are handled via the index above
                break
            }
        }

        Log.storage.info("[BackupManager] import: \(clusters.count) clusters, \(protoFiles.count) proto files, metricsDB=\(hasMetricsDB)")
        return BackupContents(
            clusters: clusters,
            protoFiles: protoFiles,
            deserializerConfigs: deserializerConfigs,
            hasMetricsDB: hasMetricsDB,
        )
    }
}
