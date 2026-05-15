import Foundation

struct KairoChatMessage: Codable {
    let role: String
    let content: String
}

final class OllamaClient {
    let baseURL = URL(string: "http://localhost:11434/v1/chat/completions")!
    let model: String

    init(model: String = "qwen2.5:7b") { self.model = model }

    func chat(messages: [KairoChatMessage]) async throws -> String {
        var req = URLRequest(url: baseURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer ollama", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let choices = json["choices"] as? [[String: Any]] ?? []
        let msg = (choices.first?["message"] as? [String: Any])?["content"] as? String ?? ""
        return msg
    }
}
