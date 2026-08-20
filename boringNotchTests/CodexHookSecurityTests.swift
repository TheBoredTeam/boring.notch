import CryptoKit
import Darwin
import XCTest
@testable import CodexHookSupport
@testable import CodexNotificationsCore

final class CodexHookSecurityTests: XCTestCase {
    private let secret = Data((0..<32).map(UInt8.init))
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testAuthenticationAcceptsAValidFreshSignedPayload() throws {
        let signed = try signedPayload(timestamp: now.timeIntervalSince1970)

        XCTAssertEqual(
            CodexHookAuthenticator.validate(
                payload: signed.payload,
                signature: signed.signature,
                secret: secret,
                now: now
            ),
            .valid
        )
    }

    func testAuthenticationRejectsAnInvalidSignature() throws {
        let signed = try signedPayload(timestamp: now.timeIntervalSince1970)
        let invalidSignature = String(repeating: "A", count: 43)

        XCTAssertEqual(
            CodexHookAuthenticator.validate(
                payload: signed.payload,
                signature: invalidSignature,
                secret: secret,
                now: now
            ),
            .invalidSignature
        )
    }

    func testAuthenticationRejectsAStalePayload() throws {
        let signed = try signedPayload(timestamp: now.timeIntervalSince1970 - 121)

        XCTAssertEqual(
            CodexHookAuthenticator.validate(
                payload: signed.payload,
                signature: signed.signature,
                secret: secret,
                now: now
            ),
            .expired
        )
    }

    func testInstallingHooksPreservesUnrelatedConfigurationAndReplacesOwnedGroups() throws {
        let unrelatedGroup: [String: Any] = [
            "matcher": "Bash",
            "hooks": [["type": "command", "command": "notify-send done", "timeout": 9]],
        ]
        let staleOwnedGroup: [String: Any] = [
            "hooks": [[
                "type": "command",
                "command": "/usr/bin/python3 '/tmp/boring-notch-notify.py'",
                "timeout": 1,
            ]],
        ]
        let root: [String: Any] = [
            "version": 1,
            "hooks": [
                "Stop": [unrelatedGroup, staleOwnedGroup],
                "CustomEvent": [unrelatedGroup],
            ],
        ]

        let updated = try CodexHookConfiguration.updating(
            root,
            installed: true,
            command: "/usr/bin/python3 '/tmp/boring-notch-notify.py'"
        )

        XCTAssertEqual(updated["version"] as? Int, 1)
        let hooks = try XCTUnwrap(updated["hooks"] as? [String: Any])
        XCTAssertEqual((hooks["CustomEvent"] as? [[String: Any]])?.count, 1)
        let stopGroups = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stopGroups.count, 2)
        XCTAssertEqual(
            ((stopGroups[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String),
            "notify-send done"
        )
        XCTAssertEqual(
            ((stopGroups[1]["hooks"] as? [[String: Any]])?.first?["timeout"] as? Int),
            5
        )
        let permissionGroups = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        XCTAssertEqual(
            ((permissionGroups[0]["hooks"] as? [[String: Any]])?.first?["timeout"] as? Int),
            75
        )
        for event in ["UserPromptSubmit", "PostToolUse"] {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]])
            XCTAssertEqual(groups.count, 1)
            XCTAssertEqual(
                ((groups[0]["hooks"] as? [[String: Any]])?.first?["timeout"] as? Int),
                5
            )
        }
    }

    func testUninstallingHooksRemovesOnlyOwnedGroups() throws {
        let unrelatedGroup: [String: Any] = [
            "hooks": [["type": "command", "command": "notify-send done", "timeout": 9]],
        ]
        let ownedGroup: [String: Any] = [
            "hooks": [[
                "type": "command",
                "command": "/usr/bin/python3 '/tmp/boring-notch-notify.py'",
                "timeout": 5,
            ]],
        ]
        var originalHooks = Dictionary(
            uniqueKeysWithValues: CodexHookConfiguration.events.map {
                ($0, [ownedGroup])
            }
        )
        originalHooks["Stop"] = [unrelatedGroup, ownedGroup]
        originalHooks["CustomEvent"] = [ownedGroup]
        let root: [String: Any] = ["hooks": originalHooks]

        let updated = try CodexHookConfiguration.updating(
            root,
            installed: false,
            command: "/usr/bin/python3 '/tmp/boring-notch-notify.py'"
        )

        let hooks = try XCTUnwrap(updated["hooks"] as? [String: Any])
        let stopGroups = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stopGroups.count, 1)
        XCTAssertEqual(
            ((stopGroups[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String),
            "notify-send done"
        )
        for event in CodexHookConfiguration.events where event != "Stop" {
            XCTAssertEqual((hooks[event] as? [[String: Any]])?.count, 0)
        }
        XCTAssertEqual((hooks["CustomEvent"] as? [[String: Any]])?.count, 1)
    }

    func testUninstallingHooksPreservesUnrelatedHandlersInOwnedGroups() throws {
        let mixedGroup: [String: Any] = [
            "matcher": "Bash",
            "hooks": [
                ["type": "command", "command": "notify-send done", "timeout": 9],
                [
                    "type": "command",
                    "command": "/usr/bin/python3 '/tmp/boring-notch-notify.py'",
                    "timeout": 5,
                ],
            ],
        ]
        let root: [String: Any] = [
            "hooks": ["Stop": [mixedGroup]],
        ]

        let updated = try CodexHookConfiguration.updating(
            root,
            installed: false,
            command: "/usr/bin/python3 '/tmp/boring-notch-notify.py'"
        )

        let hooks = try XCTUnwrap(updated["hooks"] as? [String: Any])
        let stopGroups = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stopGroups.count, 1)
        let stopGroup = try XCTUnwrap(stopGroups.first)
        XCTAssertEqual(stopGroup["matcher"] as? String, "Bash")
        let handlers = try XCTUnwrap(stopGroup["hooks"] as? [[String: Any]])
        XCTAssertEqual(handlers.count, 1)
        XCTAssertEqual(handlers[0]["command"] as? String, "notify-send done")
        XCTAssertEqual(handlers[0]["timeout"] as? Int, 9)
    }

    func testInstallingHooksPreservesHandlersThatOnlyMentionTheOwnedFilename() throws {
        let mentionOnlyCommand = "echo diagnostic boring-notch-notify.py marker"
        let root: [String: Any] = [
            "hooks": [
                "Stop": [[
                    "hooks": [[
                        "type": "command",
                        "command": mentionOnlyCommand,
                        "timeout": 9,
                    ]],
                ]],
            ],
        ]

        let updated = try CodexHookConfiguration.updating(
            root,
            installed: true,
            command: "/usr/bin/python3 '/tmp/boring-notch-notify.py'"
        )

        let hooks = try XCTUnwrap(updated["hooks"] as? [String: Any])
        let groups = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 2)
        let handlers = try XCTUnwrap(groups[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(handlers[0]["command"] as? String, mentionOnlyCommand)
    }

    func testNewHookSecretIsCreatedWithOwnerOnlyPermissions() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secretURL = directory.appendingPathComponent("hook.secret")
        let expected = Data(repeating: 0xA5, count: 32)

        let loaded = try CodexHookSecretStore.loadOrCreate(at: secretURL) { expected }

        XCTAssertEqual(loaded, expected)
        let attributes = try FileManager.default.attributesOfItem(atPath: secretURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testHookSecretStoreRejectsSymlinksWithoutReadingTheirTarget() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let targetURL = directory.appendingPathComponent("target")
        let secretURL = directory.appendingPathComponent("hook.secret")
        let targetContents = Data(repeating: 0x5A, count: 32)
        try targetContents.write(to: targetURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: targetURL.path
        )
        try FileManager.default.createSymbolicLink(
            at: secretURL,
            withDestinationURL: targetURL
        )

        XCTAssertThrowsError(
            try CodexHookSecretStore.loadOrCreate(at: secretURL) {
                Data(repeating: 0xA5, count: 32)
            }
        )
        XCTAssertEqual(try Data(contentsOf: targetURL), targetContents)
    }

    func testHookSecretStoreRejectsBroadExistingPermissions() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secretURL = directory.appendingPathComponent("hook.secret")
        try Data(repeating: 0x5A, count: 32).write(to: secretURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: secretURL.path
        )

        XCTAssertThrowsError(
            try CodexHookSecretStore.loadOrCreate(at: secretURL) {
                Data(repeating: 0xA5, count: 32)
            }
        )
    }

    func testHookSecretStoreRejectsNonRegularFilesWithoutBlocking() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secretURL = directory.appendingPathComponent("hook.secret")
        let result = secretURL.path.withCString {
            Darwin.mkfifo($0, 0o600)
        }
        XCTAssertEqual(result, 0)

        XCTAssertThrowsError(
            try CodexHookSecretStore.loadOrCreate(at: secretURL) {
                Data(repeating: 0xA5, count: 32)
            }
        )
    }

    func testHookSecretStoreLoadsSafeExistingSecretWithoutRegenerating() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secretURL = directory.appendingPathComponent("hook.secret")
        let expected = Data(repeating: 0x5A, count: 32)
        try expected.write(to: secretURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: secretURL.path
        )

        let loaded = try CodexHookSecretStore.loadOrCreate(at: secretURL) {
            XCTFail("A safe existing secret must not be regenerated")
            return Data()
        }

        XCTAssertEqual(loaded, expected)
    }

    func testReplayGuardRejectsDuplicatesUntilTheirLifetimeExpires() {
        var guardState = CodexNotificationReplayGuard(lifetime: 120)

        XCTAssertTrue(guardState.accept("payload", now: now))
        XCTAssertFalse(guardState.accept("payload", now: now.addingTimeInterval(120)))
        XCTAssertTrue(guardState.accept("payload", now: now.addingTimeInterval(121)))
    }

    private func signedPayload(timestamp: TimeInterval) throws -> (payload: String, signature: String) {
        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "Stop",
            "boring_notch_auth": [
                "timestamp": timestamp,
                "nonce": "0123456789abcdef0123456789abcdef",
            ],
        ])
        let payload = base64URL(data)
        let signature = base64URL(Data(HMAC<SHA256>.authenticationCode(
            for: Data(payload.utf8),
            using: SymmetricKey(data: secret)
        )))
        return (payload, signature)
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        return directory
    }
}
