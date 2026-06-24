// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Narrator",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Narrator",
            path: "Sources/Narrator"
        )
    ]
)
