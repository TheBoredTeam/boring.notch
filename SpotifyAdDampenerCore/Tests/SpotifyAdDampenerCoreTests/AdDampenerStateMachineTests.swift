import XCTest
@testable import SpotifyAdDampenerCore

final class AdDampenerStateMachineTests: XCTestCase {
    func testIdleAdNotInCallLowersAndPersistsSession() {
        var machine = AdDampenerStateMachine(settingsEnabled: true, targetVolume: 0.2, now: { Date(timeIntervalSince1970: 10) }, uuid: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! })
        XCTAssertEqual(machine.handle(.currentSystemVolume(0.8)), [])
        let commands = machine.handle(.spotifyPlayback(.init(kind: .ad, isPlaying: true, progressMs: 1, durationMs: 2)))
        let session = DampeningSession(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, savedVolume: 0.8, targetVolume: 0.2, startedAt: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(commands, [.lowerVolume(to: 0.2, save: 0.8, sessionID: session.id), .persistOwnedSession(session)])
        XCTAssertEqual(machine.state, .dampened(session))
    }

    func testDampenedTrackNotPlayingAuthAndNetworkFailureRestoreAndClear() {
        for event in [AdDampenerEvent.spotifyPlayback(.init(kind: .track, isPlaying: true, progressMs: nil, durationMs: nil)), .spotifyPlayback(.init(kind: .notPlaying, isPlaying: false, progressMs: nil, durationMs: nil)), .authFailed, .networkFailed] {
            var machine = dampenedMachine()
            let commands = machine.handle(event)
            XCTAssertEqual(commands, [.restoreVolume(to: 0.8, sessionID: testSession.id), .clearOwnedSession])
            XCTAssertEqual(machine.state, .idle)
        }
    }

    func testIdleAdWhileCallActiveSuppresses() {
        var machine = AdDampenerStateMachine(settingsEnabled: true, targetVolume: 0.2)
        _ = machine.handle(.currentSystemVolume(0.8))
        _ = machine.handle(.callActive(true))
        XCTAssertEqual(machine.handle(.spotifyPlayback(.init(kind: .ad, isPlaying: true, progressMs: nil, durationMs: nil))), [])
        XCTAssertEqual(machine.state, .suppressedByCall)
    }

    func testDampenedCallActiveRestores() {
        var machine = dampenedMachine()
        XCTAssertEqual(machine.handle(.callActive(true)), [.restoreVolume(to: 0.8, sessionID: testSession.id), .clearOwnedSession])
        XCTAssertEqual(machine.state, .suppressedByCall)
    }

    func testManualVolumeOverrideStopsEnforcingAndDoesNotRestore() {
        var machine = dampenedMachine()
        XCTAssertEqual(machine.handle(.manualVolumeChanged(0.5)), [.clearOwnedSession])
        XCTAssertEqual(machine.state, .idle)
    }

    func testLaunchWithPersistedOwnedSessionRestoresOnceAndClears() {
        var machine = AdDampenerStateMachine(settingsEnabled: true, targetVolume: 0.2)
        XCTAssertEqual(machine.handle(.appLaunchedWithOwnedSession(testSession)), [.restoreVolume(to: 0.8, sessionID: testSession.id), .clearOwnedSession])
        XCTAssertEqual(machine.handle(.appLaunchedWithOwnedSession(testSession)), [])
    }

    func testTargetVolumeChangeAffectsNextAdWithoutRelaunch() {
        var machine = AdDampenerStateMachine(settingsEnabled: true, targetVolume: 0.2, now: { Date(timeIntervalSince1970: 11) }, uuid: { UUID(uuidString: "00000000-0000-0000-0000-000000000002")! })
        XCTAssertEqual(machine.handle(.currentSystemVolume(0.9)), [])
        XCTAssertEqual(machine.handle(.targetVolumeChanged(0.07)), [])
        let commands = machine.handle(.spotifyPlayback(.init(kind: .ad, isPlaying: true, progressMs: 1, durationMs: 2)))
        let session = DampeningSession(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, savedVolume: 0.9, targetVolume: 0.07, startedAt: Date(timeIntervalSince1970: 11))
        XCTAssertEqual(commands, [.lowerVolume(to: 0.07, save: 0.9, sessionID: session.id), .persistOwnedSession(session)])
        XCTAssertEqual(machine.state, .dampened(session))
    }

    private var testSession: DampeningSession { DampeningSession(id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!, savedVolume: 0.8, targetVolume: 0.2, startedAt: Date(timeIntervalSince1970: 1)) }
    private func dampenedMachine() -> AdDampenerStateMachine {
        AdDampenerStateMachine(settingsEnabled: true, targetVolume: 0.2, initialState: .dampened(testSession))
    }
}
