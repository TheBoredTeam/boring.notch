import Foundation

/// Provider-agnostic chat-completion client. Anything that takes a list of
/// chat messages and returns an assistant string conforms here. Lets the
/// Brain run on Ollama (local), Claude, OpenAI, or a fallback chain without
/// caring which.
protocol LLMClient: Sendable {
    /// Short human label for logs ("ollama", "anthropic", "openai", "fallback").
    var label: String { get }
    /// Returns the assistant's reply for the given message history.
    func chat(messages: [KairoChatMessage]) async throws -> String
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case notConfigured(String)
    case transport(String)
    case httpStatus(Int, String)
    case malformedResponse
    case allBackendsFailed([Error])

    var errorDescription: String? {
        switch self {
        case .notConfigured(let s):     return "\(s) not configured (missing API key)."
        case .transport(let s):         return "Network: \(s)"
        case .httpStatus(let c, let b): return "HTTP \(c): \(b)"
        case .malformedResponse:        return "Malformed LLM response."
        case .allBackendsFailed(let errs):
            return "All LLM backends failed: \(errs.map { $0.localizedDescription }.joined(separator: " · "))"
        }
    }
}

// MARK: - Anthropic

/// Claude via Messages API. Reads `ANTHROPIC_API_KEY` from env (loaded by
/// AppDelegate from `~/.kairo.env` or `~/AI/Kairo/.env`).
struct AnthropicLLMClient: LLMClient {
    let label = "anthropic"
    var model: String
    var maxTokens: Int

    init(model: String = "claude-3-5-sonnet-20241022", maxTokens: Int = 1024) {
        self.model = model
        self.maxTokens = maxTokens
    }

    func chat(messages: [KairoChatMessage]) async throws -> String {
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty else {
            throw LLMError.notConfigured("Anthropic")
        }

        // Anthropic wants `system` separated from the `messages` array.
        // Everything role=system collapses into a single system prompt;
        // user / assistant stay in messages.
        let systemBlocks = messages.filter { $0.role == "system" }.map { $0.content }
        let systemText = systemBlocks.joined(separator: "\n\n")
        let nonSystem = messages.filter { $0.role != "system" }.map { msg -> [String: Any] in
            // Anthropic accepts only user/assistant in messages
            let role = (msg.role == "assistant") ? "assistant" : "user"
            return ["role": role, "content": msg.content]
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": nonSystem
        ]
        if !systemText.isEmpty { body["system"] = systemText }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw LLMError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.transport("no http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpStatus(http.statusCode, body.prefix(300).description)
        }

        // content: [{type:"text", text:"..."}, ...]
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let content = json["content"] as? [[String: Any]] else {
            throw LLMError.malformedResponse
        }
        let text = content
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
        guard !text.isEmpty else { throw LLMError.malformedResponse }
        return text
    }
}

// MARK: - OpenAI

/// GPT-4o-class chat client. Reads `OPENAI_API_KEY` from env.
struct OpenAILLMClient: LLMClient {
    let label = "openai"
    var model: String
    var maxTokens: Int

    init(model: String = "gpt-4o-mini", maxTokens: Int = 1024) {
        self.model = model
        self.maxTokens = maxTokens
    }

    func chat(messages: [KairoChatMessage]) async throws -> String {
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty else {
            throw LLMError.notConfigured("OpenAI")
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw LLMError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.transport("no http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpStatus(http.statusCode, body.prefix(300).description)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let choices = json["choices"] as? [[String: Any]] ?? []
        let msg = (choices.first?["message"] as? [String: Any])?["content"] as? String ?? ""
        guard !msg.isEmpty else { throw LLMError.malformedResponse }
        return msg
    }
}

// MARK: - Fallback chain

/// Tries each client in order. Returns the first success. If all fail,
/// throws `.allBackendsFailed` with the collected errors.
///
/// Default order in AppDelegate: Ollama → Anthropic → OpenAI. So Kairo
/// works fully locally when Ollama is up, automatically falls back to
/// Claude when Ollama is down (if the key is set), and finally to OpenAI.
struct LLMFallbackClient: LLMClient {
    let label: String
    let clients: [LLMClient]

    init(_ clients: [LLMClient]) {
        self.clients = clients
        self.label = "fallback(\(clients.map { $0.label }.joined(separator: "→")))"
    }

    /// Builds a chain from local + only the cloud backends whose API keys
    /// are present in the environment. Avoids polluting fallback errors with
    /// "Anthropic not configured" / "OpenAI not configured" when the user
    /// is running Ollama-only.
    ///
    /// Order: local first (cheapest, most private), then any configured
    /// cloud backends so the agent stays alive when Ollama is down.
    static func configuredChain() -> LLMFallbackClient {
        let env = ProcessInfo.processInfo.environment
        var chain: [LLMClient] = [OllamaClient()]
        if let key = env["ANTHROPIC_API_KEY"], !key.isEmpty {
            chain.append(AnthropicLLMClient())
        }
        if let key = env["OPENAI_API_KEY"], !key.isEmpty {
            chain.append(OpenAILLMClient())
        }
        return LLMFallbackClient(chain)
    }

    func chat(messages: [KairoChatMessage]) async throws -> String {
        var errors: [Error] = []
        for client in clients {
            do {
                let reply = try await client.chat(messages: messages)
                if clients.count > 1, client.label != clients.first?.label {
                    print("[Kairo] LLM fallback succeeded via \(client.label)")
                }
                return reply
            } catch {
                print("[Kairo] LLM \(client.label) failed: \(error.localizedDescription)")
                errors.append(error)
            }
        }
        throw LLMError.allBackendsFailed(errors)
    }
}

// MARK: - Make OllamaClient conform

extension OllamaClient: LLMClient {
    var label: String { "ollama" }
    // `chat(messages:)` already exists with the right signature.
}
