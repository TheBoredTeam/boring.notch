import SwiftUI
import Defaults

struct NotchNotesView: View {
    @ObservedObject private var notesManager = NotesManager.shared
    @FocusState private var editorFocused: Bool
    @Default(.enableNotes) private var notesEnabled

    private var selectedNote: Note? {
        notesManager.note(for: notesManager.selectedNoteID)
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { notesManager.selectedNoteID },
            set: { id in notesManager.selectedNoteID = id }
        )
    }

    var body: some View {
        Group {
            if notesEnabled {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        editor
                            .frame(width: max(geometry.size.width * 0.66, 280))

                        Divider()

                        sidebar
                            .frame(width: max(geometry.size.width * 0.34, 200))
                    }
                    .background(Color.black.opacity(0.4))
                }
            } else {
                disabledState
            }
        }
        .onAppear { warmupIfNeeded() }
        .onChange(of: notesEnabled) { isEnabled in
            if isEnabled {
                warmupIfNeeded()
            }
        }
    }

    private var editor: some View {
        Group {
            if let note = selectedNote {
                VStack(alignment: .leading, spacing: 16) {
                    header(for: note)

                    TextEditor(text: binding(for: note))
                        .focused($editorFocused)
                        .font(note.isMonospaced ? .system(.body, design: .monospaced) : .system(.body))
                        .scrollContentBackground(.hidden)
                        .background(Color.black.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 12)
                }
                .padding(24)
            } else {
                VStack(spacing: 12) {
                    Text("No note selected")
                        .font(.title3.bold())
                    Text("Create or select a note from the list to begin editing.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func header(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(note.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Button {
                    notesManager.togglePinned(id: note.id)
                } label: {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.plain)
                .help(note.isPinned ? "Unpin" : "Pin note")

                Button {
                    notesManager.toggleMonospaced(id: note.id)
                } label: {
                    Image(systemName: note.isMonospaced ? "character.mono.square" : "textformat")
                }
                .buttonStyle(.plain)
                .help(note.isMonospaced ? "Disable monospace" : "Enable monospace")

                Button(role: .destructive) {
                    notesManager.deleteNotes(with: Set([note.id]))
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete note")
            }

            HStack(spacing: 16) {
                Label(timestamp(note.createdAt), systemImage: "clock")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Label(timestamp(note.updatedAt), systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search", text: $notesManager.searchText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    let note = notesManager.createNote(initialContent: "")
                    notesManager.selectedNoteID = note.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        editorFocused = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .help("New note")
            }
            .padding(.horizontal)

            List(selection: selectionBinding) {
                ForEach(notesManager.filteredNotes) { note in
                    NoteListRow(note: note, isSelected: note.id == notesManager.selectedNoteID)
                        .tag(note.id as UUID?)
                        .contextMenu {
                            Button(note.isPinned ? "Unpin" : "Pin") {
                                notesManager.togglePinned(id: note.id)
                            }
                            Button("Duplicate") {
                                let duplicate = notesManager.createNote(
                                    initialContent: note.content,
                                    isPinned: note.isPinned,
                                    isMonospaced: note.isMonospaced
                                )
                                notesManager.selectedNoteID = duplicate.id
                            }
                            Divider()
                            Button(role: .destructive) {
                                notesManager.deleteNotes(with: Set([note.id]))
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete { offsets in
                    let ids = offsets.compactMap { index in
                        notesManager.filteredNotes[safe: index]?.id
                    }
                    notesManager.deleteNotes(with: Set(ids))
                }
            }
            .listStyle(.plain)
        }
    }

    private func binding(for note: Note) -> Binding<String> {
        Binding(
            get: { notesManager.note(for: note.id)?.content ?? note.content },
            set: { newValue in
                notesManager.updateNote(id: note.id) { note in
                    note.content = newValue
                }
            }
        )
    }

    private func warmup() {
        if notesManager.note(for: notesManager.selectedNoteID) == nil,
            let first = notesManager.filteredNotes.first
        {
            notesManager.selectedNoteID = first.id
        }
    }

    private func warmupIfNeeded() {
        guard notesEnabled else { return }
        warmup()
    }

    private var disabledState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Notes are disabled")
                .font(.title3.weight(.semibold))
            Text("Enable notes in Settings to take quick jot-downs from the notch.")
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                SettingsWindowController.shared.showWindow()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NoteListRow: View {
    let note: Note
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }

            Text(note.previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))
            }
        }
    }
}

private extension Note {
    var previewText: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lines = trimmed.components(separatedBy: .newlines)
        if lines.count > 1 {
            return lines[1].trimmingCharacters(in: .whitespaces)
        }
        return String(trimmed.prefix(200))
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private let noteRelativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
}()

private extension NotchNotesView {
    func timestamp(_ date: Date) -> String {
        noteRelativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
