//
//  NotchUIEvent.swift
//  boringNotch
//
//  Created as part of the architecture remediation.
//

import SwiftUI
import Combine

/// UI-presentation events emitted by hardware/OS-facing managers.
///
/// Inverts the old "manager calls `BoringViewCoordinator.shared`" direction:
/// the coordinator also *configures* those same managers (applyOSDSources),
/// so direct calls created a dependency cycle. Managers now publish events;
/// the coordinator is the single subscriber and decides what to present.
/// Presentation policy (e.g. `Defaults[.osdReplacement]`) lives on the
/// presenter side, and managers stay testable without the UI stack.
enum NotchUIEvent {
    case sneakPeek(
        type: SneakContentType,
        value: CGFloat,
        icon: String = "",
        accent: Color? = nil,
        targetScreenUUID: String? = nil
    )
    case expandingView(type: SneakContentType)
}

/// The event pipe. `BoringViewCoordinator` is the intended subscriber.
enum NotchUIEventBus {
    static let events = PassthroughSubject<NotchUIEvent, Never>()
}
