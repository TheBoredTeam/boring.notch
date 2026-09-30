//
//  ClaudeHookInstaller.swift
//  boringCode
//
//  Instala/remove os hooks do boringCode em ~/.claude/settings.json sem tocar
//  nos hooks de outras ferramentas. Lista de eventos e timeout de permissão
//  seguem o instalador do Open Island (github.com/Octane0411/open-vibe-island), GPL-3.0.
//

import Foundation
import os

enum ClaudeHookInstaller {
    enum State: Equatable {
        case installed
        case notInstalled
        /// Instalado, mas faltam eventos ou o script sumiu.
        case outdated
        case claudeNotFound
        case error(String)
    }

    static let permissionTimeout = 86_400

    /// (evento, matcher). PermissionRequest recebe timeout longo: o hook
    /// fica esperando você clicar no notch.
    private static let events: [(name: String, matcher: String?)] = [
        ("SessionStart", nil),
        ("SessionEnd", nil),
        ("UserPromptSubmit", nil),
        ("PreToolUse", "*"),
        ("PostToolUse", "*"),
        ("PostToolUseFailure", "*"),
        ("PermissionRequest", "*"),
        ("PermissionDenied", "*"),
        ("Notification", "*"),
        ("Stop", nil),
        ("StopFailure", nil),
        ("SubagentStart", nil),
        ("SubagentStop", nil),
        ("PreCompact", nil),
    ]

    private static let marker = "boringCode/bin/boringcode-hook"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "boringcode", category: "ClaudeHookInstaller")

    static var claudeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }

    static var settingsURL: URL { claudeDirectory.appendingPathComponent("settings.json") }

    // MARK: - Estado

    static func currentState() -> State {
        guard FileManager.default.fileExists(atPath: claudeDirectory.path) else { return .claudeNotFound }
        let settings: [String: Any]
        do { settings = try readSettings() } catch { return .error(error.localizedDescription) }

        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        let installedEvents = events.filter { event in
            groups(in: hooks, event: event.name).contains(where: isManagedGroup)
        }
        if installedEvents.isEmpty { return .notInstalled }
        let scriptOK = FileManager.default.isExecutableFile(atPath: AgentPaths.hookScriptURL.path)
        return installedEvents.count == events.count && scriptOK ? .installed : .outdated
    }

    // MARK: - Instalar / remover

    /// Garante que o script está atualizado no disco. Barato; roda a cada abertura do app.
    static func writeHookScript() throws {
        let url = AgentPaths.hookScriptURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(AgentHookScript.contents(socketPath: AgentHookServer.socketURL.path).utf8)
        if (try? Data(contentsOf: url)) != data {
            try data.write(to: url, options: .atomic)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    static func install() throws {
        try writeHookScript()
        var settings = try readSettings()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for event in events {
            var list = groups(in: hooks, event: event.name).filter { !isManagedGroup($0) }
            var hook: [String: Any] = [
                "type": "command",
                "command": "\(shellQuote(AgentPaths.hookScriptURL.path)) \(event.name)",
            ]
            if event.name == "PermissionRequest" { hook["timeout"] = permissionTimeout }
            var group: [String: Any] = ["hooks": [hook]]
            if let matcher = event.matcher { group["matcher"] = matcher }
            list.append(group)
            hooks[event.name] = list
        }

        settings["hooks"] = hooks
        try writeSettings(settings)
        log.info("hooks instalados em \(settingsURL.path)")
    }

    static func uninstall() throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        var settings = try readSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for (event, _) in hooks {
            let remaining = groups(in: hooks, event: event).filter { !isManagedGroup($0) }
            if remaining.isEmpty { hooks[event] = nil } else { hooks[event] = remaining }
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try writeSettings(settings)
        try? FileManager.default.removeItem(at: AgentPaths.hookScriptURL)
        log.info("hooks removidos de \(settingsURL.path)")
    }

    // MARK: - JSON

    private static func groups(in hooks: [String: Any], event: String) -> [[String: Any]] {
        hooks[event] as? [[String: Any]] ?? []
    }

    private static func isManagedGroup(_ group: [String: Any]) -> Bool {
        let entries = group["hooks"] as? [[String: Any]] ?? []
        return entries.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    private static func readSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL), !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallerError.invalidSettings
        }
        return object
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = claudeDirectory.appendingPathComponent("settings.json.boringcode-backup.\(stamp)")
            try FileManager.default.copyItem(at: settingsURL, to: backup)
            pruneBackups()
        }
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }

    /// Mantém só os 5 backups mais recentes do boringCode.
    private static func pruneBackups() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: claudeDirectory.path)) ?? []
        let backups = files.filter { $0.hasPrefix("settings.json.boringcode-backup.") }.sorted()
        for name in backups.dropLast(5) {
            try? FileManager.default.removeItem(at: claudeDirectory.appendingPathComponent(name))
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    enum InstallerError: LocalizedError {
        case invalidSettings
        var errorDescription: String? {
            "O ~/.claude/settings.json não é um JSON válido — corrija antes de instalar."
        }
    }
}

enum AgentHookScript {
    /// Script POSIX: repassa o JSON do hook para o socket do boringCode e imprime
    /// a resposta (decisão de permissão). Sai sem fazer nada se o app não estiver aberto.
    static func contents(socketPath: String) -> String {
        let quoted = "'" + socketPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return template.replacingOccurrences(of: "__BORINGCODE_SOCKET__", with: quoted)
    }

    private static let template = #"""
    #!/bin/sh
    # boringCode — ponte entre os hooks do Claude Code e o notch.
    # Gerado pelo app; será sobrescrito. Fail-open: sem o app, não faz nada.
    SOCK=__BORINGCODE_SOCKET__
    EVENT="${1:-unknown}"
    if [ -n "$BORINGCODE_SKIP_HOOKS" ] || [ ! -S "$SOCK" ]; then
      cat >/dev/null
      exit 0
    fi

    # Sobe a árvore de processos até o `claude` para achar o TTY e o PID da sessão.
    TTY=""; AGENT_PID=""; pid=$PPID; i=0
    while [ $i -lt 6 ] && [ "${pid:-0}" -gt 1 ]; do
      comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
      t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
      if [ -z "$TTY" ] && [ -n "$t" ] && [ "$t" != "??" ]; then TTY="$t"; fi
      case "$comm" in *claude*) AGENT_PID=$pid; break ;; esac
      pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
      i=$((i + 1))
    done

    MAX=3
    [ "$EVENT" = "PermissionRequest" ] && MAX=86400

    curl -s --fail --max-time "$MAX" --unix-socket "$SOCK" \
      -H "Content-Type: application/json" -H "Expect:" \
      -H "X-BC-TTY: $TTY" -H "X-BC-PID: $AGENT_PID" \
      -H "X-BC-Term: ${TERM_PROGRAM:-}" -H "X-BC-Bundle: ${__CFBundleIdentifier:-}" \
      -H "X-BC-Entrypoint: ${CLAUDE_CODE_ENTRYPOINT:-}" \
      --data-binary @- "http://localhost/hook/$EVENT" 2>/dev/null
    exit 0

    """#
}
