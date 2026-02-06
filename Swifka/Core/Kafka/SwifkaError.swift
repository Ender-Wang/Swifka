import Foundation

nonisolated enum SwifkaError: LocalizedError, Sendable {
    case notConnected
    case connectionFailed(String)
    case metadataFailed(String)
    case watermarkFailed(String)
    case consumerGroupsFailed(String)
    case messageFetchFailed(String)
    case configSaveFailed(String)
    case configLoadFailed(String)
    case keychainError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Not connected to Kafka cluster"
        case let .connectionFailed(msg):
            "Connection failed: \(msg)"
        case let .metadataFailed(msg):
            "Metadata fetch failed: \(msg)"
        case let .watermarkFailed(msg):
            "Watermark fetch failed: \(msg)"
        case let .consumerGroupsFailed(msg):
            "Consumer groups fetch failed: \(msg)"
        case let .messageFetchFailed(msg):
            "Message fetch failed: \(msg)"
        case let .configSaveFailed(msg):
            "Config save failed: \(msg)"
        case let .configLoadFailed(msg):
            "Config load failed: \(msg)"
        case let .keychainError(msg):
            "Keychain error: \(msg)"
        case let .unknown(msg):
            "Unknown error: \(msg)"
        }
    }
}
