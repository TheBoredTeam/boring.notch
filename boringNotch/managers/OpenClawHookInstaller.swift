//
//  OpenClawHookInstaller.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

enum OpenClawHookInstaller {
    private static let pluginID = "boring-notch"

    private static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".openclaw")
    }

    private static var pluginDirectory: URL {
        root.appendingPathComponent("boring-notch-plugin", isDirectory: true)
    }

    private static var tokenURL: URL { pluginDirectory.appendingPathComponent("token") }

    static func configuredToken() -> String? {
        guard let token = try? String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              token.utf8.count >= 32 else { return nil }
        return token
    }

    static func install(enableInternalHooks: Bool = false) throws -> Bool {
        let configURL = root.appendingPathComponent("openclaw.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw InstallError.missingOpenClaw
        }
        let original = try Data(contentsOf: configURL)
        guard var config = try JSONSerialization.jsonObject(with: original) as? [String: Any] else {
            throw InstallError.invalidConfiguration
        }
        let existingEntry = pluginDirectory.appendingPathComponent("index.ts")
        if FileManager.default.fileExists(atPath: pluginDirectory.path),
           !FileManager.default.fileExists(atPath: existingEntry.path),
           !(try FileManager.default.contentsOfDirectory(atPath: pluginDirectory.path)).isEmpty {
            throw InstallError.unknownExistingPlugin
        }
        if FileManager.default.fileExists(atPath: existingEntry.path) {
            let content = try String(contentsOf: existingEntry, encoding: .utf8)
            guard content.hasPrefix("// boring-notch-openclaw-plugin") else {
                throw InstallError.unknownExistingPlugin
            }
        }
        let hookDirectory = root.appendingPathComponent("hooks/boring-notch", isDirectory: true)
        let hookHandler = hookDirectory.appendingPathComponent("handler.ts")
        if FileManager.default.fileExists(atPath: hookDirectory.path),
           !FileManager.default.fileExists(atPath: hookHandler.path),
           !(try FileManager.default.contentsOfDirectory(atPath: hookDirectory.path)).isEmpty {
            throw InstallError.unknownExistingPlugin
        }
        if FileManager.default.fileExists(atPath: hookHandler.path) {
            let content = try String(contentsOf: hookHandler, encoding: .utf8)
            guard content.hasPrefix("// boring-notch-openclaw-hook") else {
                throw InstallError.unknownExistingPlugin
            }
        }
        let token = configuredToken() ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let updated = try configurationWithHooks(
            config, pluginPath: pluginDirectory.path,
            enableInternalHooks: enableInternalHooks
        )
        let configChanged = try JSONSerialization.data(withJSONObject: updated, options: [.sortedKeys])
            != JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        config = updated
        let replacement = try JSONSerialization.data(
            withJSONObject: config, options: [.prettyPrinted, .sortedKeys]
        ) + Data("\n".utf8)
        let changed = configChanged || configuredToken() == nil
            || (try? String(contentsOf: pluginDirectory.appendingPathComponent("package.json"), encoding: .utf8)) != pluginPackage
            || (try? String(contentsOf: pluginDirectory.appendingPathComponent("openclaw.plugin.json"), encoding: .utf8)) != pluginManifest
            || (try? String(contentsOf: existingEntry, encoding: .utf8)) != pluginSource
            || (try? String(contentsOf: hookDirectory.appendingPathComponent("HOOK.md"), encoding: .utf8)) != hookManifest
            || (try? String(contentsOf: hookHandler, encoding: .utf8)) != hookSource
        guard changed else { return false }

        var backup: URL?
        if configChanged {
            let formatter = ISO8601DateFormatter()
            let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let selected = root.appendingPathComponent("openclaw.json.backup-\(stamp)-boring-notch")
            guard !FileManager.default.fileExists(atPath: selected.path) else {
                throw InstallError.backupAlreadyExists
            }
            backup = selected
        }
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hookDirectory, withIntermediateDirectories: true)
        if let backup { try writePrivate(original, to: backup) }
        try writePrivate(Data((token + "\n").utf8), to: tokenURL)
        try writePrivate(Data(pluginPackage.utf8), to: pluginDirectory.appendingPathComponent("package.json"))
        try writePrivate(Data(pluginManifest.utf8), to: pluginDirectory.appendingPathComponent("openclaw.plugin.json"))
        try writePrivate(Data(pluginSource.utf8), to: existingEntry)
        try writePrivate(Data(hookManifest.utf8), to: hookDirectory.appendingPathComponent("HOOK.md"))
        try writePrivate(Data(hookSource.utf8), to: hookHandler)
        if configChanged { try writePrivate(replacement, to: configURL) }
        return true
    }

    static func configurationWithHooks(
        _ root: [String: Any], pluginPath: String,
        enableInternalHooks: Bool = false
    ) throws -> [String: Any] {
        var result = root
        var plugins = result["plugins"] as? [String: Any] ?? [:]
        guard result["plugins"] == nil || result["plugins"] is [String: Any],
              plugins["enabled"] as? Bool != false,
              !(plugins["deny"] as? [String] ?? []).contains(pluginID) else {
            throw InstallError.invalidConfiguration
        }
        var load = plugins["load"] as? [String: Any] ?? [:]
        guard plugins["load"] == nil || plugins["load"] is [String: Any],
              load["paths"] == nil || load["paths"] is [String] else {
            throw InstallError.invalidConfiguration
        }
        var paths = load["paths"] as? [String] ?? []
        if !paths.contains(pluginPath) { paths.append(pluginPath) }
        load["paths"] = paths
        plugins["load"] = load
        var entries = plugins["entries"] as? [String: Any] ?? [:]
        guard plugins["entries"] == nil || plugins["entries"] is [String: Any],
              entries[pluginID] == nil || entries[pluginID] is [String: Any] else {
            throw InstallError.invalidConfiguration
        }
        var entry = entries[pluginID] as? [String: Any] ?? [:]
        entry["enabled"] = true
        entries[pluginID] = entry
        plugins["entries"] = entries
        if var allow = plugins["allow"] as? [String], !allow.contains(pluginID) {
            allow.append(pluginID)
            plugins["allow"] = allow
        }
        result["plugins"] = plugins

        var hooks = result["hooks"] as? [String: Any] ?? [:]
        guard result["hooks"] == nil || result["hooks"] is [String: Any],
              hooks["internal"] == nil || hooks["internal"] is [String: Any] else {
            throw InstallError.invalidConfiguration
        }
        var internalHooks = hooks["internal"] as? [String: Any] ?? [:]
        if enableInternalHooks { internalHooks["enabled"] = true }
        var hookEntries = internalHooks["entries"] as? [String: Any] ?? [:]
        guard internalHooks["entries"] == nil || internalHooks["entries"] is [String: Any],
              hookEntries[pluginID] == nil || hookEntries[pluginID] is [String: Any] else {
            throw InstallError.invalidConfiguration
        }
        var hookEntry = hookEntries[pluginID] as? [String: Any] ?? [:]
        hookEntry["enabled"] = true
        hookEntries[pluginID] = hookEntry
        internalHooks["entries"] = hookEntries
        hooks["internal"] = internalHooks
        result["hooks"] = hooks
        return result
    }

    private static func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static let pluginPackage = #"""
    {"name":"boring-notch-openclaw-plugin","version":"0.1.0","private":true,"type":"module","openclaw":{"extensions":["./index.ts"]}}
    """#

    private static let pluginManifest = #"""
    {"id":"boring-notch","name":"Boring Notch","description":"Forward local session events and approvals.","configSchema":{"type":"object","additionalProperties":false}}
    """#

    private static let hookManifest = #"""
    ---
    metadata:
      openclaw:
        name: boring-notch
        description: Forward local session events.
        events:
          - command:new
          - command:reset
          - command:stop
          - message:received
          - message:sent
          - session:patch
    ---

    # Boring Notch OpenClaw Hook

    Managed by Boring Notch. Forwards session events only to the local receiver.
    """#

    static let pluginSource = #"""
    // boring-notch-openclaw-plugin
    import { readFile } from "node:fs/promises";

    const TOKEN_PATH = \#(String(decoding: try! JSONEncoder().encode(tokenURL.path), as: UTF8.self));
    const ENDPOINT = "http://127.0.0.1:37892/openclaw/event";
    const text = (value) => typeof value === "string" ? value.trim() : undefined;
    const textValue = (value) => {
      if (typeof value === "string") return value.trim() || undefined;
      if (Array.isArray(value)) return value.map(textValue).filter(Boolean).join("\n") || undefined;
      if (value && typeof value === "object") {
        return textValue(value.content ?? value.text ?? value.message ?? value.title);
      }
      return undefined;
    };
    const session = (event, ctx) => text(event?.sessionKey ?? event?.sessionId ?? ctx?.sessionKey ?? ctx?.sessionId ?? ctx?.runId);
    const cwd = (event, ctx) => text(event?.workspaceDir ?? event?.cwd ?? ctx?.workspaceDir ?? ctx?.cwd);
    const message = (event) => textValue(event?.content ?? event?.message ?? event?.text ?? event?.reply ?? event?.result?.content);

    async function send(name, event, ctx, extra = {}) {
      const id = session(event, ctx);
      if (!id) return undefined;
      const payload = { event: {
        protocol_version: "1", source: "openclaw", session_id: id,
        hook_event_name: name, timestamp: new Date().toISOString(),
        cwd: cwd(event, ctx), message: message(event), ...extra
      }};
      try {
        const token = (await readFile(TOKEN_PATH, "utf8")).trim();
        const response = await fetch(ENDPOINT, {
          method: "POST",
          headers: { "content-type": "application/json", "Authorization": `Bearer ${token}` },
          body: JSON.stringify(payload), signal: AbortSignal.timeout(22000)
        });
        return response.ok ? await response.json() : undefined;
      } catch (_) { return undefined; }
    }

    export default {
      id: "boring-notch", name: "Boring Notch",
      description: "Forward local session activity and approvals.",
      register(api) {
        api.on("session_start", async (event, ctx) => { await send("SessionStart", event, ctx); });
        api.on("session_end", async (event, ctx) => { await send("SessionEnd", event, ctx); });
        api.on("message_received", async (event, ctx) => { await send("UserPromptSubmit", event, ctx); });
        api.on("message_sent", async (event, ctx) => { await send("AfterAgentResponse", event, ctx); });
        api.on("after_tool_call", async (event, ctx) => { await send("PostToolUse", event, ctx); });
        api.on("agent_end", async (event, ctx) => { await send("SessionEnd", event, ctx); });
        api.on("before_tool_call", async (event, ctx) => {
          const input = event?.params ?? event?.toolInput ?? event?.input;
          const response = await send("PermissionRequest", event, ctx, {
            tool_name: text(event?.toolName ?? event?.name ?? event?.tool?.name) ?? "Tool",
            tool_input: input && typeof input === "object" && !Array.isArray(input)
              ? input : { value: input ?? null }
          });
          return response?.decision?.behavior === "deny"
            ? { block: true, blockReason: "Denied in Boring Notch" } : undefined;
        });
      }
    };
    """#

    static let hookSource = #"""
    // boring-notch-openclaw-hook
    import { readFile } from "node:fs/promises";

    const TOKEN_PATH = \#(String(decoding: try! JSONEncoder().encode(tokenURL.path), as: UTF8.self));
    const ENDPOINT = "http://127.0.0.1:37892/openclaw/event";
    const text = (value) => typeof value === "string" ? value.trim() : undefined;
    export default async function handler(input) {
      const type = String(input?.type ?? "").toLowerCase();
      const operation = String(input?.action ?? "").toLowerCase();
      const action = operation.includes(":") ? operation
        : type && operation ? `${type}:${operation}` : operation || type;
      const status = String(input?.status ?? input?.context?.status ?? input?.context?.patch?.status ?? "").toLowerCase();
      const events = {
        "command:new": "SessionStart", "command:reset": "SessionEnd",
        "command:stop": "Stop", "message:received": "UserPromptSubmit",
        "message:sent": "AfterAgentResponse"
      };
      const name = events[action] ?? (action === "session:patch"
        ? (["completed", "done", "idle", "stopped"].includes(status) ? "SessionEnd"
          : ["waiting", "waiting_question", "question", "input_required"].includes(status) ? "AskUserQuestion"
          : ["approval_required", "permission_required"].includes(status) ? "PermissionRequest"
          : "SessionStart") : undefined);
      const id = text(input?.sessionKey ?? input?.sessionId ?? input?.context?.sessionKey ?? input?.context?.sessionId);
      if (!name || !id) return;
      const cwd = text(input?.workspaceDir ?? input?.cwd ?? input?.context?.workspaceDir);
      const message = text(input?.message ?? input?.text ?? input?.context?.message);
      const rawQuestion = input?.question ?? input?.context?.question ?? input?.context?.patch?.question;
      const question = rawQuestion && typeof rawQuestion === "object" ? {
        header: text(rawQuestion.header ?? rawQuestion.title),
        text: text(rawQuestion.text ?? rawQuestion.question ?? rawQuestion.prompt),
        options: Array.isArray(rawQuestion.options) ? rawQuestion.options.map(option => ({
          label: text(option?.label ?? option?.title ?? option?.value),
          description: text(option?.description)
        })).filter(option => option.label) : []
      } : undefined;
      try {
        const token = (await readFile(TOKEN_PATH, "utf8")).trim();
        const response = await fetch(ENDPOINT, {
          method: "POST",
          headers: { "content-type": "application/json", "Authorization": `Bearer ${token}` },
          body: JSON.stringify({ event: {
            protocol_version: "1", source: "openclaw", session_id: id,
            hook_event_name: name, timestamp: new Date().toISOString(), cwd, message, question
          }}),
          signal: AbortSignal.timeout(name === "AskUserQuestion" ? 295000 : 22000)
        });
        if (["AskUserQuestion", "PermissionRequest"].includes(name) && response.ok) {
          return await response.json();
        }
      } catch (_) { }
    }
    """#

    enum InstallError: LocalizedError {
        case missingOpenClaw
        case invalidConfiguration
        case unknownExistingPlugin
        case backupAlreadyExists

        var errorDescription: String? {
            switch self {
            case .missingOpenClaw: "OpenClaw configuration was not found."
            case .invalidConfiguration: "OpenClaw configuration cannot be changed safely."
            case .unknownExistingPlugin: "The plugin directory contains unrecognized files."
            case .backupAlreadyExists: "A configuration backup already exists for this timestamp."
            }
        }
    }
}
