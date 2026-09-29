import AppKit
import Foundation
import SwiftUI

private enum SmokeFailure: Error { case failed(String) }

@main
struct ExtensionSmoke {
    @MainActor
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count == 2 else { throw SmokeFailure.failed("Pass a .bnplugin path") }
        let bundle = URL(fileURLWithPath: CommandLine.arguments[1])
        let runtime = try ExtensionRuntime(url: bundle) { context, name, _ in
            guard let name else { return }
            MainActor.assumeIsolated {
                // The runtime's context is opaque; only the runtime validates it.
                _ = context
                SmokeCommands.values.append(String(cString: name))
            }
        }
        defer { runtime.stop() }
        try require(runtime.manifest.capabilities == ["liveActivities", "tabs"], "capability manifest")
        let tabRegistry = ExtensionTabRegistry()
        let tabs = try runtime.tabSnapshot()
        try require(tabs.tabs.count == 1 && tabs.tabs.first?.title == "Focus", "native tab publication")
        tabRegistry.replace(providerID: runtime.manifest.id, tabs: tabs.tabs, runtime: runtime)
        let tabID = ExtensionTabID(providerID: runtime.manifest.id, localID: "focus")
        guard let firstTab = runtime.tabController(id: "focus", displayID: "display-a"),
              let secondTab = runtime.tabController(id: "focus", displayID: "display-b") else {
            throw SmokeFailure.failed("missing tab controllers")
        }
        try require(firstTab !== secondTab && firstTab.view !== secondTab.view, "independent native tab controllers")
        try require(runtime.tabController(id: "missing", displayID: nil) == nil, "unknown tab rejected")
        let tabHost = makeTabHost(id: tabID, registry: tabRegistry)
        defer { tabHost.window.close() }
        settle([tabHost.view])
        let runningTab = try capture(tabHost.view, name: "focus-tab-running")
        let initial = try runtime.activitySnapshot()
        try require(initial.activities.count == 1, "initial activity")
        guard let descriptor = initial.activities.first else { throw SmokeFailure.failed("missing initial descriptor") }
        let id = descriptor.id
        try require(descriptor.expiresAt != nil, "running deadline")
        try require(descriptor.hostDescriptor(namespace: runtime.manifest.id).id.namespace == runtime.manifest.id,
                    "host namespace ownership")
        guard let first = runtime.activityController(id: id, region: 0, displayID: "display-a"),
              let second = runtime.activityController(id: id, region: 0, displayID: "display-b"),
              let trailing = runtime.activityController(id: id, region: 1, displayID: nil) else {
            throw SmokeFailure.failed("missing activity controllers")
        }
        try require(first !== second && first.view !== second.view, "independent per-display view ownership")
        try require(first.preferredContentSize.width == 68 && trailing.preferredContentSize.width == 48,
                    "intrinsic side sizing")
        try require(runtime.activityController(id: "missing", region: 0, displayID: nil) == nil, "unknown ID rejection")
        try require(runtime.activityController(id: id, region: 99, displayID: nil) == nil, "unknown region rejection")
        try require(runtime.settingsController() != nil, "borrowed settings controller")
        let firstHost = makeHost(activity: ExtensionNotchActivity(value: descriptor, runtime: runtime), displayID: "display-a")
        let secondHost = makeHost(activity: ExtensionNotchActivity(value: descriptor, runtime: runtime), displayID: "display-b")
        defer { firstHost.window.close(); secondHost.window.close() }
        settle([firstHost.view, secondHost.view])
        try require(firstHost.width.value == 337 && secondHost.width.value == 337,
                    "native bridge initial rendered width (\(firstHost.width.value), \(secondHost.width.value))")
        runtime.send(event: "example.focus.widen")
        settle([firstHost.view, secondHost.view])
        try require(firstHost.width.value == 417 && secondHost.width.value == 417,
                    "native preferred-size-only resize (\(firstHost.width.value), \(secondHost.width.value))")
        runtime.send(event: "example.focus.compact")
        settle([firstHost.view, secondHost.view])
        try require(firstHost.width.value == 337 && secondHost.width.value == 337,
                    "native preferred-size-only shrink")
        runtime.send(snapshot: Data("{\"unknownFutureField\":true}".utf8))
        runtime.send(event: "example.focus.togglePause")
        settle([tabHost.view])
        let pausedTab = try capture(tabHost.view, name: "focus-tab-paused")
        try require(runningTab != pausedTab, "mounted tab updates from plugin-owned observable state")
        let paused = try runtime.activitySnapshot()
        try require(paused.activities.first?.id == id && paused.activities.first?.expiresAt == nil,
                    "stable identity while pausing")
        try require(first.preferredContentSize.width == 76 && second.preferredContentSize.width == 76,
                    "existing controllers observe state and resize")
        settle([firstHost.view, secondHost.view])
        try require(firstHost.width.value == 353 && secondHost.width.value == 353,
                    "native bridge same-ID rendered resize (\(firstHost.width.value), \(secondHost.width.value))")
        runtime.send(event: "example.focus.togglePause")
        try require(try runtime.activitySnapshot().activities.first?.expiresAt != nil, "renewed deadline")
        settle([firstHost.view, secondHost.view])
        try require(firstHost.width.value == 337 && secondHost.width.value == 337,
                    "native bridge releases resized width")
        runtime.send(event: "example.focus.end")
        try require(try runtime.activitySnapshot().activities.isEmpty, "withdrawal")
        runtime.send(event: "example.focus.start")
        try require(try runtime.activitySnapshot().activities.first?.id != id, "new session gets new identity")
        let identity = tabRegistry.tab(for: tabID)?.contentIdentity(displayID: "display-a")
        runtime.send(event: "example.tab.rename")
        tabRegistry.replace(providerID: runtime.manifest.id, tabs: try runtime.tabSnapshot().tabs, runtime: runtime)
        try require(tabRegistry.tab(for: tabID)?.descriptor.title == "Session", "live tab metadata update")
        try require(tabRegistry.tab(for: tabID)?.contentIdentity(displayID: "display-a") == identity,
                    "metadata preserves mounted content identity")
        runtime.send(event: "example.tab.hide")
        tabRegistry.replace(providerID: runtime.manifest.id, tabs: try runtime.tabSnapshot().tabs, runtime: runtime)
        try require(tabRegistry.tabs.isEmpty, "tab withdrawal")
        try require(NotchViews.extensionTab(tabID).reconciled(availableExtensionTabs: []) == .home, "selected removed tab falls back home")
        runtime.send(event: "example.tab.show")
        tabRegistry.replace(providerID: runtime.manifest.id, tabs: try runtime.tabSnapshot().tabs, runtime: runtime)
        try require(tabRegistry.tabs.count == 1, "tab can be registered again")
        let commandsBeforeStop = SmokeCommands.values
        try require(commandsBeforeStop.filter { $0 == "activities.changed" }.count == 4
                    && commandsBeforeStop.filter { $0 == "tabs.changed" }.count == 3, "contribution change callbacks")
        runtime.stop()
        try require(try runtime.activitySnapshot().activities.isEmpty, "stopped runtime has no activities")
        try require(try runtime.tabSnapshot().tabs.isEmpty, "stopped runtime has no tabs")
        firstTab.view.layoutSubtreeIfNeeded()
        secondTab.view.layoutSubtreeIfNeeded()
        tabRegistry.remove(providerID: runtime.manifest.id)
        // Retain and lay out both controllers after plugin destruction. The SwiftUI
        // model must outlive the C instance without accessing its old host context.
        first.view.layoutSubtreeIfNeeded()
        second.view.layoutSubtreeIfNeeded()
        trailing.view.layoutSubtreeIfNeeded()
        firstHost.view.layoutSubtreeIfNeeded()
        secondHost.view.layoutSubtreeIfNeeded()
        runtime.send(event: "example.focus.start")
        try require(SmokeCommands.values == commandsBeforeStop, "no callbacks after destruction")
        print("PASS: standalone ABI, signed package, native live tab/progress, tab metadata and withdrawal, independent views, native size 337→417→337, SwiftUI size 337→353→337, safe teardown")
    }

    @MainActor
    private static func makeTabHost(id: ExtensionTabID, registry: ExtensionTabRegistry) -> (window: NSWindow, view: NSView) {
        let view = NSHostingView(rootView: ExtensionTabContent(id: id, displayID: "display-a", registry: registry)
            .frame(width: 578, height: 132).background(.black).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 578, height: 132),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        return (window, view)
    }

    @MainActor
    private static func capture(_ view: NSView, name: String) throws -> Data {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw SmokeFailure.failed("tab bitmap unavailable")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SmokeFailure.failed("tab image unavailable")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("boring-native-tabs-validation")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name + ".png"))
        return data
    }

    @MainActor
    private static func makeHost(activity: ExtensionNotchActivity, displayID: String) -> (window: NSWindow, view: NSView, width: MeasuredWidth) {
        let width = MeasuredWidth()
        let view = NSHostingView(rootView: SmokeActivityHost(activity: activity, displayID: displayID, width: width)
            .frame(width: 640, height: 80))
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 640, height: 80),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.orderBack(nil)
        return (window, view, width)
    }

    @MainActor
    private static func settle(_ views: [NSView]) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
        views.forEach { $0.layoutSubtreeIfNeeded() }
    }

    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw SmokeFailure.failed(message) }
    }
}

@MainActor
private enum SmokeCommands {
    static var values: [String] = []
}

@MainActor
private final class MeasuredWidth {
    var value: CGFloat = 0
}

@MainActor
private struct SmokeActivityHost: View {
    let activity: ExtensionNotchActivity
    let displayID: String
    let width: MeasuredWidth

    var body: some View {
        let context = LiveActivityViewContext(displayID: displayID, height: 38, maximumSideWidth: 219.5)
        NotchActivityHost(contentID: activity.descriptor.id, safeAreaWidth: 185, height: 38, maximumWidth: 640,
                          onWidthChange: { width.value = $0 }) {
            activity.leading(context: context)
        } trailing: {
            activity.trailing(context: context)
        }
    }
}
