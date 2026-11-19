//
//  NoteStyle.swift
//  boringNotch
//
//  Apparence des notes : attributs AppKit appliqués aux plages de NoteMarkdown.
//

import AppKit

/// Apparence des notes : corps 12 pt, interligne aéré, marques Markdown atténuées.
@MainActor
enum NoteStyle {
    static let body = NSFont.systemFont(ofSize: 12)
    static let text = NSColor.white.withAlphaComponent(0.92)
    static let faint = NSColor.white.withAlphaComponent(0.32)
    static let base: [NSAttributedString.Key: Any] = {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 2.5
        p.paragraphSpacing = 2
        return [.font: body, .foregroundColor: text, .paragraphStyle: p]
    }()

    static func apply(_ span: MarkSpan, to ts: NSTextStorage) {
        let r = span.range
        switch span.style {
        case .heading(let level):
            ts.addAttribute(.font, value: NSFont.systemFont(ofSize: [15.5, 13.5, 12.5][min(level, 3) - 1], weight: level == 1 ? .bold : .semibold), range: r)
            ts.addAttribute(.foregroundColor, value: NSColor.white, range: r)
        case .bold: addTrait(.boldFontMask, ts, r)
        case .italic: addTrait(.italicFontMask, ts, r)
        case .code:
            ts.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .backgroundColor: NSColor.white.withAlphaComponent(0.1),
            ], range: r)
        case .quote:
            ts.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.6), range: r)
            addTrait(.italicFontMask, ts, r)
        case .link(let url): ts.addAttribute(.link, value: url, range: r)
        case .marker: ts.addAttribute(.foregroundColor, value: faint, range: r)
        case .linkTarget: ts.addAttributes([.foregroundColor: faint, .font: NSFont.systemFont(ofSize: 9.5)], range: r)
        case .listMarker:
            ts.addAttributes([.foregroundColor: NSColor.effectiveAccent, .font: NSFont.systemFont(ofSize: 12, weight: .bold)], range: r)
        case .task(let done):
            ts.addAttributes([
                .foregroundColor: done ? NSColor.effectiveAccent : NSColor.white.withAlphaComponent(0.55),
                .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .bold),
                .cursor: NSCursor.pointingHand,
            ], range: r)
        case .done:
            ts.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.white.withAlphaComponent(0.4),
            ], range: r)
        }
    }

    private static func addTrait(_ trait: NSFontTraitMask, _ ts: NSTextStorage, _ r: NSRange) {
        ts.enumerateAttribute(.font, in: r) { value, sub, _ in
            let font = value as? NSFont ?? body
            ts.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: sub)
        }
    }
}
