// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "screendock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "screendock",
            path: "Sources/screendock"
        )
    ]
)
