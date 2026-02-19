import Foundation

// MARK: - Per-Topic Deserializer Configuration

/// Configuration for deserializing messages in a specific topic
struct TopicDeserializerConfig: Codable, Identifiable, Sendable {
    let id: UUID
    let topicName: String
    let keyDeserializerID: String
    let valueDeserializerID: String

    // Protobuf-specific configuration (future)
    var protoFilePath: String?
    var messageTypeName: String?

    // Avro-specific configuration (future)
    var schemaRegistryURL: String?
    var schemaID: Int?

    // Decryption configuration (future)
    var requiresDecryption: Bool = false
    var decryptionKeyID: String?

    init(
        id: UUID = UUID(),
        topicName: String,
        keyDeserializerID: String = "utf8",
        valueDeserializerID: String = "utf8",
        protoFilePath: String? = nil,
        messageTypeName: String? = nil,
    ) {
        self.id = id
        self.topicName = topicName
        self.keyDeserializerID = keyDeserializerID
        self.valueDeserializerID = valueDeserializerID
        self.protoFilePath = protoFilePath
        self.messageTypeName = messageTypeName
    }
}

// MARK: - Deserializer Configuration Store

/// Manages per-topic deserializer configurations
@MainActor
@Observable
final class DeserializerConfigStore {
    static let shared = DeserializerConfigStore()

    private(set) var configs: [TopicDeserializerConfig] = []

    private let storageKey = "topic_deserializer_configs"

    private init() {
        load()
    }

    func config(for topicName: String) -> TopicDeserializerConfig? {
        configs.first { $0.topicName == topicName }
    }

    func setConfig(_ config: TopicDeserializerConfig) {
        if let index = configs.firstIndex(where: { $0.topicName == config.topicName }) {
            configs[index] = config
        } else {
            configs.append(config)
        }
        save()
    }

    func removeConfig(for topicName: String) {
        configs.removeAll { $0.topicName == topicName }
        save()
    }

    /// Import configs from cluster export, remapping proto file paths to new managed locations.
    /// Only imports configs whose topic name doesn't already have a local config.
    func importConfigs(_ imported: [TopicDeserializerConfig], protoPathMap: [String: String]) {
        for config in imported {
            // Skip if a config for this topic already exists locally
            guard !configs.contains(where: { $0.topicName == config.topicName }) else { continue }

            let remapped = TopicDeserializerConfig(
                topicName: config.topicName,
                keyDeserializerID: config.keyDeserializerID,
                valueDeserializerID: config.valueDeserializerID,
                protoFilePath: config.protoFilePath.flatMap { protoPathMap[$0] } ?? config.protoFilePath,
                messageTypeName: config.messageTypeName,
            )
            configs.append(remapped)
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let loaded = try? JSONDecoder().decode([TopicDeserializerConfig].self, from: data)
        else { return }
        configs = loaded
    }
}
