import Foundation

/// Fetches a webpage and returns the cleaned plain-text content, capped at
/// ~6KB to keep within the LLM's context budget. Strips scripts, styles,
/// and markup; collapses whitespace.
///
/// Args:
///   url:      String — the URL to fetch
///   query:    String — optional substring; if present, returns the section
///             surrounding the first occurrence + a short summary header
///   max:      Int — optional override on max returned chars (default 6000)
///
/// Used by the ReAct loop for "read this page and answer X" flows:
///   THOUGHT: I should check this restaurant's menu.
///   [CALL] {"tool": "web_read", "args": {"url": "https://...", "query": "vegan"}}
///   [OBSERVATION] ok: ...page content with vegan section...
///
struct WebReadTool: Tool {
    let name = "web_read"
    let description = "Fetches a webpage and returns its plain-text content"
    let permissionTier: PermissionTier = .safe
    let supportedTiers: [ExecutionTier] = [.native]

    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult {
        let urlString = (args["url"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            return ToolResult(success: false, output: "Missing or invalid 'url'", tierUsed: .native)
        }
        let query = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let maxChars = (args["max"] as? Int) ?? 6000

        var req = URLRequest(url: url)
        req.setValue("Kairo/1.0 (compatible; +https://kairo.app)", forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            return ToolResult(success: false, output: "Fetch failed: \(error.localizedDescription)", tierUsed: .native)
        }

        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            return ToolResult(success: false, output: "HTTP \(http.statusCode) from \(url.host ?? "host")", tierUsed: .native)
        }

        // Decode (HTML usually utf-8; fall back to ISO Latin-1)
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""

        let cleaned = Self.stripHTML(html)
        guard !cleaned.isEmpty else {
            return ToolResult(success: false, output: "Page has no readable text", tierUsed: .native)
        }

        let host = url.host ?? "page"
        let scoped = Self.scoped(text: cleaned, around: query, maxChars: maxChars)
        let header = query.isEmpty
            ? "FROM \(host) (\(cleaned.count) chars total):"
            : "FROM \(host) — section matching \"\(query)\" (\(cleaned.count) chars total):"
        return ToolResult(success: true, output: "\(header)\n\n\(scoped)", tierUsed: .native)
    }

    // MARK: - HTML stripping
    //
    // Not a real parser — we don't ship SwiftSoup. Good enough for getting
    // body text out of typical content pages. The strategy:
    //   1. Drop <script>, <style>, <noscript>, <svg>, <head> blocks entirely
    //   2. Replace block-ish tags with newlines
    //   3. Strip remaining tags
    //   4. Decode common HTML entities
    //   5. Collapse whitespace

    static func stripHTML(_ raw: String) -> String {
        var text = raw

        // 1. Drop entire <script>/<style>/<head>/<svg>/<noscript> blocks
        for tag in ["script", "style", "head", "svg", "noscript"] {
            let pattern = "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
            }
        }

        // 2. Block tags → newlines
        let blockTags = ["br", "p", "div", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "section", "article"]
        for tag in blockTags {
            let pattern = "</?\(tag)\\b[^>]*>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "\n")
            }
        }

        // 3. Strip any remaining tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }

        // 4. Decode common HTML entities (cheap; not exhaustive)
        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&hellip;", "…"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&rsquo;", "'"),
            ("&lsquo;", "'"),
            ("&ldquo;", "\""),
            ("&rdquo;", "\"")
        ]
        for (e, r) in entities { text = text.replacingOccurrences(of: e, with: r) }

        // Numeric entities (&#1234; / &#xABCD;)
        if let regex = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);", options: []) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            var result = ""
            var cursor = 0
            for m in matches {
                let pre = nsText.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                result += pre
                let codeStr = nsText.substring(with: m.range(at: 1))
                let scalar: UInt32?
                if codeStr.lowercased().hasPrefix("x") {
                    scalar = UInt32(codeStr.dropFirst(), radix: 16)
                } else {
                    scalar = UInt32(codeStr, radix: 10)
                }
                if let s = scalar, let u = Unicode.Scalar(s) {
                    result.append(Character(u))
                } else {
                    result += nsText.substring(with: m.range)
                }
                cursor = m.range.location + m.range.length
            }
            result += nsText.substring(with: NSRange(location: cursor, length: nsText.length - cursor))
            text = result
        }

        // 5. Collapse whitespace
        text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // Collapse spaces/tabs
        if let regex = try? NSRegularExpression(pattern: "[ \\t]+", options: []) {
            let r = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: r, withTemplate: " ")
        }
        // Collapse blank lines
        if let regex = try? NSRegularExpression(pattern: "\\n{3,}", options: []) {
            let r = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: r, withTemplate: "\n\n")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns either the whole text (capped at maxChars), or — if `query`
    /// is non-empty and present — a ~maxChars window centered on the first
    /// match.
    static func scoped(text: String, around query: String, maxChars: Int) -> String {
        guard !query.isEmpty else {
            return String(text.prefix(maxChars))
        }
        let lower = text.lowercased()
        guard let range = lower.range(of: query.lowercased()) else {
            // No match — return the head plus a hint
            return "[No match for \"\(query)\" in page text]\n\n\(String(text.prefix(maxChars)))"
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
