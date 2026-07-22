import SwiftUI
import XCTest
@testable import boringNotch

@MainActor
final class PomodoroDomainTests: XCTestCase {
    func testPomodoroPhaseMetadataIsStable() {
        XCTAssertEqual(PomodoroPhase.focus.systemImage, "brain.head.profile")
        XCTAssertEqual(PomodoroPhase.shortBreak.systemImage, "cup.and.saucer")
        XCTAssertEqual(PomodoroPhase.longBreak.systemImage, "figure.walk")

        XCTAssertEqual(PomodoroPhase.focus.tintColor, .red)
        XCTAssertEqual(PomodoroPhase.shortBreak.tintColor, .green)
        XCTAssertEqual(PomodoroPhase.longBreak.tintColor, .blue)
    }

    func testPomodoroPhaseAlertModeHasExpectedCases() {
        XCTAssertEqual(Set(PomodoroPhaseAlertMode.allCases), Set([.none, .inline, .system, .both]))
    }

    func testShouldShowPanelInHomeDependsOnBothFlags() {
        let timer = PomodoroTimerViewModel.shared
        XCTAssertTrue(timer.shouldShowPanelInHome(panelEnabled: true, isSelectedInHome: true))
        XCTAssertFalse(timer.shouldShowPanelInHome(panelEnabled: false, isSelectedInHome: true))
        XCTAssertFalse(timer.shouldShowPanelInHome(panelEnabled: true, isSelectedInHome: false))
    }
}
