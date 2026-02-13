import Foundation

nonisolated enum DataRetentionPolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    case oneDay = "1d"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case ninetyDays = "90d"
    case unlimited

    var id: String {
        rawValue
    }

    var cutoffDate: Date? {
        let days: Int? = switch self {
        case .oneDay: 1
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .unlimited: nil
        }
        guard let days else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: Date())
    }
}
