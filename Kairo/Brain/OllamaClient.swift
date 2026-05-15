import Foundation

struct KairoChatMessage: Codable {
    let role: String
    let content: String
}

/// Local-LLM client talking to Ollama's OpenAI-compatible `/v1/chat/completions`
/// on `localhost:11434`. Model and base URL are env-overridable so the user
/// can point at whichever model they've pulled without recompiling.
///
/// Env vars:
///   OLLAMA_URL   — defaults to http://localhost:11434
///   OLLAMA_MODEL — defaults to qwen2.5:7b
///
/// Errors thrown:
///   .notRunning   — couldn't connect (Ollama not started, wrong URL)
///   .modelMissing — HTTP 404 from /chat/completions (model isn't pulled)
///   .httpError    — any other non-2xx response
///   .malformed    — 2xx but no `choices[0].message.content`
final class OllamaClient {
    let baseURL: URL
    let model: String

    enum Error: LocalizedError {
        case notRunning(String)
        case modelMissing(String)
        case httpError(Int, String)
        case malformed

        var errorDescription: String? {
            switch self {
            case .notRunning(let s):
                return "Ollama not running (\(s)). Run `ollama serve` and try again."
            case .modelMissing(let m):
                return "Ollama model not pulled: \(m). Run `ollama pull \(m)`."
            case .httpError(let c, let b):
                return "Ollama HTTP \(c): \(b)"
            case .malformed:
                return "Ollama returned an unexpected payload."
            }
        }
    }

    init(model: String? = nil, baseURL: URL? = nil) {
        let env = ProcessInfo.processInfo.environment
        let urlString = baseURL?.absoluteString ?? env["OLLAMA_URL"] ?? "http://localhost:11434"
        self.baseURL = URL(string: urlString) ?? URL(string: "http://localhost:11434")!
        self.model = model ?? env["OLLAMA_MODEL"] ?? "qwen2.5:7b"
    }

    /// One-shot chat completion. Surfaces helpful errors instead of returning
    /// empty strings when the local model is misconfigured.
    func chat(messages: [KairoChatMessage]) async throws -> String {
        let endpoint = baseURL.appendingPathComponent("v1/chat/completions")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer ollama", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60     // local model — generation can take time

        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            // URLSession failures here are almost always "server down"
            throw Error.notRunning(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw Error.malformed
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 404 || bodyStr.localizedCaseInsensitiveContains("model")
                || bodyStr.localizedCaseInsensitiveContains("not found")
            {
                throw Error.modelMissing(model)
            }
            throw Error.httpError(http.statusCode, bodyStr.prefix(200).description)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let firstMsg = choices.first?["message"] as? [String: Any],
            let content = firstMsg["content"] as? String,
            !content.isEmpty
        else {
            throw Error.malformed
        }
        return content
    }

    // MARK: - Diagnostics

    /// Quick "is the server up + which models do you have" probe. Used by the
    /// `Test Ollama` menu item to give the user a one-glance status.
    func diagnose() async -> String {
        let endpoint = baseURL.appendingPathComponent("api/tags")
        var req = URLRequest(url: endpoint)
        req.timeoutInterval = 3
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return "✗ Ollama responded with status \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let models = (json["models"] as? [[String: Any]]) ?? []
            let names = models.compactMap { $0["name"] as? String }
            let hasOurs = names.contains(where: { $0.hasPrefix(model) || $0 == model })
            var lines: [String] = []
            lines.append("✓ Ollama running at \(baseURL.host ?? "localhost"):\(baseURL.port ?? 11434)")
            lines.append("• Configured model: \(model) \(hasOurs ? "✓ available" : "✗ NOT pulled — run `ollama pull \(model)`")")
            if names.isEmpty {
                lines.append("• No models pulled yet")
            } else {
                lines.append("• Available: \(names.prefix(5).joined(separator: ", "))\(names.count > 5 ? "…" : "")")
            }
            return lines.joined(separator: "\n")
        } catch {
            return "✗ Ollama unreachable at \(baseURL.absoluteString) — \(error.localizedDescription)"
        }
    }
}
