// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TypeSpeak",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TypeSpeak",
            path: "Sources/TypeSpeak"
        )
    ]
)
