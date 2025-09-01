
	//
	//  NotchNotesView.swift
	//  boringNotch
	//
	//  Created by Adon Omeri on 31/8/2025.
	//

import SwiftUI

struct NotchNotesView: View {
	@EnvironmentObject var vm: BoringViewModel
	@StateObject var notesManager = NotesManager()
	@State private var selectedNoteIndex = 0

	var body: some View {
		GeometryReader { geo in
			HStack(spacing: 0) {
				VStack {
					if notesManager.notes.indices.contains(selectedNoteIndex) {
						ZStack(alignment: .topLeading) {
							RoundedRectangle(cornerRadius: 10)
								.fill(Color.white.opacity(0.07))

							if notesManager.notes[selectedNoteIndex].content.isEmpty {
								Text("Enter your note...")
									.foregroundColor(.gray)
									.font(.caption)
									.padding([.leading, .top], 10)

							}

							TextEditor(text: $notesManager.notes[selectedNoteIndex].content)
								.fontWeight(.light)
								.fontWidth(.expanded)
								.textEditorStyle(.plain)
								.onChange(of: notesManager.notes[selectedNoteIndex].content) { _, newValue in
									notesManager.save(note: newValue, at: selectedNoteIndex)
								}
								.transition(.opacity.combined(with: .blurReplace))
								.id(selectedNoteIndex)
								.padding(.leading, 6)
								.padding(.top, 10)

						}
					}
				}
				.animation(.easeInOut, value: selectedNoteIndex)
				.frame(width: (geo.size.width / 3) * 2)

				VStack {
					HStack {
						ForEach(notesManager.notes) { note in
							Button {
								selectedNoteIndex = note.id
							} label: {
								Text("\(note.id + 1)")
									.frame(maxWidth: .infinity)
									.padding(5)
									.background(selectedNoteIndex == note.id ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.1))
									.clipShape(RoundedRectangle(cornerRadius: 8))
									.transition(.opacity.combined(with: .blurReplace))
									.animation(.easeInOut, value: selectedNoteIndex)
							}
							.buttonStyle(.plain)
						}
					}
					Spacer()
				}
				.padding(8)
				.frame(width: geo.size.width / 3)
			}
		}
		.transition(.opacity.combined(with: .blurReplace))
	}
}

#Preview {
	NotchNotesView()
}
