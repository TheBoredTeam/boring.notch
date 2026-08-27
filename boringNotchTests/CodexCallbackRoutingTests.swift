import Foundation
import XCTest
@testable import CodexNotificationsCore

@MainActor
final class CodexCallbackRoutingTests: XCTestCase {
    func testThreadRouteTargetsTheOfficialCodexApplication() async throws {
        let workspace = RecordingCodexWorkspace()
        workspace.applicationURL = URL(fileURLWithPath: "/Applications/Codex.app")
        let launcher = CodexApplicationLauncher(workspace: workspace)
        let threadURL = try XCTUnwrap(
            CodexApplicationRoute.threadURL(sessionID: "thread:with/slashes")
        )

        try await launcher.open(threadURL)

        XCTAssertEqual(workspace.requestedBundleIdentifiers, ["com.openai.codex"])
        XCTAssertEqual(
            workspace.openedRequests,
            [.init(applicationURL: workspace.applicationURL!, url: threadURL)]
        )
        XCTAssertEqual(threadURL.absoluteString, "codex://threads/thread%3Awith%2Fslashes")
    }

    func testSettingsRouteUsesTheSameOfficialApplicationTarget() async throws {
        let workspace = RecordingCodexWorkspace()
        workspace.applicationURL = URL(fileURLWithPath: "/Applications/Codex.app")
        let launcher = CodexApplicationLauncher(workspace: workspace)

        try await launcher.open(CodexApplicationRoute.settingsURL)

        XCTAssertEqual(workspace.requestedBundleIdentifiers, ["com.openai.codex"])
        XCTAssertEqual(
            workspace.openedRequests,
            [.init(
                applicationURL: workspace.applicationURL!,
                url: CodexApplicationRoute.settingsURL
            )]
        )
    }

    func testMissingOfficialApplicationFailsWithoutOpeningAGenericHandler() async {
        let workspace = RecordingCodexWorkspace()
        let launcher = CodexApplicationLauncher(workspace: workspace)

        do {
            try await launcher.open(CodexApplicationRoute.settingsURL)
            XCTFail("Expected the official Codex application lookup to fail")
        } catch {
            XCTAssertEqual(error as? CodexApplicationLaunchError, .applicationUnavailable)
        }

        XCTAssertEqual(workspace.requestedBundleIdentifiers, ["com.openai.codex"])
        XCTAssertTrue(workspace.openedRequests.isEmpty)
    }

    func testTargetedOpenFailureIsPropagated() async {
        let workspace = RecordingCodexWorkspace()
        workspace.applicationURL = URL(fileURLWithPath: "/Applications/Codex.app")
        workspace.openError = TestError.openFailed
        let launcher = CodexApplicationLauncher(workspace: workspace)

        do {
            try await launcher.open(CodexApplicationRoute.settingsURL)
            XCTFail("Expected the targeted Codex launch to fail")
        } catch {
            XCTAssertEqual(error as? TestError, .openFailed)
        }

        XCTAssertEqual(workspace.openedRequests.count, 1)
    }

    func testPermissionTapExpandsWhilePassiveNotificationTapOpensCodex() {
        XCTAssertEqual(
            CodexClosedActivityTapRouting(status: .needsAction(.permission)),
            .expandNotch
        )
        XCTAssertEqual(
            CodexClosedActivityTapRouting(status: .succeeded),
            .openCodex
        )
        XCTAssertEqual(
            CodexClosedActivityTapRouting(status: .failed),
            .openCodex
        )
    }

    func testPermissionAccessibilityDescribesReviewInsideBoringNotch() {
        let accessibility = CodexClosedActivityAccessibility(
            status: .needsAction(.permission),
            projectName: "Example"
        )

        XCTAssertEqual(accessibility.value, "Permission required.")
        XCTAssertEqual(
            accessibility.hint,
            "Activate to review this permission in Boring Notch."
        )
        XCTAssertFalse(accessibility.hint.contains("open Codex"))
    }

    func testFailedCompactLaunchAccessibilityOffersRetry() {
        let accessibility = CodexClosedActivityAccessibility(
            status: .failed,
            projectName: "Example",
            launchError: "The official Codex app could not be found."
        )

        XCTAssertEqual(
            accessibility.value,
            "The official Codex app could not be found."
        )
        XCTAssertEqual(
            accessibility.hint,
            "Activate to retry opening this task in Codex."
        )
    }

    func testReviewHandoffLaunchesCodexBeforeConsumingThePermission() async throws {
        var events: [String] = []

        try await CodexPermissionReviewHandoff.perform(
            openCodex: { events.append("open") },
            handOffPermission: { events.append("handoff") }
        )

        XCTAssertEqual(events, ["open", "handoff"])
    }

    func testReviewHandoffDoesNotConsumePermissionWhenLaunchFails() async {
        var events: [String] = []

        do {
            try await CodexPermissionReviewHandoff.perform(
                openCodex: {
                    events.append("open")
                    throw TestError.openFailed
                },
                handOffPermission: { events.append("handoff") }
            )
            XCTFail("Expected the Codex launch to fail")
        } catch {
            XCTAssertEqual(error as? TestError, .openFailed)
        }

        XCTAssertEqual(events, ["open"])
    }
}

@MainActor
private final class RecordingCodexWorkspace: CodexApplicationWorkspace {
    struct OpenRequest: Equatable {
        let applicationURL: URL
        let url: URL?
    }

    var applicationURL: URL?
    var openError: Error?
    private(set) var requestedBundleIdentifiers: [String] = []
    private(set) var openedRequests: [OpenRequest] = []

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        requestedBundleIdentifiers.append(bundleIdentifier)
        return applicationURL
    }

    func open(_ url: URL?, withApplicationAt applicationURL: URL) async throws {
        openedRequests.append(.init(applicationURL: applicationURL, url: url))
        if let openError {
            throw openError
        }
    }
}

private enum TestError: Error, Equatable {
    case openFailed
}
