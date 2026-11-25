// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LinedKit",
    platforms: [.iOS("27.0"), .macOS("15.0")],
    products: [
        .library(name: "LinedModel", targets: ["LinedModel"]),
        .library(name: "LinedStorage", targets: ["LinedStorage"]),
    ],
    targets: [
        .target(name: "LinedModel"),
        .target(name: "LinedStorage", dependencies: ["LinedModel"]),
        .testTarget(name: "LinedModelTests", dependencies: ["LinedModel"]),
        .testTarget(name: "LinedStorageTests", dependencies: ["LinedStorage"]),
    ],
    swiftLanguageModes: [.v6]
)
