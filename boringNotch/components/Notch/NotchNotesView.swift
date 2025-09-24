import SwiftUI
import Defaults

struct NotchNotesView: View {
    @ObservedObject private var notesManager = NotesManager.shared
    @Default(.enableNotes) private var notesEnabled
    @FocusState private var editorFocused: Bool

    private var selectedNote: Note? {
        notesManager.note(for: notesManager.selectedNoteID)
    }

    var body: some View {
        Group {
            if notesEnabled {
                GeometryReader { _ in
                    HStack(spacing: 0) {
                        editorPane
                            .frame(minWidth: 360, maxWidth: .infinity)
                            .layoutPriority(1)
                            .allowsHitTesting(true)

                        Divider()
                            .background(Color.white.opacity(0.1))

                        sidebar
                            .frame(minWidth: 180, idealWidth: 210, maxWidth: 240)
                            .allowsHitTesting(true)
                            .background(Color.black.opacity(0.04))
                    }
                    .allowsHitTesting(true)
                }
            } else {
                disabledState
            }
        }
        .onAppear {
            warmupIfNeeded()
            NotificationCenter.default.post(
                name: .boringNotchWindowKeyboardFocus,
                object: nil,
                userInfo: ["allow": true]
            )
        }
        .onChange(of: notesEnabled) { enabled in
            if enabled {
                warmupIfNeeded()
            }
        }
        .onChange(of: notesManager.selectedNoteID) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if selectedNote != nil {
                    editorFocused = true
                } else {
                    editorFocused = false
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if selectedNote != nil {
                    editorFocused = true
                } else {
                    editorFocused = false
                }
            }
        }
        .onDisappear {
            NotificationCenter.default.post(
                name: .boringNotchWindowKeyboardFocus,
                object: nil,
                userInfo: ["allow": false]
            )
        }
    }

    // MARK: - Editor

    private var editorPane: some View {
        Group {
            if let note = selectedNote {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: binding(for: note))
                        .focused($editorFocused)
                        .font(note.isMonospaced ? .system(.body, design: .monospaced) : .system(.body))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(editorFocused ? 0.12 : 0.08))
                                .allowsHitTesting(false)
                                .animation(.easeInOut(duration: 0.2), value: editorFocused)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(editorFocused ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.12), lineWidth: editorFocused ? 2 : 1)
                                .allowsHitTesting(false)
                                .animation(.easeInOut(duration: 0.2), value: editorFocused)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editorFocused = true
                        }
                        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)

                    if note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Start typing…")
                            .font(.body)
                            .foregroundStyle(.secondary.opacity(0.7))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.pencil")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No note selected")
                        .font(.title3.weight(.semibold))
                    Text("Create or select a note from the list to begin editing.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity, alignment: .topLeading)
    }

        // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 12) {
            // Search and Add Button
            HStack(spacing: 8) {
                TextField("Search notes...", text: $notesManager.searchText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                Button(action: createAndFocusNote) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color.blue)
                        )
                }
                .buttonStyle(.plain)
                .help("New note")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            if notesManager.filteredNotes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.6))
                    
                    VStack(spacing: 4) {
                        Text(notesManager.searchText.isEmpty ? "No notes yet" : "No results")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        if notesManager.searchText.isEmpty {
                            Text("Create your first note to get started")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(notesManager.filteredNotes) { note in
                            sidebarRow(for: note)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func sidebarRow(for note: Note) -> some View {
        let isSelected = note.id == notesManager.selectedNoteID

        return Button {
            notesManager.selectedNoteID = note.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                editorFocused = true
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(note.headingTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !note.previewText.isEmpty {
                        Text(note.previewText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    HStack {
                        Text(timestamp(note.updatedAt))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
        
                VStack(spacing: 8) {
                    Button {
                        notesManager.togglePinned(id: note.id)
                    } label: {
                        Image(systemName: note.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 12))
                            .foregroundStyle(note.isPinned ? Color.yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(isSelected ? 1 : 0.6)
                    .help(note.isPinned ? "Unpin" : "Pin note")

                    Button(role: .destructive) {
                        notesManager.deleteNotes(with: Set([note.id]))
                        warmupIfNeeded()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .opacity(isSelected ? 1 : 0.6)
                    .help("Delete note")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(note.isPinned ? "Unpin" : "Pin") {
                notesManager.togglePinned(id: note.id)
            }
            Button("Delete", role: .destructive) {
                notesManager.deleteNotes(with: Set([note.id]))
                warmupIfNeeded()
            }
        }
    }

    // MARK: - Helpers

    private func binding(for note: Note) -> Binding<String> {
        Binding(
            get: { notesManager.note(for: note.id)?.content ?? note.content },
            set: { newValue in
                notesManager.updateNote(id: note.id) { $0.content = newValue }
            }
        )
    }

    private func createAndFocusNote() {
        let note = notesManager.createNote(initialContent: "")
        notesManager.selectedNoteID = note.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            editorFocused = true
        }
    }

    private func warmup() {
        if notesManager.note(for: notesManager.selectedNoteID) == nil,
           let first = notesManager.filteredNotes.first {
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
        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
    }

    private func timestamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct NoteListRow: View {
    let note: Note
    let lastUpdated: String
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.headingTitle)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if !note.previewText.isEmpty {
                Text(note.previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }

            HStack {
                Text(lastUpdated)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary.opacity(0.6))

                Spacer()

                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .frame(maxWidth: CGFloat.infinity, alignment: .leading)
    }
}
