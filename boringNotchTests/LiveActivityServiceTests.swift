// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Combine
import Foundation
import XCTest
@testable import boringNotch

@MainActor
private final class ActivityTestScheduler: LiveActivityScheduling {
    private final class ScheduledAction {
        let deadline: Date
        let action: @MainActor () -> Void
        var cancelled = false
        var delivered = false

        init(deadline: Date, action: @escaping @MainActor () -> Void) {
            self.deadline = deadline
            self.action = action
        }
    }

    var now = Date(timeIntervalSinceReferenceDate: 1_000)
    private var actions: [ScheduledAction] = []

    func schedule(at deadline: Date, action: @escaping @MainActor () -> Void) -> AnyCancellable {
        let scheduled = ScheduledAction(deadline: deadline, action: action)
        actions.append(scheduled)
        return AnyCancellable { scheduled.cancelled = true }
    }

    func advance(by interval: TimeInterval, deliver: Bool = true) {
        now += interval
        guard deliver else { return }
        for scheduled in actions where !scheduled.cancelled && !scheduled.delivered && scheduled.deadline <= now {
            scheduled.delivered = true
            scheduled.action()
        }
    }

    /// Delivers a cancelled callback to exercise the ownership/generation defense.
    func deliverStaleCallback(at index: Int) { actions[index].action() }
}

@MainActor
final class LiveActivityServiceTests: XCTestCase {
    private let display = LiveActivityContext(displayID: "built-in")

    private func descriptor(
        _ name: String,
        priority: Int = 0,
        presentation: LiveActivityPresentation = .activity,
        lifetime: LiveActivityLifetime = .persistent,
        scope: LiveActivityDisplayScope = .all,
        participatesInCycling: Bool = true
    ) -> LiveActivityDescriptor {
        LiveActivityDescriptor(
            id: LiveActivityID(namespace: "test.provider", name: name),
            priority: priority, presentation: presentation,
            lifetime: lifetime, displayScope: scope,
            participatesInCycling: participatesInCycling
        )
    }

    func testNamespacesDoNotCollideAndDuplicateRegistrationsAreRejected() throws {
        let service = LiveActivityService()
        let first = descriptor("same")
        let other = LiveActivityDescriptor(id: LiveActivityID(namespace: "other.provider", name: "same"))
        let firstOwner = try service.register(first)
        let secondOwner = try service.register(other)
        defer { firstOwner.unregister(); secondOwner.unregister() }

        XCTAssertEqual(service.registeredIDs, [first.id, other.id])
        XCTAssertThrowsError(try service.register(first)) {
            XCTAssertEqual($0 as? LiveActivityRegistrationError, .duplicateID(first.id))
        }
        XCTAssertNotEqual(
            LiveActivityID(namespace: "a/b", name: "c"),
            LiveActivityID(namespace: "a", name: "b/c")
        )
    }

    func testNewHigherOrPeerPriorityActivityPreemptsAndResumesUserChoice() throws {
        let service = LiveActivityService()
        let music = descriptor("music", priority: 10)
        let timer = descriptor("timer", priority: 10)
        let musicOwner = try service.register(music)
        let timerOwner = try service.register(timer)
        defer { musicOwner.unregister(); timerOwner.unregister() }
        XCTAssertEqual(service.snapshot(in: display).selectedID, timer.id)
        XCTAssertTrue(service.select(music.id, in: display))

        let notification = descriptor("notification", priority: 100)
        let notificationOwner = try service.register(notification)
        XCTAssertEqual(service.snapshot(in: display).selectedID, notification.id)
        notificationOwner.unregister()
        XCTAssertEqual(service.snapshot(in: display).selectedID, music.id)

        let peer = descriptor("new-peer", priority: 10)
        let peerOwner = try service.register(peer)
        XCTAssertEqual(service.snapshot(in: display).selectedID, peer.id)
        peerOwner.end()
        XCTAssertEqual(service.snapshot(in: display).selectedID, music.id)
        peerOwner.unregister()
    }

    func testContentRefreshDoesNotStealFocusOrReorderActivities() throws {
        let service = LiveActivityService()
        let music = descriptor("music", priority: 10)
        let notice = descriptor("notice", priority: 100)
        let musicOwner = try service.register(music)
        let noticeOwner = try service.register(notice)
        defer { musicOwner.unregister(); noticeOwner.unregister() }
        XCTAssertTrue(service.select(music.id, in: display))

        for _ in 0..<3 { try noticeOwner.update(notice) }
        XCTAssertEqual(service.snapshot(in: display).selectedID, music.id)
        XCTAssertEqual(service.snapshot(in: display).activities.map(\.id), [notice.id, music.id])

        noticeOwner.end()
        try noticeOwner.update(notice)
        XCTAssertEqual(service.snapshot(in: display).selectedID, notice.id, "restarting is a new activation")
    }

    func testLowerPriorityArrivalDoesNotInterruptUserChoice() throws {
        let service = LiveActivityService()
        let preferred = descriptor("preferred", priority: 100)
        let preferredOwner = try service.register(preferred)
        XCTAssertTrue(service.select(preferred.id, in: display))
        let ambientOwner = try service.register(descriptor("ambient", priority: 0))
        defer { preferredOwner.unregister(); ambientOwner.unregister() }
        XCTAssertEqual(service.snapshot(in: display).selectedID, preferred.id)
    }

    func testInterruptCannotBeCycledAwayAndSurvivesOrdinarySuppression() throws {
        let service = LiveActivityService()
        let music = descriptor("music")
        let timer = descriptor("timer")
        let musicOwner = try service.register(music)
        let timerOwner = try service.register(timer)
        XCTAssertTrue(service.select(music.id, in: display))
        let osd = descriptor("osd", presentation: .interrupt, participatesInCycling: false)
        let osdOwner = try service.register(osd)
        defer { musicOwner.unregister(); timerOwner.unregister(); osdOwner.unregister() }

        XCTAssertEqual(service.snapshot(in: display).selectedID, osd.id)
        XCTAssertFalse(service.snapshot(in: display).canCycle)
        XCTAssertFalse(service.cycle(in: display))
        XCTAssertFalse(service.select(timer.id, in: display))
        let suppressed = LiveActivityContext(displayID: "built-in", isPresentationEnabled: false)
        XCTAssertEqual(service.snapshot(in: suppressed).activities.map(\.id), [osd.id])
        osdOwner.end()
        XCTAssertNil(service.snapshot(in: suppressed).selectedID)
        XCTAssertEqual(service.snapshot(in: display).selectedID, music.id)
    }

    func testPerDisplayEligibilityAndSelectionAreIndependent() throws {
        let service = LiveActivityService()
        let primary = descriptor("primary", scope: .displays(["built-in"]))
        let global = descriptor("global")
        let primaryOwner = try service.register(primary)
        let globalOwner = try service.register(global)
        defer { primaryOwner.unregister(); globalOwner.unregister() }
        let external = LiveActivityContext(displayID: "external")
        XCTAssertTrue(service.select(primary.id, in: display))
        XCTAssertFalse(service.select(primary.id, in: external))
        XCTAssertEqual(service.snapshot(in: display).selectedID, primary.id)
        XCTAssertEqual(service.snapshot(in: external).selectedID, global.id)
        XCTAssertEqual(service.snapshot(in: LiveActivityContext(displayID: nil)).activities.map(\.id), [global.id])

        XCTAssertTrue(service.cycle(.next, in: display))
        XCTAssertEqual(service.snapshot(in: display).selectedID, global.id)
        XCTAssertTrue(service.cycle(.previous, in: display))
        XCTAssertEqual(service.snapshot(in: display).selectedID, primary.id)
    }

    func testBackgroundIsOnlyAvailableWhenOrdinaryActivitiesAreAbsent() throws {
        let service = LiveActivityService()
        let background = descriptor("face", priority: 1000, presentation: .background)
        let backgroundOwner = try service.register(background)
        let music = descriptor("music")
        let musicOwner = try service.register(music)
        defer { backgroundOwner.unregister(); musicOwner.unregister() }
        XCTAssertEqual(service.snapshot(in: display).activities.map(\.id), [music.id])
        musicOwner.end()
        XCTAssertEqual(service.snapshot(in: display).selectedID, background.id)
        XCTAssertFalse(service.snapshot(in: display).canCycle)
        XCTAssertFalse(service.select(background.id, in: display))
    }

    func testExpiryRestoresSelectionAndRenewalRejectsStaleTimer() throws {
        let scheduler = ActivityTestScheduler()
        let service = LiveActivityService(scheduler: scheduler)
        let music = descriptor("music")
        let musicOwner = try service.register(music)
        XCTAssertTrue(service.select(music.id, in: display))
        var notice = descriptor("notice", priority: 100, lifetime: .until(scheduler.now + 5))
        let noticeOwner = try service.register(notice)
        defer { musicOwner.unregister(); noticeOwner.unregister() }
        XCTAssertEqual(service.snapshot(in: display).selectedID, notice.id)

        scheduler.advance(by: 3)
        notice.lifetime = .until(scheduler.now + 10)
        try noticeOwner.update(notice)
        scheduler.advance(by: 3)
        scheduler.deliverStaleCallback(at: 0)
        XCTAssertEqual(service.snapshot(in: display).selectedID, notice.id)
        scheduler.advance(by: 7)
        XCTAssertEqual(service.snapshot(in: display).selectedID, music.id)
        XCTAssertTrue(service.registeredIDs.contains(notice.id), "expiry ends the activation, not provider ownership")
    }

    func testExpiredCandidatesAreHiddenEvenBeforeTimerDelivery() throws {
        let scheduler = ActivityTestScheduler()
        let service = LiveActivityService(scheduler: scheduler)
        let activity = descriptor("transient", lifetime: .until(scheduler.now + 1))
        let owner = try service.register(activity)
        defer { owner.unregister() }
        scheduler.advance(by: 2, deliver: false)
        XCTAssertTrue(service.snapshot(in: display).activities.isEmpty)
    }

    func testOldRegistrationAndCancelledExpiryCannotTouchReusedID() throws {
        let scheduler = ActivityTestScheduler()
        let service = LiveActivityService(scheduler: scheduler)
        let activity = descriptor("reused", lifetime: .until(scheduler.now + 2))
        let oldOwner = try service.register(activity)
        oldOwner.unregister()
        let replacement = descriptor("reused")
        let newOwner = try service.register(replacement)
        defer { newOwner.unregister() }
        oldOwner.end()
        oldOwner.unregister()
        XCTAssertThrowsError(try oldOwner.update(activity))
        scheduler.advance(by: 3)
        scheduler.deliverStaleCallback(at: 0)
        XCTAssertEqual(service.snapshot(in: display).selectedID, replacement.id)
    }

    func testEndedOwnerRetainsReservationAndRejectsIdentityMutation() throws {
        let service = LiveActivityService()
        let activity = descriptor("owned")
        let owner = try service.register(activity)
        owner.end()
        XCTAssertTrue(service.snapshot(in: display).activities.isEmpty)
        XCTAssertThrowsError(try service.register(activity))
        XCTAssertThrowsError(try owner.update(descriptor("different"))) {
            XCTAssertEqual(
                $0 as? LiveActivityRegistrationError,
                .mismatchedID(expected: activity.id, actual: self.descriptor("different").id)
            )
        }
        try owner.update(activity)
        XCTAssertEqual(service.snapshot(in: display).selectedID, activity.id)
        owner.unregister()
        XCTAssertFalse(service.registeredIDs.contains(activity.id))
    }

    func testInvalidInputIsRejectedWithoutReplacingExistingActivity() throws {
        let service = LiveActivityService()
        let emptyID = LiveActivityDescriptor(id: LiveActivityID(namespace: " ", name: "test"))
        XCTAssertThrowsError(try service.register(emptyID))
        let activity = descriptor("valid")
        let owner = try service.register(activity)
        defer { owner.unregister() }
        var invalid = activity
        invalid.lifetime = .until(Date(timeIntervalSinceReferenceDate: .infinity))
        XCTAssertThrowsError(try owner.update(invalid))
        XCTAssertEqual(service.snapshot(in: display).selectedID, activity.id)
    }

    func testSelectionPolicyCanBeReplacedWithoutChangingLifecycle() throws {
        struct AlphabeticalPolicy: LiveActivitySelectionPolicy {
            func orderedCandidates(_ candidates: [LiveActivityCandidate]) -> [LiveActivityCandidate] {
                candidates.sorted { $0.descriptor.id.name < $1.descriptor.id.name }
            }
            func selectedID(from candidates: [LiveActivityCandidate], userSelection: LiveActivityUserSelection?) -> LiveActivityID? {
                orderedCandidates(candidates).first?.descriptor.id
            }
        }
        let service = LiveActivityService(policy: AlphabeticalPolicy())
        let first = descriptor("a", priority: -100)
        let firstOwner = try service.register(first)
        let secondOwner = try service.register(descriptor("z", priority: 100))
        defer { firstOwner.unregister(); secondOwner.unregister() }
        XCTAssertEqual(service.snapshot(in: display).selectedID, first.id)
    }

    func testSurfaceBoundaryExcludesDesktopContentIncludingInterrupts() throws {
        let service = LiveActivityService()
        let desktop = descriptor("private-notification", priority: 1000, presentation: .interrupt)
        var badge = descriptor("public-badge", priority: -100)
        badge.surface = .lockScreen
        let desktopOwner = try service.register(desktop)
        let badgeOwner = try service.register(badge)
        defer { desktopOwner.unregister(); badgeOwner.unregister() }
        let locked = LiveActivityContext(displayID: "built-in", surface: .lockScreen)
        XCTAssertEqual(service.snapshot(in: display).activities.map(\.id), [desktop.id])
        XCTAssertEqual(service.snapshot(in: locked).activities.map(\.id), [badge.id])
        badgeOwner.unregister()
        XCTAssertNil(service.snapshot(in: locked).selectedID)
    }

    func testSelectionIsIndependentForEachSurfaceOnTheSameDisplay() throws {
        let service = LiveActivityService()
        let desktopA = descriptor("desktop-a")
        let desktopB = descriptor("desktop-b")
        var lockedA = descriptor("locked-a")
        lockedA.surface = .lockScreen
        var lockedB = descriptor("locked-b")
        lockedB.surface = .lockScreen
        let registrations = try [desktopA, desktopB, lockedA, lockedB].map(service.register)
        defer { registrations.forEach { $0.unregister() } }
        let locked = LiveActivityContext(displayID: "built-in", surface: .lockScreen)
        XCTAssertTrue(service.select(desktopA.id, in: display))
        XCTAssertTrue(service.select(lockedA.id, in: locked))
        XCTAssertEqual(service.snapshot(in: display).selectedID, desktopA.id)
        XCTAssertEqual(service.snapshot(in: locked).selectedID, lockedA.id)
        XCTAssertFalse(service.select(desktopB.id, in: locked))
        service.forgetSelection(for: "built-in")
        XCTAssertEqual(service.snapshot(in: display).selectedID, desktopB.id)
        XCTAssertEqual(service.snapshot(in: locked).selectedID, lockedB.id)
    }
}
