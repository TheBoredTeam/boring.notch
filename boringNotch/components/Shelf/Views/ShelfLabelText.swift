//
//  ShelfLabelText.swift
//  boringNotch
//
//  Created by Codex on 2025-10-11.
//

import AppKit
import SwiftUI

struct ShelfLabelText: View {
    let text: String
    let fontSize: CGFloat
    let lineLimit: Int
    let textColor: NSColor
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    private var displayText: String {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let lines = ShelfLabelFormatter.lines(
            text: text,
            font: font,
            maxWidth: maxWidth,
            maxLines: max(1, lineLimit)
        )
        return lines.joined(separator: "\n")
    }

    var body: some View {
        Text(displayText)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(Color(nsColor: textColor))
            .multilineTextAlignment(.center)
            .frame(width: maxWidth, height: maxHeight, alignment: .top)
    }
}

private enum ShelfLabelFormatter {
    static func lines(text: String, font: NSFont, maxWidth: CGFloat, maxLines: Int) -> [String] {
        guard maxLines > 0 else { return [] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [""] }

        if maxLines == 1 {
            return [truncate(trimmed, font: font, maxWidth: maxWidth)]
        }

        let first = splitLine(text: trimmed, font: font, maxWidth: maxWidth)
        let remainder = trimmed.dropFirst(first.count).trimmingCharacters(in: .whitespacesAndNewlines)
        if remainder.isEmpty {
            return [first]
        }

        let second = truncate(String(remainder), font: font, maxWidth: maxWidth)
        return [first, second]
    }

    private static func splitLine(text: String, font: NSFont, maxWidth: CGFloat) -> String {
        var bestFitIndex: String.Index?
        var bestBreakIndex: String.Index?
        let separators: Set<Character> = [" ", ".", "-", "_"]

        var index = text.startIndex
        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            let prefix = String(text[..<nextIndex])
            if width(of: prefix, font: font) <= maxWidth {
                bestFitIndex = nextIndex
                let ch = text[index]
                if separators.contains(ch) {
                    bestBreakIndex = nextIndex
                }
            } else {
                break
            }
            index = nextIndex
        }

        if let breakIndex = bestBreakIndex {
            return String(text[..<breakIndex])
        }
        if let fitIndex = bestFitIndex {
            return String(text[..<fitIndex])
        }
        return truncate(text, font: font, maxWidth: maxWidth)
    }

    private static func truncate(_ text: String, font: NSFont, maxWidth: CGFloat) -> String {
        if width(of: text, font: font) <= maxWidth {
            return text
        }
        let ellipsis = "…"
        let ellipsisWidth = width(of: ellipsis, font: font)
        var bestIndex: String.Index?

        var index = text.startIndex
        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            let prefix = String(text[..<nextIndex])
            if width(of: prefix, font: font) + ellipsisWidth <= maxWidth {
                bestIndex = nextIndex
            } else {
                break
            }
            index = nextIndex
        }

        if let bestIndex = bestIndex {
            return String(text[..<bestIndex]) + ellipsis
        }
        return ellipsis
    }

    private static func width(of text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

extension NSFont {
    var shelfLineHeight: CGFloat {
        ascender - descender + leading
    }
}
