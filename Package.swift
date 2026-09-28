// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BackgroundCheck",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BackgroundCheckCore"),
        .testTarget(name: "BackgroundCheckCoreTests", dependencies: ["BackgroundCheckCore"]),
    ],
    swiftLanguageModes: [.v5]
)
