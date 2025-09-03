//
//  NotchNotesView.swift
//  boringNotch
//
//  Created by Adon Omeri on 31/8/2025.
//

import SwiftUI

struct NotchNotesView: View {
	@EnvironmentObject var notesManager: NotesManager

	@EnvironmentObject var focusManager: FocusManager

	@State private var searchText: String = ""

	@FocusState private var editorIsFocused: Bool

	var body: some View {
		GeometryReader { geo in
			HStack(spacing: 0) {
				VStack {
					if notesManager.notes.indices.contains(notesManager.selectedNoteIndex) {
						ZStack(alignment: .topLeading) {
							let currentNote = notesManager.notes[notesManager.selectedNoteIndex]

							if currentNote.content.isEmpty {
								Text("Enter your note...")
									.foregroundColor(.gray)
									.padding(.leading, 8)
									.padding(.top, 4)
									.font(
										notesManager.notes.indices.contains(notesManager.selectedNoteIndex) &&
											notesManager.notes[notesManager.selectedNoteIndex].isMonospaced
											? .system(.caption, design: .monospaced)
											: .caption
									)
									.frame(maxWidth: .infinity, alignment: .leading)
									.allowsHitTesting(false)
							}

							ZStack(alignment: .bottomTrailing) {
								TextEditor(
									text: Binding(
										get: {
											guard
												notesManager.selectedNoteIndex < notesManager.notes.count,
												!notesManager.notes.isEmpty
											else { return "" }
											return notesManager.notes[notesManager.selectedNoteIndex].content
										},
										set: { newValue in
											guard focusManager.editorCanFocus else { return }
											guard
												notesManager.selectedNoteIndex < notesManager.notes.count,
												!notesManager.notes.isEmpty
											else { return }
											notesManager.save(note: newValue, at: notesManager.selectedNoteIndex)
										}
									)
								)
								.focused($editorIsFocused)
//								.disabled(!focusManager.editorCanFocus)
								.onChange(
									of: focusManager.editorCanFocus
								) { _, editorCanFocus in
									editorIsFocused = editorCanFocus
								}
								.fontWeight(.thin)
								.font(
									notesManager.notes.indices.contains(notesManager.selectedNoteIndex) &&
										notesManager.notes[notesManager.selectedNoteIndex].isMonospaced
										? .system(.caption, design: .monospaced)
										: .caption
								)
								.animation(
									.easeInOut(duration: 0.2),
									value: notesManager.notes[notesManager.selectedNoteIndex].isMonospaced
								)
								.textEditorStyle(.plain)
								.transition(.opacity.combined(with: .blurReplace))
								.id(notesManager.selectedNoteIndex)
								.padding(4)

								Button {
									notesManager.toggleMonospaced(at: notesManager.selectedNoteIndex)
								} label: {
									Image(systemName: "textformat")
										.padding(5)
										.background(
											ZStack {
												Rectangle()
													.fill(.ultraThinMaterial)
												if notesManager.notes.indices.contains(notesManager.selectedNoteIndex) &&
													notesManager.notes[notesManager.selectedNoteIndex].isMonospaced
												{
													Rectangle()
														.fill(Color.white.opacity(0.15))
												}
											}
										)
										.clipShape(RoundedRectangle(cornerRadius: 8))
										.padding(3)
								}
								.buttonStyle(.plain)
							}
						}
						.background(
							RoundedRectangle(cornerRadius: 10)
								.fill(Color.white.opacity(0.07))
						)
					}
				}
				.animation(.easeInOut, value: notesManager.selectedNoteIndex)
				.frame(width: (geo.size.width / 3) * 2)

				VStack {
					ScrollView(.vertical) {
						HStack {
							TextField("Search", text: $searchText)
								.textFieldStyle(.plain)
								.frame(maxWidth: .infinity)
								.padding(3)
								.padding(.leading, 3)
								.frame(height: 25)
								.background(Color.white.opacity(0.1))
								.clipShape(RoundedRectangle(cornerRadius: 8))
								.contentShape(RoundedRectangle(cornerRadius: 8))

							Button {
								notesManager.addNote()
							} label: {
								Image(systemName: "plus")
									.frame(width: 25, height: 25)
									.padding(.bottom, 1)
									.background(Color.white.opacity(0.1))
									.clipShape(RoundedRectangle(cornerRadius: 8))
									.contentShape(RoundedRectangle(cornerRadius: 8))
							}
							.buttonStyle(.plain)
						}

						LazyVStack(spacing: 4) {
							let displayed = Array(notesManager.notes.enumerated())
								.filter { searchText.isEmpty || $0.element.content.localizedCaseInsensitiveContains(searchText) }

							ForEach(displayed, id: \.element.id) { originalIndex, note in
								HStack {
									Button {
										notesManager.selectedNoteIndex = originalIndex
									} label: {
										HStack {
											if !note.content.isEmpty {
												Text(note.content)
													.lineLimit(1)
													.padding(4)
													.transition(.opacity.combined(with: .blurReplace))
													.font(
														notesManager.notes.indices.contains(notesManager.selectedNoteIndex) &&
															notesManager.notes[notesManager.selectedNoteIndex].isMonospaced
															? .system(.caption, design: .monospaced)
															: .caption
													)
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
											notesManager.selectedNoteIndex == originalIndex
												? Color.accentColor.opacity(0.4)
												: Color.white.opacity(0.1)
										)
										.clipShape(RoundedRectangle(cornerRadius: 8))
										.contentShape(RoundedRectangle(cornerRadius: 8))
									}
									.buttonStyle(.plain)

									Button {
										notesManager.removeNote(at: originalIndex)
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
								.transition(.opacity.combined(with: .blurReplace))
								.frame(height: 25)
								.padding(.vertical, 1)
							}
						}
						.animation(.easeInOut, value: notesManager.notes.count)
					}
					.scrollIndicators(.never)
					.transition(.opacity.combined(with: .blurReplace))
				}
				.padding(.leading, 8)
				.frame(width: geo.size.width / 3)
				.clipShape(RoundedRectangle(cornerRadius: 8))
			}
			.preferredColorScheme(.dark)
			.frame(height: geo.size.height)
		}
		.transition(.opacity.combined(with: .blurReplace))
	}
}
