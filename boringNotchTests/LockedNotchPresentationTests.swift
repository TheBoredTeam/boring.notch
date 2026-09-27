import Combine
import XCTest
@testable import boringNotch

@MainActor
final class LockedNotchPresentationTests: XCTestCase {
    func testUnlockFinishesOnceAndLeavesNoTask() async {
        let presentation = LockedNotchPresentation()
        let completed = expectation(description: "unlock completed")
        var phases: [LockedNotchPresentation.Phase] = []
        let subscription = presentation.$phase.sink { phases.append($0) }
        presentation.unlock(reduceMotion: false) { completed.fulfill() }
        presentation.unlock(reduceMotion: false) { XCTFail("duplicate unlock must not replay") }
        XCTAssertEqual(presentation.phase, .unlocked)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(phases, [.locked, .unlocked, .dismissed])
        XCTAssertFalse(presentation.isTransitioning)
        withExtendedLifetime(subscription) {}
    }

    func testRelockCancelsOldCompletionAndCanUnlockAgain() async throws {
        let presentation = LockedNotchPresentation()
        presentation.unlock(reduceMotion: false) { XCTFail("stale completion must not restore the notch") }
        try await Task.sleep(for: .milliseconds(50))
        presentation.cancel()
        XCTAssertEqual(presentation.phase, .locked)
        XCTAssertFalse(presentation.isTransitioning)
        let completed = expectation(description: "new unlock completed")
        presentation.unlock(reduceMotion: true) { completed.fulfill() }
        await fulfillment(of: [completed], timeout: 2)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(presentation.phase, .dismissed)
        XCTAssertFalse(presentation.isTransitioning)
    }

    func testCancellationDuringFadeDoesNotRestoreNotch() async throws {
        let presentation = LockedNotchPresentation()
        let fading = expectation(description: "fade started")
        let subscription = presentation.$phase.filter { $0 == .dismissed }.first().sink { _ in fading.fulfill() }
        presentation.unlock(reduceMotion: false) { XCTFail("cancelled fade must not restore notch") }
        await fulfillment(of: [fading], timeout: 2)
        presentation.cancel()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(presentation.phase, .locked)
        XCTAssertFalse(presentation.isTransitioning)
        withExtendedLifetime(subscription) {}
    }

    func testTaskDoesNotKeepPresentationAlive() async throws {
        var presentation: LockedNotchPresentation? = LockedNotchPresentation()
        weak var reference = presentation
        presentation?.unlock(reduceMotion: false) { XCTFail("released presentation must not complete") }
        presentation = nil
        XCTAssertNil(reference)
        try await Task.sleep(for: .milliseconds(650))
    }
}
