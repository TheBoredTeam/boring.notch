import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Adapt response-only markup before handing the document to MarkdownUI.
struct CodexResponseDocument {
    let markdown: String
    let equations: [URL: CodexMathEquation]
    private(set) var annotationURLs: Set<URL> = []

    init(source: String) {
        let math = CodexMathDocument(source: source)
        equations = math.equations
        cmark_gfm_core_extensions_ensure_registered()
        let parser = cmark_parser_new(CMARK_OPT_DEFAULT)
        defer { cmark_parser_free(parser) }
        for name in ["autolink", "strikethrough", "tagfilter", "tasklist", "table"] {
            if let syntax = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, syntax)
            }
        }
        cmark_parser_feed(parser, math.markdown, math.markdown.utf8.count)
        guard let root = cmark_parser_finish(parser) else {
            markdown = math.markdown
            return
        }
        defer { cmark_node_free(root) }
        var annotations: Set<URL> = []
        let changed = Self.rewrite(root, equations: equations, annotations: &annotations)
        if changed, let rendered = cmark_render_commonmark(root, CMARK_OPT_DEFAULT, 0) {
            markdown = String(cString: rendered)
            free(rendered)
        } else {
            markdown = math.markdown
        }
        annotationURLs = annotations
    }

    private static let annotation = try! NSRegularExpression(
        pattern: #":codex-annotation\{index="([1-9][0-9]{0,8})"\}"#
    )

    private static func rewrite(
        _ node: UnsafeMutablePointer<cmark_node>, equations: [URL: CodexMathEquation], annotations: inout Set<URL>
    ) -> Bool {
        let type = cmark_node_get_type(node)
        // Examples, destinations, alt text and raw HTML are literal content.
        if [CMARK_NODE_CODE, CMARK_NODE_CODE_BLOCK, CMARK_NODE_LINK, CMARK_NODE_IMAGE,
            CMARK_NODE_HTML_BLOCK, CMARK_NODE_HTML_INLINE].contains(type) { return false }
        if type == CMARK_NODE_TEXT, let literal = cmark_node_get_literal(node) {
            let text = String(cString: literal) as NSString
            let matches = annotation.matches(in: text as String, range: NSRange(location: 0, length: text.length))
            guard !matches.isEmpty else { return false }
            var offset = 0
            for match in matches {
                insertText(text.substring(with: NSRange(location: offset, length: match.range.location - offset)), before: node)
                let index = text.substring(with: match.range(at: 1))
                let url = URL(string: "boringnotch-annotation://index/\(index)")!
                let link = cmark_node_new(CMARK_NODE_LINK)!
                cmark_node_set_url(link, url.absoluteString)
                cmark_node_set_title(link, "View annotation \(index) in Codex")
                let label = cmark_node_new(CMARK_NODE_TEXT)!
                cmark_node_set_literal(label, "Annotation \(index)")
                cmark_node_append_child(link, label)
                cmark_node_insert_before(node, link)
                annotations.insert(url)
                offset = NSMaxRange(match.range)
            }
            insertText(text.substring(from: offset), before: node)
            cmark_node_free(node)
            return true
        }

        var changed = false
        var child = cmark_node_first_child(node)
        while let current = child {
            child = cmark_node_next(current)
            if rewrite(current, equations: equations, annotations: &annotations) { changed = true }
        }
        let name = String(cString: cmark_node_get_type_string(node))
        guard type == CMARK_NODE_EMPH || type == CMARK_NODE_STRONG || name == "strikethrough" else { return changed }
        child = cmark_node_first_child(node)
        var hasEquation = false
        while let current = child {
            if isEquation(current, equations: equations) { hasEquation = true; break }
            child = cmark_node_next(current)
        }
        guard hasEquation else { return changed }

        // MarkdownUI's attributed-text path drops images nested in emphasis.
        // Split the wrapper around local equations, preserving styled prose on
        // either side and letting TeX itself control the equation's typography.
        var segment: UnsafeMutablePointer<cmark_node>?
        child = cmark_node_first_child(node)
        while let current = child {
            child = cmark_node_next(current)
            if isEquation(current, equations: equations) {
                if let segment { trimStyleBoundaries(segment) }
                cmark_node_insert_before(node, current)
                segment = nil
            } else {
                if segment == nil {
                    segment = cmark_node_new_with_ext(type, cmark_node_get_syntax_extension(node))!
                    cmark_node_insert_before(node, segment)
                }
                cmark_node_append_child(segment, current)
            }
        }
        if let segment { trimStyleBoundaries(segment) }
        cmark_node_free(node)
        return true
    }

    private static func isEquation(_ node: UnsafeMutablePointer<cmark_node>, equations: [URL: CodexMathEquation]) -> Bool {
        guard cmark_node_get_type(node) == CMARK_NODE_IMAGE,
              let rawURL = cmark_node_get_url(node), let url = URL(string: String(cString: rawURL)) else { return false }
        return equations[url] != nil
    }

    /// Markdown emphasis cannot open/close next to inner whitespace. Keep those
    /// spaces outside a split wrapper so reparsing cannot swallow the equation.
    private static func trimStyleBoundaries(_ node: UnsafeMutablePointer<cmark_node>) {
        if let first = cmark_node_first_child(node), cmark_node_get_type(first) == CMARK_NODE_TEXT,
           let raw = cmark_node_get_literal(first) {
            let text = String(cString: raw)
            let spaces = String(text.prefix(while: \.isWhitespace))
            insertText(spaces, before: node)
            let trimmed = String(text.dropFirst(spaces.count))
            if trimmed.isEmpty { cmark_node_free(first) } else { cmark_node_set_literal(first, trimmed) }
        }
        if let last = cmark_node_last_child(node), cmark_node_get_type(last) == CMARK_NODE_TEXT,
           let raw = cmark_node_get_literal(last) {
            let text = String(cString: raw)
            let spaces = String(text.reversed().prefix(while: \.isWhitespace).reversed())
            if !spaces.isEmpty {
                let content = cmark_node_new(CMARK_NODE_TEXT)!
                cmark_node_set_literal(content, spaces)
                cmark_node_insert_after(node, content)
                let trimmed = String(text.dropLast(spaces.count))
                if trimmed.isEmpty { cmark_node_free(last) } else { cmark_node_set_literal(last, trimmed) }
            }
        }
        if cmark_node_first_child(node) == nil { cmark_node_free(node) }
    }

    private static func insertText(_ text: String, before node: UnsafeMutablePointer<cmark_node>) {
        guard !text.isEmpty else { return }
        let content = cmark_node_new(CMARK_NODE_TEXT)!
        cmark_node_set_literal(content, text)
        cmark_node_insert_before(node, content)
    }
}
