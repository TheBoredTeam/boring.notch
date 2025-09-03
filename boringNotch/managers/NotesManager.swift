//
//  NotesManager.swift
//  boringNotch
//
//  Created by Adon Omeri on 31/8/2025.
//

import Foundation

struct Note: Identifiable, Codable {
	let id: Int
	var content: String
	var lastEdited: Date
	var isMonospaced: Bool
}

@MainActor
final class NotesManager: ObservableObject {
	@Published var notes: [Note] = []
	@Published var selectedNoteIndex: Int = 0

	private let notesFolderURL: URL
	private let fileManager = FileManager.default

	private var saveWorkItem: DispatchWorkItem?

	static let shared = NotesManager()


	private init() {
		print("NotesManager init started")
		let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		notesFolderURL = appSupport.appendingPathComponent("Notes")
		print("Notes folder URL: \(notesFolderURL)")

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			guard let self = self else { return }
			print("Creating notes directory if needed")
			if !self.fileManager.fileExists(atPath: self.notesFolderURL.path) {
				do {
					try self.fileManager.createDirectory(at: self.notesFolderURL, withIntermediateDirectories: true)
					print("Notes directory created")
				} catch {
					print("Failed to create notes directory: \(error)")
				}
			}
			self.loadAllNotesBackground()
		}
	}

	// MARK: - Private functions

	private func loadAllNotesBackground() {
		print("Loading notes from background")
		var loaded: [Note] = []
		do {
			let fileURLs = try fileManager.contentsOfDirectory(at: notesFolderURL, includingPropertiesForKeys: nil)
			let jsonFiles = fileURLs.filter { $0.pathExtension.lowercased() == "json" }
			print("Found \(jsonFiles.count) JSON files")
			loaded = try jsonFiles.compactMap { url in
				print("Loading note from: \(url)")
				let data = try Data(contentsOf: url)
				return try JSONDecoder().decode(Note.self, from: data)
			}
			print("Loaded \(loaded.count) notes")
		} catch {
			print("Error loading notes: \(error)")
			loaded = []
		}

		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }
			self.notes = loaded
			if self.notes.isEmpty {
				self.addNote()
			} else {
				self.sortNotesByEdited()
			}
		}
	}

	private func sortNotesByEdited(preserveSelectedID preservedID: Int? = nil) {
		let selectedIDBefore: Int? = preservedID ?? (notes.indices.contains(selectedNoteIndex) ? notes[selectedNoteIndex].id : nil)
		notes.sort { $0.lastEdited > $1.lastEdited }
		if let id = selectedIDBefore, let newIndex = notes.firstIndex(where: { $0.id == id }) {
			selectedNoteIndex = newIndex
		} else {
			selectedNoteIndex = min(selectedNoteIndex, notes.count - 1)
			print("Updated selected index to \(selectedNoteIndex)")
		}
	}

	private func saveToFile(note: Note) {
		let url = notesFolderURL.appendingPathComponent("\(note.id).json")
		do {
			let data = try JSONEncoder().encode(note)
			try data.write(to: url, options: .atomic)
		} catch {
			print("Failed to save note \(note.id): \(error)")
		}
	}

	// MARK: - Public functions

	func save(note content: String, at index: Int) {
		guard index >= 0, index < notes.count else {
			print("Invalid index \(index) for notes count \(notes.count)")
			return
		}

		notes[index].content = content
		notes[index].lastEdited = Date()
		sortNotesByEdited(preserveSelectedID: notes[index].id)

		saveWorkItem?.cancel()
		let noteToSave = notes[index]
		let workItem = DispatchWorkItem { [weak self] in
			self?.saveToFile(note: noteToSave)
		}
		saveWorkItem = workItem
		DispatchQueue
			.global(qos: .userInitiated)
			.asyncAfter(deadline: .now() + 0.5, execute: workItem)
	}

	func addNote() {
		print("Adding new note")
		let newID = (notes.map(\.id).max() ?? -1) + 1
		let newNote = Note(id: newID, content: "", lastEdited: Date(), isMonospaced: false)
		notes.append(newNote)
		print("Added note with ID \(newID)")
		sortNotesByEdited(preserveSelectedID: newID)
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			print("Saving new note \(newID) to file")
			self?.saveToFile(note: newNote)
		}
	}

	func removeNote(at index: Int) {
		print("Remove note called for index \(index)")
		guard index >= 0, index < notes.count, notes.count > 1 else {
			print("Cannot remove note - invalid conditions")
			return
		}
		let noteID = notes[index].id
		let url = notesFolderURL.appendingPathComponent("\(noteID).json")
		print("Removing note \(noteID)")

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			do {
				try self?.fileManager.removeItem(at: url)
				print("Successfully deleted file for note \(noteID)")
			} catch {
				print("Failed to delete file for note \(noteID): \(error)")
			}
			DispatchQueue.main.async {
				guard let self = self else { return }
				self.notes.remove(at: index)
				print("Removed note from array, new count: \(self.notes.count)")
				if self.selectedNoteIndex >= self.notes.count {
					self.selectedNoteIndex = self.notes.count - 1
					print("Updated selected index to \(self.selectedNoteIndex)")
				}
			}
		}
	}

	func toggleMonospaced(at index: Int) {
		print("Toggle monospaced called for index \(index)")
		guard index >= 0, index < notes.count else {
			print("Invalid index for toggle monospaced")
			return
		}
		notes[index].isMonospaced.toggle()
		notes[index].lastEdited = Date()
		print("Toggled monospaced for note \(notes[index].id) to \(notes[index].isMonospaced)")
		sortNotesByEdited(preserveSelectedID: notes[index].id)

		let noteToSave = notes[index]
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			print("Saving monospaced change for note \(noteToSave.id)")
			self?.saveToFile(note: noteToSave)
		}
	}
}
