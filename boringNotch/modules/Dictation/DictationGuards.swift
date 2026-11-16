//
//  DictationGuards.swift
//  boringNotch
//
//  Garde-fous contre le texte inventé : vocabulaire récité (sur un blanc, ou recopié depuis la consigne du modèle),
//  mots ajoutés par la correction, prise muette. Foundation seul : vérifié par scripts/dictation-selftest.
//

import Foundation

enum DictationGuards {
    /// En dessous, la prise est muette : rien n'est collé (même seuil que Hex : −50 dBFS).
    // ponytail: seuil en dur ; un réglage si un micro faible est jeté.
    static let silenceRMS: Float = 0.00316

    /// Part des mots de 4 lettres ou plus de `input` encore présents dans `output` (comparaison sur les 4 premières lettres,
    /// sans accents ni casse : un accord corrigé ne compte pas comme un mot perdu, un mot supprimé oui).
    static func retained(_ output: String, of input: String) -> Double {
        func stems(_ s: String) -> [String] {
            fold(s).split { !$0.isLetter && !$0.isNumber }.filter { $0.count >= 4 }.map { String($0.prefix(4)) }
        }
        let src = stems(input)
        guard !src.isEmpty else { return 1 }
        let out = Set(stems(output))
        return Double(src.filter(out.contains).count) / Double(src.count)
    }

    /// Retire chaque ligne qui ne fait que réciter le vocabulaire : au moins 2 occurrences de termes,
    /// couvrant au moins la moitié des mots de la ligne. Une vraie phrase qui cite deux noms est gardée.
    // ponytail: par ligne ; une liste récitée sur la même ligne qu'une vraie phrase reste.
    static func dropRecitation(_ text: String, vocabulary: [String]) -> String {
        guard !vocabulary.isEmpty else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            let words = words(String(line)).count
            let hits = vocabulary.map { (count: occurrences(of: $0, in: String(line)), size: self.words($0).count) }
            let n = hits.reduce(0) { $0 + $1.count }
            let covered = hits.reduce(0) { $0 + $1.count * $1.size }
            return !(n >= 2 && covered * 2 >= words)
        }.joined(separator: "\n")
    }

    /// Un terme du vocabulaire apparaît dans la sortie sans avoir été dit : le modèle l'a ajouté.
    static func addsVocabulary(_ output: String, to input: String, vocabulary: [String]) -> Bool {
        vocabulary.contains { occurrences(of: $0, in: output) > occurrences(of: $0, in: input) }
    }

    private static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    private static func words(_ s: String) -> [Substring] { s.split { !$0.isLetter && !$0.isNumber } }

    /// Occurrences du terme en mot entier, sans casse ni accents.
    private static func occurrences(of term: String, in text: String) -> Int {
        let t = fold(term).trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let re = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: t) + "(?![\\p{L}\\p{N}])") else { return 0 }
        let s = fold(text)
        return re.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s))
    }
}
