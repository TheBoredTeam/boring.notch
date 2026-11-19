//
//  NoteStyle.swift
//  boringNotch
//
//  Apparence des notes : attributs AppKit appliqués aux plages de NoteMarkdown, plus quelques décorations
//  dessinées par-dessus (cases, puces rondes, barre de citation, fond du code). Le texte, lui, ne change jamais.
//

import AppKit

extension NSAttributedString.Key {
    /// Décoration à dessiner sur la plage : voir `NoteStyle.Decor`.
    static let noteDecor = NSAttributedString.Key("boringNotch.noteDecor")
}

@MainActor
enum NoteStyle {
    enum Decor: String { case bullet, box, boxDone, quote, code }

    static let body = NSFont.systemFont(ofSize: 12)
    static let text = NSColor.white.withAlphaComponent(0.9)
    static let faint = NSColor.white.withAlphaComponent(0.32)
    static let lineSpacing: CGFloat = 3
    private static let clear = NSColor.clear

    static let base: [NSAttributedString.Key: Any] = [.font: body, .foregroundColor: text, .paragraphStyle: paragraph(before: 0)]

    private static func paragraph(before: CGFloat) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        p.paragraphSpacing = 2
        p.paragraphSpacingBefore = before
        return p
    }

    /// `reveal` : la plage est sur la ligne du curseur, ses marques (# ** `) sont un peu plus visibles.
    static func apply(_ span: MarkSpan, to ts: NSTextStorage, reveal: Bool) {
        let r = span.range
        let mark = NSColor.white.withAlphaComponent(reveal ? 0.4 : 0.15)
        switch span.style {
        case .heading(let level):
            ts.addAttributes([
                .font: NSFont.systemFont(ofSize: [16, 13.5, 12.5][min(level, 3) - 1], weight: level == 1 ? .bold : .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph(before: level == 1 ? 5 : 3),
            ], range: r)
        case .bold: addTrait(.boldFontMask, ts, r); ts.addAttribute(.foregroundColor, value: NSColor.white, range: r)
        case .italic: addTrait(.italicFontMask, ts, r)
        case .code:
            ts.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor(calibratedRed: 1, green: 0.78, blue: 0.62, alpha: 1),
                .noteDecor: Decor.code.rawValue,
            ], range: r)
        case .quote:
            ts.addAttributes([.foregroundColor: NSColor.white.withAlphaComponent(0.62), .noteDecor: Decor.quote.rawValue], range: r)
            addTrait(.italicFontMask, ts, r)
        case .link(let url): ts.addAttribute(.link, value: url, range: r)
        case .marker:
            // « > » d'une citation : remplacé par la barre dessinée.
            let isQuote = ts.attribute(.noteDecor, at: r.location, effectiveRange: nil) as? String == Decor.quote.rawValue
            ts.addAttribute(.foregroundColor, value: isQuote ? clear : mark, range: r)
        case .linkTarget: ts.addAttributes([.foregroundColor: mark, .font: NSFont.systemFont(ofSize: 9.5)], range: r)
        case .listMarker:
            let symbol = (ts.string as NSString).substring(with: r)
            if symbol.first?.isNumber == true {
                ts.addAttributes([.foregroundColor: NSColor.effectiveAccent, .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)], range: r)
            } else {
                ts.addAttributes([.foregroundColor: clear, .kern: 3.5, .noteDecor: Decor.bullet.rawValue], range: r)
            }
        case .hidden: ts.addAttributes([.foregroundColor: clear, .font: NSFont.systemFont(ofSize: 0.5)], range: r)
        case .task(let done):
            ts.addAttributes([
                .foregroundColor: clear,
                .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular),
                .cursor: NSCursor.pointingHand,
                .noteDecor: (done ? Decor.boxDone : Decor.box).rawValue,
            ], range: r)
        case .done:
            ts.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: NSColor.white.withAlphaComponent(0.3),
                .foregroundColor: NSColor.white.withAlphaComponent(0.38),
            ], range: r)
        }
    }

    /// Dessine les décorations sous le texte (appelé avant `super.draw`).
    static func drawDecorations(in tv: NSTextView) {
        guard let lm = tv.layoutManager, let tc = tv.textContainer, let ts = tv.textStorage else { return }
        let origin = tv.textContainerOrigin
        let accent = NSColor.effectiveAccent
        ts.enumerateAttribute(.noteDecor, in: NSRange(location: 0, length: ts.length)) { value, r, _ in
            guard let raw = value as? String, let decor = Decor(rawValue: raw) else { return }
            let glyphs = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: glyphs, in: tc).offsetBy(dx: origin.x, dy: origin.y)
            rect.size.height -= lineSpacing   // l'interligne est sous le texte
            switch decor {
            case .code:
                NSColor.white.withAlphaComponent(0.08).setFill()
                lm.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { r, _ in
                    var box = r.offsetBy(dx: origin.x, dy: origin.y)
                    box.size.height -= lineSpacing
                    NSBezierPath(roundedRect: box.insetBy(dx: -2, dy: 0.5), xRadius: 4, yRadius: 4).fill()
                }
            case .quote:
                accent.withAlphaComponent(0.75).setFill()
                NSBezierPath(roundedRect: NSRect(x: rect.minX + 1, y: rect.minY + 1, width: 2.5, height: rect.height - 2), xRadius: 1.25, yRadius: 1.25).fill()
            case .bullet:
                accent.setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.midX - 2.25, y: rect.midY - 2.25, width: 4.5, height: 4.5)).fill()
            case .box, .boxDone:
                let side: CGFloat = 11.5
                let square = NSRect(x: rect.minX + 1, y: rect.midY - side / 2, width: side, height: side)
                let path = NSBezierPath(roundedRect: square, xRadius: 3.5, yRadius: 3.5)
                if decor == .boxDone {
                    accent.setFill(); path.fill()
                    let check = NSBezierPath()
                    check.move(to: NSPoint(x: square.minX + 3, y: square.midY + 0.2))
                    check.line(to: NSPoint(x: square.minX + 5, y: square.maxY - 3))   // vue retournée : y croît vers le bas
                    check.line(to: NSPoint(x: square.maxX - 2.8, y: square.minY + 3.2))
                    check.lineWidth = 1.7
                    check.lineCapStyle = .round
                    check.lineJoinStyle = .round
                    NSColor.black.withAlphaComponent(0.85).setStroke(); check.stroke()
                } else {
                    NSColor.white.withAlphaComponent(0.45).setStroke()
                    let inner = NSBezierPath(roundedRect: square.insetBy(dx: 0.6, dy: 0.6), xRadius: 3.2, yRadius: 3.2)
                    inner.lineWidth = 1.2
                    inner.stroke()
                }
            }
        }
    }

    private static func addTrait(_ trait: NSFontTraitMask, _ ts: NSTextStorage, _ r: NSRange) {
        ts.enumerateAttribute(.font, in: r) { value, sub, _ in
            let font = value as? NSFont ?? body
            ts.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: sub)
        }
    }
}
