// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Combine
import Foundation

/// Registration is an ownership capability, not an activity ID lookup. Old
/// owners and delayed callbacks cannot mutate a newer registration with the same ID.
/// Retain it for the provider's lifetime; releasing it unregisters the provider.
@MainActor
final class LiveActivityRegistration {
    let id: LiveActivityID
    private let owner: UUID
    private weak var service: LiveActivityService?

    fileprivate init(id: LiveActivityID, owner: UUID, service: LiveActivityService) {
        self.id = id
        self.owner = owner
        self.service = service
    }

    /// Publishes the next descriptor, or begins a new activation after `end()`.
    func update(_ descriptor: LiveActivityDescriptor) throws {
        guard let service else { throw LiveActivityRegistrationError.unregistered }
        guard descriptor.id == id else {
            throw LiveActivityRegistrationError.mismatchedID(expected: id, actual: descriptor.id)
        }
        try service.update(descriptor, owner: owner)
    }

    /// Removes the current activity while preserving this provider's ID reservation.
    /// A future update starts a new activation. Use unregister for terminal cleanup.
    func end() {
        service?.end(id, owner: owner)
    }

    func unregister() {
        service?.unregister(id, owner: owner)
        service = nil
    }

    deinit {
        let id = id
        let owner = owner
        let service = service
        Task { @MainActor in
            service?.unregister(id, owner: owner)
        }
    }
}

/// The host's lifecycle and arbitration boundary. Providers register descriptors;
/// a separate presentation registry owns their SwiftUI leading and trailing views.
/// No built-in activity or extension transport is special-cased here.
@MainActor
final class LiveActivityService: ObservableObject {
    @Published private(set) var revision: UInt64 = 0

    private struct Entry {
        let owner: UUID
        var descriptor: LiveActivityDescriptor?
        var activationOrder: UInt64
        var expirationGeneration: UUID
        var expiration: AnyCancellable?
    }

    private struct SelectionContext: Hashable {
        let displayID: String?
        let surface: LiveActivitySurface

        init(_ context: LiveActivityContext) {
            displayID = context.displayID
            surface = context.surface
        }
    }

    private var entries: [LiveActivityID: Entry] = [:]
    private var userSelections: [SelectionContext: LiveActivityUserSelection] = [:]
    private var activationOrder: UInt64 = 0
    private let policy: any LiveActivitySelectionPolicy
    private let scheduler: any LiveActivityScheduling

    init(
        policy: any LiveActivitySelectionPolicy = DefaultLiveActivitySelectionPolicy(),
        scheduler: (any LiveActivityScheduling)? = nil
    ) {
        self.policy = policy
        self.scheduler = scheduler ?? LiveActivityScheduler()
    }

    func register(_ descriptor: LiveActivityDescriptor) throws -> LiveActivityRegistration {
        try validate(descriptor)
        guard entries[descriptor.id] == nil else {
            throw LiveActivityRegistrationError.duplicateID(descriptor.id)
        }
        let owner = UUID()
        entries[descriptor.id] = Entry(
            owner: owner, descriptor: nil, activationOrder: 0,
            expirationGeneration: UUID(), expiration: nil
        )
        try update(descriptor, owner: owner)
        return LiveActivityRegistration(id: descriptor.id, owner: owner, service: self)
    }

    func snapshot(in context: LiveActivityContext) -> LiveActivitySnapshot {
        let candidates = eligibleCandidates(in: context)
        let ordered = policy.orderedCandidates(candidates)
        let requestedID = policy.selectedID(
            from: candidates, userSelection: userSelections[SelectionContext(context)]
        )
        // A custom policy cannot resurrect an ineligible or expired activity.
        let selectedID = requestedID.flatMap { id in
            candidates.contains { $0.descriptor.id == id } ? id : nil
        }
        return LiveActivitySnapshot(activities: ordered.map(\.descriptor), selectedID: selectedID)
    }

    @discardableResult
    func select(_ id: LiveActivityID, in context: LiveActivityContext) -> Bool {
        let current = snapshot(in: context)
        guard current.selectedActivity?.presentation != .interrupt,
              current.cyclingActivities.contains(where: { $0.id == id }) else { return false }
        userSelections[SelectionContext(context)] = LiveActivityUserSelection(
            id: id, acknowledgedActivationOrder: activationOrder
        )
        publishChange()
        return true
    }

    @discardableResult
    func cycle(_ direction: LiveActivityCycleDirection = .next, in context: LiveActivityContext) -> Bool {
        let current = snapshot(in: context)
        guard current.canCycle else { return false }
        let activities = current.cyclingActivities
        let offset = direction == .next ? 1 : -1
        let currentIndex = activities.firstIndex { $0.id == current.selectedID }
            ?? (direction == .next ? -1 : 0)
        let index = (currentIndex + offset + activities.count) % activities.count
        return select(activities[index].id, in: context)
    }

    /// Forget UI state when a display permanently departs, without ending providers.
    func forgetSelection(for displayID: String?) {
        let previousCount = userSelections.count
        userSelections = userSelections.filter { $0.key.displayID != displayID }
        guard userSelections.count != previousCount else { return }
        publishChange()
    }

    /// Used by presentation registries to release renderers after terminal cleanup.
    var registeredIDs: Set<LiveActivityID> { Set(entries.keys) }

    fileprivate func update(_ descriptor: LiveActivityDescriptor, owner: UUID) throws {
        guard var entry = entries[descriptor.id], entry.owner == owner else {
            throw LiveActivityRegistrationError.unregistered
        }
        try validate(descriptor)
        entry.expiration?.cancel()
        entry.expiration = nil
        entry.expirationGeneration = UUID()

        if hasExpired(descriptor) {
            entry.descriptor = nil
            entries[descriptor.id] = entry
            clearSelection(of: descriptor.id)
            publishChange()
            return
        }

        if entry.descriptor == nil || entry.descriptor.map(hasExpired) == true {
            activationOrder &+= 1
            entry.activationOrder = activationOrder
        }
        entry.descriptor = descriptor
        entries[descriptor.id] = entry

        if case .until(let deadline) = descriptor.lifetime {
            let generation = entry.expirationGeneration
            let cancellation = scheduler.schedule(at: deadline) { [weak self] in
                self?.expire(descriptor.id, owner: owner, generation: generation)
            }
            // A test scheduler is allowed to deliver synchronously.
            if entries[descriptor.id]?.expirationGeneration == generation,
               entries[descriptor.id]?.descriptor != nil {
                entries[descriptor.id]?.expiration = cancellation
            } else {
                cancellation.cancel()
            }
        }
        publishChange()
    }

    fileprivate func end(_ id: LiveActivityID, owner: UUID) {
        guard var entry = entries[id], entry.owner == owner, entry.descriptor != nil else { return }
        entry.expiration?.cancel()
        entry.expiration = nil
        entry.expirationGeneration = UUID()
        entry.descriptor = nil
        entries[id] = entry
        clearSelection(of: id)
        publishChange()
    }

    fileprivate func unregister(_ id: LiveActivityID, owner: UUID) {
        guard let entry = entries[id], entry.owner == owner else { return }
        entry.expiration?.cancel()
        entries.removeValue(forKey: id)
        clearSelection(of: id)
        publishChange()
    }

    private func expire(_ id: LiveActivityID, owner: UUID, generation: UUID) {
        guard let entry = entries[id], entry.owner == owner,
              entry.expirationGeneration == generation,
              let descriptor = entry.descriptor, hasExpired(descriptor) else { return }
        end(id, owner: owner)
    }

    private func eligibleCandidates(in context: LiveActivityContext) -> [LiveActivityCandidate] {
        let candidates = entries.values.compactMap { entry -> LiveActivityCandidate? in
            guard let descriptor = entry.descriptor,
                  descriptor.surface == context.surface,
                  descriptor.displayScope.includes(context.displayID),
                  context.isPresentationEnabled || descriptor.presentation == .interrupt,
                  !hasExpired(descriptor) else { return nil }
            return LiveActivityCandidate(descriptor: descriptor, activationOrder: entry.activationOrder)
        }
        let hasActivity = candidates.contains { $0.descriptor.presentation == .activity }
        return candidates.filter { !hasActivity || $0.descriptor.presentation != .background }
    }

    private func hasExpired(_ descriptor: LiveActivityDescriptor) -> Bool {
        if case .until(let deadline) = descriptor.lifetime { return deadline <= scheduler.now }
        return false
    }

    private func validate(_ descriptor: LiveActivityDescriptor) throws {
        guard !descriptor.id.namespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !descriptor.id.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LiveActivityRegistrationError.invalidID
        }
        if case .until(let deadline) = descriptor.lifetime,
           !deadline.timeIntervalSinceReferenceDate.isFinite {
            throw LiveActivityRegistrationError.invalidDeadline
        }
    }

    private func clearSelection(of id: LiveActivityID) {
        userSelections = userSelections.filter { $0.value.id != id }
    }

    private func publishChange() { revision &+= 1 }
}
