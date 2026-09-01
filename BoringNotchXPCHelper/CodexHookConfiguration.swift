import Foundation

public enum CodexHookConfiguration {
    public static let events = [
        "UserPromptSubmit",
        "PermissionRequest",
        "Stop",
    ]

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

        for event in events {
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
                    "timeout": event == "PermissionRequest" ? 75 : 5,
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
