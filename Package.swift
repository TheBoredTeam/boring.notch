// swift-tools-version: 5.9

import PackageDescription

// A focused, dependency-free test seam for the activity host and package loader.
// The application itself continues to build with boringNotch.xcodeproj.
let package = Package(
    name: "BoringNotchActivityHost",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "boringNotch",
            path: "boringNotch/components/LiveActivities",
            exclude: ["BoringBattery.swift", "MarqueeTextView.swift", "BuiltinLiveActivitySource.swift",
                      "BuiltinLiveActivityViews.swift", "Extensions/ExtensionManager.swift"],
            sources: ["Core", "LiveActivityCenter.swift", "NotchActivityHost.swift", "NotchActivityLayoutMetrics.swift",
                      "Extensions/ExtensionActivity.swift", "Extensions/ExtensionActivityDescriptor.swift",
                      "Extensions/ExtensionArchive.swift", "Extensions/ExtensionInstallation.swift",
                      "Extensions/ExtensionPackage.swift", "Extensions/ExtensionRuntime.swift",
                      "Extensions/ExtensionCatalog.swift", "Extensions/ExtensionStore.swift",
                      "Extensions/ExtensionStoreTransfer.swift"]
        ),
        .testTarget(
            name: "ActivityHostTests",
            dependencies: ["boringNotch"],
            path: "boringNotchTests",
            exclude: ["BundleIDResolverTests.swift", "CalendarBoundaryTests.swift", "CameraLifecycleTests.swift",
                      "MeetingLinkDetectorTests.swift", "NotchUIEventTests.swift", "NotificationPanelDetectionTests.swift",
                      "NowPlayingAvailabilityTests.swift", "OTPDetectorTests.swift", "PearWebSocketRequestTests.swift",
                      "PreferenceCompatibilityTests.swift"],
            sources: ["LiveActivityServiceTests.swift", "NotchActivityLayoutTests.swift", "ExtensionArchiveTests.swift",
                      "ExtensionPackageTests.swift", "ExtensionActivityDescriptorTests.swift", "LiveActivityCenterTests.swift",
                      "ExtensionCatalogTests.swift", "ExtensionStoreTransferTests.swift"]
        )
    ]
)
