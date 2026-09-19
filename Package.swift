// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UP",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "UP",
            path: "Sources/UP",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
