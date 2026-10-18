// swift-tools-version: 5.9
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.


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
            exclude: ["BoringBattery.swift", "LiveActivityModifier.swift", "MarqueeTextView.swift"],
            sources: ["Core/LiveActivityModel.swift", "Core/LiveActivityScheduler.swift", "Core/LiveActivitySelectionPolicy.swift", "Core/LiveActivityService.swift", "Core/NotchWorkspaceLayout.swift", "LiveActivityCenter.swift", "NotchActivityHost.swift", "NotchActivityLayoutMetrics.swift", "LockedLiveActivityView.swift", "Extensions/ExtensionActivity.swift", "Extensions/ExtensionActivityDescriptor.swift", "Extensions/ExtensionArchive.swift", "Extensions/ExtensionInstallation.swift", "Extensions/ExtensionPackage.swift", "Extensions/ExtensionRuntime.swift", "Extensions/ExtensionTabDescriptor.swift", "Extensions/ExtensionTabRegistry.swift", "Extensions/ExtensionTab.swift", "Extensions/ExtensionCatalog.swift", "Extensions/ExtensionStore.swift", "Extensions/ExtensionStoreTransfer.swift"]
        ),
        .testTarget(
            name: "ActivityHostTests",
            dependencies: ["boringNotch"],
            path: "boringNotchTests",
            exclude: ["BundleIDResolverTests.swift", "CalendarBoundaryTests.swift", "CameraLifecycleTests.swift", "MeetingLinkDetectorTests.swift", "NotchUIEventTests.swift", "NotificationPanelDetectionTests.swift", "NowPlayingAvailabilityTests.swift", "OTPDetectorTests.swift", "PearWebSocketRequestTests.swift", "PreferenceCompatibilityTests.swift"],
            sources: ["LiveActivityServiceTests.swift", "NotchActivityLayoutTests.swift", "ExtensionArchiveTests.swift", "ExtensionPackageTests.swift", "ExtensionActivityDescriptorTests.swift", "LiveActivityCenterTests.swift", "ExtensionCatalogTests.swift", "ExtensionStoreTransferTests.swift", "LockedLiveActivityViewTests.swift", "ExtensionTabDescriptorTests.swift", "ExtensionTabInteractionTests.swift", "NotchWorkspaceLayoutTests.swift"]
        )
    ]
)
