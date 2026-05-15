import Foundation

/// Kairo's LLM brain. One turn = build context → call Ollama → record both
/// sides into short-term memory. Long-term memory (when present) is threaded
/// into the system messages by the ContextBuilder.
@MainActor
final class KairoBrain {
    let ollama: OllamaClient
    let contextBuilder: ContextBuilder
    let executor: TieredExecutor
    let shortTerm: KairoShortTermMemory
    let longTerm: KairoLongTermMemory?

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
        let messages = contextBuilder.build(
            userInput: input,
            shortTerm: shortTerm.recent(),
            ambient: ambient,
            longTerm: longTerm?.all() ?? []
        )
        let response = try await ollama.chat(messages: messages)
        shortTerm.append("user: \(input)")
        shortTerm.append("kairo: \(response)")
        return response
    }
}
