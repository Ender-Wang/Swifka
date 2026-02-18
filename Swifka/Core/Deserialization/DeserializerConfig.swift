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
