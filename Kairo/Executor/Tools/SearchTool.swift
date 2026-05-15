import Foundation

/// Real web search.
///
/// Strategy:
///   1. If `BRAVE_SEARCH_API_KEY` is set, use Brave Search (5 results).
///   2. Otherwise fall back to DuckDuckGo Instant Answer API (free, no key).
///
/// Brave gives general web results; DDG IA gives only summary/definition-style
/// answers but is good enough to ground the LLM with no key required.
struct SearchTool: Tool {
    let name = "web_search"
    let description = "Searches the web and returns results"
    let permissionTier: PermissionTier = .safe
    let supportedTiers: [ExecutionTier] = [.native]

    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult {
        let query = (args["query"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return ToolResult(success: false, output: "Empty query", tierUsed: .native)
        }

        // Prefer Brave if key is present
        if let key = ProcessInfo.processInfo.environment["BRAVE_SEARCH_API_KEY"],
           !key.isEmpty,
           let braveResult = try? await braveSearch(query: query, key: key),
           !braveResult.isEmpty {
            return ToolResult(success: true, output: braveResult, tierUsed: .native)
        }

        // Fall back to DuckDuckGo Instant Answer
        let ddgResult = (try? await duckDuckGoInstantAnswer(query: query))
            ?? "No results for: \(query)"
        return ToolResult(success: true, output: ddgResult, tierUsed: .native)
    }

    // MARK: - Brave

    private func braveSearch(query: String, key: String) async throws -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(encoded)&count=5") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let web = json["web"] as? [String: Any] ?? [:]
        let results = web["results"] as? [[String: Any]] ?? []

        let lines = results.prefix(5).compactMap { r -> String? in
            guard let title = r["title"] as? String,
                  let desc  = r["description"] as? String else { return nil }
            let cleanDesc = desc
                .replacingOccurrences(of: "<strong>", with: "")
                .replacingOccurrences(of: "</strong>", with: "")
            return "• \(title) — \(cleanDesc)"
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - DuckDuckGo Instant Answer

    private func duckDuckGoInstantAnswer(query: String) async throws -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("Kairo/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8

        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        var lines: [String] = []
        if let answer = json["Answer"] as? String, !answer.isEmpty {
            lines.append(answer)
        }
        if let abstract = json["AbstractText"] as? String, !abstract.isEmpty {
            let source = (json["AbstractSource"] as? String).map { " — \($0)" } ?? ""
            lines.append(abstract + source)
        }
        if let definition = json["Definition"] as? String, !definition.isEmpty,
           !lines.contains(definition) {
            lines.append(definition)
        }
        if let topics = json["RelatedTopics"] as? [[String: Any]] {
            let topThree = topics.prefix(3).compactMap { topic -> String? in
                guard let text = topic["Text"] as? String, !text.isEmpty else { return nil }
                return "• \(text)"
            }
            lines.append(contentsOf: topThree)
        }

        return lines.isEmpty ? "No instant answer for: \(query)" : lines.joined(separator: "\n")
    }
}
