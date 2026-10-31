// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Combine
import SwiftUI

/// An activity describes its content, never the physical notch or window geometry.
/// AppKit and extension adapters enter through this same contract as built-in features.
@MainActor
protocol NotchLiveActivity {
    associatedtype Leading: View
    associatedtype Trailing: View

    var descriptor: LiveActivityDescriptor { get }
    @ViewBuilder func leading(context: LiveActivityViewContext) -> Leading
    @ViewBuilder func trailing(context: LiveActivityViewContext) -> Trailing
}

struct LiveActivityViewContext {
    let displayID: String?
    let height: CGFloat
    let maximumSideWidth: CGFloat
    var surface: LiveActivitySurface = .desktop
    var isHovered: Bool = false
    var gestureProgress: CGFloat = 0
}

/// Type erasure happens once at the registration boundary, not inside selection policy.
struct AnyNotchLiveActivity: NotchLiveActivity {
    let descriptor: LiveActivityDescriptor
    private let leadingContent: (LiveActivityViewContext) -> AnyView
    private let trailingContent: (LiveActivityViewContext) -> AnyView

    init<Activity: NotchLiveActivity>(_ activity: Activity) {
        descriptor = activity.descriptor
        leadingContent = { AnyView(activity.leading(context: $0)) }
        trailingContent = { AnyView(activity.trailing(context: $0)) }
    }

    init<Leading: View, Trailing: View>(
        descriptor: LiveActivityDescriptor,
        @ViewBuilder leading: @escaping (LiveActivityViewContext) -> Leading,
        @ViewBuilder trailing: @escaping (LiveActivityViewContext) -> Trailing
    ) {
        self.descriptor = descriptor
        leadingContent = { AnyView(leading($0)) }
        trailingContent = { AnyView(trailing($0)) }
    }

    func leading(context: LiveActivityViewContext) -> AnyView { leadingContent(context) }
    func trailing(context: LiveActivityViewContext) -> AnyView { trailingContent(context) }
}

/// App-owned registry. Window recreation does not destroy activities or display selection.
@MainActor
final class LiveActivityCenter: ObservableObject {
    static let shared = LiveActivityCenter()

    let service: LiveActivityService
    @Published private(set) var session = LiveActivitySessionState()
    private var content: [LiveActivityID: AnyNotchLiveActivity] = [:]
    private var owners: [LiveActivityID: UUID] = [:]
    private var subscription: AnyCancellable?

    init(service: LiveActivityService? = nil) {
        self.service = service ?? LiveActivityService()
        subscription = self.service.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func activity(for id: LiveActivityID) -> AnyNotchLiveActivity? { content[id] }

    func updateSession(locked: Bool? = nil, awake: Bool? = nil, active: Bool? = nil) {
        var next = session
        if let locked { next.isLocked = locked }
        if let awake { next.isAwake = awake }
        if let active { next.isSessionActive = active }
        if next != session { session = next }
    }

    func register<Activity: NotchLiveActivity>(_ activity: Activity) throws -> NotchActivityRegistration {
        let registration = try service.register(activity.descriptor)
        let owner = UUID()
        owners[activity.descriptor.id] = owner
        content[activity.descriptor.id] = AnyNotchLiveActivity(activity)
        objectWillChange.send()
        return NotchActivityRegistration(center: self, registration: registration, id: activity.descriptor.id, owner: owner)
    }

    fileprivate func update<Activity: NotchLiveActivity>(
        _ activity: Activity, registration: LiveActivityRegistration, owner: UUID
    ) throws {
        try registration.update(activity.descriptor)
        guard owners[activity.descriptor.id] == owner else { return }
        content[activity.descriptor.id] = AnyNotchLiveActivity(activity)
        objectWillChange.send()
    }

    fileprivate func removeContent(id: LiveActivityID, owner: UUID, unregister: Bool) {
        guard owners[id] == owner else { return }
        content.removeValue(forKey: id)
        if unregister { owners.removeValue(forKey: id) }
        objectWillChange.send()
    }
}

/// Retain one token per source activity. End hides it; update reactivates it;
/// unregister releases its identity. Sources explicitly unregister during teardown.
@MainActor
final class NotchActivityRegistration {
    let id: LiveActivityID
    private weak var center: LiveActivityCenter?
    private let registration: LiveActivityRegistration
    private let owner: UUID

    fileprivate init(center: LiveActivityCenter, registration: LiveActivityRegistration, id: LiveActivityID, owner: UUID) {
        self.center = center
        self.registration = registration
        self.id = id
        self.owner = owner
    }

    func update<Activity: NotchLiveActivity>(_ activity: Activity) throws {
        guard let center else { throw LiveActivityRegistrationError.unregistered }
        try center.update(activity, registration: registration, owner: owner)
    }

    func end() {
        registration.end()
        center?.removeContent(id: id, owner: owner, unregister: false)
    }

    func unregister() {
        registration.unregister()
        center?.removeContent(id: id, owner: owner, unregister: true)
    }

    deinit {
        let center = center
        let id = id
        let owner = owner
        Task { @MainActor in
            center?.removeContent(id: id, owner: owner, unregister: true)
        }
    }
}
