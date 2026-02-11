import Foundation

nonisolated enum Constants {
    static let defaultWindowWidth: CGFloat = 1100
    static let defaultWindowHeight: CGFloat = 700
    static let minWindowWidth: CGFloat = 756
    static let minWindowHeight: CGFloat = 420 // 472 - 52 (toolbar height)
    static let sidebarMinWidth: CGFloat = 200

    static let kafkaTimeout: Int32 = 10000 // 10 seconds
    static let defaultMaxMessages: Int = 100
    static let defaultFetchTimeout: Int32 = 1000 // 1 second

    static let configDirectory = "Swifka"
    static let configFileName = "clusters.json"

    static let keychainService = "io.github.ender-wang.Swifka"
}
