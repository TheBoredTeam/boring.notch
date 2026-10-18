// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Foundation

/// The namespace belongs to a provider; the name identifies one of its activities.
/// Keeping both components avoids delimiter collisions in extension supplied IDs.
struct LiveActivityID: Hashable, Sendable, CustomStringConvertible {
    let namespace: String
    let name: String

    var description: String { "\(namespace)/\(name)" }
}

enum LiveActivityPresentation: Sendable {
    /// Ordinary content that the user can browse.
    case activity
    /// A temporary system presentation that takes ownership of the slot.
    case interrupt
    /// Fallback content, eligible only when no ordinary activity is available.
    case background
}

/// Content must explicitly opt into the locked surface. Ordinary activities,
/// including system interrupts, never cross this boundary implicitly.
enum LiveActivitySurface: String, Codable, CaseIterable, Hashable, Sendable {
    case desktop
    case lockScreen
}

struct LiveActivitySessionState: Equatable, Sendable {
    var isLocked = false
    var isAwake = true
    var isSessionActive = true

    var canPresentOnLockScreen: Bool { isLocked && isAwake && isSessionActive }
}

enum LiveActivityLifetime: Equatable, Sendable {
    case persistent
    case until(Date)
}

enum LiveActivityDisplayScope: Equatable, Sendable {
    case all
    case displays(Set<String>)

    func includes(_ displayID: String?) -> Bool {
        switch self {
        case .all: return true
        case .displays(let identifiers):
            return displayID.map(identifiers.contains) ?? false
        }
    }
}

struct LiveActivityDescriptor: Equatable, Sendable, Identifiable {
    let id: LiveActivityID
    var priority: Int
    var presentation: LiveActivityPresentation
    var lifetime: LiveActivityLifetime
    var displayScope: LiveActivityDisplayScope
    var surface: LiveActivitySurface
    var participatesInCycling: Bool

    init(
        id: LiveActivityID,
        priority: Int = 0,
        presentation: LiveActivityPresentation = .activity,
        lifetime: LiveActivityLifetime = .persistent,
        displayScope: LiveActivityDisplayScope = .all,
        surface: LiveActivitySurface = .desktop,
        participatesInCycling: Bool = true
    ) {
        self.id = id
        self.priority = priority
        self.presentation = presentation
        self.lifetime = lifetime
        self.displayScope = displayScope
        self.surface = surface
        self.participatesInCycling = participatesInCycling
    }
}

struct LiveActivityContext: Equatable, Sendable {
    let displayID: String?
    let surface: LiveActivitySurface
    var isPresentationEnabled: Bool

    init(displayID: String?, surface: LiveActivitySurface = .desktop, isPresentationEnabled: Bool = true) {
        self.displayID = displayID
        self.surface = surface
        self.isPresentationEnabled = isPresentationEnabled
    }
}

enum LiveActivityCycleDirection: Sendable {
    case next
    case previous
}

struct LiveActivitySnapshot: Equatable, Sendable {
    /// Eligible activities, ordered by the injected policy.
    let activities: [LiveActivityDescriptor]
    let selectedID: LiveActivityID?

    var selectedActivity: LiveActivityDescriptor? {
        activities.first { $0.id == selectedID }
    }

    var cyclingActivities: [LiveActivityDescriptor] {
        activities.filter { $0.presentation == .activity && $0.participatesInCycling }
    }

    var canCycle: Bool {
        selectedActivity?.presentation != .interrupt && cyclingActivities.count > 1
    }
}

enum LiveActivityRegistrationError: Error, Equatable {
    case invalidID
    case duplicateID(LiveActivityID)
    case mismatchedID(expected: LiveActivityID, actual: LiveActivityID)
    case unregistered
    case invalidDeadline
}
