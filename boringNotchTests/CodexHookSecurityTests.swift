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

    func testHookSecretStoreLoadOrCreateRejectsExtendedACL() throws {
        let directory = try makeACLTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secretURL = directory.appendingPathComponent("hook.secret")
        try Data(repeating: 0x5A, count: 32).write(to: secretURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: secretURL.path
        )
        try addExtendedReadACL(to: secretURL)
        XCTAssertTrue(try hasExtendedACLEntries(at: secretURL))

        XCTAssertThrowsError(
            try CodexHookSecretStore.loadOrCreate(at: secretURL) {
                XCTFail("An ACL-bearing secret must not be regenerated")
                return Data(repeating: 0xA5, count: 32)
            }
        )
    }

    func testHookSecretStoreRuntimeLoadRejectsBroadPermissions() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secretURL = directory.appendingPathComponent("hook.secret")
        try Data(repeating: 0x5A, count: 32).write(to: secretURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: secretURL.path
        )

        XCTAssertThrowsError(try CodexHookSecretStore.load(at: secretURL))
    }

    func testHookSecretStoreRuntimeLoadRejectsSymlinkReplacement() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let targetURL = directory.appendingPathComponent("target")
        let secretURL = directory.appendingPathComponent("hook.secret")
        try Data(repeating: 0x5A, count: 32).write(to: targetURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: targetURL.path
        )
        try FileManager.default.createSymbolicLink(
            at: secretURL,
            withDestinationURL: targetURL
        )

        XCTAssertThrowsError(try CodexHookSecretStore.load(at: secretURL))
    }

    func testHookSecretStoreRuntimeLoadReturnsSafeSecret() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secretURL = directory.appendingPathComponent("hook.secret")
        let expected = Data(repeating: 0x5A, count: 32)
        try expected.write(to: secretURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: secretURL.path
        )

        XCTAssertEqual(try CodexHookSecretStore.load(at: secretURL), expected)
    }

    func testHookSecretStoreRuntimeLoadRejectsExtendedACL() throws {
        let directory = try makeACLTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secretURL = directory.appendingPathComponent("hook.secret")
        try Data(repeating: 0x5A, count: 32).write(to: secretURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: secretURL.path
        )
        try addExtendedReadACL(to: secretURL)
        XCTAssertTrue(try hasExtendedACLEntries(at: secretURL))

        XCTAssertThrowsError(try CodexHookSecretStore.load(at: secretURL))
    }

    func testClearingExtendedACLRemovesEntriesFromDescriptor() throws {
        let directory = try makeACLTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secretURL = directory.appendingPathComponent("hook.secret")
        try Data(repeating: 0xA5, count: 32).write(to: secretURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: secretURL.path
        )
        try addExtendedReadACL(to: secretURL)
        XCTAssertTrue(try hasExtendedACLEntries(at: secretURL))

        let descriptor = secretURL.path.withCString {
            Darwin.open($0, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw systemError() }
        defer { Darwin.close(descriptor) }
        try CodexHookSecretStore.clearExtendedACL(from: descriptor)

        XCTAssertFalse(try hasExtendedACLEntries(at: secretURL))
    }

    func testPublishingHookFilesRejectsAnInheritedEveryoneWriteACL() throws {
        let directory = try makeACLTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: directory.path
        )
        try addInheritedEveryoneWriteACL(to: directory)

        for filename in ["boring-notch-notify.py", "hooks.json"] {
            let url = directory.appendingPathComponent(filename)
            XCTAssertThrowsError(
                try CodexHookFileStore.publish(Data("managed".utf8), at: url)
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testHookFileLoadRejectsACLMetadataForScriptAndConfiguration() throws {
        let directory = try makeACLTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        for filename in ["boring-notch-notify.py", "hooks.json"] {
            let url = directory.appendingPathComponent(filename)
            try Data("managed".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            try addExtendedReadACL(to: url)
            XCTAssertTrue(try hasExtendedACLEntries(at: url))
            XCTAssertThrowsError(try CodexHookFileStore.load(at: url))
        }
    }

    func testPublishingHookFilesCreatesOwnerOnlyACLFreeFiles() throws {
        let directory = try makeACLTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = Data("managed".utf8)

        for filename in ["boring-notch-notify.py", "hooks.json"] {
            let url = directory.appendingPathComponent(filename)
            try CodexHookFileStore.publish(expected, at: url)

            XCTAssertEqual(try CodexHookFileStore.load(at: url), expected)
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path
            )
            XCTAssertEqual(
                (attributes[.posixPermissions] as? NSNumber)?.intValue,
                0o600
            )
            XCTAssertFalse(try hasExtendedACLEntries(at: url))
        }
    }

    func testPublishingHookFileRejectsSymlinkAndFIFOWithoutBlocking() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let targetURL = directory.appendingPathComponent("target")
        let symlinkURL = directory.appendingPathComponent("boring-notch-notify.py")
        let fifoURL = directory.appendingPathComponent("hooks.json")
        let targetContents = Data("target".utf8)
        try targetContents.write(to: targetURL)
        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: targetURL
        )
        XCTAssertEqual(fifoURL.path.withCString { Darwin.mkfifo($0, 0o600) }, 0)

        XCTAssertThrowsError(
            try CodexHookFileStore.publish(Data("managed".utf8), at: symlinkURL)
        )
        XCTAssertThrowsError(
            try CodexHookFileStore.publish(Data("managed".utf8), at: fifoURL)
        )
        XCTAssertEqual(try Data(contentsOf: targetURL), targetContents)
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

    private func makeACLTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        return directory
    }

    private func addExtendedReadACL(to url: URL) throws {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw systemError() }
        defer { Darwin.close(descriptor) }

        let text = "!#acl 1\ngroup:ABCDEFAB-CDEF-ABCD-EFAB-CDEF00000014:staff:20:allow:read\n"
        guard let accessList = text.withCString(acl_from_text) else {
            throw systemError()
        }
        defer { acl_free(UnsafeMutableRawPointer(accessList)) }

        guard acl_set_fd_np(descriptor, accessList, ACL_TYPE_EXTENDED) == 0 else {
            throw systemError()
        }
    }

    private func addInheritedEveryoneWriteACL(to url: URL) throws {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw systemError() }
        defer { Darwin.close(descriptor) }

        var accessList: acl_t? = acl_init(1)
        guard accessList != nil else { throw systemError() }
        defer {
            if let accessList { acl_free(UnsafeMutableRawPointer(accessList)) }
        }
        var entry: acl_entry_t?
        guard acl_create_entry(&accessList, &entry) == 0, let entry,
              acl_set_tag_type(entry, ACL_EXTENDED_ALLOW) == 0 else {
            throw systemError()
        }
        var principal = UUID(
            uuidString: "ABCDEFAB-CDEF-ABCD-EFAB-CDEF0000000C"
        )!.uuid
        guard withUnsafePointer(to: &principal, { acl_set_qualifier(entry, $0) }) == 0 else {
            throw systemError()
        }
        var permissions: acl_permset_t?
        guard acl_get_permset(entry, &permissions) == 0, let permissions,
              acl_clear_perms(permissions) == 0 else {
            throw systemError()
        }
        for permission in [
            ACL_READ_DATA,
            ACL_WRITE_DATA,
            ACL_APPEND_DATA,
            ACL_READ_ATTRIBUTES,
            ACL_WRITE_ATTRIBUTES,
            ACL_READ_EXTATTRIBUTES,
            ACL_WRITE_EXTATTRIBUTES,
        ] where acl_add_perm(permissions, permission) != 0 {
            throw systemError()
        }
        guard acl_set_permset(entry, permissions) == 0 else { throw systemError() }
        var flags: acl_flagset_t?
        guard acl_get_flagset_np(UnsafeMutableRawPointer(entry), &flags) == 0,
              let flags,
              acl_clear_flags_np(flags) == 0,
              acl_add_flag_np(flags, ACL_ENTRY_FILE_INHERIT) == 0,
              acl_add_flag_np(flags, ACL_ENTRY_ONLY_INHERIT) == 0,
              acl_set_flagset_np(UnsafeMutableRawPointer(entry), flags) == 0 else {
            throw systemError()
        }
        guard let accessList,
              acl_set_fd_np(descriptor, accessList, ACL_TYPE_EXTENDED) == 0 else {
            throw systemError()
        }
    }

    private func hasExtendedACLEntries(at url: URL) throws -> Bool {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        guard descriptor >= 0 else { throw systemError() }
        defer { Darwin.close(descriptor) }

        if let accessList = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) {
            acl_free(UnsafeMutableRawPointer(accessList))
            return true
        }
        if errno == ENOENT { return false }
        throw systemError()
    }

    private func systemError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
