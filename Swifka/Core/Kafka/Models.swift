import Foundation
import SwiftUI

// MARK: - Cluster Configuration

nonisolated struct ClusterConfig: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var authType: AuthType
    var saslMechanism: SASLMechanism?
    var saslUsername: String?
    var useTLS: Bool
    var createdAt: Date
    var updatedAt: Date

    /// Schema Registry (optional)
    var schemaRegistryURL: String? = nil

    // Cluster manager enhancements
    var isPinned: Bool = false
    var lastConnectedAt: Date? = nil
    var sortOrder: Int = 0

    /// Computed property for compatibility
    var bootstrapServers: String {
        "\(host):\(port)"
    }

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int,
        authType: AuthType = .none,
        saslMechanism: SASLMechanism? = nil,
        saslUsername: String? = nil,
        useTLS: Bool = false,
        schemaRegistryURL: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        lastConnectedAt: Date? = nil,
        sortOrder: Int = 0,
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.authType = authType
        self.saslMechanism = saslMechanism
        self.saslUsername = saslUsername
        self.useTLS = useTLS
        self.schemaRegistryURL = schemaRegistryURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.lastConnectedAt = lastConnectedAt
        self.sortOrder = sortOrder
    }

    /// Custom decoding to handle migration from old bootstrapServers format
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        // Try new format first (host + port)
        if let host = try? container.decode(String.self, forKey: .host),
           let port = try? container.decode(Int.self, forKey: .port)
        {
            self.host = host
            self.port = port
        } else {
            // Fall back to old format (bootstrapServers)
            let bootstrapServers = try container.decode(String.self, forKey: .bootstrapServers)
            let parts = bootstrapServers.split(separator: ":")
            if parts.count == 2, let portNum = Int(parts[1]) {
                host = String(parts[0])
                port = portNum
            } else {
                host = bootstrapServers
                port = 9092
            }
        }

        authType = try container.decode(AuthType.self, forKey: .authType)
        saslMechanism = try container.decodeIfPresent(SASLMechanism.self, forKey: .saslMechanism)
        saslUsername = try container.decodeIfPresent(String.self, forKey: .saslUsername)
        useTLS = try container.decode(Bool.self, forKey: .useTLS)
        schemaRegistryURL = try container.decodeIfPresent(String.self, forKey: .schemaRegistryURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    /// Custom encoding to use new host + port format
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(authType, forKey: .authType)
        try container.encodeIfPresent(saslMechanism, forKey: .saslMechanism)
        try container.encodeIfPresent(saslUsername, forKey: .saslUsername)
        try container.encode(useTLS, forKey: .useTLS)
        try container.encodeIfPresent(schemaRegistryURL, forKey: .schemaRegistryURL)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(lastConnectedAt, forKey: .lastConnectedAt)
        try container.encode(sortOrder, forKey: .sortOrder)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, host, port, bootstrapServers, authType, saslMechanism, saslUsername, useTLS
        case schemaRegistryURL, createdAt, updatedAt, isPinned, lastConnectedAt, sortOrder
    }
}

nonisolated enum AuthType: String, Codable, CaseIterable, Sendable {
    case none
    case sasl
}

nonisolated enum SASLMechanism: String, Codable, CaseIterable, Sendable {
    case plain = "PLAIN"
    case scramSHA256 = "SCRAM-SHA-256"
    case scramSHA512 = "SCRAM-SHA-512"
}

// MARK: - Connection Status

nonisolated enum ConnectionStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - Broker Info

nonisolated struct BrokerInfo: Identifiable, Hashable, Sendable {
    let id: Int32
    let host: String
    let port: Int32
}

/// Statistics for a broker derived from partition metadata.
nonisolated struct BrokerStats: Identifiable, Hashable, Sendable {
    let id: Int32
    let host: String
    let port: Int32
    let leaderCount: Int
    let replicaCount: Int

    var hostPort: String {
        "\(host):\(port)"
    }
}

// MARK: - Topic Info

nonisolated struct TopicInfo: Identifiable, Hashable, Sendable {
    var id: String {
        name
    }

    let name: String
    let partitions: [PartitionInfo]

    var partitionCount: Int {
        partitions.count
    }

    var replicaCount: Int {
        partitions.first?.replicas.count ?? 0
    }

    var isInternal: Bool {
        name.hasPrefix("__")
    }
}

nonisolated struct PartitionInfo: Identifiable, Hashable, Sendable {
    var id: Int32 {
        partitionId
    }

    let partitionId: Int32
    let leader: Int32
    let replicas: [Int32]
    let isr: [Int32]
    var lowWatermark: Int64?
    var highWatermark: Int64?

    var messageCount: Int64? {
        guard let low = lowWatermark, let high = highWatermark else { return nil }
        return max(0, high - low)
    }
}

// MARK: - Kafka Message

nonisolated struct KafkaMessageRecord: Identifiable, Sendable {
    var id: String {
        "\(partition)-\(offset)"
    }

    let topic: String
    let partition: Int32
    let offset: Int64
    let key: Data?
    let value: Data?
    let timestamp: Date?
    let headers: [(String, Data)]

    init(
        topic: String,
        partition: Int32,
        offset: Int64,
        key: Data? = nil,
        value: Data? = nil,
        timestamp: Date? = nil,
        headers: [(String, Data)] = [],
    ) {
        self.topic = topic
        self.partition = partition
        self.offset = offset
        self.key = key
        self.value = value
        self.timestamp = timestamp
        self.headers = headers
    }

    func keyString(format: MessageFormat, protoContext: ProtobufContext? = nil) -> String {
        formatData(key, format: format, protoContext: protoContext)
    }

    func valueString(format: MessageFormat, protoContext: ProtobufContext? = nil) -> String {
        formatData(value, format: format, protoContext: protoContext)
    }

    func keyPrettyString(format: MessageFormat, protoContext: ProtobufContext? = nil) -> String {
        prettyFormatData(key, format: format, protoContext: protoContext)
    }

    func valuePrettyString(format: MessageFormat, protoContext: ProtobufContext? = nil) -> String {
        prettyFormatData(value, format: format, protoContext: protoContext)
    }

    private func formatData(_ data: Data?, format: MessageFormat, protoContext: ProtobufContext? = nil) -> String {
        guard let data else { return "(null)" }
        if data.isEmpty { return "(empty)" }
        switch format {
        case .utf8:
            return String(data: data, encoding: .utf8) ?? "(binary data)"
        case .hex:
            return data.map { String(format: "%02x", $0) }.joined(separator: " ")
        case .base64:
            return data.base64EncodedString()
        case .protobuf:
            guard let ctx = protoContext else {
                return "(protobuf - not configured)"
            }
            do {
                var decoder = ProtobufWireDecoder(data: data)
                let fields = try decoder.decodeFields()
                return ProtobufDeserializer.formatFlatWithSchema(fields, schema: ctx.schema, messageType: ctx.messageTypeName)
            } catch {
                return "(protobuf decode error: \(error.localizedDescription))"
            }
        }
    }

    private func prettyFormatData(_ data: Data?, format: MessageFormat, protoContext: ProtobufContext? = nil) -> String {
        if format == .protobuf {
            guard let data, !data.isEmpty else { return formatData(data, format: format, protoContext: protoContext) }
            guard let ctx = protoContext else {
                return "(protobuf - not configured)"
            }
            do {
                var decoder = ProtobufWireDecoder(data: data)
                let fields = try decoder.decodeFields()
                return ProtobufDeserializer.formatPrettyWithSchema(fields, schema: ctx.schema, messageType: ctx.messageTypeName)
            } catch {
                return "(protobuf decode error: \(error.localizedDescription))"
            }
        }
        // UTF-8 supports pretty printing (JSON formatting)
        guard format == .utf8, let data, !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: pretty, encoding: .utf8)
        else {
            return formatData(data, format: format, protoContext: protoContext)
        }
        return prettyString
    }

    // MARK: - New Deserializer-based API

    /// Deserialize key using the new protocol-based system
    @MainActor
    func deserializeKey(using deserializer: any MessageDeserializer) -> DeserializedContent {
        deserializer.deserialize(key)
    }

    /// Deserialize value using the new protocol-based system
    @MainActor
    func deserializeValue(using deserializer: any MessageDeserializer) -> DeserializedContent {
        deserializer.deserialize(value)
    }

    /// Pretty-format key using the new protocol-based system
    @MainActor
    func prettyDeserializeKey(using deserializer: any MessageDeserializer) -> DeserializedContent {
        deserializer.prettyFormat(key)
    }

    /// Pretty-format value using the new protocol-based system
    @MainActor
    func prettyDeserializeValue(using deserializer: any MessageDeserializer) -> DeserializedContent {
        deserializer.prettyFormat(value)
    }
}

nonisolated enum MessageFormat: String, CaseIterable, Identifiable, Sendable {
    case utf8 = "UTF-8"
    case hex = "Hex"
    case base64 = "Base64"
    case protobuf = "Protobuf"

    var id: String {
        rawValue
    }

    /// Bridge to new deserializer system
    @MainActor
    var deserializer: any MessageDeserializer {
        switch self {
        case .utf8:
            UTF8Deserializer()
        case .hex:
            HexDeserializer()
        case .base64:
            Base64Deserializer()
        case .protobuf:
            ProtobufDeserializer()
        }
    }

    /// Get deserializer ID for registry lookup
    var deserializerID: String {
        switch self {
        case .utf8: "utf8"
        case .hex: "hex"
        case .base64: "base64"
        case .protobuf: "protobuf"
        }
    }
}

// MARK: - Consumer Group

nonisolated struct ConsumerGroupInfo: Identifiable, Hashable, Sendable {
    var id: String {
        name
    }

    let name: String
    let state: String
    let protocolType: String
    let `protocol`: String
    let members: [GroupMemberInfo]
}

nonisolated struct GroupMemberInfo: Identifiable, Hashable, Sendable {
    var id: String {
        memberId
    }

    let memberId: String
    let clientId: String
    let clientHost: String
    /// Partition assignments decoded from the Kafka consumer protocol `member_assignment` blob.
    let assignments: [PartitionAssignment]
}

/// A topic + partition list assigned to a consumer group member.
nonisolated struct PartitionAssignment: Hashable, Sendable {
    let topic: String
    let partitions: [Int32]
}

/// Per-partition lag for a single consumer group.
nonisolated struct PartitionLag: Identifiable, Sendable {
    let topic: String
    let partition: Int32
    let committedOffset: Int64
    let highWatermark: Int64
    let lag: Int64

    var id: String {
        "\(topic)-\(partition)"
    }
}

// MARK: - Settings

nonisolated enum RefreshMode: Codable, Hashable, Identifiable, Sendable {
    case manual
    case interval(Int)

    var id: String {
        switch self {
        case .manual: "manual"
        case let .interval(seconds): "interval-\(seconds)"
        }
    }

    static let presets: [RefreshMode] = [
        .manual,
        .interval(1),
        .interval(3),
        .interval(5),
        .interval(10),
        .interval(15),
        .interval(30),
        .interval(45),
        .interval(60),
    ]
}

// MARK: - Row Density

nonisolated enum RowDensity: String, CaseIterable, Identifiable, Sendable {
    case compact
    case regular
    case large

    var id: String {
        rawValue
    }

    var tablePadding: CGFloat {
        switch self {
        case .compact: 2
        case .regular: 4
        case .large: 8
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .compact: 12
        case .regular: 13
        case .large: 15
        }
    }

    var captionSize: CGFloat {
        switch self {
        case .compact: 10
        case .regular: 11
        case .large: 13
        }
    }

    var gridSpacing: CGFloat {
        switch self {
        case .compact: 4
        case .regular: 6
        case .large: 10
        }
    }

    var rowHeight: CGFloat {
        switch self {
        case .compact: 22
        case .regular: 28
        case .large: 38
        }
    }
}

// MARK: - Appearance

nonisolated enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Navigation

nonisolated enum SidebarItem: String, Hashable, Sendable {
    case dashboard
    case trends
    case lag
    case topics
    case messages
    case schemaRegistry
    case consumerGroups
    case brokers
    case clusters
    case settings
}

// MARK: - ISR Alerts

nonisolated enum ISRAlertSeverity: Int, Comparable, Sendable {
    case warning = 0 // Under-replicated (ISR < replicas but ISR > 1)
    case critical = 1 // ISR = 1 (single point of failure)
    case danger = 2 // ISR < min.insync.replicas

    nonisolated static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated struct ISRAlertDetail: Equatable, Sendable {
    let topic: String
    let partition: Int32
    let isrCount: Int
    let replicaCount: Int
    let severity: ISRAlertSeverity
}

nonisolated struct ISRAlertState: Equatable, Sendable {
    let severity: ISRAlertSeverity
    let timestamp: Date
    let affectedPartitions: [ISRAlertDetail]
    let totalPartitions: Int
    let underReplicatedCount: Int
    let criticalCount: Int // ISR = 1
    let belowMinISRCount: Int // ISR < min.insync.replicas
}
