// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MirNavigation",
    products: [.library(name: "MirNavigation", targets: ["MirNavigation"])],
    targets: [
        .target(name: "MirNavigation", path: "Sources/Core"),
        .testTarget(name: "MirNavigationTests", dependencies: ["MirNavigation"], path: "Tests")
    ]
)
