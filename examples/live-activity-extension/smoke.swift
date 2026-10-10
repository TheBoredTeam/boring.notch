// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

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
        try require(tabs.tabs.first?.presentations == [.regular, .compact], "explicit regular and compact support")
        tabRegistry.replace(providerID: runtime.manifest.id, tabs: tabs.tabs, runtime: runtime)
        let tabID = ExtensionTabID(providerID: runtime.manifest.id, localID: "focus")
        let regularContext = ExtensionTabLayoutContext(presentation: .regular, displayID: "display-a",
                                                       contentSize: CGSize(width: 578, height: 132))
        let compactContext = ExtensionTabLayoutContext(presentation: .compact, displayID: "display-b",
                                                       contentSize: CGSize(width: 336, height: 132))
        let customContext = ExtensionTabLayoutContext(presentation: .regular, displayID: nil,
                                                      contentSize: CGSize(width: 520, height: 120))
        guard let firstTab = runtime.tabController(id: "focus", context: regularContext),
              let secondTab = runtime.tabController(id: "focus", context: compactContext),
              let customTab = runtime.tabController(id: "focus", context: customContext) else {
            throw SmokeFailure.failed("missing tab controllers")
        }
        try require(firstTab !== secondTab && firstTab.view !== secondTab.view, "independent native tab controllers")
        try require(firstTab.view.identifier?.rawValue == "focus-tab-regular"
                    && secondTab.view.identifier?.rawValue == "focus-tab-compact", "v2 receives requested presentation")
        try require(secondTab.preferredContentSize == CGSize(width: 336, height: 132)
                    && customTab.preferredContentSize == CGSize(width: 520, height: 120), "v2 receives actual content bounds")
        try require(runtime.tabController(id: "missing", context: regularContext) == nil, "unknown tab rejected")
        try verifyLegacyAndInvalidContexts(bundle: bundle)
        let tabHost = makeTabHost(id: tabID, registry: tabRegistry, presentation: .regular)
        let compactTabHost = makeTabHost(id: tabID, registry: tabRegistry, presentation: .compact)
        defer { tabHost.window.close(); compactTabHost.window.close() }
        settle([tabHost.view, compactTabHost.view])
        let runningTab = try capture(tabHost.view, name: "focus-tab-running")
        let runningCompactTab = try capture(compactTabHost.view, name: "focus-tab-compact-running")
        try require(runningTab != runningCompactTab, "separate regular and compact layouts render")
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
        settle([tabHost.view, compactTabHost.view])
        let pausedTab = try capture(tabHost.view, name: "focus-tab-paused")
        let pausedCompactTab = try capture(compactTabHost.view, name: "focus-tab-compact-paused")
        try require(runningTab != pausedTab, "mounted tab updates from plugin-owned observable state")
        try require(runningCompactTab != pausedCompactTab, "compact tab observes the same paused timer model")
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
        let identity = tabRegistry.tab(for: tabID)?.contentIdentity(context: regularContext)
        runtime.send(event: "example.tab.rename")
        tabRegistry.replace(providerID: runtime.manifest.id, tabs: try runtime.tabSnapshot().tabs, runtime: runtime)
        try require(tabRegistry.tab(for: tabID)?.descriptor.title == "Session", "live tab metadata update")
        try require(tabRegistry.tab(for: tabID)?.contentIdentity(context: regularContext) == identity,
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
        print("PASS: standalone ABI, signed package, v2 presentation/bounds, regular and compact shared live state, legacy v1 layout, invalid context rejection, tab metadata and withdrawal, independent views, native size 337→417→337, SwiftUI size 337→353→337, safe teardown")
    }

    @MainActor
    private static func makeTabHost(id: ExtensionTabID, registry: ExtensionTabRegistry,
                                    presentation: ExtensionTabPresentation) -> (window: NSWindow, view: NSView) {
        let width: CGFloat = presentation == .compact ? 336 : 578
        let view = NSHostingView(rootView: ExtensionTabContent(id: id, displayID: "display-a",
                                                             presentation: presentation, registry: registry)
            .frame(width: width, height: 132).background(.black).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: width, height: 132),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        return (window, view)
    }

    /// Exercise the public C exports as an old host would, and feed malformed
    /// contexts directly to the independently compiled decoder. This creates
    /// another instance of the same loaded image, not a second copy of Swift code.
    @MainActor
    private static func verifyLegacyAndInvalidContexts(bundle: URL) throws {
        typealias Command = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Double) -> Void
        typealias Create = @convention(c) (UnsafeMutableRawPointer?, Command) -> UnsafeMutableRawPointer?
        typealias Destroy = @convention(c) (UnsafeMutableRawPointer) -> Void
        typealias LegacyView = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
        typealias ContextView = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
        guard let executable = Bundle(url: bundle)?.executableURL,
              let handle = dlopen(executable.path, RTLD_NOW | RTLD_LOCAL) else {
            throw SmokeFailure.failed("cannot inspect example C exports")
        }
        defer { dlclose(handle) }
        let create: Create = try symbol("bn_extension_create_v1", in: handle)
        let destroy: Destroy = try symbol("bn_extension_destroy_v1", in: handle)
        let legacyView: LegacyView = try symbol("bn_extension_tab_view_v1", in: handle)
        let contextView: ContextView = try symbol("bn_extension_tab_view_v2", in: handle)
        guard let instance = create(nil, { _, _, _ in }) else { throw SmokeFailure.failed("legacy create") }
        defer { destroy(instance) }
        guard let legacyPointer = "focus".withCString({ legacyView(instance, $0, nil) }) else {
            throw SmokeFailure.failed("legacy regular factory")
        }
        let legacy = Unmanaged<NSViewController>.fromOpaque(legacyPointer).takeRetainedValue()
        try require(legacy.view.identifier?.rawValue == "focus-tab-regular", "old host receives regular layout through v1")
        let invalidContexts = [
            #"{"presentation":"unknown","displayID":null,"contentSize":{"width":336,"height":132}}"#,
            #"{"presentation":"compact","displayID":null,"contentSize":{"width":-1,"height":132}}"#,
            #"{"presentation":"compact","contentSize":{"width":336,"height":0}}"#,
            #"{"presentation":"compact","contentSize":{"width":"NaN","height":132}}"#,
            String(repeating: " ", count: 65_537)
        ]
        for json in invalidContexts {
            let pointer = "focus".withCString { id in json.withCString { contextView(instance, id, $0) } }
            if let pointer { _ = Unmanaged<NSViewController>.fromOpaque(pointer).takeRetainedValue() }
            try require(pointer == nil, "invalid compact context rejected")
        }
        let valid = #"{"presentation":"compact","displayID":null,"contentSize":{"width":319,"height":128},"futureField":true}"#
        guard let pointer = "focus".withCString({ id in valid.withCString { contextView(instance, id, $0) } }) else {
            throw SmokeFailure.failed("valid compact context with unknown key rejected")
        }
        let compact = Unmanaged<NSViewController>.fromOpaque(pointer).takeRetainedValue()
        try require(compact.view.identifier?.rawValue == "focus-tab-compact"
                    && compact.preferredContentSize == CGSize(width: 319, height: 128), "forward compatible context decoder")
    }

    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer) throws -> T {
        guard let address = dlsym(handle, name) else { throw SmokeFailure.failed("missing \(name)") }
        return unsafeBitCast(address, to: T.self)
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
