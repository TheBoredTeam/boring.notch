//
//  PiMarkdownView.swift
//  boringNotch
//
//  Lightweight streaming-markdown renderer for Pi answers. The sidecar streams the
//  agent's raw markdown token-by-token, so the expanded tab can't just show plain
//  Text — headings, lists, fenced code, and (crucially) connection links all need to
//  render. Block-level: headings, fenced code, bullet/ordered lists, blockquotes,
//  paragraphs. Inline: bold, italic, inline code, explicit [links](url) AND
//  auto-linked bare URLs — so a Composio connection link is tappable without
//  copy/paste. Re-parses cheaply on each delta (transcripts are short).
//

import SwiftUI

struct PiMarkdownView: View {
    let text: String
    var accent: Color = .effectiveAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(MDBlock.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(accent)
        .textSelection(.enabled)
    }

    // MARK: Block → View

    @ViewBuilder
    private func view(for block: MDBlock) -> some View {
        switch block {
        case let .heading(level, content):
            Text(Self.inline(content, accent: accent))
                .font(.system(size: headingSize(level), weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                // Extra air above the top-level headings so sections read as sections,
                // not just slightly-bigger lines. (The VStack's 7pt handles the rest.)
                .padding(.top, level <= 2 ? 3 : 0)

        case let .paragraph(content):
            Text(Self.inline(content, accent: accent))
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

        case let .list(items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(item.ordered.map { "\($0)." } ?? "•")
                            .font(.system(size: 12, weight: item.ordered == nil ? .bold : .regular))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: item.ordered == nil ? 9 : 16, alignment: .leading)
                            .monospacedDigit()
                        Text(Self.inline(item.text, accent: accent))
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case let .code(code):
            Text(code)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )

        case let .quote(content):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(accent.opacity(0.6))
                    .frame(width: 2.5)
                Text(Self.inline(content, accent: accent))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 16
        case 2: return 14.5
        case 3: return 13.5
        default: return 12.5
        }
    }

    // MARK: Inline styling

    /// Parse a single line's inline markdown (bold/italic/code/links) into a styled
    /// AttributedString, then auto-link any bare URLs the markdown parser left plain.
    static func inline(_ source: String, accent: Color) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        var attr = (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)

        autolink(&attr)

        // Style links and inline-code runs. Collect ranges first so we don't mutate
        // while iterating runs.
        var linkRanges: [Range<AttributedString.Index>] = []
        var codeRanges: [Range<AttributedString.Index>] = []
        for run in attr.runs {
            if run.link != nil { linkRanges.append(run.range) }
            if run.inlinePresentationIntent?.contains(.code) == true { codeRanges.append(run.range) }
        }
        for range in linkRanges {
            attr[range].foregroundColor = accent
            attr[range].underlineStyle = .single
        }
        for range in codeRanges {
            attr[range].font = .system(size: 11.5, design: .monospaced)
            attr[range].backgroundColor = Color.white.opacity(0.10)
        }
        return attr
    }

    /// Attach `.link` to bare URLs (https://…, www.…) that the markdown parser left
    /// as plain text. Skips spans that already carry a link (explicit `[…](…)`).
    private static func autolink(_ attr: inout AttributedString) {
        let text = String(attr.characters)
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return }
        let full = NSRange(location: 0, length: (text as NSString).length)
        for match in detector.matches(in: text, range: full) {
            guard let url = match.url, let r = Range(match.range, in: text) else { continue }
            let lower = text.distance(from: text.startIndex, to: r.lowerBound)
            let length = text.distance(from: r.lowerBound, to: r.upperBound)
            let start = attr.index(attr.startIndex, offsetByCharacters: lower)
            let end = attr.index(start, offsetByCharacters: length)
            if attr[start..<end].link == nil {
                attr[start..<end].link = url
            }
        }
    }
}

// MARK: - Inline-only renderer

/// Lightweight single-`Text` renderer for streaming or block-free prose. Joins the
/// transcript's lines into one paragraph and runs them through `PiMarkdownView.inline`
/// — so bold/italic/inline-code and autolinked bare URLs stay styled and tappable —
/// without the block layout that reflows mid-stream. The answer view uses this while
/// `pi.isRunning` or when a settled transcript has no block structure.
struct PiInlineText: View {
    let text: String
    var accent: Color = .effectiveAccent

    var body: some View {
        Text(PiMarkdownView.inline(structuredText, accent: accent))
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .tint(accent)
    }

    /// The streamed text with line breaks PRESERVED — only each line's trailing
    /// whitespace is trimmed and runs of blank lines collapsed to one. Previously every
    /// newline was flattened to a space, which turned a multi-paragraph answer into one
    /// run-on wall that read as cut off / wrong-sized while streaming. Inline markdown is
    /// parsed with `.inlineOnlyPreservingWhitespace`, so the newlines render as real line
    /// breaks without the per-delta block re-parse that streaming must avoid.
    private var structuredText: String {
        var out: [String] = []
        var lastBlank = false
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let blank = line.isEmpty
            if blank && lastBlank { continue }
            out.append(line)
            lastBlank = blank
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Block model + parser

enum MDBlock {
    case heading(Int, String)
    case paragraph(String)
    case list([Item])
    case code(String)
    case quote(String)

    struct Item {
        let ordered: Int?   // nil → bullet, otherwise the rendered number
        let text: String
    }

    /// Split raw markdown into block elements. Deliberately small: this handles the
    /// shapes an agent actually emits (headings, bullets, fenced code, quotes,
    /// paragraphs) and leaves inline parsing to AttributedString.
    static func parse(_ raw: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        let lines = raw.components(separatedBy: "\n")
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block.
            if trimmed.hasPrefix("```") {
                flushParagraph()
                var code: [String] = []
                i += 1
                while i < lines.count,
                      !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                i += 1 // consume closing fence (if present)
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            // Heading.
            if let heading = headingMatch(trimmed) {
                flushParagraph()
                blocks.append(.heading(heading.level, heading.text))
                i += 1
                continue
            }

            // Blockquote (consume the run of `>` lines).
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    quote.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(quote.joined(separator: " ")))
                continue
            }

            // List (consume the run of list items).
            if listItem(trimmed) != nil {
                flushParagraph()
                var items: [Item] = []
                while i < lines.count,
                      let item = listItem(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    i += 1
                }
                blocks.append(.list(items))
                continue
            }

            // Blank line ends a paragraph.
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            paragraph.append(trimmed)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    /// True if `raw` contains any block-level markdown — a `#` heading, ```` ``` ````
    /// fence, `>` quote, list marker, or `|` table row. Used by the answer view to
    /// decide between the lightweight inline `Text` (plain prose / mid-stream) and the
    /// full block renderer (settled + structured). O(lines) with an early return on
    /// the first block marker; only runs while settled, never per streamed delta.
    static func hasBlockStructure(_ raw: String) -> Bool {
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("```") { return true }
            if trimmed.hasPrefix(">") { return true }
            if trimmed.hasPrefix("|") { return true }
            if headingMatch(trimmed) != nil { return true }
            if listItem(trimmed) != nil { return true }
        }
        return false
    }

    private static func headingMatch(_ line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#", level < 6 {
            level += 1
            idx = line.index(after: idx)
        }
        guard idx < line.endIndex, line[idx] == " " else { return nil }
        let text = String(line[idx...]).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func listItem(_ line: String) -> Item? {
        // Bullet: -, *, + followed by a space.
        if let first = line.first, "-*+".contains(first),
           line.dropFirst().first == " " {
            return Item(ordered: nil, text: String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }
        // Ordered: `1.` / `1)` followed by a space.
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty {
            let after = line[digits.endIndex...]
            if let sep = after.first, sep == "." || sep == ")",
               after.dropFirst().first == " " {
                let text = String(after.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return Item(ordered: Int(digits), text: text)
            }
        }
        return nil
    }
}
