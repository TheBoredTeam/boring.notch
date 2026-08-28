//
//  AgentHookInstaller.swift
//  boringNotch
//
//  Installs the Claude Code integration into ~/.claude:
//    - two hook scripts under ~/.claude/hooks/boring-notch/ that forward
//      hook payloads to the bridge (HTTP), and
//    - hook registrations merged into ~/.claude/settings.json so every
//      Claude Code session (interactive terminal or headless) reports to
//      the notch and can be approved/answered from it.
//
//  Everything fails open: if the scripts or the app are missing, Claude
//  Code continues completely unaffected.
//

import Foundation

enum AgentHookInstaller {
    static var claudeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
    }

    static var hooksDirectory: URL {
        claudeDirectory.appendingPathComponent("hooks/boring-notch", isDirectory: true)
    }

    static var settingsFileURL: URL {
        claudeDirectory.appendingPathComponent("settings.json")
    }

    static var disabledFileURL: URL {
        hooksDirectory.appendingPathComponent("DISABLED")
    }

    static let notifyScriptName = "boring-notify.sh"
    static let decideScriptName = "boring-decide.sh"

    /// Ports must match AgentBridgeServer.portRange.
    private static let portList = (8742...8752).map(String.init).joined(separator: " ")

    static var installedScripts: [String] { [notifyScriptName, decideScriptName] }

    // MARK: - Script sources

    /// Fire-and-forget hook forwarder (SessionStart, UserPromptSubmit, Stop,
    /// Notification, SessionEnd).
    static let notifyScript = ##"""
    #!/bin/sh
    # Boring Notch <-> Claude Code: forwards hook payloads to the notch
    # bridge. Fire-and-forget: fails silently when the notch is not running.
    [ -f "$HOME/.claude/hooks/boring-notch/DISABLED" ] && exit 0
    T=$(mktemp "${TMPDIR:-/tmp}/boring-hook.XXXXXX") || exit 0
    O=$(mktemp "${TMPDIR:-/tmp}/boring-out.XXXXXX") || { rm -f "$T"; exit 0; }
    cat > "$T" 2>/dev/null
    [ -s "$T" ] || { rm -f "$T" "$O"; exit 0; }
    for P in __PORTS__; do
      curl -s -m 3 -o "$O" -X POST "http://127.0.0.1:$P/v1/hook" \
        -H 'Content-Type: application/json' --data-binary @"$T" 2>/dev/null
      RC=$?
      [ "$RC" -eq 0 ] && { rm -f "$T" "$O"; exit 0; }
      # 28 = the bridge accepted but never answered: the app is up but
      # stuck, so scanning the remaining ports (same app) is pointless.
      [ "$RC" -eq 28 ] && break
    done
    rm -f "$T" "$O"
    exit 0
    """##.replacingOccurrences(of: "__PORTS__", with: portList)

    /// PreToolUse bridge: holds until the user decides from the notch, then
    /// prints the hookSpecificOutput JSON. Prints nothing to fall through.
    /// The 40s cap matches the bridge's 30s hold with margin — if the app
    /// is up but unresponsive, this fails open instead of hanging the tool
    /// call for minutes.
    static let decideScript = ##"""
    #!/bin/sh
    # Boring Notch <-> Claude Code PreToolUse bridge. Prints the notch's
    # decision JSON on stdout; prints nothing to fall through to Claude
    # Code's normal permission flow. Fails open on any error.
    [ -f "$HOME/.claude/hooks/boring-notch/DISABLED" ] && exit 0
    T=$(mktemp "${TMPDIR:-/tmp}/boring-hook.XXXXXX") || exit 0
    O=$(mktemp "${TMPDIR:-/tmp}/boring-out.XXXXXX") || { rm -f "$T"; exit 0; }
    cat > "$T" 2>/dev/null
    [ -s "$T" ] || { rm -f "$T" "$O"; exit 0; }
    for P in __PORTS__; do
      curl -s -m 40 -o "$O" -X POST "http://127.0.0.1:$P/v1/hook" \
        -H 'Content-Type: application/json' --data-binary @"$T" 2>/dev/null
      RC=$?
      [ "$RC" -eq 0 ] && { [ -s "$O" ] && cat "$O"; rm -f "$T" "$O"; exit 0; }
      [ "$RC" -eq 28 ] && break
    done
    rm -f "$T" "$O"
    exit 0
    """##.replacingOccurrences(of: "__PORTS__", with: portList)

    // MARK: Install / uninstall

    static func ensureInstalled() {
        if !isInstalled() {
            install()
        }
    }

    static func isInstalled() -> Bool {
        scriptsInstalled() && settingsConfigured()
    }

    @discardableResult
    static func install() -> Bool {
        let scripts = installScripts()
        let config = installSettingsHooks()
        NSLog("[Agent] hook install: scripts=\(scripts) settings=\(config)")
        return scripts && config
    }

    static func uninstall() {
        for name in installedScripts {
            try? FileManager.default.removeItem(at: hooksDirectory.appendingPathComponent(name))
        }
        removeSettingsHooks()
        NSLog("[Agent] hooks uninstalled")
    }

    // MARK: Scripts

    @discardableResult
    static func installScripts() -> Bool {
        do {
            try FileManager.default.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)
            for (name, source) in [(notifyScriptName, notifyScript), (decideScriptName, decideScript)] {
                let url = hooksDirectory.appendingPathComponent(name)
                try source.write(to: url, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
            return true
        } catch {
            NSLog("[Agent] hook script install failed: \(error)")
            return false
        }
    }

    static func scriptsInstalled() -> Bool {
        for (name, source) in [(notifyScriptName, notifyScript), (decideScriptName, decideScript)] {
            let url = hooksDirectory.appendingPathComponent(name)
            guard let current = try? String(contentsOf: url, encoding: .utf8), current == source else {
                return false
            }
        }
        return true
    }

    // MARK: settings.json merge

    /// Event names that just forward payloads.
    private static let notifyEvents = ["SessionStart", "UserPromptSubmit", "Stop", "Notification", "SessionEnd"]
    /// PreToolUse matcher: tools the user may need to decide on.
    private static let decideMatcher = "Write|Edit|MultiEdit|NotebookEdit|Bash|AskUserQuestion"

    @discardableResult
    static func installSettingsHooks() -> Bool {
        guard var root = readSettings() else { return false }

        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for event in notifyEvents {
            var groups = hooks[event] as? [[String: Any]] ?? []
            if groups.contains(where: { isOurGroup($0, script: notifyScriptName) }) { continue }
            groups.append([
                "matcher": "",
                "hooks": [["type": "command", "command": notifyScriptPath]],
            ])
            hooks[event] = groups
        }

        var preToolUse = hooks["PreToolUse"] as? [[String: Any]] ?? []
        if !preToolUse.contains(where: { isOurGroup($0, script: decideScriptName) }) {
            preToolUse.append([
                "matcher": decideMatcher,
                "hooks": [["type": "command", "command": decideScriptPath]],
            ])
            hooks["PreToolUse"] = preToolUse
        }

        root["hooks"] = hooks
        return writeSettings(root)
    }

    static func removeSettingsHooks() {
        guard var root = readSettings(),
              var hooks = root["hooks"] as? [String: Any] else { return }

        for event in notifyEvents {
            guard var groups = hooks[event] as? [[String: Any]] else { continue }
            groups.removeAll { isOurGroup($0, script: notifyScriptName) }
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }

        if var preToolUse = hooks["PreToolUse"] as? [[String: Any]] {
            preToolUse.removeAll { isOurGroup($0, script: decideScriptName) }
            if preToolUse.isEmpty {
                hooks.removeValue(forKey: "PreToolUse")
            } else {
                hooks["PreToolUse"] = preToolUse
            }
        }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        _ = writeSettings(root)
    }

    static func settingsConfigured() -> Bool {
        guard let root = readSettings(),
              let hooks = root["hooks"] as? [String: Any] else { return false }
        for event in notifyEvents {
            let groups = hooks[event] as? [[String: Any]] ?? []
            guard groups.contains(where: { isOurGroup($0, script: notifyScriptName) }) else { return false }
        }
        let preToolUse = hooks["PreToolUse"] as? [[String: Any]] ?? []
        return preToolUse.contains(where: { isOurGroup($0, script: decideScriptName) })
    }

    private static var notifyScriptPath: String { hooksDirectory.appendingPathComponent(notifyScriptName).path }
    private static var decideScriptPath: String { hooksDirectory.appendingPathComponent(decideScriptName).path }

    private static func isOurGroup(_ group: [String: Any], script: String) -> Bool {
        let hooks = group["hooks"] as? [[String: Any]] ?? []
        return hooks.contains { hook in
            (hook["command"] as? String)?.contains(script) == true
        }
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: settingsFileURL.path) else {
            return [:] // no settings yet — start fresh
        }
        if data.isEmpty { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    @discardableResult
    private static func writeSettings(_ root: [String: Any]) -> Bool {
        do {
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
            try data.write(to: settingsFileURL, options: .atomic)
            return true
        } catch {
            NSLog("[Agent] settings write failed: \(error)")
            return false
        }
    }

    // MARK: Kill switch

    /// When the DISABLED marker exists, every hook script exits immediately
    /// and Claude Code behaves exactly as if the notch integration were gone.
    static var killSwitchEnabled: Bool {
        get { FileManager.default.fileExists(atPath: disabledFileURL.path) }
        set {
            if newValue {
                try? FileManager.default.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: disabledFileURL.path, contents: Data())
            } else {
                try? FileManager.default.removeItem(at: disabledFileURL)
            }
        }
    }
}