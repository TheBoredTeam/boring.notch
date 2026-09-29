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
        try require(runtime.manifest.capabilities == ["liveActivities"], "capability manifest")
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
        let commandsBeforeStop = SmokeCommands.values
        try require(commandsBeforeStop.count == 4 && commandsBeforeStop.allSatisfy { $0 == "activities.changed" },
                    "activity change callbacks")
        runtime.stop()
        try require(try runtime.activitySnapshot().activities.isEmpty, "stopped runtime has no activities")
        // Retain and lay out both controllers after plugin destruction. The SwiftUI
        // model must outlive the C instance without accessing its old host context.
        first.view.layoutSubtreeIfNeeded()
        second.view.layoutSubtreeIfNeeded()
        trailing.view.layoutSubtreeIfNeeded()
        firstHost.view.layoutSubtreeIfNeeded()
        secondHost.view.layoutSubtreeIfNeeded()
        runtime.send(event: "example.focus.start")
        try require(SmokeCommands.values == commandsBeforeStop, "no callbacks after destruction")
        print("PASS: standalone ABI, signed package, independent views, native size 337→417→337, SwiftUI size 337→353→337, withdrawal and safe teardown")
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
