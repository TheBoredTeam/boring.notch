// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

// Loads every signed image through the real host runtime without launching the app.
import AppKit
import Foundation
import SwiftUI

private struct FixtureIndex: Decodable {
    struct Provider: Decodable { let id: String; let bundle: String; let firstTab: Int; let lastTab: Int }
    let providerCount: Int
    let tabCount: Int
    let compactTabs: Int
    let providers: [Provider]
}

@main
struct TabStressSmoke {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count == 2,
              ProcessInfo.processInfo.environment["BN_TAB_STRESS_LOG"] != nil else {
            throw Failure("Use smoke.sh to isolate fixture telemetry.")
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let index = try JSONDecoder().decode(FixtureIndex.self, from: Data(contentsOf: directory.appendingPathComponent("index.json")))
        let registry = ExtensionTabRegistry()
        var runtimes: [ExtensionRuntime] = []
        defer { runtimes.forEach { $0.stop() } }
        for provider in index.providers {
            let runtime = try ExtensionRuntime(url: directory.appendingPathComponent(provider.bundle)) { _, command, _ in
                guard let command else { return }
                MainActor.assumeIsolated { Commands.values.append(String(cString: command)) }
            }
            runtimes.append(runtime)
            let snapshot = try runtime.tabSnapshot()
            try require(snapshot.tabs.count == 8, "each provider contributes eight tabs")
            registry.replace(providerID: provider.id, tabs: snapshot.tabs, runtime: runtime)
        }
        try require(registry.tabs.count == index.tabCount && registry.tabs(for: .compact).count == index.compactTabs,
                    "400 regular and 200 compact registrations")
        try require(Set(registry.tabs.map(\.id)).count == index.tabCount, "namespaced unique tab IDs")
        try require(Set(registry.tabs.map { $0.descriptor.title }) == Set((1...index.tabCount).map { String(format: "Probe %03d", $0) }),
                    "all expected probe titles")
        var events = try readEvents()
        try require(events.filter { $0["event"] as? String == "instance.create" }.count == index.providerCount,
                    "all images instantiate together")
        try require(events.allSatisfy { $0["event"] as? String != "controller.create" },
                    "registering hundreds of tabs creates no view controllers")

        // Exercise distinct Objective-C classes from every simultaneously loaded image.
        // Only these explicitly requested tabs may allocate controllers.
        var classes = Set<String>()
        for (provider, runtime) in zip(index.providers, runtimes) {
            try autoreleasepool {
                let compact = ExtensionTabLayoutContext(presentation: .compact, displayID: "smoke-display",
                                                        contentSize: CGSize(width: 336, height: 132))
                let regular = ExtensionTabLayoutContext(presentation: .regular, displayID: nil,
                                                        contentSize: CGSize(width: 578, height: 132))
                let oddID = String(format: "probe-%03d", provider.firstTab)
                let evenID = String(format: "probe-%03d", provider.lastTab)
                let first = try unwrap(runtime.tabController(id: oddID, context: compact), "compact factory")
                let second = try unwrap(runtime.tabController(id: evenID, context: regular), "regular-only factory")
                try require(first !== second, "fresh controller ownership")
                try require(first.preferredContentSize == CGSize(width: 336, height: 132)
                            && second.preferredContentSize == CGSize(width: 578, height: 132), "context geometry crosses ABI")
                try require(runtime.tabController(id: evenID, context: compact) == nil, "regular-only compact request rejected")
                try require(runtime.tabController(id: "missing", context: regular) == nil, "unknown tab rejected")
                classes.insert(NSStringFromClass(type(of: first)))
            }
        }
        try require(classes.count == index.providerCount, "unique Objective-C controller classes across all 50 images")
        let directRequests = index.providerCount * 2
        events = try readEvents()
        try require(events.filter { $0["event"] as? String == "controller.create" }.count == directRequests,
                    "only requested native views were created")

        let firstProvider = try unwrap(index.providers.first, "first provider")
        let lastProvider = try unwrap(index.providers.last, "last provider")
        let firstID = ExtensionTabID(providerID: firstProvider.id, localID: String(format: "probe-%03d", firstProvider.firstTab))
        let lateID = ExtensionTabID(providerID: lastProvider.id, localID: String(format: "probe-%03d", lastProvider.lastTab - 1))
        mountAndSwitch(first: firstID, second: lateID, registry: registry)
        events = try readEvents()
        try require(events.filter { $0["event"] as? String == "controller.create" }.count == directRequests + 2,
                    "real native bridge mounts only the two selected tabs out of 400")

        runtimes[0].send(event: "stress.tabs.withdraw")
        registry.replace(providerID: firstProvider.id, tabs: try runtimes[0].tabSnapshot().tabs, runtime: runtimes[0])
        try require(registry.tabs.count == index.tabCount - 8 && registry.tabs(for: .compact).count == index.compactTabs - 4,
                    "live descriptor withdrawal removes exactly one provider")
        try require(NotchViews.extensionTab(firstID).reconciled(availableExtensionTabs: Set(registry.tabs.map(\.id))) == .home,
                    "selected withdrawn tab falls back home")
        runtimes[0].send(event: "stress.tabs.restore")
        registry.replace(providerID: firstProvider.id, tabs: try runtimes[0].tabSnapshot().tabs, runtime: runtimes[0])
        try require(registry.tabs.count == index.tabCount && registry.tabs(for: .compact).count == index.compactTabs,
                    "restore preserves counts")
        try require(Commands.values == ["tabs.changed", "tabs.changed"], "public change callback")

        for (provider, runtime) in zip(index.providers, runtimes) {
            registry.remove(providerID: provider.id)
            runtime.stop()
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        events = try readEvents()
        let created = Set(events.filter { $0["event"] as? String == "controller.create" }.compactMap { $0["controllerID"] as? String })
        let released = Set(events.filter { $0["event"] as? String == "controller.deinit" }.compactMap { $0["controllerID"] as? String })
        try require(created == released, "all requested controllers log deinit after teardown (\(created.count) created, \(released.count) released)")
        try require(events.filter { $0["event"] as? String == "instance.destroy" }.count == index.providerCount, "all instance teardown")
        print("PASS: \(index.providerCount) signed native images, \(index.tabCount) regular / \(index.compactTabs) compact tabs, zero eager controllers, unique ObjC classes, native selected-only mounting, finite bounds, regular-only rejection, live withdrawal/restore, \(created.count) balanced controller lifetimes.")
    }

    @MainActor private static func mountAndSwitch(first: ExtensionTabID, second: ExtensionTabID,
                                                 registry: ExtensionTabRegistry) {
        autoreleasepool {
            func content(_ id: ExtensionTabID) -> AnyView {
                AnyView(ExtensionTabContent(id: id, displayID: "native-smoke", presentation: .compact, registry: registry)
                    .frame(width: 336, height: 132))
            }
            let view = NSHostingView(rootView: content(first))
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 336, height: 132),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.orderBack(nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            view.layoutSubtreeIfNeeded()
            view.rootView = content(second)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            view.layoutSubtreeIfNeeded()
            view.rootView = AnyView(EmptyView())
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
    }

    private static func readEvents() throws -> [[String: Any]] {
        let path = ProcessInfo.processInfo.environment["BN_TAB_STRESS_LOG"]!
        return try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map {
            try unwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any], "event JSON")
        }
    }
    private static func require(_ value: Bool, _ reason: String) throws {
        if !value { throw Failure(reason) }
    }
    private static func unwrap<T>(_ value: T?, _ reason: String) throws -> T {
        guard let value else { throw Failure(reason) }
        return value
    }
    struct Failure: Error, CustomStringConvertible { let description: String; init(_ value: String) { description = value } }
}

@MainActor private enum Commands { static var values: [String] = [] }
