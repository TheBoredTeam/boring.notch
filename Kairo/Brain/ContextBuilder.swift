import Foundation
import AppKit

/// Builds the LLM prompt context for a turn. Threads three sources:
///   1. The static system prompt (`KairoSystemPrompt.kairo`)
///   2. Long-term facts from `KairoLongTermMemory` (persisted)
///   3. Ambient signals (time, location, focused app)
///   4. Last 5 short-term turns
///
/// Long-term facts are included only when non-empty — Brain decides whether
/// to construct LTM at all.
@MainActor
final class ContextBuilder {
    func build(
        userInput: String,
        shortTerm: [String],
        ambient: KairoAmbientContext,
        longTerm: [String] = []
    ) -> [KairoChatMessage] {
        var messages: [KairoChatMessage] = []
        messages.append(KairoChatMessage(role: "system", content: KairoSystemPrompt.kairo))

        if !longTerm.isEmpty {
            let facts = longTerm.map { "- \($0)" }.joined(separator: "\n")
            messages.append(KairoChatMessage(
                role: "system",
                content: "KNOWN FACTS ABOUT JOHN:\n\(facts)"
            ))
        }

        let ctx = """
        TIME: \(ambient.time)
        LOCATION: \(ambient.location)
        FOCUSED APP: \(ambient.focusedApp)
        RECENT: \(shortTerm.suffix(5).joined(separator: " | "))
        """
        messages.append(KairoChatMessage(role: "system", content: ctx))
        messages.append(KairoChatMessage(role: "user", content: userInput))
        return messages
    }
}
