import Foundation
import XCTest

final class CodexCallbackRoutingTests: XCTestCase {
    func testCodexDeepLinksAreOpenedWithTheOfficialApplication() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let managerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "boringNotch/features/CodexNotifications/CodexNotificationManager.swift"
            ),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "boringNotch/components/Settings/Views/CodexNotificationSettingsView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            managerSource.contains("withApplicationAt: applicationURL"),
            "Codex deep links must be opened with the official Codex application URL."
        )
        XCTAssertFalse(
            managerSource.contains("NSWorkspace.shared.open(threadURL)"),
            "Thread URLs must not be sent to the machine's generic codex: scheme handler."
        )
        XCTAssertTrue(
            settingsSource.contains(
                "CodexNotificationManager.shared.openCodex(at: hooksURL)"
            ),
            "The settings action must use the same targeted Codex launcher."
        )
        XCTAssertFalse(
            settingsSource.contains("NSWorkspace.shared.open(hooksURL)"),
            "Settings URLs must not be sent to the machine's generic codex: scheme handler."
        )
    }
}
