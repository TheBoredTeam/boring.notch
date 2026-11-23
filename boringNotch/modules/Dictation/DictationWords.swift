//
//  DictationWords.swift
//  boringNotch
//
//  Logique pure du dictionnaire de dictée : substitutions « avant => après » et mots à graphie fixe.
//  Foundation seulement (testé par scripts/dictation-selftest).
//

import Foundation

enum DictationWords {
    /// Une règle par ligne `avant => après`. Doublon de `avant` : le premier gagne. Triées du plus long au plus court
    /// (« boring notch » doit passer avant « notch »).
    static func rules(_ raw: String) -> [(from: String, to: String)] {
        var seen = Set<String>()
        var out: [(from: String, to: String)] = []
        for line in raw.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let from = parts[0].trimmingCharacters(in: .whitespaces)
            let to = parts[1].trimmingCharacters(in: .whitespaces)
            guard !from.isEmpty, seen.insert(from.lowercased()).inserted else { continue }
            out.append((from, to))
        }
        // ponytail: tri explicitement stable (index en départage), sort() ne le garantit pas.
        return out.enumerated().sorted { ($0.element.from.count, $1.offset) > ($1.element.from.count, $0.offset) }.map(\.element)
    }

    /// Applique les règles dans l'ordre reçu : mot entier, insensible à la casse, cible insérée telle quelle.
    static func substitute(_ text: String, rules: [(from: String, to: String)]) -> String {
        rules.reduce(text) { replace($0, $1.from, with: $1.to) }
    }

    /// Dictionnaire : un mot ou une expression par ligne (les lignes de règle `=>` n'en font pas partie).
    static func words(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("=>") && seen.insert($0.lowercased()).inserted }
    }

    /// Chaque occurrence d'un mot du dictionnaire prend sa graphie exacte. Un seul passage, les plus longs d'abord :
    /// « notch » ne doit pas défaire la casse de « Boring Notch ».
    static func fixCase(_ text: String, words: [String]) -> String {
        let sorted = words.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        guard !sorted.isEmpty else { return text }
        var exact: [String: String] = [:]
        for w in sorted where exact[w.lowercased()] == nil { exact[w.lowercased()] = w }
        let alt = sorted.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        guard let re = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])(?:" + alt + ")(?![\\p{L}\\p{N}])", options: .caseInsensitive) else { return text }
        var out = text
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let r = Range(m.range, in: out), let w = exact[out[r].lowercased()] else { continue }
            out.replaceSubrange(r, with: w)
        }
        return out
    }

    /// Ce qu'on donne à la reconnaissance et au modèle : le dictionnaire, puis les cibles des règles.
    // ponytail: 100 premiers, au-delà la reconnaissance se dilue.
    static func vocabulary(words: [String], rules: [(from: String, to: String)]) -> [String] {
        var seen = Set<String>()
        return Array((words + rules.map(\.to)).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(100))
    }

    /// Correction qui ne change que la casse (« synolia » → « Synolia ») : ce n'est pas une substitution à apprendre.
    static func isCaseOnly(_ a: String, _ b: String) -> Bool {
        let trim = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let x = a.trimmingCharacters(in: trim), y = b.trimmingCharacters(in: trim)
        return x != y && x.lowercased() == y.lowercased()
    }

    private static func replace(_ text: String, _ from: String, with to: String) -> String {
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: from) + "(?![\\p{L}\\p{N}])"
        return text.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: to),
                                         options: [.regularExpression, .caseInsensitive])
    }
}
