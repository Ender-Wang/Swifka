// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Swifka",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SwifkaExplorer", targets: ["SwifkaExplorer"])
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/swift-kafka-client", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "SwifkaExplorer",
            dependencies: [
                .product(name: "Kafka", package: "swift-kafka-client")
            ]
        )
    ]
)
