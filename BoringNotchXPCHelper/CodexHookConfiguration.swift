import Foundation

public enum CodexHookConfiguration {
    public static let definitions: [(name: String, trustName: String, timeout: Int)] = [
        ("UserPromptSubmit", "user_prompt_submit", 5),
        ("PermissionRequest", "permission_request", 75),
        ("Stop", "stop", 5),
        ("Interrupt", "interrupt", 3),
    ]
    public static let events = definitions.map(\.name)

    public static func containsCurrentOwnedHook(
        in root: [String: Any], event: String, command: String
    ) -> Bool {
        guard let definition = definitions.first(where: { $0.name == event }),
              let hooks = root["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]] else { return false }
        let ownedGroups = groups.filter { isOwnedGroup($0, command: command) }
        guard ownedGroups.count == 1,
              let handlers = ownedGroups[0]["hooks"] as? [[String: Any]],
              handlers.count == 1 else { return false }
        let handler = handlers[0]
        return handler["type"] as? String == "command"
            && handler["command"] as? String == command
            && handler["timeout"] as? Int == definition.timeout
            && handler["async"] == nil
    }

    public static func renderScript(_ template: String, appBundlePath: String) throws -> String {
        // JSON string escaping is also valid for a Python string literal.
        let data = try JSONSerialization.data(withJSONObject: appBundlePath, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        let literal = String(decoding: data, as: UTF8.self)
        return template.replacingOccurrences(of: "\"__BORING_NOTCH_APP_BUNDLE__\"", with: literal)
    }

    public static func updating(
        _ root: [String: Any],
        installed: Bool,
        command: String
    ) throws -> [String: Any] {
        var updatedRoot = root
        var hooks: [String: Any]
        if let existingHooks = root["hooks"] {
            guard let typedHooks = existingHooks as? [String: Any] else {
                throw configurationError(
                    code: 4,
                    message: "Codex hooks.json has an invalid hooks object."
                )
            }
            hooks = typedHooks
        } else {
            hooks = [:]
        }

        for event in Array(hooks.keys) {
            guard let groups = hooks[event] as? [[String: Any]] else { continue }
            hooks[event] = groups.compactMap { group in
                guard let handlers = group["hooks"] as? [[String: Any]] else {
                    return group
                }
                let remainingHandlers = handlers.filter { handler in
                    handler["command"] as? String != command
                }
                guard remainingHandlers.count != handlers.count else {
                    return group
                }
                guard !remainingHandlers.isEmpty else { return nil }

                var updatedGroup = group
                updatedGroup["hooks"] = remainingHandlers
                return updatedGroup
            }
        }

        for definition in definitions {
            let event = definition.name
            var groups: [[String: Any]]
            if let existingGroups = hooks[event] {
                guard let typedGroups = existingGroups as? [[String: Any]] else {
                    throw configurationError(
                        code: 5,
                        message: "Codex hooks.json has invalid \(event) hooks."
                    )
                }
                groups = typedGroups
            } else {
                groups = []
            }

            if installed {
                let handler: [String: Any] = [
                    "type": "command",
                    "command": command,
                    "timeout": definition.timeout,
                ]
                groups.append(["hooks": [handler]])
            }
            hooks[event] = groups
        }

        updatedRoot["hooks"] = hooks
        return updatedRoot
    }

    public static func isOwnedGroup(
        _ group: [String: Any],
        command: String
    ) -> Bool {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
        return handlers.contains { handler in
            handler["command"] as? String == command
        }
    }

    private static func configurationError(code: Int, message: String) -> NSError {
        NSError(
            domain: "BoringNotch.CodexHooks",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
