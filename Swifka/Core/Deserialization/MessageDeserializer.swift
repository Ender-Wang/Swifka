import Foundation

// MARK: - Deserializer Protocol

/// Protocol for message deserialization
/// Extensible for future formats like Protobuf, Avro, etc.
protocol MessageDeserializer: Identifiable, Sendable {
    /// Unique identifier (e.g., "utf8", "protobuf")
    var id: String { get }

    /// Display name for UI (e.g., "UTF-8", "Protocol Buffers")
    var displayName: String { get }

    /// Whether this deserializer requires configuration (e.g., .proto files)
    var requiresConfiguration: Bool { get }

    /// Deserialize raw bytes into displayable content
    func deserialize(_ data: Data?) -> DeserializedContent

    /// Pretty-format the content (e.g., JSON pretty-print)
    func prettyFormat(_ data: Data?) -> DeserializedContent
}

// MARK: - Deserialized Content

/// Result of deserialization
struct DeserializedContent: Sendable {
    let text: String
    let format: ContentFormat

    enum ContentFormat: Sendable {
        case plainText
        case json
        case binary
    }

    static func plainText(_ text: String) -> DeserializedContent {
        DeserializedContent(text: text, format: .plainText)
    }

    static func json(_ text: String) -> DeserializedContent {
        DeserializedContent(text: text, format: .json)
    }

    static func binary(_ text: String) -> DeserializedContent {
        DeserializedContent(text: text, format: .binary)
    }
}

// MARK: - UTF-8 Deserializer

nonisolated struct UTF8Deserializer: MessageDeserializer {
    let id = "utf8"
    let displayName = "UTF-8"
    let requiresConfiguration = false

    func deserialize(_ data: Data?) -> DeserializedContent {
        guard let data, !data.isEmpty else {
            return data == nil ? .plainText("(null)") : .plainText("(empty)")
        }

        guard let string = String(data: data, encoding: .utf8) else {
            return .plainText("(binary data)")
        }

        return .plainText(string)
    }

    func prettyFormat(_ data: Data?) -> DeserializedContent {
        guard let data, !data.isEmpty else {
            return deserialize(data)
        }

        // Try JSON pretty-printing
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: json,
                  options: [.prettyPrinted, .sortedKeys],
              ),
              let prettyString = String(data: pretty, encoding: .utf8)
        else {
            return deserialize(data)
        }

        return .json(prettyString)
    }
}

// MARK: - Hex Deserializer

nonisolated struct HexDeserializer: MessageDeserializer {
    let id = "hex"
    let displayName = "Hex"
    let requiresConfiguration = false

    func deserialize(_ data: Data?) -> DeserializedContent {
        guard let data, !data.isEmpty else {
            return data == nil ? .binary("(null)") : .binary("(empty)")
        }

        let hexString = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        return .binary(hexString)
    }

    func prettyFormat(_ data: Data?) -> DeserializedContent {
        // Hex doesn't have a "pretty" format
        deserialize(data)
    }
}

// MARK: - Base64 Deserializer

nonisolated struct Base64Deserializer: MessageDeserializer {
    let id = "base64"
    let displayName = "Base64"
    let requiresConfiguration = false

    func deserialize(_ data: Data?) -> DeserializedContent {
        guard let data, !data.isEmpty else {
            return data == nil ? .binary("(null)") : .binary("(empty)")
        }

        let base64String = data.base64EncodedString()
        return .binary(base64String)
    }

    func prettyFormat(_ data: Data?) -> DeserializedContent {
        // Base64 doesn't have a "pretty" format
        deserialize(data)
    }
}

// MARK: - Deserializer Registry

/// Central registry for all available deserializers
@MainActor
@Observable
final class DeserializerRegistry {
    static let shared = DeserializerRegistry()

    private(set) var deserializers: [any MessageDeserializer] = []

    private init() {
        // Register built-in deserializers
        register(UTF8Deserializer())
        register(HexDeserializer())
        register(Base64Deserializer())
        register(ProtobufDeserializer())
    }

    func register(_ deserializer: any MessageDeserializer) {
        deserializers.append(deserializer)
    }

    func deserializer(for id: String) -> (any MessageDeserializer)? {
        deserializers.first { $0.id == id }
    }

    /// Get deserializer for a topic (falls back to default if no topic-specific config)
    func deserializer(for _: String, defaultID: String = "utf8") -> any MessageDeserializer {
        // TODO: Look up per-topic configuration
        // For now, just return default
        deserializer(for: defaultID) ?? UTF8Deserializer()
    }
}
