// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "moj",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "moj",
            path: "Sources/moj",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
