import Foundation
import Defaults

@MainActor
final class NotesManager: ObservableObject {
    static let shared = NotesManager()

    @Published private(set) var notes: [Note] = []
    @Published var searchText: String = ""
    @Published var selectedNoteID: UUID?

    var filteredNotes: [Note] {
        let sorted = notes.sorted(by: NotesManager.sorter)
        guard searchText.isEmpty else {
            return sorted.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
        return sorted
    }

    private let fileManager: FileManager
    private let notesFolderURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private var saveQueue = DispatchQueue(label: "com.boringnotch.notes.save", qos: .utility)
    private var saveWorkItems: [UUID: DispatchWorkItem] = [:]

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? documentsDirectory
        notesFolderURL = supportDirectory.appendingPathComponent("boringNotch/Notes", isDirectory: true)
        createNotesDirectoryIfNeeded()
        loadNotes()
        if notes.isEmpty && Defaults[.enableNotes] {
            _ = createNote(initialContent: "")
        }
    }

    @discardableResult
    func createNote(initialContent: String, isPinned: Bool = false, isMonospaced: Bool = Defaults[.notesDefaultMonospace]) -> Note {
        let now = Date()
        var note = Note(content: initialContent, createdAt: now, updatedAt: now, isPinned: isPinned, isMonospaced: isMonospaced)
        notes.append(note)
        selectedNoteID = note.id
        scheduleSave(for: note)
        return note
    }

    func deleteNotes(with ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        notes.removeAll { note in
            if ids.contains(note.id) {
                cancelPendingSave(for: note.id)
                deleteFile(for: note.id)
                return true
            }
            return false
        }
        if let current = selectedNoteID, ids.contains(current) {
            selectedNoteID = notes.sorted(by: NotesManager.sorter).first?.id
        }
    }

    func updateNote(id: UUID, mutate block: (inout Note) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var note = notes[index]
        block(&note)
        note.updatedAt = Date()
        notes[index] = note
        scheduleSave(for: note)
    }

    func togglePinned(id: UUID) {
        updateNote(id: id) { $0.isPinned.toggle() }
    }

    func toggleMonospaced(id: UUID) {
        updateNote(id: id) { $0.isMonospaced.toggle() }
    }

    func note(for id: UUID?) -> Note? {
        guard let id else { return nil }
        return notes.first(where: { $0.id == id })
    }

    private func createNotesDirectoryIfNeeded() {
        do {
            try fileManager.createDirectory(at: notesFolderURL, withIntermediateDirectories: true)
        } catch {
            NSLog("NotesManager: Failed to create notes directory: \(error.localizedDescription)")
        }
    }

    private func loadNotes() {
        do {
            let files = try fileManager.contentsOfDirectory(at: notesFolderURL, includingPropertiesForKeys: nil)
            let loaded = files.compactMap { url -> Note? in
                guard url.pathExtension == "json" else { return nil }
                do {
                    let data = try Data(contentsOf: url)
                    return try decoder.decode(Note.self, from: data)
                } catch {
                    NSLog("NotesManager: Failed to decode note at \(url.lastPathComponent): \(error.localizedDescription)")
                    return nil
                }
            }
            notes = loaded
            selectedNoteID = loaded.sorted(by: NotesManager.sorter).first?.id
        } catch {
            NSLog("NotesManager: Failed to load notes: \(error.localizedDescription)")
            notes = []
        }
    }

    private func scheduleSave(for note: Note) {
        cancelPendingSave(for: note.id)
        let workItem = DispatchWorkItem { [weak self] in
            self?.persist(note)
        }
        saveWorkItems[note.id] = workItem
        let interval = Defaults[.notesAutoSaveInterval]
        saveQueue.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    private func cancelPendingSave(for id: UUID) {
        if let item = saveWorkItems[id] {
            item.cancel()
            saveWorkItems.removeValue(forKey: id)
        }
    }

    private func persist(_ note: Note) {
        let url = fileURL(for: note.id)
        do {
            let data = try encoder.encode(note)
            try data.write(to: url, options: .atomic)
            Task { @MainActor in
                self.saveWorkItems.removeValue(forKey: note.id)
            }
        } catch {
            NSLog("NotesManager: Failed to save note \(note.id): \(error.localizedDescription)")
        }
    }

    private func deleteFile(for id: UUID) {
        let url = fileURL(for: id)
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            NSLog("NotesManager: Failed to delete note file \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func fileURL(for id: UUID) -> URL {
        notesFolderURL.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    private static func sorter(lhs: Note, rhs: Note) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }
        return lhs.updatedAt > rhs.updatedAt
    }
}
