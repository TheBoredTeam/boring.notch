// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

// Standalone example: imports system frameworks only, never the host app module.

import AppKit
import Combine
import SwiftUI

public typealias BNExtensionCommand = @convention(c) (
    UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Double
) -> Void

@MainActor
private final class FocusState: ObservableObject {
    @Published private(set) var remainingSeconds = 25 * 60
    @Published private(set) var isRunning = false
    @Published private(set) var isActive = false
    @Published private(set) var isAvailable = true
    private(set) var deadline: Date?
    private(set) var activityID = "focus-0"
    private var session = 0
    var activitiesChanged: (() -> Void)?
    // Independent sizing signal: the smoke test changes native preferred size
    // without publishing SwiftUI state or replacing the activity descriptor.
    let additionalLeadingWidth = CurrentValueSubject<CGFloat, Never>(0)

    var clockText: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var statusText: String { isActive ? (isRunning ? "In progress" : "Paused") : "Ready" }

    func start() {
        guard isAvailable else { return }
        session += 1
        activityID = "focus-\(session)"
        remainingSeconds = 25 * 60
        deadline = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        isActive = true
        isRunning = true
        activitiesChanged?()
    }

    func togglePause() {
        guard isAvailable, isActive else { return }
        if isRunning {
            tick()
            guard isActive else { return }
            deadline = nil
            isRunning = false
        } else {
            deadline = Date().addingTimeInterval(TimeInterval(remainingSeconds))
            isRunning = true
        }
        activitiesChanged?()
    }

    func end() {
        deadline = nil
        isRunning = false
        isActive = false
        activitiesChanged?()
    }

    func tick() {
        guard isAvailable, isActive, isRunning, let deadline else { return }
        remainingSeconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        if remainingSeconds == 0 { end() }
    }

    func shutdown() {
        // Views can outlive the C instance. Their controls become inert, and they
        // can no longer call a command callback with the old host context.
        activitiesChanged = nil
        isAvailable = false
        end()
    }
}

@MainActor
private struct FocusRegion: View {
    @ObservedObject var state: FocusState
    let region: Int32

    var body: some View {
        Group {
            if region == 0 {
                HStack(spacing: 5) {
                    Image(systemName: state.isRunning ? "timer" : "pause.circle")
                        .foregroundStyle(.orange)
                    Text(state.isRunning ? "Focus" : "Paused")
                        .font(.system(size: 11, weight: .medium))
                }
            } else {
                Text(state.clockText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.white)
        .fixedSize()
        .accessibilityLabel(region == 0 ? "Focus timer" : state.clockText)
    }
}

@MainActor
private final class FocusRegionController: NSHostingController<FocusRegion> {
    private var sizeSubscription: AnyCancellable?

    init(state: FocusState, region: Int32) {
        super.init(rootView: FocusRegion(state: state, region: region))
        preferredContentSize = NSSize(width: region == 0 ? 68 : 48, height: 24)
        if region == 0 {
            sizeSubscription = Publishers.CombineLatest(state.$isRunning, state.additionalLeadingWidth)
                .sink { [weak self] running, additionalWidth in
                    self?.preferredContentSize = NSSize(width: (running ? 68 : 76) + additionalWidth, height: 24)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

@MainActor
private struct FocusSettings: View {
    @ObservedObject var state: FocusState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Focus timer").font(.title2.bold())
            Text("A standalone live activity built with the public extension API.")
                .foregroundStyle(.secondary)
            Text(state.clockText).font(.system(size: 36, design: .monospaced))
            HStack {
                Button("Start 25 minutes") { state.start() }
                Button(state.isRunning ? "Pause" : "Resume") { state.togglePause() }
                    .disabled(!state.isActive)
                Button("End") { state.end() }.disabled(!state.isActive)
            }
        }
        .padding(20)
        .disabled(!state.isAvailable)
    }
}

/// Decode the public JSON contract locally; this bundle imports no host types.
/// Unknown keys remain forward compatible, but unsupported layouts or invalid
/// geometry cannot accidentally mount the regular layout in a compact viewport.
private struct TabLayoutContext: Decodable {
    enum Presentation: String, Decodable { case regular, compact }
    struct ContentSize: Decodable {
        let width: CGFloat
        let height: CGFloat
        var isValid: Bool { width.isFinite && height.isFinite && width > 0 && height > 0 }
        var size: CGSize { CGSize(width: width, height: height) }
    }

    let presentation: Presentation
    let displayID: String?
    let contentSize: ContentSize

    static let legacy = Self(presentation: .regular, displayID: nil,
                             contentSize: ContentSize(width: 578, height: 132))

    static func decode(_ json: UnsafePointer<CChar>) -> Self? {
        let maximumBytes = 65_536
        let count = strnlen(json, maximumBytes + 1)
        guard count <= maximumBytes,
              let context = try? JSONDecoder().decode(Self.self, from: Data(bytes: json, count: count)),
              context.contentSize.isValid else { return nil }
        return context
    }
}

/// Both presentations share their state and controls. Compact deliberately
/// moves the timer beside its heading and the controls below its progress bar;
/// it does not scale down the regular desktop layout.
@MainActor
private struct FocusTab: View {
    @ObservedObject var state: FocusState
    let presentation: TabLayoutContext.Presentation

    var body: some View {
        Group {
            switch presentation {
            case .regular: regularLayout
            case .compact: compactLayout
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .disabled(!state.isAvailable)
    }

    private var regularLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Focus timer", systemImage: "timer").font(.headline)
                Spacer()
                status
            }
            HStack {
                clock(size: 32)
                Spacer()
                FocusControls(state: state)
            }
            progress
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Focus", systemImage: "timer").font(.subheadline.weight(.semibold))
                    status
                }
                Spacer(minLength: 12)
                clock(size: 28)
            }
            progress
            HStack {
                Spacer(minLength: 0)
                FocusControls(state: state)
            }
        }
    }

    private var status: some View {
        Text(state.statusText).font(.caption).foregroundStyle(.secondary)
    }

    private func clock(size: CGFloat) -> some View {
        Text(state.clockText).font(.system(size: size, weight: .medium, design: .monospaced))
            .monospacedDigit()
    }

    private var progress: some View {
        ProgressView(value: Double(25 * 60 - state.remainingSeconds), total: 25 * 60)
            .tint(.orange)
            .accessibilityLabel("Session progress")
    }
}

@MainActor
private struct FocusControls: View {
    @ObservedObject var state: FocusState

    var body: some View {
        HStack {
            Button("Start") { state.start() }.disabled(state.isActive)
            Button(state.isRunning ? "Pause" : "Resume") { state.togglePause() }.disabled(!state.isActive)
            Button("End") { state.end() }.disabled(!state.isActive)
        }
        .controlSize(.small)
    }
}

@MainActor
private final class FocusPlugin {
    let state = FocusState()
    private let context: UnsafeMutableRawPointer?
    private let command: BNExtensionCommand
    private var ticker: Task<Void, Never>?
    private var jsonBuffer: UnsafeMutablePointer<CChar>?
    private var settings: NSHostingController<FocusSettings>?
    private var tabVisible = true
    private var tabTitle = "Focus"
    private var receivedInitialSnapshot = false

    init(context: UnsafeMutableRawPointer?, command: @escaping BNExtensionCommand) {
        self.context = context
        self.command = command
        state.start()
        state.activitiesChanged = { [weak self] in
            guard let self else { return }
            "activities.changed".withCString { self.command(self.context, $0, 0) }
        }
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                self.state.tick()
            }
        }
    }

    func snapshot() -> UnsafePointer<CChar>? {
        var activity: [String: Any] = [
            "id": state.activityID, "label": "Focus timer", "relevance": "active"
        ]
        if let deadline = state.deadline { activity["expiresAt"] = deadline.timeIntervalSince1970 }
        let value: [String: Any] = ["activities": state.isActive ? [activity] : []]
        return encodeSnapshot(value)
    }

    func tabSnapshot() -> UnsafePointer<CChar>? {
        encodeSnapshot(["tabs": tabVisible ? [["id": "focus", "title": tabTitle, "symbol": "timer",
                                               "presentations": ["regular", "compact"]]] : []])
    }

    private func encodeSnapshot(_ value: [String: Any]) -> UnsafePointer<CChar>? {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let json = String(data: data, encoding: .utf8) else { return nil }
        free(jsonBuffer)
        jsonBuffer = strdup(json)
        return jsonBuffer.map { UnsafePointer($0) }
    }

    func controller(activityID: String, region: Int32) -> NSViewController? {
        guard state.isActive, state.activityID == activityID, region == 0 || region == 1 else { return nil }
        return FocusRegionController(state: state, region: region)
    }

    func tabController(id: String, layout: TabLayoutContext = .legacy) -> NSViewController? {
        guard tabVisible, state.isAvailable, id == "focus" else { return nil }
        let controller = NSHostingController(rootView: FocusTab(state: state, presentation: layout.presentation))
        controller.preferredContentSize = layout.contentSize.size
        // A stable native identifier also lets the standalone smoke harness
        // verify which presentation the real runtime requested.
        controller.view.identifier = NSUserInterfaceItemIdentifier("focus-tab-\(layout.presentation.rawValue)")
        return controller
    }

    var settingsController: NSViewController {
        if let settings { return settings }
        let controller = NSHostingController(rootView: FocusSettings(state: state))
        controller.preferredContentSize = NSSize(width: 440, height: 210)
        settings = controller
        return controller
    }

    func event(_ name: String) {
        switch name {
        case "wake", "session-active": state.tick()
        // Example-specific events are exercised by the standalone smoke harness.
        case "example.focus.start": state.start()
        case "example.focus.togglePause": state.togglePause()
        case "example.focus.end": state.end()
        case "example.focus.widen": state.additionalLeadingWidth.send(40)
        case "example.focus.compact": state.additionalLeadingWidth.send(0)
        case "example.tab.hide":
            tabVisible = false
            "tabs.changed".withCString { command(context, $0, 0) }
        case "example.tab.show":
            tabVisible = true
            "tabs.changed".withCString { command(context, $0, 0) }
        case "example.tab.rename":
            tabTitle = "Session"
            "tabs.changed".withCString { command(context, $0, 0) }
        default: break
        }
    }

    func receiveSnapshot() {
        guard state.isAvailable, !receivedInitialSnapshot else { return }
        receivedInitialSnapshot = true
        // This extension owns its timer. Suspending media delivery leaves both
        // its registered activity and tab available.
        "presentation.active".withCString { command(context, $0, 0) }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        state.shutdown()
        settings = nil
        free(jsonBuffer)
        jsonBuffer = nil
    }
}

@_cdecl("bn_extension_create_v1")
@MainActor
public func createFocusPlugin(_ context: UnsafeMutableRawPointer?, _ command: @escaping BNExtensionCommand) -> UnsafeMutableRawPointer? {
    guard Thread.isMainThread else { return nil }
    return Unmanaged.passRetained(FocusPlugin(context: context, command: command)).toOpaque()
}

@_cdecl("bn_extension_destroy_v1")
@MainActor
public func destroyFocusPlugin(_ pointer: UnsafeMutableRawPointer) {
    guard Thread.isMainThread else { return }
    Unmanaged<FocusPlugin>.fromOpaque(pointer).takeRetainedValue().stop()
}

@_cdecl("bn_extension_update_v1")
@MainActor
public func updateFocusPlugin(_ pointer: UnsafeMutableRawPointer, _ bytes: UnsafePointer<UInt8>, _ count: Int) {
    // This example has its own state and needs no host media data. Extensions
    // that consume snapshots should copy/parse bytes here and ignore unknown keys.
    guard Thread.isMainThread, count >= 0 else { return }
    Unmanaged<FocusPlugin>.fromOpaque(pointer).takeUnretainedValue().receiveSnapshot()
}

@_cdecl("bn_extension_event_v1")
@MainActor
public func eventFocusPlugin(_ pointer: UnsafeMutableRawPointer, _ event: UnsafePointer<CChar>) {
    guard Thread.isMainThread else { return }
    Unmanaged<FocusPlugin>.fromOpaque(pointer).takeUnretainedValue().event(String(cString: event))
}

@_cdecl("bn_extension_settings_v1")
@MainActor
public func settingsFocusPlugin(_ pointer: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    guard Thread.isMainThread else { return nil }
    let controller = Unmanaged<FocusPlugin>.fromOpaque(pointer).takeUnretainedValue().settingsController
    return Unmanaged.passUnretained(controller).toOpaque()
}

@_cdecl("bn_extension_activities_v1")
@MainActor
public func activitiesFocusPlugin(_ pointer: UnsafeMutableRawPointer) -> UnsafePointer<CChar>? {
    guard Thread.isMainThread else { return nil }
    return Unmanaged<FocusPlugin>.fromOpaque(pointer).takeUnretainedValue().snapshot()
}

@_cdecl("bn_extension_activity_view_v1")
@MainActor
public func activityViewFocusPlugin(
    _ pointer: UnsafeMutableRawPointer, _ activityID: UnsafePointer<CChar>,
    _ region: Int32, _ displayID: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    guard Thread.isMainThread else { return nil }
    guard let controller = Unmanaged<FocusPlugin>.fromOpaque(pointer).takeUnretainedValue()
        .controller(activityID: String(cString: activityID), region: region) else { return nil }
    return Unmanaged.passRetained(controller).toOpaque()
}

@_cdecl("bn_extension_tabs_v1")
@MainActor
public func tabsFocusPlugin(_ pointer: UnsafeMutableRawPointer) -> UnsafePointer<CChar>? {
    guard Thread.isMainThread else { return nil }
    return Unmanaged<FocusPlugin>.fromOpaque(pointer).takeUnretainedValue().tabSnapshot()
}

@_cdecl("bn_extension_tab_view_v1")
@MainActor
public func tabViewFocusPlugin(
    _ pointer: UnsafeMutableRawPointer, _ tabID: UnsafePointer<CChar>, _ displayID: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    guard Thread.isMainThread else { return nil }
    guard let controller = Unmanaged<FocusPlugin>.fromOpaque(pointer).takeUnretainedValue()
        .tabController(id: String(cString: tabID)) else { return nil }
    return Unmanaged.passRetained(controller).toOpaque()
}

@_cdecl("bn_extension_tab_view_v2")
@MainActor
public func tabViewFocusPluginV2(
    _ pointer: UnsafeMutableRawPointer, _ tabID: UnsafePointer<CChar>, _ contextJSON: UnsafePointer<CChar>
) -> UnsafeMutableRawPointer? {
    guard Thread.isMainThread, let layout = TabLayoutContext.decode(contextJSON),
          let controller = Unmanaged<FocusPlugin>.fromOpaque(pointer).takeUnretainedValue()
            .tabController(id: String(cString: tabID), layout: layout) else { return nil }
    return Unmanaged.passRetained(controller).toOpaque()
}
