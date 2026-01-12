import SwiftUI
import Defaults

struct NotchNotesView: View {
    @ObservedObject private var notesManager = NotesManager.shared
    @Default(.enableNotes) private var notesEnabled
    @FocusState private var editorFocused: Bool
    @State private var showCopiedFeedback = false
    
    /// The scratchpad note - always use the first note or create one
    private var scratchpadNote: Note? {
        if let first = notesManager.notes.first {
            // Ensure it's selected
            if notesManager.selectedNoteID != first.id {
                Task { @MainActor in
                    notesManager.selectedNoteID = first.id
                }
            }
            return first
        }
        return nil
    }
    
    private var characterCount: Int {
        scratchpadNote?.content.count ?? 0
    }
    
    private var wordCount: Int {
        guard let content = scratchpadNote?.content, !content.isEmpty else { return 0 }
        return content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var body: some View {
        Group {
            if notesEnabled {
                scratchpadContent
            } else {
                disabledState
            }
        }
        .onAppear {
            ensureScratchpadExists()
            requestKeyboardFocus()
        }
        .onDisappear {
            releaseKeyboardFocus()
        }
    }
    
    // MARK: - Scratchpad Content
    
    private var scratchpadContent: some View {
        VStack(spacing: 0) {
            // Editor area
            ZStack(alignment: .topLeading) {
                if let note = scratchpadNote {
                    TextEditor(text: contentBinding(for: note))
                        .focused($editorFocused)
                        .font(.system(.body, design: note.isMonospaced ? .monospaced : .default))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Placeholder
                    if note.content.isEmpty {
                        Text("Start typing...")
                            .font(.body)
                            .foregroundStyle(.secondary.opacity(0.5))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(editorFocused ? 0.1 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(editorFocused ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                requestKeyboardFocus()
            }
            
            Spacer().frame(height: 10)
            
            // Bottom toolbar
            HStack(spacing: 12) {
                // Word/character count
                Text("\(wordCount) words · \(characterCount) chars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                // Font toggle
                if let note = scratchpadNote {
                    Button {
                        notesManager.toggleMonospaced(id: note.id)
                    } label: {
                        Image(systemName: note.isMonospaced ? "textformat" : "textformat.alt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(note.isMonospaced ? "Switch to regular font" : "Switch to monospace font")
                }
                
                // Copy button
                Button {
                    copyContent()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        if showCopiedFeedback {
                            Text("Copied")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(showCopiedFeedback ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy all content")
                .disabled(characterCount == 0)
                
                // Clear button
                Button {
                    clearContent()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear scratchpad")
                .disabled(characterCount == 0)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    // MARK: - Disabled State
    
    private var disabledState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Scratchpad is disabled")
                .font(.title3.weight(.semibold))
            Text("Enable it in Settings to quickly jot down notes.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                SettingsWindowController.shared.showWindow()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Helpers
    
    private func contentBinding(for note: Note) -> Binding<String> {
        Binding(
            get: { notesManager.note(for: note.id)?.content ?? "" },
            set: { newValue in
                notesManager.updateNote(id: note.id) { $0.content = newValue }
            }
        )
    }
    
    private func ensureScratchpadExists() {
        if notesManager.notes.isEmpty && notesEnabled {
            _ = notesManager.createNote(initialContent: "")
        }
        if let first = notesManager.notes.first {
            notesManager.selectedNoteID = first.id
        }
    }
    
    private func requestKeyboardFocus() {
        // Post notification to make window key
        NotificationCenter.default.post(
            name: .boringNotchWindowKeyboardFocus,
            object: nil,
            userInfo: ["allow": true]
        )
        // Focus the editor after window becomes key
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            editorFocused = true
        }
    }
    
    private func releaseKeyboardFocus() {
        NotificationCenter.default.post(
            name: .boringNotchWindowKeyboardFocus,
            object: nil,
            userInfo: ["allow": false]
        )
    }
    
    private func copyContent() {
        guard let content = scratchpadNote?.content, !content.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopiedFeedback = false
            }
        }
    }
    
    private func clearContent() {
        guard let note = scratchpadNote else { return }
        notesManager.updateNote(id: note.id) { $0.content = "" }
    }
}
