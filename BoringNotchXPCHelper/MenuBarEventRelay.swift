//
//  MenuBarEventRelay.swift
//  BoringNotchXPCHelper
//
//  The three-stage event barrier is adapted from Ice 2's macOS 26 menu bar
//  item event handling (Copyright (c) 2024 Jordan Baird and
//  Copyright (c) 2026 Teddy Chan, GPL-3.0-or-later).
//

import CoreGraphics
import OSLog

/// Passes a targeted menu bar event from the source process, through the
/// session event stream, and back to the source process. WindowServer only
/// treats synthetic Command-drags as real status-item moves when the event is
/// observed at every stage of that route.
final class MenuBarEventRelay {
    private enum Stage: String {
        case processBarrier = "process barrier"
        case sessionEvent = "session event"
        case processEvent = "process event"
    }

    private final class TapContext {
        weak var relay: MenuBarEventRelay?
        let stage: Stage

        init(stage: Stage) {
            self.stage = stage
        }
    }

    private let event: CGEvent
    private let processIdentifier: pid_t
    private let completion: (Bool) -> Void
    private let entryMarker = Int64(UInt32.random(in: 1...UInt32.max))
    private let exitMarker = Int64(UInt32.random(in: 1...UInt32.max))
    private var remainingRepetitions: Int

    private let barrierContext = TapContext(stage: .processBarrier)
    private let sessionContext = TapContext(stage: .sessionEvent)
    private let processContext = TapContext(stage: .processEvent)

    private var barrierTap: CFMachPort?
    private var sessionTap: CFMachPort?
    private var processTap: CFMachPort?
    private var barrierSource: CFRunLoopSource?
    private var sessionSource: CFRunLoopSource?
    private var processSource: CFRunLoopSource?
    private var isFinished = false
    private var lastObservedStage: Stage?
    private var receivedEntryBarrier = false
    private var usesDirectDelivery = false

    private static let logger = Logger(
        subsystem: "theboringteam.boringnotch.helper",
        category: "MenuBarEventRelay"
    )

    init?(
        event: CGEvent,
        processIdentifier: pid_t,
        repetitions: Int = 1,
        completion: @escaping (Bool) -> Void
    ) {
        guard repetitions > 0 else { return nil }

        self.event = event
        self.processIdentifier = processIdentifier
        self.remainingRepetitions = repetitions
        self.completion = completion

        barrierContext.relay = self
        sessionContext.relay = self
        processContext.relay = self

        guard let barrierTap = CGEvent.tapCreateForPid(
            pid: processIdentifier,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: 1 << CGEventType.null.rawValue,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(barrierContext).toOpaque()
        ), let sessionTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: 1 << event.type.rawValue,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(sessionContext).toOpaque()
        ), let processTap = CGEvent.tapCreateForPid(
            pid: processIdentifier,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: 1 << event.type.rawValue,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(processContext).toOpaque()
        ) else {
            return nil
        }

        self.barrierTap = barrierTap
        self.sessionTap = sessionTap
        self.processTap = processTap
        barrierSource = CFMachPortCreateRunLoopSource(nil, barrierTap, 0)
        sessionSource = CFMachPortCreateRunLoopSource(nil, sessionTap, 0)
        processSource = CFMachPortCreateRunLoopSource(nil, processTap, 0)

        guard barrierSource != nil, sessionSource != nil, processSource != nil else {
            return nil
        }
    }

    func start() {
        guard let barrierTap,
              let sessionTap,
              let processTap,
              let barrierSource,
              let sessionSource,
              let processSource else {
            finish(success: false)
            return
        }

        let runLoop = CFRunLoopGetMain()
        // Match Ice's ordering: enable each tap before attaching its source to
        // the run loop. This avoids losing the entry event during setup.
        CGEvent.tapEnable(tap: barrierTap, enable: true)
        CGEvent.tapEnable(tap: sessionTap, enable: true)
        CGEvent.tapEnable(tap: processTap, enable: true)
        CFRunLoopAddSource(runLoop, barrierSource, .commonModes)
        CFRunLoopAddSource(runLoop, sessionSource, .commonModes)
        CFRunLoopAddSource(runLoop, processSource, .commonModes)

        postBarrier(marker: entryMarker)

        // In an embedded XPC service macOS 26 can accept a per-PID event tap
        // while silently dropping null events posted to that PID. Ice runs its
        // relay in a normal application process and does not hit this case.
        // If the entry barrier is not acknowledged promptly, start the real
        // event through the already-installed session and process taps. The
        // process tap remains the acknowledgement, so this does not report a
        // move as delivered merely because it was posted.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self,
                  !self.isFinished,
                  !self.receivedEntryBarrier else { return }
            self.usesDirectDelivery = true
            Self.logger.notice(
                "PID null barrier unavailable; using direct acknowledged delivery pid=\(self.processIdentifier, privacy: .public)"
            )
            self.postNextDirectEvent()
        }

        // A busy menu extra can occasionally take longer than Ice's adaptive
        // 50...300 ms window. Give the XPC helper enough time to service all
        // three taps without treating main-run-loop scheduling as a failure.
        let timeout = 0.75 * Double(remainingRepetitions)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, !self.isFinished else { return }
            let lastStage = self.lastObservedStage?.rawValue ?? "none"
            Self.logger.error(
                "Event relay timed out pid=\(self.processIdentifier, privacy: .public) lastStage=\(lastStage, privacy: .public)"
            )
            self.finish(success: false)
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = {
        _, type, incomingEvent, contextPointer in
        guard let contextPointer else {
            return Unmanaged.passUnretained(incomingEvent)
        }
        let context = Unmanaged<TapContext>
            .fromOpaque(contextPointer)
            .takeUnretainedValue()
        guard let relay = context.relay else {
            return Unmanaged.passUnretained(incomingEvent)
        }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            relay.enableTap(for: context.stage)
            return nil
        }
        return relay.handle(
            incomingEvent,
            type: type,
            at: context.stage
        ).map(Unmanaged.passUnretained)
    }

    private func handle(
        _ incomingEvent: CGEvent,
        type: CGEventType,
        at stage: Stage
    ) -> CGEvent? {
        guard !isFinished else { return incomingEvent }

        switch stage {
        case .processBarrier:
            guard type == .null else { return incomingEvent }
            let marker = incomingEvent.getIntegerValueField(.eventSourceUserData)
            if marker == entryMarker {
                guard !usesDirectDelivery else { return nil }
                lastObservedStage = .processBarrier
                receivedEntryBarrier = true
                remainingRepetitions -= 1
                event.post(tap: .cgSessionEventTap)
                return nil
            }
            if marker == exitMarker {
                guard !usesDirectDelivery else { return nil }
                lastObservedStage = .processBarrier
                finishAfterCurrentEvent(success: true)
                return nil
            }
            return incomingEvent

        case .sessionEvent:
            guard matches(incomingEvent) else { return incomingEvent }
            lastObservedStage = .sessionEvent
            if remainingRepetitions <= 0, let sessionTap {
                CGEvent.tapEnable(tap: sessionTap, enable: false)
            }
            event.postToPid(processIdentifier)
            // CGEventPost to the session stream does not reliably preserve
            // eventTargetUnixProcessID on macOS 26. WindowServer needs the
            // session copy to remain targeted in addition to the explicit PID
            // copy above, otherwise a Command-drag is not recognized.
            incomingEvent.setIntegerValueField(
                .eventTargetUnixProcessID,
                value: Int64(processIdentifier)
            )
            return incomingEvent

        case .processEvent:
            guard matches(incomingEvent) else { return incomingEvent }
            lastObservedStage = .processEvent
            if usesDirectDelivery {
                if remainingRepetitions <= 0 {
                    finishAfterCurrentEvent(success: true)
                } else {
                    postNextDirectEvent()
                }
            } else if remainingRepetitions <= 0 {
                if let processTap {
                    CGEvent.tapEnable(tap: processTap, enable: false)
                }
                postBarrier(marker: exitMarker)
            } else {
                postBarrier(marker: entryMarker)
            }
            incomingEvent.setIntegerValueField(
                .eventTargetUnixProcessID,
                value: Int64(processIdentifier)
            )
            return incomingEvent
        }
    }

    private func postNextDirectEvent() {
        guard !isFinished, remainingRepetitions > 0 else { return }
        remainingRepetitions -= 1
        event.post(tap: .cgSessionEventTap)
    }

    private func matches(_ incomingEvent: CGEvent) -> Bool {
        let fields: [CGEventField] = [
            .eventSourceUserData,
            .mouseEventWindowUnderMousePointer,
            .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
            .menuBarWindowID,
        ]
        return fields.allSatisfy {
            incomingEvent.getIntegerValueField($0) == event.getIntegerValueField($0)
        }
    }

    private func postBarrier(marker: Int64) {
        guard let barrierEvent = CGEvent(source: nil) else {
            finish(success: false)
            return
        }
        barrierEvent.setIntegerValueField(.eventSourceUserData, value: marker)
        barrierEvent.postToPid(processIdentifier)
    }

    private func enableTap(for stage: Stage) {
        let tap: CFMachPort? = switch stage {
        case .processBarrier: barrierTap
        case .sessionEvent: sessionTap
        case .processEvent: processTap
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    /// Event-tap callbacks can be invoked while WindowServer is still routing
    /// the event returned by this relay. Tear the taps down on the next main
    /// run-loop turn so the acknowledged event can finish that route first.
    private func finishAfterCurrentEvent(success: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.finish(success: success)
        }
    }

    private func finish(success: Bool) {
        guard !isFinished else { return }
        isFinished = true

        let runLoop = CFRunLoopGetMain()
        if let barrierSource {
            CFRunLoopRemoveSource(runLoop, barrierSource, .commonModes)
        }
        if let sessionSource {
            CFRunLoopRemoveSource(runLoop, sessionSource, .commonModes)
        }
        if let processSource {
            CFRunLoopRemoveSource(runLoop, processSource, .commonModes)
        }
        [barrierTap, sessionTap, processTap].forEach { tap in
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
        }
        completion(success)
    }
}

private extension CGEventField {
    static let menuBarWindowID = CGEventField(rawValue: 0x33)!
}
