	//  NotesManager.swift
	//  boringNotch
	//
	//  Created by Adon Omeri on 31/8/2025.
	//



import Foundation

struct Note: Identifiable {
	let id: Int
	var content: String
}

class NotesManager: ObservableObject {
	private let notesFolderURL: URL
	private let fileManager = FileManager.default

	@Published var selectedNoteIndex = 0
	@Published var notes: [Note] = []

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
			let txtFiles = fileURLs
				.filter { $0.pathExtension == "txt" }
				.compactMap { url -> (Int, URL)? in
					let nameWithoutExtension = url.deletingPathExtension().lastPathComponent
					guard let index = Int(nameWithoutExtension) else { return nil }
					return (index, url)
				}
				.sorted { $0.0 < $1.0 }

			notes = txtFiles.map { index, url in
				let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
				return Note(id: index, content: content)
			}
		} catch {
			notes = []
		}

		if notes.isEmpty {
			addNote()
		}
	}

	func save(note: String, at index: Int) {
		guard index >= 0 && index < notes.count else { return }
		let noteID = notes[index].id
		let url = notesFolderURL.appendingPathComponent("\(noteID).txt")
		try? note.write(to: url, atomically: true, encoding: .utf8)
		notes[index].content = note
	}

	func addNote() {
		let newID = (notes.map(\.id).max() ?? -1) + 1
		let newNote = Note(id: newID, content: "")
		notes.append(newNote)

		let url = notesFolderURL.appendingPathComponent("\(newID).txt")
		try? "".write(to: url, atomically: true, encoding: .utf8)
	}

	func removeNote(at index: Int) {
		guard index >= 0 && index < notes.count && notes.count > 1 else { return }

		let noteID = notes[index].id
		let url = notesFolderURL.appendingPathComponent("\(noteID).txt")
		try? fileManager.removeItem(at: url)

		notes.remove(at: index)

		if selectedNoteIndex >= notes.count {
			selectedNoteIndex = notes.count - 1
		}
	}
}
