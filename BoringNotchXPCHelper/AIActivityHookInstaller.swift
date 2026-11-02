import Darwin
import Foundation

enum AIActivityHookInstaller {
    private static let marker = "--boring-notch-ai-hook"

    static var userHome: URL {
        // Do not inherit the main app's sandbox container as the user's home.
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func configurationURL(for provider: AIProvider, home: URL = userHome) -> URL? {
        switch provider {
        case .claudeCode: return home.appendingPathComponent(".claude/settings.json")
        case .codex: return home.appendingPathComponent(".codex/hooks.json")
        default: return nil
        }
    }

    static func command(for provider: AIProvider, executableURL: URL) -> String {
        // Shell-quote the executable path; a bundle may live in a path containing spaces or quotes.
        let quoted = "'" + executableURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return quoted + " " + marker + " --provider " + provider.rawValue
    }

    /// Hooks without which a light can get stuck. Older installs lacking one show Reconnect.
    static func requiredEvents(for provider: AIProvider) -> [String] {
        let core = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"]
        return provider == .claudeCode ? core + ["PostToolUseFailure"] : core
    }

    static func isConnected(_ provider: AIProvider, executableURL: URL? = Bundle.main.executableURL,
                            home: URL = userHome) -> Bool {
        connection(provider, executableURL: executableURL, home: home).state == .connected
    }

    static func connection(_ provider: AIProvider, executableURL: URL? = Bundle.main.executableURL,
                           home: URL = userHome) -> AIHookConnection {
        guard let url = configurationURL(for: provider, home: home), let data = try? Data(contentsOf: url),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = config["hooks"] as? [String: Any] else { return AIHookConnection() }
        let suffix = " " + marker + " --provider " + provider.rawValue
        func commands(_ event: String) -> [String] {
            (hooks[event] as? [[String: Any]] ?? []).flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            }.filter { $0.hasSuffix(suffix) }
        }
        let owned = hooks.keys.sorted().flatMap(commands)
        guard let first = owned.first else { return AIHookConnection() }
        // Display the installed path by reversing the single-quote shell quoting above.
        var path = String(first.dropLast(suffix.count))
        if path.hasPrefix("'") && path.hasSuffix("'") && path.count >= 2 {
            path = String(path.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
        }
        let expected = executableURL.map { command(for: provider, executableURL: $0) }
        let complete = config["disableAllHooks"] as? Bool != true && expected != nil
            && requiredEvents(for: provider).allSatisfy {
                commands($0).contains(expected!)
            }
        return AIHookConnection(state: complete ? .connected : .needsReconnect, executablePath: path)
    }

    static func update(_ provider: AIProvider, remove: Bool, executableURL: URL? = Bundle.main.executableURL,
                       home: URL = userHome) throws -> String {
        guard let url = configurationURL(for: provider, home: home), let executableURL else { throw InstallError.unsupported }
        let fm = FileManager.default
        var config: [String: Any] = [:]
        var original: Data?
        if fm.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw InstallError.invalidConfiguration }
            config = dictionary
            original = data
        }
        if !remove && config["disableAllHooks"] as? Bool == true { throw InstallError.disabled }
        if let value = config["hooks"], !(value is [String: Any]) { throw InstallError.invalidConfiguration }
        var hooks = config["hooks"] as? [String: Any] ?? [:]
        var removedOwnHook = false
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { throw InstallError.invalidConfiguration }
            var remaining: [[String: Any]] = []
            for var group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else { throw InstallError.invalidConfiguration }
                let kept = handlers.filter {
                    !(($0["command"] as? String ?? "").contains(marker + " --provider " + provider.rawValue))
                }
                removedOwnHook = removedOwnHook || kept.count != handlers.count
                if !kept.isEmpty { group["hooks"] = kept; remaining.append(group) }
            }
            if remaining.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = remaining }
        }

        if remove && !removedOwnHook { return "No changes were needed." }

        if !remove {
            let hookCommand = command(for: provider, executableURL: executableURL)
            var events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
                          "SubagentStart", "SubagentStop", "Stop", "SessionEnd"]
            events += provider == .claudeCode
                ? ["Elicitation", "ElicitationResult", "StopFailure", "PostToolUseFailure", "PermissionDenied"]
                : ["Interrupt"]
            for event in events {
                var groups = hooks[event] as? [[String: Any]] ?? []
                // Omit matcher: the provider chooses which events support it.
                groups.append(["hooks": [["type": "command", "command": hookCommand, "timeout": 2]]])
                hooks[event] = groups
            }
        }
        if hooks.isEmpty { config.removeValue(forKey: "hooks") } else { config["hooks"] = hooks }
        // Without .withoutEscapingSlashes every path in the user's settings would be rewritten as "\/".
        let data = try JSONSerialization.data(withJSONObject: config,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        if original == data || (remove && original == nil) { return "No changes were needed." }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        if let original {
            // One rolling backup of the state before the latest change, rather than one file per click.
            let backup = url.appendingPathExtension("boring-notch-backup")
            try original.write(to: backup, options: .atomic)
            chmod(backup.path, 0o600)
        }
        try data.write(to: url, options: .atomic)
        chmod(url.path, 0o600)
        return remove ? "Disconnected. Existing unrelated hooks were kept."
            : provider == .codex
                ? "Connected. Review and trust these hooks in Codex /hooks, then start a new local chat."
                : "Connected. Start a new local session in Claude Desktop's Code tab."
    }

    enum InstallError: LocalizedError {
        case unsupported, invalidConfiguration, disabled
        var errorDescription: String? {
            switch self {
            case .unsupported: return "This source does not support automatic hook setup."
            case .invalidConfiguration: return "The existing hook configuration has an unexpected format. It was left unchanged."
            case .disabled: return "Hooks are disabled in your settings. Enable them before connecting."
            }
        }
    }
}
