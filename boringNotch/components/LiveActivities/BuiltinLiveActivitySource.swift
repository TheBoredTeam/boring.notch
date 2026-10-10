// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Combine
import Defaults
import SwiftUI

enum BuiltinLiveActivityID {
    static let music = LiveActivityID(namespace: "boringnotch", name: "music")
    static let battery = LiveActivityID(namespace: "boringnotch", name: "battery")
    static let face = LiveActivityID(namespace: "boringnotch", name: "face")
    static let osd = LiveActivityID(namespace: "boringnotch", name: "osd")
}

/// Adapts existing feature state to the same registration boundary available to
/// other app-owned sources. It does not decide which activity wins a display.
@MainActor
final class BuiltinLiveActivitySource {
    static let shared = BuiltinLiveActivitySource()

    private let center: LiveActivityCenter
    private let coordinator: BoringViewCoordinator
    private let music: MusicManager
    private var subscriptions: Set<AnyCancellable> = []
    private var registrations: [LiveActivityID: NotchActivityRegistration] = [:]
    private var descriptors: [LiveActivityID: LiveActivityDescriptor] = [:]

    private init() {
        center = .shared
        coordinator = .shared
        music = .shared
    }

    func start() {
        guard subscriptions.isEmpty else { return }
        Publishers.MergeMany([
            coordinator.objectWillChange.eraseToAnyPublisher(),
            music.objectWillChange.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .map { _ in () }.eraseToAnyPublisher()
        ])
        // objectWillChange arrives before @Published stores its new value.
        // Reconcile on the next run-loop delivery, after that mutation finishes.
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.reconcile() }
        .store(in: &subscriptions)
        reconcile()
    }

    func stop() {
        subscriptions.removeAll()
        registrations.values.forEach { $0.unregister() }
        registrations.removeAll()
        descriptors.removeAll()
    }

    private func reconcile() {
        let desired = activities()
        let desiredIDs = Set(desired.map(\.descriptor.id))
        for id in Array(registrations.keys) where !desiredIDs.contains(id) {
            registrations.removeValue(forKey: id)?.unregister()
            descriptors.removeValue(forKey: id)
        }
        for activity in desired {
            let descriptor = activity.descriptor
            // Progress, artwork and level updates are observed by content views.
            // They must not churn registrations or reset the user's selection.
            guard descriptors[descriptor.id] != descriptor else { continue }
            do {
                if let registration = registrations[descriptor.id] {
                    try registration.update(activity)
                } else {
                    registrations[descriptor.id] = try center.register(activity)
                }
                descriptors[descriptor.id] = descriptor
            } catch {
                NSLog("Could not register built-in live activity %@: %@", descriptor.id.description, String(describing: error))
            }
        }
    }

    private func activities() -> [AnyNotchLiveActivity] {
        var activities: [AnyNotchLiveActivity] = []
        let inlineMusicPeek = coordinator.expandingView.show
            && coordinator.expandingView.type == .music
            && Defaults[.sneakPeekStyles] == .inline
        // Music remains registered beneath interrupts. An inline song-change
        // peek may activate it even when the persistent preference is disabled.
        if ((music.isPlaying || !music.isPlayerIdle) && coordinator.musicLiveActivityEnabled) || inlineMusicPeek {
            activities.append(AnyNotchLiveActivity(
                descriptor: LiveActivityDescriptor(id: BuiltinLiveActivityID.music),
                leading: { BuiltinMusicLeading(context: $0) },
                trailing: { BuiltinMusicTrailing(context: $0) }
            ))
        }
        if coordinator.expandingView.show,
           coordinator.expandingView.type == .battery,
           Defaults[.showPowerStatusNotifications] {
            activities.append(AnyNotchLiveActivity(
                descriptor: LiveActivityDescriptor(id: BuiltinLiveActivityID.battery, priority: 300, presentation: .interrupt, participatesInCycling: false),
                leading: { _ in BuiltinBatteryLeading() },
                trailing: { _ in BuiltinBatteryTrailing() }
            ))
        }
        // Main owns one shared HUD state, so its activity follows that existing
        // display behavior instead of importing dev's display-specific OSD API.
        let state = coordinator.sneakPeek
        if Defaults[.inlineHUD], state.show, state.type != .music, state.type != .battery {
            activities.append(AnyNotchLiveActivity(
                descriptor: LiveActivityDescriptor(
                    id: BuiltinLiveActivityID.osd, priority: 200,
                    presentation: .interrupt, participatesInCycling: false
                ),
                leading: { BuiltinOSDLeading(context: $0) },
                trailing: { BuiltinOSDTrailing(context: $0) }
            ))
        }
        if !coordinator.expandingView.show, !music.isPlaying, music.isPlayerIdle, Defaults[.showNotHumanFace] {
            activities.append(AnyNotchLiveActivity(
                descriptor: LiveActivityDescriptor(id: BuiltinLiveActivityID.face, priority: -100, presentation: .background, participatesInCycling: false),
                leading: { _ in EmptyView() },
                trailing: { context in
                    let scale = min(1, context.height / 30)
                    MinimalFaceFeatures(height: 24 * scale, width: 30 * scale)
                }
            ))
        }
        return activities
    }
}
