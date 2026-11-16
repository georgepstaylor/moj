// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "moj",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "moj",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/moj",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // build.sh copies Sparkle.framework into moj.app/Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ]
)
