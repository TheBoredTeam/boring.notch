// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "BoringNotchCodexNotifications",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexNotificationsCore", targets: ["CodexNotificationsCore"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/gonzalezreal/swift-markdown-ui",
            exact: "2.4.1"
        ),
        .package(url: "https://github.com/swiftlang/swift-cmark", exact: "0.9.0"),
        .package(url: "https://github.com/colinc86/MathJaxSwift", exact: "3.5.0"),
        .package(url: "https://github.com/swhitty/SwiftDraw", exact: "0.29.0")
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
        .target(
            name: "CodexReplySupport",
            path: "boringNotch/features/CodexNotifications",
            exclude: [
                "Core", "Rendering", "CodexNotificationManager.swift",
                "CodexResponseDetailView.swift", "CodexPermissionRelay.swift", "CodexNotificationExtension.swift"
            ],
            sources: ["CodexReplyTransport.swift", "CodexReplyOutcome.swift"]
        ),
        .target(
            name: "CodexResponseRendering",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
                .product(name: "MathJaxSwift", package: "MathJaxSwift"),
                .product(name: "SwiftDraw", package: "SwiftDraw"),
            ],
            path: "boringNotch/features/CodexNotifications/Rendering"
        ),
        .testTarget(
            name: "CodexNotificationsCoreTests",
            dependencies: [
                "CodexNotificationsCore",
                "CodexHookSupport",
                "CodexHookTrustState",
                "CodexResponseRendering",
                "CodexReplySupport",
            ],
            path: "boringNotchTests"
        )
    ]
)
