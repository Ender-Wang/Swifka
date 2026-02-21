import OSLog

nonisolated enum Log {
    static let kafka = Logger(subsystem: "io.github.ender-wang.Swifka", category: "kafka")
    static let storage = Logger(subsystem: "io.github.ender-wang.Swifka", category: "storage")
    static let decode = Logger(subsystem: "io.github.ender-wang.Swifka", category: "decode")
    static let alerts = Logger(subsystem: "io.github.ender-wang.Swifka", category: "alerts")
    static let app = Logger(subsystem: "io.github.ender-wang.Swifka", category: "app")
    static let updates = Logger(subsystem: "io.github.ender-wang.Swifka", category: "updates")
}
