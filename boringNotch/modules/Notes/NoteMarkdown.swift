//
//  NoteMarkdown.swift
//  boringNotch
//
//  Markdown léger des notes, sans AppKit : le texte reste brut sur disque, la vue le met en forme sur place
//  (les marques # ** ` restent visibles, atténuées). Plages en UTF-16 (NSString), comme NSTextStorage.
//

import Foundation

enum MarkStyle: Equatable {
    case heading(Int)       // # ## ###
    case bold, italic, code, quote
    case link(URL)
    case marker             // # ** ` > [ ] : atténués
    case linkTarget         // ](https://…) d'un lien Markdown : atténué et plus petit
    case listMarker         // - * 1. : en couleur d'accent
    case task(done: Bool)   // [ ] / [x] : cliquable
    case done               // texte d'une tâche cochée : barré, atténué
}

struct MarkSpan: Equatable {
    let range: NSRange
    let style: MarkStyle
}

enum NoteMarkdown {
    private static func rx(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.anchorsMatchLines])
    }
    private static let heading = rx(#"^(#{1,3})[ \t]+\S.*$"#)
    private static let quote = rx(#"^(>)[ \t]?.*$"#)
    private static let task = rx(#"^[ \t]*[-*+][ \t]+(\[([ xX])\])(?:[ \t]+(.*))?$"#)
    private static let list = rx(#"^[ \t]*([-*+]|\d+\.)[ \t]+"#)
    private static let code = rx(#"`[^`\n]+`"#)
    private static let bold = rx(#"\*\*[^*\n]+\*\*"#)
    private static let italic = rx(#"(?<![*\w])\*(?!\*)[^*\n]+?(?<!\*)\*(?![*\w])|(?<!\w)_[^_\n]+_(?!\w)"#)
    private static let mdLink = rx(#"\[([^\]\n]+)\]\((https?://[^)\s]+)\)"#)
    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    // ponytail: tout le texte est réanalysé à chaque frappe ; une note de l'encoche reste courte.
    static func spans(_ text: String) -> [MarkSpan] {
        let s = text as NSString
        let all = NSRange(location: 0, length: s.length)
        var out: [MarkSpan] = []
        func each(_ r: NSRegularExpression, _ f: (NSTextCheckingResult) -> Void) {
            r.enumerateMatches(in: text, range: all) { m, _, _ in if let m { f(m) } }
        }
        each(heading) { m in
            out.append(MarkSpan(range: m.range, style: .heading(m.range(at: 1).length)))
            out.append(MarkSpan(range: m.range(at: 1), style: .marker))
        }
        each(quote) { m in
            out.append(MarkSpan(range: m.range, style: .quote))
            out.append(MarkSpan(range: m.range(at: 1), style: .marker))
        }
        var taskLines: [NSRange] = []
        each(task) { m in
            taskLines.append(m.range)
            let done = s.substring(with: m.range(at: 2)) != " "
            out.append(MarkSpan(range: m.range(at: 1), style: .task(done: done)))
            if done, m.range(at: 3).location != NSNotFound { out.append(MarkSpan(range: m.range(at: 3), style: .done)) }
        }
        each(list) { m in
            out.append(MarkSpan(range: m.range(at: 1), style: .listMarker))
        }
        var codeRanges: [NSRange] = []
        each(code) { m in
            codeRanges.append(m.range)
            out.append(MarkSpan(range: m.range, style: .code))
            out.append(MarkSpan(range: NSRange(location: m.range.location, length: 1), style: .marker))
            out.append(MarkSpan(range: NSRange(location: NSMaxRange(m.range) - 1, length: 1), style: .marker))
        }
        func inCode(_ r: NSRange) -> Bool { codeRanges.contains { NSIntersectionRange($0, r).length > 0 } }
        each(bold) { m in
            guard !inCode(m.range) else { return }
            out.append(MarkSpan(range: m.range, style: .bold))
            out.append(MarkSpan(range: NSRange(location: m.range.location, length: 2), style: .marker))
            out.append(MarkSpan(range: NSRange(location: NSMaxRange(m.range) - 2, length: 2), style: .marker))
        }
        each(italic) { m in
            guard !inCode(m.range) else { return }
            out.append(MarkSpan(range: m.range, style: .italic))
            out.append(MarkSpan(range: NSRange(location: m.range.location, length: 1), style: .marker))
            out.append(MarkSpan(range: NSRange(location: NSMaxRange(m.range) - 1, length: 1), style: .marker))
        }
        var linkRanges: [NSRange] = []
        each(mdLink) { m in
            guard let url = URL(string: s.substring(with: m.range(at: 2))) else { return }
            linkRanges.append(m.range)
            let label = m.range(at: 1)
            out.append(MarkSpan(range: label, style: .link(url)))
            out.append(MarkSpan(range: NSRange(location: m.range.location, length: 1), style: .marker))
            out.append(MarkSpan(range: NSRange(location: NSMaxRange(label), length: NSMaxRange(m.range) - NSMaxRange(label)), style: .linkTarget))
        }
        detector.enumerateMatches(in: text, range: all) { m, _, _ in
            guard let m, let url = m.url, !inCode(m.range),
                  !linkRanges.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) else { return }
            out.append(MarkSpan(range: m.range, style: .link(url)))
        }
        return out
    }

    /// Clic à l'index `i` : s'il tombe sur une case « [ ] » / « [x] », renvoie la plage à remplacer et son nouveau texte.
    static func taskToggle(in text: String, at i: Int) -> (range: NSRange, replacement: String)? {
        let s = text as NSString
        var hit: (NSRange, String)?
        task.enumerateMatches(in: text, range: NSRange(location: 0, length: s.length)) { m, _, stop in
            guard let m else { return }
            let box = m.range(at: 1)
            // Un peu de tolérance : le clic juste avant ou juste après la case compte.
            guard i >= box.location - 1, i <= NSMaxRange(box) else { return }
            hit = (box, s.substring(with: m.range(at: 2)) == " " ? "[x]" : "[ ]")
            stop.pointee = true
        }
        return hit
    }

    /// Entrée en fin de ligne de liste : le préfixe à insérer sur la nouvelle ligne (`- `, `- [ ] `, `3. `),
    /// ou `endList` si la ligne n'est qu'une puce vide (on retire alors la puce au lieu d'en ajouter une).
    enum Continuation: Equatable { case prefix(String), endList }

    static func continuation(forLine line: String) -> Continuation? {
        let ns = line as NSString
        let r = NSRange(location: 0, length: ns.length)
        let taskPrefix = rx(#"^([ \t]*[-*+][ \t]+)\[[ xX]\][ \t]*"#)
        let listPrefix = rx(#"^([ \t]*)([-*+]|(\d+)\.)[ \t]+"#)
        if let m = taskPrefix.firstMatch(in: line, range: r) {
            return m.range.length == ns.length ? .endList : .prefix(ns.substring(with: m.range(at: 1)) + "[ ] ")
        }
        if let m = listPrefix.firstMatch(in: line, range: r) {
            if m.range.length == ns.length { return .endList }
            let indent = ns.substring(with: m.range(at: 1))
            if m.range(at: 3).location != NSNotFound, let n = Int(ns.substring(with: m.range(at: 3))) {
                return .prefix("\(indent)\(n + 1). ")
            }
            return .prefix("\(indent)\(ns.substring(with: m.range(at: 2))) ")
        }
        return nil
    }
}
