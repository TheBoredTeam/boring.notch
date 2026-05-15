import Foundation

/// Kairo's LLM brain with a real tool-calling loop.
///
/// Each turn:
///   1. Build messages (system prompt + LTM + ambient + short-term + user)
///   2. Ask Ollama
///   3. If the reply contains a `[CALL] {...}` line, execute the tool and
///      feed `[TOOL_RESULT] {...}` back as a user message → loop (step 2)
///   4. Otherwise return the cleaned reply
///
/// Bounded by `maxToolHops` to prevent runaway loops.
@MainActor
final class KairoBrain {
    let ollama: OllamaClient
    let contextBuilder: ContextBuilder
    let executor: TieredExecutor
    let shortTerm: KairoShortTermMemory
    let longTerm: KairoLongTermMemory?

    /// Max number of tool-call hops per turn before we give up.
    private let maxToolHops = 4

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
        var messages = contextBuilder.build(
            userInput: input,
            shortTerm: shortTerm.recent(),
            ambient: ambient,
            longTerm: longTerm?.all() ?? []
        )

        for hop in 0..<maxToolHops {
            let raw = try await ollama.chat(messages: messages)

            // Parse for tool call
            if let call = Self.extractToolCall(raw) {
                kairoDebug("Brain tool-call hop \(hop): \(call.name) args=\(call.argsJSON)")

                // Record assistant's call in the running message log
                messages.append(KairoChatMessage(role: "assistant", content: raw))

                let result = await runTool(call.name, args: call.args)
                let resultLine = "[TOOL_RESULT] \(result.success ? "ok" : "error"): \(result.output)"
                kairoDebug("Brain tool-result: \(resultLine.prefix(160))")

                // Feed the result back as a user-role message — Ollama's
                // /v1/chat/completions accepts arbitrary content here.
                messages.append(KairoChatMessage(role: "user", content: resultLine))
                continue
            }

            // No more tool calls — finalize this turn.
            let cleaned = Self.stripStrayTags(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            shortTerm.append("user: \(input)")
            shortTerm.append("kairo: \(cleaned)")
            return cleaned
        }

        // Exceeded hop limit. Return whatever the last assistant turn said,
        // stripped of unfinished tool tags.
        let last = messages.last(where: { $0.role == "assistant" })?.content ?? "I'm stuck in a loop. Try rephrasing."
        let cleaned = Self.stripStrayTags(last).trimmingCharacters(in: .whitespacesAndNewlines)
        shortTerm.append("user: \(input)")
        shortTerm.append("kairo: \(cleaned)")
        return cleaned
    }

    // MARK: - Tool execution

    private func runTool(_ name: String, args: [String: Any]) async -> ToolResult {
        do {
            return try await executor.run(toolName: name, args: args)
        } catch {
            return ToolResult(success: false, output: "Tool error: \(error.localizedDescription)", tierUsed: .native)
        }
    }

    // MARK: - Parsing

    struct ToolCall {
        let name: String
        let args: [String: Any]
        let argsJSON: String
    }

    /// Finds the FIRST `[CALL] {…}` line in the model output. Tolerant of
    /// surrounding whitespace and other text on the same line. Returns nil
    /// if there's no parseable call.
    static func extractToolCall(_ text: String) -> ToolCall? {
        // Split into lines and scan
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let range = line.range(of: "[CALL]") else { continue }
            let afterTag = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            // Need to find the JSON object
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

    /// Strip stray `[CALL]…`, `[TOOL_RESULT]…` lines from a reply we're
    /// about to surface to the user (defensive — the loop shouldn't produce
    /// these in the final hop but the model can leak partial markers).
    static func stripStrayTags(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !t.hasPrefix("[CALL]") && !t.hasPrefix("[TOOL_RESULT]")
        }
        return kept.joined(separator: "\n")
    }
}
