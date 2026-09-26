//
//  OpenClawHookInstallerTests.swift
//  boringNotchTests
//

import XCTest
@testable import boringNotch

final class OpenClawHookInstallerTests: XCTestCase {
    func testInstallationConfigurationPreservesUnrelatedSettings() throws {
        let original: [String: Any] = [
            "agents": ["defaults": ["model": "example"]],
            "plugins": [
                "load": ["paths": ["/tmp/another-plugin"]],
                "entries": ["another": ["enabled": true]],
                "allow": ["another"],
            ],
            "hooks": ["internal": ["entries": ["another": ["enabled": true]]]],
        ]
        let updated = try OpenClawHookInstaller.configurationWithHooks(
            original, pluginPath: "/tmp/boring-notch-plugin", enableInternalHooks: true
        )
        XCTAssertEqual(
            (updated["agents"] as? [String: Any])?["defaults"] as? [String: String],
            ["model": "example"]
        )
        let plugins = try XCTUnwrap(updated["plugins"] as? [String: Any])
        let paths = try XCTUnwrap((plugins["load"] as? [String: Any])?["paths"] as? [String])
        XCTAssertEqual(paths, ["/tmp/another-plugin", "/tmp/boring-notch-plugin"])
        XCTAssertEqual(plugins["allow"] as? [String], ["another", "boring-notch"])
        let hooks = try XCTUnwrap(updated["hooks"] as? [String: Any])
        let entries = try XCTUnwrap((hooks["internal"] as? [String: Any])?["entries"] as? [String: Any])
        XCTAssertEqual((hooks["internal"] as? [String: Any])?["enabled"] as? Bool, true)
        XCTAssertNotNil(entries["another"])
        XCTAssertEqual((entries["boring-notch"] as? [String: Any])?["enabled"] as? Bool, true)
    }

    func testDisabledPluginSystemIsNotChangedSilently() {
        let original: [String: Any] = ["plugins": ["enabled": false]]
        XCTAssertThrowsError(try OpenClawHookInstaller.configurationWithHooks(
            original, pluginPath: "/tmp/boring-notch-plugin"
        ))
    }

    func testInternalHooksStayDisabledUnlessRequested() throws {
        let updated = try OpenClawHookInstaller.configurationWithHooks(
            ["hooks": ["internal": ["enabled": false]]],
            pluginPath: "/tmp/boring-notch-plugin"
        )
        let hooks = try XCTUnwrap(updated["hooks"] as? [String: Any])
        let internalHooks = try XCTUnwrap(hooks["internal"] as? [String: Any])
        XCTAssertEqual(internalHooks["enabled"] as? Bool, false)
    }

    func testOpenClawApprovalResponseOnlyBlocksExplicitDenial() {
        let denied = ClaudeApprovalBridge.openClawPermissionDecision(allow: false)
        let allowed = ClaudeApprovalBridge.openClawPermissionDecision(allow: true)
        XCTAssertEqual((denied["decision"] as? [String: String])?["behavior"], "deny")
        XCTAssertEqual((allowed["decision"] as? [String: String])?["behavior"], "allow")
    }

    func testGeneratedScriptsHaveAConcretePrivateTokenPath() {
        XCTAssertTrue(OpenClawHookInstaller.pluginSource.contains("const TOKEN_PATH = \""))
        XCTAssertTrue(OpenClawHookInstaller.hookSource.contains("const TOKEN_PATH = \""))
        XCTAssertFalse(OpenClawHookInstaller.pluginSource.contains("#("))
        XCTAssertFalse(OpenClawHookInstaller.hookSource.contains("#("))
    }
}
