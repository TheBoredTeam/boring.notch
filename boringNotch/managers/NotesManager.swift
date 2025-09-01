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
	private let noteFiles = ["note0.txt", "note1.txt", "note2.txt", "note3.txt"]

	@Published var notes: [Note] = []

	init() {
		let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		notesFolderURL = appSupport.appendingPathComponent("MyAppNotes")

		if !fileManager.fileExists(atPath: notesFolderURL.path) {
			try? fileManager.createDirectory(at: notesFolderURL, withIntermediateDirectories: true)
		}

		loadAllNotes()
	}

	func loadAllNotes() {
		notes = noteFiles.enumerated().map { index, fileName in
			let url = notesFolderURL.appendingPathComponent(fileName)
			let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
			return Note(id: index, content: content)
		}
	}

	func save(note: String, at index: Int) {
		guard index >= 0 && index < noteFiles.count else { return }
		let url = notesFolderURL.appendingPathComponent(noteFiles[index])
		try? note.write(to: url, atomically: true, encoding: .utf8)
		notes[index].content = note
	}
}
