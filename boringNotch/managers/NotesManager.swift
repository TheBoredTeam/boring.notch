//  NotesManager.swift
//  boringNotch
//
//  Created by Adon Omeri on 31/8/2025.
//

import Foundation

// MARK: - Model + Manager

struct Note: Identifiable, Codable {
	let id: Int
	var content: String
	var lastEdited: Date
	var isMonospaced: Bool
}

final class NotesManager: ObservableObject {
	@Published var notes: [Note] = []
	@Published var selectedNoteIndex: Int = 0

	private let notesFolderURL: URL
	private let fileManager = FileManager.default

	init() {
		let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		notesFolderURL = appSupport.appendingPathComponent("Notes")

		if !fileManager.fileExists(atPath: notesFolderURL.path) {
			try? fileManager.createDirectory(at: notesFolderURL, withIntermediateDirectories: true)
		}

		loadAllNotes()
	}

	func loadAllNotes() {
		do {
			let fileURLs = try fileManager.contentsOfDirectory(at: notesFolderURL, includingPropertiesForKeys: nil)
			let jsonFiles = fileURLs.filter { $0.pathExtension.lowercased() == "json" }

			notes = try jsonFiles.compactMap { url in
				let data = try Data(contentsOf: url)
				return try JSONDecoder().decode(Note.self, from: data)
			}
		} catch {
			notes = []
		}

		if notes.isEmpty {
			addNote()
		} else {
			sortNotesByEdited()
		}
	}

	func save(note: Note) {
		guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
		notes[index] = note
		let url = notesFolderURL.appendingPathComponent("\(note.id).json")
		if let data = try? JSONEncoder().encode(note) {
			try? data.write(to: url, options: .atomic)
		}
	}

	func save(note content: String, at index: Int) {
		guard index >= 0, index < notes.count else { return }
		var note = notes[index]
		note.content = content
		note.lastEdited = Date()
		save(note: note)
		sortNotesByEdited(preserveSelectedID: note.id)
	}

	func addNote() {
		let newID = (notes.map(\.id).max() ?? -1) + 1
		let newNote = Note(id: newID, content: "", lastEdited: Date(), isMonospaced: false)
		notes.append(newNote)
		save(note: newNote)
		sortNotesByEdited(preserveSelectedID: newNote.id)
	}

	func removeNote(at index: Int) {
		guard index >= 0, index < notes.count, notes.count > 1 else { return }
		let noteID = notes[index].id
		let url = notesFolderURL.appendingPathComponent("\(noteID).json")
		try? fileManager.removeItem(at: url)
		notes.remove(at: index)

		if selectedNoteIndex >= notes.count {
			selectedNoteIndex = notes.count - 1
		}
	}

	func toggleMonospaced(at index: Int) {
		guard index >= 0, index < notes.count else { return }
		var note = notes[index]
		note.isMonospaced.toggle()
		note.lastEdited = Date()
		save(note: note)
		sortNotesByEdited(preserveSelectedID: note.id)
	}

	private func sortNotesByEdited(preserveSelectedID preservedID: Int? = nil) {
		let selectedIDBefore: Int? = preservedID ?? (notes.indices.contains(selectedNoteIndex) ? notes[selectedNoteIndex].id : nil)
		notes.sort { $0.lastEdited > $1.lastEdited }
		if let id = selectedIDBefore, let newIndex = notes.firstIndex(where: { $0.id == id }) {
			selectedNoteIndex = newIndex
		} else {
			selectedNoteIndex = min(selectedNoteIndex, notes.count - 1)
		}
	}
}
