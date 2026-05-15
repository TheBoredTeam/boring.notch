import Foundation

// MARK: - Agent state

/// What the agent is currently doing. Surfaced in the CaptionHUD so the user
/// can see *what the agent is working on*, not just "thinking".
public enum KairoAgentState: Equatable {
    case idle
    case listening
    case thinking
    case searching(String)   // query
    case reading(String)     // URL or host
    case seeing              // screen capture / vision
    case acting(String)      // tool name
    case speaking

    public var label: String {
        switch self {
        case .idle:                return "Idle"
        case .listening:           return "Listening"
        case .thinking:            return "Thinking"
        case .searching(let q):    return "Searching · \"\(String(q.prefix(40)))\""
        case .reading(let u):      return "Reading · \(String(u.prefix(40)))"
        case .seeing:              return "Looking at screen"
        case .acting(let t):       return "Acting · \(t)"
        case .speaking:            return "Speaking"
        }
    }
}

// MARK: - Brain

/// Kairo's ReAct loop. Each turn:
///   1. Ask the LLM for a THOUGHT + (CALL | ANSWER)
///   2. If CALL, run the tool, append OBSERVATION, loop
///   3. If ANSWER, return cleaned final
///
/// Bounded by `maxToolHops`. Emits `stateObserver` updates per hop so the
/// UI can show "Searching · ...", "Reading · ...", etc.
@MainActor
final class KairoBrain {
    let ollama: OllamaClient
    let contextBuilder: ContextBuilder
    let executor: TieredExecutor
    let shortTerm: KairoShortTermMemory
    let longTerm: KairoLongTermMemory?

    /// UI hook — set by AppDelegate to drive the CaptionHUD header.
    var stateObserver: ((KairoAgentState) -> Void)?

    /// Trace log — every THOUGHT / CALL / OBSERVATION / ANSWER from the
    /// last turn, in order. Useful for debugging.
    private(set) var lastTrace: [String] = []

    private let maxToolHops = 6

    init(
        ollama: OllamaClient,
        contextBuilder: ContextBuilder,
        executor: TieredExecutor,
        shortTerm: KairoShortTermMemory,
        longTerm: KairoLongTermMemory? = nil
    ) {
        self.ollama = ollama
        self.contextBuilder = contextBuilder
        self.executor = executor
        self.shortTerm = shortTerm
        self.longTerm = longTerm
    }

    func handle(input: String, ambient: KairoAmbientContext) async throws -> String {
        lastTrace.removeAll()
        emitState(.thinking)

        var messages = contextBuilder.build(
            userInput: input,
            shortTerm: shortTerm.recent(),
            ambient: ambient,
            longTerm: longTerm?.all() ?? []
        )

        for hop in 0..<maxToolHops {
            emitState(.thinking)
            let raw = try await ollama.chat(messages: messages)
            traceModelOutput(raw)

            // 1. Did the model give us a final answer?
            if let answer = Self.extractAnswer(raw) {
                let cleaned = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                shortTerm.append("user: \(input)")
                shortTerm.append("kairo: \(cleaned)")
                emitState(.speaking)
                return cleaned
            }

            // 2. Did the model emit a tool call?
            if let call = Self.extractToolCall(raw) {
                kairoDebug("Brain hop \(hop): [CALL] \(call.name) args=\(call.argsJSON)")
                emitState(stateForCall(call))

                messages.append(KairoChatMessage(role: "assistant", content: raw))
                let result = await runTool(call.name, args: call.args)
                let obs = "[OBSERVATION] \(result.success ? "ok" : "error"): \(truncate(result.output, max: 4000))"
                lastTrace.append(obs)
                kairoDebug("Brain hop \(hop): \(obs.prefix(200))")

                messages.append(KairoChatMessage(role: "user", content: obs))
                continue
            }

            // 3. No CALL, no ANSWER — treat the raw text as the answer
            // (model went off-script; fall back gracefully)
            let fallback = Self.stripStrayTags(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                shortTerm.append("user: \(input)")
                shortTerm.append("kairo: \(fallback)")
                emitState(.speaking)
                return fallback
            }
        }

        // Exceeded hop limit
        emitState(.speaking)
        let fallback = "Hit my tool-loop limit before finishing. Try a simpler question or break it into steps."
        shortTerm.append("user: \(input)")
        shortTerm.append("kairo: \(fallback)")
        return fallback
    }

    // MARK: - Tool execution

    private func runTool(_ name: String, args: [String: Any]) async -> ToolResult {
        do {
            return try await executor.run(toolName: name, args: args)
        } catch {
            return ToolResult(success: false, output: "Tool error: \(error.localizedDescription)", tierUsed: .native)
        }
    }

    // MARK: - State emission helpers

    private func stateForCall(_ call: ToolCall) -> KairoAgentState {
        switch call.name {
        case "web_search":
            let q = (call.args["query"] as? String) ?? ""
            return .searching(q)
        case "web_read":
            let url = (call.args["url"] as? String) ?? ""
            let host = URL(string: url)?.host ?? url
            return .reading(host)
        case "see_screen", "vision":
            return .seeing
        default:
            return .acting(call.name)
        }
    }

    private func emitState(_ s: KairoAgentState) {
        stateObserver?(s)
    }

    private func traceModelOutput(_ raw: String) {
        // Trim to keep the trace readable; full raw still goes through debug.
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true).prefix(6)
        for line in lines {
            lastTrace.append(String(line))
        }
    }

    private func truncate(_ s: String, max: Int) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max)) + " …(truncated)"
    }

    // MARK: - Parsing

    struct ToolCall {
        let name: String
        let args: [String: Any]
        let argsJSON: String
    }

    /// Find the first `[CALL] {…}` line anywhere in the model output.
    static func extractToolCall(_ text: String) -> ToolCall? {
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let range = line.range(of: "[CALL]") else { continue }
            let afterTag = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard let braceStart = afterTag.firstIndex(of: "{") else { continue }
            let jsonStr = String(afterTag[braceStart...])
            guard
                let data = jsonStr.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let name = obj["tool"] as? String
            else { continue }
            let args = (obj["args"] as? [String: Any]) ?? [:]
            return ToolCall(name: name, args: args, argsJSON: jsonStr)
        }
        return nil
    }

    /// Find the first `[ANSWER]` block — returns everything from that token
    /// to end of message (next `[CALL]` would have been processed first).
    static func extractAnswer(_ text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        var collected: [String] = []
        var inAnswer = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let r = trimmed.range(of: "[ANSWER]") {
                inAnswer = true
                let after = trimmed[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if !after.isEmpty { collected.append(String(after)) }
                continue
            }
            if inAnswer {
                // Stop at any new tag
                if trimmed.hasPrefix("[CALL]") || trimmed.hasPrefix("[OBSERVATION]") || trimmed.hasPrefix("THOUGHT:") {
                    break
                }
                collected.append(line)
            }
        }
        guard inAnswer else { return nil }
        return collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripStrayTags(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !t.hasPrefix("[CALL]")
                && !t.hasPrefix("[OBSERVATION]")
                && !t.hasPrefix("THOUGHT:")
                && !t.hasPrefix("[ANSWER]")
        }
        return kept.joined(separator: "\n")
    }
}
