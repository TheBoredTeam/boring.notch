//
//  NotchNotesView.swift
//  boringNotch
//
//  Created by Adon Omeri on 31/8/2025.
//

import SwiftUI

struct NotchNotesView: View {
	@StateObject var notesManager = NotesManager()

	var body: some View {
		GeometryReader { geo in
			HStack(spacing: 0) {
				// editor panel
				VStack {
					if notesManager.notes.indices.contains(notesManager.selectedNoteIndex) {
						ZStack(alignment: .topLeading) {
							if notesManager.notes[notesManager.selectedNoteIndex].content.isEmpty {
								Text("Enter your note...")
									.foregroundColor(.gray)
									.padding(.leading, 8)
									.padding(.top, 4)
									.font(.caption)
									.frame(maxWidth: .infinity, alignment: .leading)
									.allowsHitTesting(false)
							}

							TextEditor(
								text: Binding(
									get: {
										guard notesManager.selectedNoteIndex < notesManager.notes.count else { return "" }
										return notesManager.notes[notesManager.selectedNoteIndex].content
									},
									set: { newValue in
										guard notesManager.selectedNoteIndex < notesManager.notes.count else { return }
										notesManager.save(note: newValue, at: notesManager.selectedNoteIndex)
									}
								)
							)
							.fontWeight(.ultraLight)
							.fontWidth(.expanded)
							.textEditorStyle(.plain)
							.transition(.opacity.combined(with: .blurReplace))
							.id(notesManager.selectedNoteIndex)
							.padding(4)
						}
						.background(
							RoundedRectangle(cornerRadius: 10)
								.fill(Color.white.opacity(0.07))
						)
					}
				}
				.animation(.easeInOut, value: notesManager.selectedNoteIndex)
				.frame(width: (geo.size.width / 3) * 2)

				// sidebar
				VStack {
					ScrollView(.vertical) {
						Button {
							notesManager.addNote()
							notesManager.selectedNoteIndex = notesManager.notes.count - 1
						} label: {
							Image(systemName: "plus")
								.frame(maxWidth: .infinity)
								.frame(height: 25)
								.padding(.vertical, 1)
								.background(Color.white.opacity(0.1))
								.clipShape(RoundedRectangle(cornerRadius: 8))
								.contentShape(RoundedRectangle(cornerRadius: 8))
						}
						.buttonStyle(.plain)

						LazyVStack(spacing: 4) {
							ForEach(Array(notesManager.notes.enumerated()), id: \.element.id) {
								index,
									note in
								HStack {
									Button {
										notesManager.selectedNoteIndex = index
									} label: {
										HStack {
											if !note.content.isEmpty {
												Text(note.content)
													.lineLimit(1)
													.padding(4)
													.transition(.opacity.combined(with: .blurReplace))
											} else {
												Text("\(note.id + 1)")
													.padding(.horizontal, 2)
													.padding(.vertical, 4)
													.transition(.opacity.combined(with: .blurReplace))
											}
										}
										.animation(.easeInOut, value: note.content)
										.frame(maxWidth: .infinity, alignment: .center)
										.background(
											notesManager.selectedNoteIndex == index
												? Color.accentColor.opacity(0.4)
												: Color.white.opacity(0.1)
										)
										.clipShape(RoundedRectangle(cornerRadius: 8))
										.contentShape(RoundedRectangle(cornerRadius: 8))
									}
									.buttonStyle(.plain)

									Button {
										notesManager.removeNote(at: index)
									} label: {
										Label("Delete", systemImage: "trash")
											.foregroundStyle(.white.opacity(0.7))
											.labelStyle(.iconOnly)
									}
									.frame(width: 25, height: 25)
									.buttonStyle(.plain)
									.background(
										RoundedRectangle(cornerRadius: 8)
											.fill(Color.red.opacity(0.2))
									)
								}
								.frame(height: 25)
								.padding(.vertical, 1)
							}
						}
					}
					.scrollIndicators(.never)
					.transition(.opacity.combined(with: .blurReplace))
				}
				.padding(.leading, 8)
				.frame(width: geo.size.width / 3)
				.clipShape(RoundedRectangle(cornerRadius: 8))
			}
			.frame(height: geo.size.height)
		}
		.transition(.opacity.combined(with: .blurReplace))
	}
}

#Preview {
	NotchNotesView()
}
