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
            name: "CodexHookTrustState",
            path: "BoringNotchXPCHelper",
            sources: ["CodexHookTrustState.swift"]
        ),
        .target(
            name: "CodexHookSupport",
            path: "BoringNotchXPCHelper",
            sources: ["CodexHookAuthenticator.swift", "CodexHookConfiguration.swift"]
        ),
        .target(
            name: "CodexNotificationsCore",
            path: "boringNotch/features/CodexNotifications/Core"
        ),
        .testTarget(
            name: "CodexNotificationsCoreTests",
            dependencies: [
                "CodexNotificationsCore",
                "CodexHookSupport",
                "CodexHookTrustState",
            ],
            path: "boringNotchTests"
        )
    ]
)
