// Modèle pur du bloc-notes : aucune dépendance UI, testable avec swiftc seul.

import Foundation

struct Note: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var updatedAt: Date

    /// Première ligne non vide, espaces retirés ; "Nouvelle note" si rien.
    var title: String {
        let line = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line ?? "Nouvelle note"
    }
}

struct NotesBook: Codable, Equatable {
    static let limit = 5

    /// Jamais vide : au moins une note existe toujours.
    private(set) var notes: [Note]
    var selected: UUID

    /// Une note vide, sélectionnée.
    init() {
        let note = Note(id: UUID(), text: "", updatedAt: Date())
        notes = [note]
        selected = note.id
    }

    var canAdd: Bool { notes.count < Self.limit }

    /// Ajoute une note vide et la sélectionne ; nil à la limite.
    @discardableResult
    mutating func add(now: Date) -> Note? {
        guard canAdd else { return nil }
        let note = Note(id: UUID(), text: "", updatedAt: now)
        notes.append(note)
        selected = note.id
        return note
    }

    /// Ne fait rien si l'identifiant est inconnu.
    mutating func update(_ id: UUID, text: String, now: Date) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].text = text
        notes[i].updatedAt = now
    }

    /// La dernière note restante est vidée, pas supprimée. Si la note sélectionnée
    /// disparaît, la voisine au même index (ou la précédente) est sélectionnée.
    mutating func remove(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        if notes.count == 1 {
            notes[0].text = ""
            return
        }
        let wasSelected = notes[i].id == selected
        notes.remove(at: i)
        if wasSelected { selected = notes[min(i, notes.count - 1)].id }
    }

    /// nil si les données sont illisibles ou ne contiennent aucune note.
    /// Si la sélection n'existe plus, la première note est sélectionnée.
    static func decode(_ data: Data) -> NotesBook? {
        guard var book = try? JSONDecoder().decode(NotesBook.self, from: data),
              !book.notes.isEmpty else { return nil }
        if !book.notes.contains(where: { $0.id == book.selected }) {
            book.selected = book.notes[0].id
        }
        return book
    }
}
