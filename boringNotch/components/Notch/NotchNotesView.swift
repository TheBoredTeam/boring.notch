//
//  NotchNotesView.swift
//  boringNotch
//

import AppKit
import SwiftUI

struct NotchNotesView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var notesManager = AppleNotesManager.shared

    @State private var selectedNoteID: String?
    @State private var isCreatingNote = false
    @State private var draftTitle = ""
    @State private var draftText = ""
    @State private var draftColorIndex = 0
    @State private var isSaving = false
    @State private var notePendingDeletion: AppleNote?
    @State private var scrollSuppressionToken = UUID()
    @State private var isSuppressingScrollGesture = false

    private var selectedNote: AppleNote? {
        notesManager.notes.first(where: { $0.id == selectedNoteID })
    }

    var body: some View {
        ZStack {
            if isCreatingNote {
                AppleNoteEditorView(
                    note: nil,
                    title: $draftTitle,
                    content: $draftText,
                    colorIndex: $draftColorIndex,
                    isSaving: isSaving,
                    onDone: saveDraft,
                    onBack: resetEditor
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let selectedNote {
                AppleNoteEditorView(
                    note: selectedNote,
                    title: $draftTitle,
                    content: $draftText,
                    colorIndex: $draftColorIndex,
                    isSaving: isSaving,
                    onDone: saveDraft,
                    onBack: resetEditor,
                    onColorChange: { colorIndex in
                        notesManager.setColorIndex(colorIndex, for: selectedNote.id)
                    },
                    onReveal: {
                        Task { await notesManager.revealInNotes(id: selectedNote.id) }
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                AppleNotesListView(
                    notes: notesManager.notes,
                    isSyncing: notesManager.isSyncing,
                    error: notesManager.lastError,
                    onRefresh: { Task { await notesManager.refresh() } },
                    onCreate: createBlankNote,
                    onCreateFromClipboard: createNoteFromClipboard,
                    onSelect: select,
                    onTogglePin: notesManager.togglePin,
                    onDelete: { notePendingDeletion = $0 }
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.spring(response: 0.35, dampingFraction: 0.84), value: isCreatingNote)
        .animation(.spring(response: 0.35, dampingFraction: 0.84), value: selectedNoteID)
        .task {
            updateLayoutState()
            await notesManager.refresh()
        }
        .onChange(of: isCreatingNote) { _, _ in
            updateLayoutState()
        }
        .onChange(of: selectedNoteID) { _, _ in
            updateLayoutState()
        }
        .onChange(of: notesManager.notes) { _, notes in
            guard let selectedNoteID,
                  !notes.contains(where: { $0.id == selectedNoteID })
            else {
                return
            }
            resetEditor()
        }
        .onDisappear {
            updateScrollGestureSuppression(false)
            coordinator.notesLayoutState = .list
        }
        .onHover { hovering in
            updateScrollGestureSuppression(hovering)
        }
        .alert("Delete Note?", isPresented: deletionAlertIsPresented) {
            Button("Delete", role: .destructive) {
                deletePendingNote()
            }
            Button("Cancel", role: .cancel) {
                notePendingDeletion = nil
            }
        } message: {
            Text("This removes the note from Apple Notes. This action cannot be undone.")
        }
    }

    private var deletionAlertIsPresented: Binding<Bool> {
        Binding(
            get: { notePendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    notePendingDeletion = nil
                }
            }
        )
    }

    private func createBlankNote() {
        selectedNoteID = nil
        isCreatingNote = true
        draftTitle = ""
        draftText = ""
        draftColorIndex = 0
    }

    private func createNoteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        createBlankNote()
        draftText = text
    }

    private func select(_ note: AppleNote) {
        selectedNoteID = note.id
        isCreatingNote = false
        draftTitle = note.title
        draftText = note.plaintext
        draftColorIndex = note.colorIndex
    }

    private func saveDraft() {
        guard !isSaving else { return }

        Task {
            isSaving = true
            defer { isSaving = false }

            if isCreatingNote {
                guard await notesManager.createManagedNote(
                    title: draftTitle,
                    plaintext: draftText,
                    colorIndex: draftColorIndex
                ) != nil else {
                    return
                }
            } else if let selectedNote {
                notesManager.setColorIndex(draftColorIndex, for: selectedNote.id)
                guard await notesManager.updateManagedNote(
                    id: selectedNote.id,
                    title: draftTitle,
                    plaintext: draftText
                ) else {
                    return
                }
            }

            resetEditor()
        }
    }

    private func deletePendingNote() {
        guard let note = notePendingDeletion else { return }
        notePendingDeletion = nil

        Task {
            if await notesManager.deleteManagedNote(id: note.id) {
                resetEditor()
            }
        }
    }

    private func resetEditor() {
        selectedNoteID = nil
        isCreatingNote = false
        draftTitle = ""
        draftText = ""
        draftColorIndex = 0
    }

    private func updateLayoutState() {
        coordinator.notesLayoutState = (isCreatingNote || selectedNoteID != nil) ? .editor : .list
    }

    private func updateScrollGestureSuppression(_ active: Bool) {
        guard active != isSuppressingScrollGesture else { return }
        isSuppressingScrollGesture = active
        vm.setScrollGestureSuppression(active, token: scrollSuppressionToken)
    }
}

private struct AppleNotesListView: View {
    let notes: [AppleNote]
    let isSyncing: Bool
    let error: String?
    let onRefresh: () -> Void
    let onCreate: () -> Void
    let onCreateFromClipboard: () -> Void
    let onSelect: (AppleNote) -> Void
    let onTogglePin: (String) -> Void
    let onDelete: (AppleNote) -> Void

    @State private var searchText = ""
    @State private var selectedColorIndex: Int?
    @State private var isSearchExpanded = false
    @State private var hostWindow: BoringNotchSkyLightWindow?
    @FocusState private var isSearchFocused: Bool

    private var filteredNotes: [AppleNote] {
        notes.filter { note in
            let matchesSearch = searchText.isEmpty
                || note.title.localizedCaseInsensitiveContains(searchText)
                || note.plaintext.localizedCaseInsensitiveContains(searchText)
            let matchesColor = selectedColorIndex.map { note.colorIndex == $0 } ?? true
            return matchesSearch && matchesColor
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isSearchExpanded {
                searchControls
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if isSyncing && notes.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredNotes.isEmpty {
                emptyState
            } else {
                notesGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NotesWindowAccessor { hostWindow = $0 as? BoringNotchSkyLightWindow })
        .onChange(of: hostWindow) { _, window in
            if isSearchFocused {
                window?.wantsKeyForTextInput = true
            }
        }
        .onChange(of: isSearchFocused) { _, focused in
            if focused {
                hostWindow?.wantsKeyForTextInput = true
            }
        }
        .onDisappear {
            hostWindow?.wantsKeyForTextInput = false
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Notes")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Image(systemName: "apple.logo")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSyncing ? .yellow : .white.opacity(0.45))
                .rotationEffect(.degrees(isSyncing ? 360 : 0))
                .animation(
                    isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                    value: isSyncing
                )

            Spacer()

            circularToolbarButton(systemName: "arrow.triangle.2.circlepath", help: "Refresh", action: onRefresh)
                .disabled(isSyncing)

            circularToolbarButton(systemName: "magnifyingglass", help: "Search notes") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
                    isSearchExpanded.toggle()
                }
                if isSearchExpanded {
                    DispatchQueue.main.async {
                        isSearchFocused = true
                    }
                } else {
                    isSearchFocused = false
                }
            }
            .accessibilityValue(isSearchExpanded ? "Expanded" : "Collapsed")

            circularToolbarButton(systemName: "doc.on.clipboard", help: "Create from Clipboard", action: onCreateFromClipboard)
                .disabled(NSPasteboard.general.string(forType: .string)?.isEmpty != false)

            circularToolbarButton(systemName: "plus", help: "New Note", action: onCreate)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, isSearchExpanded ? 7 : 9)
    }

    private var searchControls: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search notes", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(Text("Clear"))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        selectedColorIndex = nil
                    } label: {
                        Text("All")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                selectedColorIndex == nil ? Color.white.opacity(0.18) : Color.white.opacity(0.07),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)

                    ForEach(AppleNoteAppearance.colors.indices, id: \.self) { index in
                        Button {
                            selectedColorIndex = selectedColorIndex == index ? nil : index
                        } label: {
                            Circle()
                                .fill(AppleNoteAppearance.color(for: index))
                                .frame(width: 15, height: 15)
                                .overlay {
                                    Circle()
                                        .stroke(.white, lineWidth: selectedColorIndex == index ? 2 : 0)
                                        .padding(-2)
                                }
                        }
                        .buttonStyle(.plain)
                        .help(Text("Filter notes"))
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: searchText.isEmpty ? "note.text" : "magnifyingglass")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary.opacity(0.55))
            Text(searchText.isEmpty ? "No notes yet" : "No results found")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notesGrid: some View {
        ScrollView {
            let useGrid = filteredNotes.count > 3
            let columns = useGrid
                ? [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]
                : [GridItem(.flexible())]

            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(filteredNotes) { note in
                    AppleNoteCard(
                        note: note,
                        isCompact: useGrid,
                        onSelect: { onSelect(note) },
                        onTogglePin: { onTogglePin(note.id) },
                        onDelete: note.isManagedByBoringNotch ? { onDelete(note) } : nil
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
    }

    private func circularToolbarButton(
        systemName: String,
        help: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 17, height: 17)
                .padding(5)
                .background(Color.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.78))
        .help(Text(help))
    }
}

private struct AppleNoteCard: View {
    let note: AppleNote
    let isCompact: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onDelete: (() -> Void)?

    @State private var isHovered = false
    @State private var isCopied = false

    var body: some View {
        HStack(spacing: isCompact ? 8 : 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppleNoteAppearance.color(for: note.colorIndex))
                    .frame(width: 4)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        if note.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AppleNoteAppearance.color(for: note.colorIndex))
                        }
                        Text(note.title)
                            .font(.system(size: isCompact ? 12 : 14, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    }

                    Text(note.plaintext.isEmpty ? "No content" : note.plaintext)
                        .font(.system(size: isCompact ? 10 : 12))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !isCompact {
                        Text(note.modificationDate.formatted(.relative(presentation: .named)))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !isHovered && !isCompact {
                    Image(systemName: note.isManagedByBoringNotch ? "square.and.pencil" : "eye")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
        }
        .padding(10)
        .padding(.trailing, isHovered ? (isCompact ? 52 : 86) : 2)
        .frame(minHeight: isCompact ? 78 : 92, alignment: .leading)
        .background(
            Color.white.opacity(isHovered ? 0.13 : 0.075),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppleNoteAppearance.color(for: note.colorIndex).opacity(0.28), lineWidth: 1)
        }
        .overlay(alignment: .trailing) {
            if isHovered {
                hoverActions
                    .padding(.trailing, 8)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onSelect)
        .foregroundStyle(.white)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 3) {
            iconAction(
                systemName: note.isPinned ? "pin.slash.fill" : "pin.fill",
                help: note.isPinned ? "Unpin" : "Pin",
                action: onTogglePin
            )

            iconAction(
                systemName: isCopied ? "checkmark" : "doc.on.doc",
                help: "Copy"
            ) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(note.plaintext, forType: .string)
                withAnimation { isCopied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { isCopied = false }
                }
            }

            if let onDelete {
                iconAction(systemName: "trash", help: "Delete", tint: .red, action: onDelete)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.58), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
    }

    private func iconAction(
        systemName: String,
        help: LocalizedStringKey,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundStyle(tint)
                .background(Color.white.opacity(0.11), in: Circle())
        }
        .buttonStyle(.plain)
        .help(Text(help))
    }
}

private struct AppleNoteEditorView: View {
    let note: AppleNote?
    @Binding var title: String
    @Binding var content: String
    @Binding var colorIndex: Int
    let isSaving: Bool
    let onDone: () -> Void
    let onBack: () -> Void
    var onColorChange: ((Int) -> Void)?
    var onReveal: (() -> Void)?

    @FocusState private var focusedField: EditableField?
    @State private var hostWindow: BoringNotchSkyLightWindow?

    private enum EditableField {
        case title
        case content
    }

    private var isEditable: Bool {
        note == nil || note?.isManagedByBoringNotch == true
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            titleRow
            Divider()
                .overlay(Color.white.opacity(0.12))
            contentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .background(NotesWindowAccessor { hostWindow = $0 as? BoringNotchSkyLightWindow })
        .onAppear {
            guard note == nil else { return }
            DispatchQueue.main.async {
                focusedField = .content
            }
        }
        .onChange(of: hostWindow) { _, window in
            if focusedField != nil {
                window?.wantsKeyForTextInput = true
            }
        }
        .onChange(of: focusedField) { _, field in
            if field != nil {
                hostWindow?.wantsKeyForTextInput = true
            }
        }
        .onDisappear {
            hostWindow?.wantsKeyForTextInput = false
        }
    }

    private var toolbar: some View {
        HStack {
            Button(action: onBack) {
                Label("Notes", systemImage: "chevron.left")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            Spacer()

            if isEditable {
                Button(action: onDone) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Done")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .foregroundStyle(AppleNoteAppearance.color(for: colorIndex))
            } else if let onReveal {
                Button("Open in Notes", action: onReveal)
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppleNoteAppearance.color(for: colorIndex))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            if isEditable {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .focused($focusedField, equals: .title)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text("Read-only")
                        if let accountName = note?.accountName, !accountName.isEmpty {
                            Text(accountName)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(AppleNoteAppearance.colors.indices, id: \.self) { index in
                        Button {
                            colorIndex = index
                            onColorChange?(index)
                        } label: {
                            Circle()
                                .fill(AppleNoteAppearance.color(for: index))
                                .frame(width: 17, height: 17)
                                .overlay {
                                    Circle()
                                        .stroke(.white, lineWidth: colorIndex == index ? 2 : 0)
                                        .padding(-2)
                                }
                        }
                        .buttonStyle(.plain)
                        .help(Text("Local label color"))
                    }
                }
                .padding(3)
            }
            .frame(maxWidth: 180)
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .padding(.bottom, 11)
    }

    @ViewBuilder
    private var contentArea: some View {
        if isEditable {
            ZStack(alignment: .topLeading) {
                if content.isEmpty {
                    Text("Start typing...")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.white.opacity(0.44))
                        .padding(.top, 15)
                        .padding(.leading, 18)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $content)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .frame(maxHeight: .infinity)
                    .background(Color.white.opacity(0.045))
                    .focused($focusedField, equals: .content)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(content.isEmpty ? "No content" : content)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(content.isEmpty ? Color.secondary : Color.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    Text("Existing Apple Notes are read-only here. Open a note in Notes for attachments, checklists, tables, collaboration, and other native features.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
            .background(Color.white.opacity(0.045))
        }
    }
}

private enum AppleNoteAppearance {
    static let colors: [Color] = [
        Color(red: 0.96, green: 0.69, blue: 0.22),
        Color(red: 0.32, green: 0.76, blue: 0.48),
        Color(red: 0.27, green: 0.62, blue: 0.93),
        Color(red: 0.80, green: 0.43, blue: 0.75),
        Color(red: 0.94, green: 0.40, blue: 0.36),
        Color(red: 0.42, green: 0.75, blue: 0.76)
    ]

    static func color(for index: Int) -> Color {
        colors[index % colors.count]
    }
}

private struct NotesWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onResolve(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
