import CryptoKit
import Foundation
import cmark_gfm

struct CodexMathEquation: Equatable, Sendable {
    let latex: String
    let isDisplay: Bool

    var url: URL {
        let data = Data(("\(isDisplay):" + latex).utf8)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return URL(string: "boringnotch-math://equation/\(digest)")!
    }
}

/// Protect math delimiters from CommonMark's escape processing, using its own AST
/// to leave code, links, images and raw HTML untouched.
struct CodexMathDocument {
    let markdown: String
    let equations: [URL: CodexMathEquation]

    init(source: String) {
        let protected = Self.protectedRanges(in: source)
        let text = source as NSString
        var result = source
        var equations: [URL: CodexMathEquation] = [:]
        for match in Self.math.matches(in: source, range: NSRange(location: 0, length: text.length)).reversed() {
            guard let range = Range(match.range, in: source) else { continue }
            let bytes = source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)..<source.utf8.distance(from: source.utf8.startIndex, to: range.upperBound)
            guard !protected.contains(where: { $0.overlaps(bytes) }) else { continue }
            guard let group = (1...4).first(where: { match.range(at: $0).location != NSNotFound }) else { continue }
            let equation = CodexMathEquation(
                latex: text.substring(with: match.range(at: group)),
                isDisplay: group == 1 || group == 3
            )
            equations[equation.url] = equation
            let replacement = "![Equation](\(equation.url.absoluteString))"
            result = (result as NSString).replacingCharacters(
                in: match.range,
                with: equation.isDisplay ? "\n\n\(replacement)\n\n" : replacement
            )
        }
        markdown = result
        self.equations = equations
    }

    // Paired \[...\], \(...\), $$...$$ and $...$. A dollar closer followed by
    // a digit is excluded so ordinary prices such as "$5 and $10" stay text.
    private static let math = try! NSRegularExpression(
        pattern: #"(?s)(?<!\\)\\\[(.*?)\\\]|(?<!\\)\\\((.*?)\\\)|(?<!\\)\$\$(.*?)\$\$|(?<![\\$])\$(?![\s$])((?:\\.|[^$\n])*?[^$\s])(?<!\\)\$(?![\d$])"#
    )

    private static func protectedRanges(in source: String) -> [Range<Int>] {
        let bytes = Array(source.utf8)
        guard let root = source.withCString({ cmark_parse_document($0, bytes.count, CMARK_OPT_DEFAULT) }) else { return [] }
        defer { cmark_node_free(root) }
        guard let iterator = cmark_iter_new(root) else { return [] }
        defer { cmark_iter_free(iterator) }
        var lineStarts = [0]
        for (index, byte) in bytes.enumerated() where byte == 10 { lineStarts.append(index + 1) }
        let protectedTypes = [CMARK_NODE_CODE, CMARK_NODE_CODE_BLOCK, CMARK_NODE_LINK, CMARK_NODE_IMAGE, CMARK_NODE_HTML_BLOCK, CMARK_NODE_HTML_INLINE]
        var ranges: [Range<Int>] = []
        while cmark_iter_next(iterator) != CMARK_EVENT_DONE {
            guard cmark_iter_get_event_type(iterator) == CMARK_EVENT_ENTER,
                  let node = cmark_iter_get_node(iterator),
                  protectedTypes.contains(cmark_node_get_type(node)) else { continue }
            let startLine = Int(cmark_node_get_start_line(node)) - 1
            let endLine = Int(cmark_node_get_end_line(node)) - 1
            guard lineStarts.indices.contains(startLine), lineStarts.indices.contains(endLine) else { continue }
            let start = min(bytes.count, lineStarts[startLine] + max(0, Int(cmark_node_get_start_column(node)) - 1))
            let end = min(bytes.count, lineStarts[endLine] + max(0, Int(cmark_node_get_end_column(node))))
            if start < end { ranges.append(start..<end) }
        }
        return ranges
    }
}
