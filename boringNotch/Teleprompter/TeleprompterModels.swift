//
//  TeleprompterModels.swift
//  boringNotch
//
//  Teleprompter data model: tokenizes a script into words and readable
//  "chunks" (lines). Words are what we highlight as they're spoken; chunks
//  are what we scroll between.
//

import Foundation

/// A single word of the script.
///
/// `display` keeps the original spelling and punctuation so the text reads
/// naturally; `normalized` is a lowercased, punctuation-stripped form used to
/// match against speech-recognition output.
struct ScriptWord: Identifiable, Equatable {
    let id: Int          // global index within the script
    let display: String
    let normalized: String

    var globalIndex: Int { id }
}

/// A group of consecutive words rendered together as one line.
struct ScriptChunk: Identifiable, Equatable {
    let id: Int
    let words: [ScriptWord]

    var startIndex: Int { words.first?.globalIndex ?? 0 }
    /// Exclusive end index.
    var endIndex: Int { (words.last?.globalIndex ?? -1) + 1 }

    func contains(_ wordIndex: Int) -> Bool {
        wordIndex >= startIndex && wordIndex < endIndex
    }
}

enum TeleprompterTokenizer {
    /// Lowercase and strip everything that isn't a letter or number.
    /// Returns "" for pure punctuation, which callers skip.
    static func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let scalars = lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Split raw text into words, preserving spelling for display.
    static func words(from text: String) -> [ScriptWord] {
        var result: [ScriptWord] = []
        var index = 0
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let display = String(token)
            let normalized = normalize(display)
            guard !normalized.isEmpty else { continue }
            result.append(ScriptWord(id: index, display: display, normalized: normalized))
            index += 1
        }
        return result
    }

    /// Group words into readable lines of roughly `maxWords`, breaking early
    /// on sentence-ending punctuation so lines end at natural pauses.
    static func chunks(from words: [ScriptWord], maxWords: Int = 12) -> [ScriptChunk] {
        var chunks: [ScriptChunk] = []
        var current: [ScriptWord] = []
        var chunkID = 0

        func flush() {
            guard !current.isEmpty else { return }
            chunks.append(ScriptChunk(id: chunkID, words: current))
            chunkID += 1
            current = []
        }

        for word in words {
            current.append(word)
            let endsSentence = word.display.last.map { ".!?".contains($0) } ?? false
            if current.count >= maxWords || (endsSentence && current.count >= 4) {
                flush()
            }
        }
        flush()
        return chunks
    }
}

/// Default script shown the first time the teleprompter is opened.
enum TeleprompterSampleScript {
    static let text = """
    Welcome to your notch teleprompter. Paste your own script here from \
    Settings, then press play and start speaking. As you talk, the words \
    you say light up and the text scrolls to keep pace with you. If it ever \
    drifts, use the arrow keys to nudge it back into place. Take a breath, \
    look up, and speak naturally. You've got this.
    """
}
