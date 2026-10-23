// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "screendock",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "WindowCore"),
        .executableTarget(
            name: "screendock",
            dependencies: ["WindowCore"],
            path: "Sources/screendock"
        ),
        .testTarget(name: "WindowCoreTests", dependencies: ["WindowCore"])
    ]
)
