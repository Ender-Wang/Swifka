import Foundation

@Observable
final class ConfigStore {
    var clusters: [ClusterConfig] = []
    var selectedClusterId: UUID? {
        didSet {
            if let id = selectedClusterId {
                UserDefaults.standard.set(id.uuidString, forKey: "configStore.selectedClusterId")
            } else {
                UserDefaults.standard.removeObject(forKey: "configStore.selectedClusterId")
            }
        }
    }

    var selectedCluster: ClusterConfig? {
        clusters.first { $0.id == selectedClusterId }
    }

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first!
        let dir = appSupport.appendingPathComponent(Constants.configDirectory)
        fileURL = dir.appendingPathComponent(Constants.configFileName)

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - CRUD

    func addCluster(_ cluster: ClusterConfig) {
        clusters.append(cluster)
        if selectedClusterId == nil {
            selectedClusterId = cluster.id
        }
        save()
    }

    func updateCluster(_ cluster: ClusterConfig) {
        if let index = clusters.firstIndex(where: { $0.id == cluster.id }) {
            var updated = cluster
            updated.updatedAt = Date()
            clusters[index] = updated
            save()
        }
    }

    func deleteCluster(_ id: UUID) {
        clusters.removeAll { $0.id == id }
        if selectedClusterId == id {
            selectedClusterId = clusters.first?.id
        }
        save()
    }

    func togglePin(for clusterId: UUID) {
        if let index = clusters.firstIndex(where: { $0.id == clusterId }) {
            clusters[index].isPinned.toggle()
            save()
        }
    }

    func updateLastConnected(for clusterId: UUID) {
        if let index = clusters.firstIndex(where: { $0.id == clusterId }) {
            clusters[index].lastConnectedAt = Date()
            save()
        }
    }

    // MARK: - Persistence

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(clusters)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("ConfigStore: Failed to save: \(error)")
        }
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            clusters = try decoder.decode([ClusterConfig].self, from: data)
            if let savedId = UserDefaults.standard.string(forKey: "configStore.selectedClusterId"),
               let uuid = UUID(uuidString: savedId),
               clusters.contains(where: { $0.id == uuid })
            {
                selectedClusterId = uuid
            } else {
                selectedClusterId = clusters.first?.id
            }
        } catch {
            print("ConfigStore: Failed to load: \(error)")
        }
    }

    // MARK: - Import/Export

    func exportConfig() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return try? encoder.encode(clusters)
    }

    static func exportClusters(_ clusters: [ClusterConfig]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return try? encoder.encode(clusters)
    }

    func importSelectedClusters(_ selectedClusters: [ClusterConfig]) throws {
        // Assign new UUIDs to avoid conflicts with existing clusters
        let withNewIds = selectedClusters.map { cluster in
            ClusterConfig(
                id: UUID(), // Generate new UUID
                name: cluster.name,
                host: cluster.host,
                port: cluster.port,
                authType: cluster.authType,
                saslMechanism: cluster.saslMechanism,
                saslUsername: cluster.saslUsername,
                useTLS: cluster.useTLS,
                createdAt: Date(), // Reset creation time
                updatedAt: Date(),
                isPinned: false, // Don't import pin status
                lastConnectedAt: nil, // Reset last connected
                sortOrder: 0,
            )
        }

        clusters.append(contentsOf: withNewIds)
        save()
    }

    func importConfig(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode([ClusterConfig].self, from: data)

        // Assign new UUIDs to avoid conflicts with existing clusters
        let withNewIds = imported.map { cluster in
            ClusterConfig(
                id: UUID(), // Generate new UUID
                name: cluster.name,
                host: cluster.host,
                port: cluster.port,
                authType: cluster.authType,
                saslMechanism: cluster.saslMechanism,
                saslUsername: cluster.saslUsername,
                useTLS: cluster.useTLS,
                createdAt: Date(), // Reset creation time
                updatedAt: Date(),
                isPinned: false, // Don't import pin status
                lastConnectedAt: nil, // Reset last connected
                sortOrder: 0,
            )
        }

        clusters.append(contentsOf: withNewIds)
        save()
    }
}
