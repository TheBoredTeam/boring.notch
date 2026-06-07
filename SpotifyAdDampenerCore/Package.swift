// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpotifyAdDampenerCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SpotifyAdDampenerCore", targets: ["SpotifyAdDampenerCore"]),
    ],
    targets: [
        .target(name: "SpotifyAdDampenerCore"),
        .testTarget(name: "SpotifyAdDampenerCoreTests", dependencies: ["SpotifyAdDampenerCore"]),
    ]
)
