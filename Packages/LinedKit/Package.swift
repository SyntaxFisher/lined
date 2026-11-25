// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LinedKit",
    platforms: [.iOS("27.0"), .macOS("15.0")],
    products: [
        .library(name: "LinedModel", targets: ["LinedModel"]),
    ],
    targets: [
        .target(name: "LinedModel"),
        .testTarget(name: "LinedModelTests", dependencies: ["LinedModel"]),
    ],
    swiftLanguageModes: [.v6]
)
