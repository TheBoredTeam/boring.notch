//
//  NotchUIEvent.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Created as part of the architecture remediation.
//

import SwiftUI
import Combine

/// Payload for `.notification` sneak peeks: the passive marquee mirror of
/// a banner's content — icon/title/body travel with the event so peek
/// rendering never needs to reach back into the notification queue.
struct NotificationPeekPayload {
    var appName: String?
    var title: String?
    var body: String?
    var bundleID: String?
}

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
        targetScreenUUID: String? = nil,
        duration: TimeInterval = 1.5,
        payload: NotificationPeekPayload? = nil
    )
    case expandingView(type: SneakContentType)
}

/// The event pipe. `BoringViewCoordinator` is the intended subscriber.
enum NotchUIEventBus {
    static let events = PassthroughSubject<NotchUIEvent, Never>()
}
