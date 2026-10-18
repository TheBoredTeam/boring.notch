// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Foundation

/// Activation order changes only when an activity begins or resumes after `end`.
/// Progress, artwork and other content updates cannot repeatedly steal focus.
struct LiveActivityCandidate: Equatable, Sendable {
    let descriptor: LiveActivityDescriptor
    let activationOrder: UInt64
}

struct LiveActivityUserSelection: Equatable, Sendable {
    let id: LiveActivityID
    /// Activities already present when the user made this choice are acknowledged.
    let acknowledgedActivationOrder: UInt64
}

/// An application policy sees value types only: no views, transports or managers.
/// Filtering by display, lifetime and presentation context is the service's job.
protocol LiveActivitySelectionPolicy {
    func orderedCandidates(_ candidates: [LiveActivityCandidate]) -> [LiveActivityCandidate]
    func selectedID(
        from candidates: [LiveActivityCandidate],
        userSelection: LiveActivityUserSelection?
    ) -> LiveActivityID?
}

struct DefaultLiveActivitySelectionPolicy: LiveActivitySelectionPolicy {
    func orderedCandidates(_ candidates: [LiveActivityCandidate]) -> [LiveActivityCandidate] {
        candidates.sorted { lhs, rhs in
            let lhsPresentation = rank(lhs.descriptor.presentation)
            let rhsPresentation = rank(rhs.descriptor.presentation)
            if lhsPresentation != rhsPresentation { return lhsPresentation > rhsPresentation }
            if lhs.descriptor.priority != rhs.descriptor.priority {
                return lhs.descriptor.priority > rhs.descriptor.priority
            }
            if lhs.activationOrder != rhs.activationOrder {
                return lhs.activationOrder > rhs.activationOrder
            }
            if lhs.descriptor.id.namespace != rhs.descriptor.id.namespace {
                return lhs.descriptor.id.namespace < rhs.descriptor.id.namespace
            }
            return lhs.descriptor.id.name < rhs.descriptor.id.name
        }
    }

    func selectedID(
        from candidates: [LiveActivityCandidate],
        userSelection: LiveActivityUserSelection?
    ) -> LiveActivityID? {
        let ordered = orderedCandidates(candidates)
        if let interrupt = ordered.first(where: { $0.descriptor.presentation == .interrupt }) {
            return interrupt.descriptor.id
        }
        guard let selection = userSelection,
              let preferred = ordered.first(where: { $0.descriptor.id == selection.id }) else {
            return ordered.first?.descriptor.id
        }

        // A new peer or higher priority activity may interrupt, but the saved user
        // choice remains intact and is restored when the interrupting item ends.
        if let incoming = ordered.first(where: {
            $0.descriptor.presentation == .activity
                && $0.activationOrder > selection.acknowledgedActivationOrder
                && $0.descriptor.priority >= preferred.descriptor.priority
        }) {
            return incoming.descriptor.id
        }
        return preferred.descriptor.id
    }

    private func rank(_ presentation: LiveActivityPresentation) -> Int {
        switch presentation {
        case .interrupt: return 2
        case .activity: return 1
        case .background: return 0
        }
    }
}
