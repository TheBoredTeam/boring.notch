//
//  AgentHookInstaller.swift
//  boringCode
//
//  Instala/remove os hooks do boringCode nos agentes (Claude Code em
//  ~/.claude/settings.json, Codex em ~/.codex/hooks.json) sem tocar nos hooks
//  de outras ferramentas. Eventos, timeouts e o flag `[features] hooks` do Codex
//  seguem os instaladores do Open Island (github.com/Octane0411/open-vibe-island), GPL-3.0.
//

import Foundation
import os

struct AgentHookInstaller {
    enum State: Equatable {
        case installed
        case notInstalled
        /// Instalado, mas faltam eventos ou o script sumiu.
        case outdated
        /// O agente não está instalado (a pasta ~/.claude ou ~/.codex não existe).
        case agentNotFound
        case error(String)
    }

    struct Event {
        let name: String
        var matcher: String?
        var timeout: Int?
    }

    let agent: AgentKind
    let directory: URL
    let fileName: String
    let events: [Event]

    var fileURL: URL { directory.appendingPathComponent(fileName) }

    static let permissionTimeout = 86_400

    static let claude = AgentHookInstaller(
        agent: .claude,
        directory: home.appendingPathComponent(".claude", isDirectory: true),
        fileName: "settings.json",
        events: [
            Event(name: "SessionStart"),
            Event(name: "SessionEnd"),
            Event(name: "UserPromptSubmit"),
            Event(name: "PreToolUse", matcher: "*"),
            Event(name: "PostToolUse", matcher: "*"),
            Event(name: "PostToolUseFailure", matcher: "*"),
            // Timeout longo: o hook fica esperando você clicar no notch.
            Event(name: "PermissionRequest", matcher: "*", timeout: permissionTimeout),
            Event(name: "PermissionDenied", matcher: "*"),
            Event(name: "Notification", matcher: "*"),
            Event(name: "Stop"),
            Event(name: "StopFailure"),
            Event(name: "SubagentStart"),
            Event(name: "SubagentStop"),
            Event(name: "PreCompact"),
        ]
    )

    /// Codex: sem Pre/PostToolUse de propósito — um hook por comando polui o log do Codex.
    static let codex = AgentHookInstaller(
        agent: .codex,
        directory: home.appendingPathComponent(".codex", isDirectory: true),
        fileName: "hooks.json",
        events: [
            Event(name: "SessionStart", matcher: "startup|resume", timeout: 30),
            Event(name: "UserPromptSubmit", timeout: 30),
            Event(name: "PermissionRequest", timeout: 3_600),
            Event(name: "Stop", timeout: 30),
        ]
    )

    static let all = [claude, codex]

    static func installer(for agent: AgentKind) -> AgentHookInstaller {
        agent == .claude ? claude : codex
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static let marker = "boringCode/bin/boringcode-hook"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "boringcode", category: "AgentHookInstaller")

    // MARK: - Estado

    func currentState() -> State {
        guard FileManager.default.fileExists(atPath: directory.path) else { return .agentNotFound }
        let settings: [String: Any]
        do { settings = try readJSON() } catch { return .error(error.localizedDescription) }

        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        let installedEvents = events.filter { event in
            Self.groups(in: hooks, event: event.name).contains(where: Self.isManagedGroup)
        }
        if installedEvents.isEmpty { return .notInstalled }
        let scriptOK = FileManager.default.isExecutableFile(atPath: AgentPaths.hookScriptURL.path)
        let flagOK = agent != .codex || CodexFeatureFlag.isEnabled(in: directory)
        return installedEvents.count == events.count && scriptOK && flagOK ? .installed : .outdated
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

    func install() throws {
        try Self.writeHookScript()
        var settings = try readJSON()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for event in events {
            var list = Self.groups(in: hooks, event: event.name).filter { !Self.isManagedGroup($0) }
            var command = "\(Self.shellQuote(AgentPaths.hookScriptURL.path)) \(event.name)"
            if agent != .claude { command += " \(agent.rawValue)" }
            var hook: [String: Any] = ["type": "command", "command": command]
            if let timeout = event.timeout { hook["timeout"] = timeout }
            var group: [String: Any] = ["hooks": [hook]]
            if let matcher = event.matcher { group["matcher"] = matcher }
            list.append(group)
            hooks[event.name] = list
        }

        settings["hooks"] = hooks
        try writeJSON(settings)
        if agent == .codex { try CodexFeatureFlag.enable(in: directory) }
        Self.log.info("hooks instalados em \(fileURL.path)")
    }

    /// Remove só as entradas do boringCode. No Codex, o flag `[features] hooks`
    /// fica — outras ferramentas (ex.: Open Island) também dependem dele.
    func uninstall() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        var settings = try readJSON()
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for (event, _) in hooks {
            let remaining = Self.groups(in: hooks, event: event).filter { !Self.isManagedGroup($0) }
            if remaining.isEmpty { hooks[event] = nil } else { hooks[event] = remaining }
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try writeJSON(settings)
        Self.log.info("hooks removidos de \(fileURL.path)")
    }

    // MARK: - JSON

    private static func groups(in hooks: [String: Any], event: String) -> [[String: Any]] {
        hooks[event] as? [[String: Any]] ?? []
    }

    private static func isManagedGroup(_ group: [String: Any]) -> Bool {
        let entries = group["hooks"] as? [[String: Any]] ?? []
        return entries.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    private func readJSON() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallerError.invalidJSON(fileURL.path)
        }
        return object
    }

    private func writeJSON(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Self.backup(fileURL)
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: fileURL, options: .atomic)
    }

    /// Copia `arquivo.boringcode-backup.<data>` e mantém só os 5 mais recentes daquele arquivo.
    static func backup(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let prefix = url.lastPathComponent + ".boringcode-backup."
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(prefix + stamp))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in files.filter({ $0.hasPrefix(prefix) }).sorted().dropLast(5) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    enum InstallerError: LocalizedError {
        case invalidJSON(String)
        var errorDescription: String? {
            switch self {
            case .invalidJSON(let path): "\(path) não é um JSON válido — corrija antes de instalar."
            }
        }
    }
}

/// `[features] hooks = true` no ~/.codex/config.toml — sem ele o Codex ignora o hooks.json.
/// Edição linha a linha (sem parser TOML), mexendo só nessa chave.
enum CodexFeatureFlag {
    private static func configURL(in directory: URL) -> URL {
        directory.appendingPathComponent("config.toml")
    }

    static func isEnabled(in directory: URL) -> Bool {
        let lines = (try? String(contentsOf: configURL(in: directory), encoding: .utf8))?
            .components(separatedBy: "\n") ?? []
        guard let range = featuresRange(lines) else { return false }
        return lines[range].contains { isFlagLine($0, value: "true") }
    }

    static func enable(in directory: URL) throws {
        guard !isEnabled(in: directory) else { return }
        let url = configURL(in: directory)
        let original = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = original.isEmpty ? [] : original.components(separatedBy: "\n")

        if let range = featuresRange(lines) {
            if let index = lines[range].firstIndex(where: { isFlagLine($0, value: nil) }) {
                lines[index] = "hooks = true"
            } else {
                lines.insert("hooks = true", at: range.lowerBound)
            }
        } else {
            if let last = lines.last, !last.isEmpty { lines.append("") }
            lines.append(contentsOf: ["[features]", "hooks = true", ""])
        }

        AgentHookInstaller.backup(url)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Linhas dentro da seção `[features]` (depois do cabeçalho, até a próxima seção).
    private static func featuresRange(_ lines: [String]) -> Range<Int>? {
        guard let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[features]" }) else {
            return nil
        }
        let start = header + 1
        let end = lines[start...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }) ?? lines.count
        return start..<end
    }

    private static func isFlagLine(_ line: String, value: String?) -> Bool {
        let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, parts[0] == "hooks" else { return false }
        guard let value else { return true }
        return parts[1].split(separator: "#").first?.trimmingCharacters(in: .whitespaces) == value
    }
}

enum AgentHookScript {
    /// Script POSIX: repassa o JSON do hook para o socket do boringCode e imprime
    /// a resposta (decisão de permissão). Sai sem fazer nada se o app não estiver aberto.
    /// Uso: boringcode-hook <Evento> [claude|codex]
    static func contents(socketPath: String) -> String {
        let quoted = "'" + socketPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return template.replacingOccurrences(of: "__BORINGCODE_SOCKET__", with: quoted)
    }

    private static let template = #"""
    #!/bin/sh
    # boringCode — ponte entre os hooks dos agentes (Claude Code, Codex) e o notch.
    # Gerado pelo app; será sobrescrito. Fail-open: sem o app, não faz nada.
    SOCK=__BORINGCODE_SOCKET__
    EVENT="${1:-unknown}"
    AGENT="${2:-claude}"
    if [ -n "$BORINGCODE_SKIP_HOOKS" ] || [ ! -S "$SOCK" ]; then
      cat >/dev/null
      exit 0
    fi

    # Sobe a árvore de processos até o agente para achar o TTY e o PID da sessão.
    TTY=""; AGENT_PID=""; pid=$PPID; i=0
    while [ $i -lt 6 ] && [ "${pid:-0}" -gt 1 ]; do
      comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
      t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
      if [ -z "$TTY" ] && [ -n "$t" ] && [ "$t" != "??" ]; then TTY="$t"; fi
      case "$comm" in *claude*|*codex*) AGENT_PID=$pid; break ;; esac
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
      --data-binary @- "http://localhost/hook/$AGENT/$EVENT" 2>/dev/null
    exit 0

    """#
}
