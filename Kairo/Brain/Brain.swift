import Foundation

@MainActor
final class KairoBrain {
    let ollama: OllamaClient
    let contextBuilder: ContextBuilder
    let executor: TieredExecutor
    let memory: KairoShortTermMemory

    init(ollama: OllamaClient, contextBuilder: ContextBuilder, executor: TieredExecutor, memory: KairoShortTermMemory) {
        self.ollama = ollama
        self.contextBuilder = contextBuilder
        self.executor = executor
        self.memory = memory
    }

    func handle(input: String, ambient: KairoAmbientContext) async throws -> String {
        let messages = contextBuilder.build(userInput: input, shortTerm: memory.recent(), ambient: ambient)
        let response = try await ollama.chat(messages: messages)
        memory.append("user: \(input)")
        memory.append("kairo: \(response)")
        return response
    }
}
