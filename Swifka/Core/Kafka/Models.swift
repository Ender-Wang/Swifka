import Foundation
import SwiftUI

// MARK: - Cluster Configuration

nonisolated struct ClusterConfig: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var bootstrapServers: String
    var authType: AuthType
    var saslMechanism: SASLMechanism?
    var saslUsername: String?
    var useTLS: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        bootstrapServers: String,
        authType: AuthType = .none,
        saslMechanism: SASLMechanism? = nil,
        saslUsername: String? = nil,
        useTLS: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
    ) {
        self.id = id
        self.name = name
        self.bootstrapServers = bootstrapServers
        self.authType = authType
        self.saslMechanism = saslMechanism
        self.saslUsername = saslUsername
        self.useTLS = useTLS
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
    let id: UUID
    let topic: String
    let partition: Int32
    let offset: Int64
    let key: Data?
    let value: Data?
    let timestamp: Date?
    let headers: [(String, Data)]

    init(
        id: UUID = UUID(),
        topic: String,
        partition: Int32,
        offset: Int64,
        key: Data? = nil,
        value: Data? = nil,
        timestamp: Date? = nil,
        headers: [(String, Data)] = [],
    ) {
        self.id = id
        self.topic = topic
        self.partition = partition
        self.offset = offset
        self.key = key
        self.value = value
        self.timestamp = timestamp
        self.headers = headers
    }

    func keyString(format: MessageFormat) -> String {
        formatData(key, format: format)
    }

    func valueString(format: MessageFormat) -> String {
        formatData(value, format: format)
    }

    func keyPrettyString(format: MessageFormat) -> String {
        prettyFormatData(key, format: format)
    }

    func valuePrettyString(format: MessageFormat) -> String {
        prettyFormatData(value, format: format)
    }

    private func formatData(_ data: Data?, format: MessageFormat) -> String {
        guard let data else { return "(null)" }
        if data.isEmpty { return "(empty)" }
        switch format {
        case .utf8:
            return String(data: data, encoding: .utf8) ?? "(binary data)"
        case .hex:
            return data.map { String(format: "%02x", $0) }.joined(separator: " ")
        case .base64:
            return data.base64EncodedString()
        }
    }

    private func prettyFormatData(_ data: Data?, format: MessageFormat) -> String {
        guard format == .utf8, let data, !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: pretty, encoding: .utf8)
        else {
            return formatData(data, format: format)
        }
        return prettyString
    }
}

nonisolated enum MessageFormat: String, CaseIterable, Identifiable, Sendable {
    case utf8 = "UTF-8"
    case hex = "Hex"
    case base64 = "Base64"

    var id: String {
        rawValue
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
}

// MARK: - Settings

nonisolated enum OperationLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case readonly
    case write
    case admin
    case dangerous

    var id: String {
        rawValue
    }

    var isAvailable: Bool {
        self == .readonly
    }
}

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
    case topics
    case messages
    case consumerGroups
    case brokers
    case settings
}
