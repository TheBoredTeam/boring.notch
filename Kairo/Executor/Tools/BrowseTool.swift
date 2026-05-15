import Foundation

/// `browse` — opens a URL in the in-app **Agent Browser** (a HUD-styled
/// WKWebView window the user can see), waits for the page to load, then
/// returns the extracted plain-text content to the LLM.
///
/// Differences vs `web_read`:
///  - `web_read` is a headless URLSession fetch + regex HTML strip.
///    Fast, but misses JavaScript-rendered pages and the user never
///    sees what's happening.
///  - `browse` uses a real WKWebView. Executes JS. Renders the page.
///    The user SEES the agent loading the page in a premium floating
///    HUD window. The extracted text is what a human would actually
///    read.
///
/// Use `browse` for research where the user benefits from seeing what
/// the agent saw (hotels, restaurants, products, news). Use `web_read`
/// for cheap-and-fast text-only fetches.
///
/// Args:
///   url:   String (required) — the URL to load
///   query: String (optional) — substring to focus on (returned section
///          centered on the match)
///   max:   Int    (optional) — cap on returned chars (default 6000)
struct BrowseTool: Tool {
    let name = "browse"
    let description = "Opens a URL in the in-app Agent Browser, returns the page text"
    let permissionTier: PermissionTier = .safe
    let supportedTiers: [ExecutionTier] = [.native]

    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult {
        let raw = (args["url"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, let url = URL(string: raw) else {
            return ToolResult(success: false, output: "Missing or invalid 'url'", tierUsed: .native)
        }
        let maxChars = (args["max"] as? Int) ?? 6000
        let query = (args["query"] as? String).flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        }

        do {
            let text = try await KairoAgentBrowser.shared.load(url: url, maxChars: maxChars)
            guard !text.isEmpty else {
                return ToolResult(success: false, output: "Page loaded but had no readable text", tierUsed: .native)
            }
            let host = url.host ?? "page"
            let scoped = scope(text: text, around: query, maxChars: maxChars)
            let header = query == nil
                ? "BROWSED \(host) (\(text.count) chars):"
                : "BROWSED \(host) — section matching \"\(query!)\":"
            return ToolResult(success: true, output: "\(header)\n\n\(scoped)", tierUsed: .native)
        } catch {
            return ToolResult(success: false, output: "Browse failed: \(error.localizedDescription)", tierUsed: .native)
        }
    }

    /// If `query` is set, returns a maxChars-wide window centered on the
    /// first occurrence. Otherwise returns the prefix.
    private func scope(text: String, around query: String?, maxChars: Int) -> String {
        guard let query, !query.isEmpty else {
            return String(text.prefix(maxChars))
        }
        let lower = text.lowercased()
        guard let range = lower.range(of: query.lowercased()) else {
            return "[No match for \"\(query)\" in page]\n\n\(String(text.prefix(maxChars)))"
        }
        let half = maxChars / 2
        let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let from = max(0, matchStart - half)
        let to = min(text.count, matchStart + half)
        let startIdx = text.index(text.startIndex, offsetBy: from)
        let endIdx = text.index(text.startIndex, offsetBy: to)
        let ellipsisStart = from > 0 ? "…" : ""
        let ellipsisEnd = to < text.count ? "…" : ""
        return "\(ellipsisStart)\(text[startIdx..<endIdx])\(ellipsisEnd)"
    }
}
