// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "BoringNotchDailyPlanning",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DailyPlanningCore", targets: ["DailyPlanningCore"])
    ],
    targets: [
        .target(
            name: "DailyPlanningCore",
            path: "boringNotch/features/DailyPlanning/Core"
        ),
        .testTarget(
            name: "DailyPlanningCoreTests",
            dependencies: ["DailyPlanningCore"],
            path: "boringNotchTests"
        ),
    ]
)
