// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "BoringNotchCodexNotifications",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexNotificationsCore", targets: ["CodexNotificationsCore"])
    ],
    targets: [
        .target(
            name: "CodexNotificationsCore",
            path: "boringNotch/features/CodexNotifications/Core"
        ),
        .testTarget(
            name: "CodexNotificationsCoreTests",
            dependencies: ["CodexNotificationsCore"],
            path: "boringNotchTests"
        )
    ]
)
