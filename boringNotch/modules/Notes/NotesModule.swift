//
//  NotesModule.swift
//  boringNotch
//
//  Onglet « Notes » : jusqu'à 5 notes en texte simple, tapées dans l'encoche.
//  L'encoche ne prend le clavier qu'après un clic dans la zone de texte et le rend en fin d'édition.
//  Sauvegarde : différée d'1 s à chaque frappe, immédiate en fin d'édition et à la fermeture de l'app.
//

import AppKit
import SwiftUI

struct NotesModule: NotchModule {
    let id = "notes"
    let label = "Notes"
    let icon = "note.text"

    func start() { Task { @MainActor in NotesStore.shared.load() } }

    @MainActor func makeView() -> AnyView { AnyView(NotesView()) }
}

@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    @Published private(set) var book = NotesBook()
    private var pendingSave: Task<Void, Never>?
    private var loaded = false

    private static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("notes.json")

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotesStore.shared.saveNow() }
        }
    }

    /// Fichier absent : livre neuf. Fichier illisible : renommé en notes.json.bak, livre neuf ; un .bak déjà là est
    /// d'abord renommé notes-<date>.json.bak (aucune sauvegarde n'est jamais supprimée).
    /// Si un renommage échoue, `loaded` reste faux : aucune écriture, le fichier illisible reste intact.
    func load() {
        guard !loaded else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.url.path) {
            if let data = try? Data(contentsOf: Self.url), let book = NotesBook.decode(data) {
                self.book = book
            } else {
                let bak = Self.url.appendingPathExtension("bak")
                do {
                    if fm.fileExists(atPath: bak.path) {
                        // ponytail: horodatage à la seconde ; deux corruptions dans la même seconde → échec du renommage, donc aucune écriture.
                        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
                        try fm.moveItem(at: bak, to: Self.url.deletingLastPathComponent().appendingPathComponent("notes-\(stamp).json.bak"))
                    }
                    try fm.moveItem(at: Self.url, to: bak)
                } catch {
                    NSLog("Notes : notes.json illisible et impossible à mettre de côté, sauvegarde désactivée : \(error)")
                    return
                }
            }
        }
        loaded = true
    }

    func edit(_ id: UUID, text: String) {
        book.update(id, text: text, now: .now)
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    func select(_ id: UUID) {
        guard book.notes.contains(where: { $0.id == id }) else { return }
        book.selected = id
    }

    func add() { if book.add(now: .now) != nil { saveNow() } }
    func remove(_ id: UUID) { book.remove(id); saveNow() }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard loaded else { return }   // ne jamais écraser un fichier pas encore lu
        do {
            try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(book).write(to: Self.url, options: .atomic)
        } catch {
            NSLog("Notes : échec de la sauvegarde : \(error)")
        }
    }
}

private struct NotesView: View {
    @ObservedObject private var store = NotesStore.shared
    @State private var pendingDelete: Note?

    var body: some View {
        VStack(spacing: 7) {
            if let note = pendingDelete {
                confirmBar(note)
            } else {
                pills
            }
            NoteTextArea(note: store.book.notes.first { $0.id == store.book.selected } ?? store.book.notes[0])
                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.08)) }
                .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private var pills: some View {
        HStack(spacing: 6) {
            ForEach(store.book.notes) { note in
                let selected = note.id == store.book.selected
                Button { store.select(note.id) } label: {
                    Text(note.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 100)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .foregroundStyle(selected ? .black : .white.opacity(0.85))
                        .background(selected ? Color.effectiveAccent : .white.opacity(0.1), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Supprimer", role: .destructive) {
                        if note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { store.remove(note.id) } else { pendingDelete = note }
                    }
                }
            }
            Button { store.add() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.1), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(!store.book.canAdd)
            .opacity(store.book.canAdd ? 1 : 0.35)
            .help(store.book.canAdd ? "Nouvelle note" : "\(NotesBook.limit) notes au maximum")
            Spacer(minLength: 0)
        }
    }

    /// Confirmation dans l'encoche. Elle ne bloque pas la fermeture : si l'encoche se ferme, la vue est recréée et la
    /// suppression est simplement annulée.
    private func confirmBar(_ note: Note) -> some View {
        HStack(spacing: 8) {
            Text("Supprimer « \(note.title) » ?")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Annuler") { pendingDelete = nil }
            Button("Supprimer", role: .destructive) { store.remove(note.id); pendingDelete = nil }
                .foregroundStyle(.red)
        }
        .controlSize(.small)
        .frame(height: 22)
    }
}

/// NSTextView enveloppé : clic fiable dans une fenêtre non clé, Échap, et raccourcis ⌘ gérés par la vue elle-même
/// (l'app n'étant pas active, le menu principal ne les distribue pas).
private struct NoteTextArea: NSViewRepresentable {
    let note: Note

    func makeCoordinator() -> NoteEditor { NoteEditor() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = makeNoteScrollView()
        let tv = scroll.documentView as? NoteTextView ?? NoteTextView()   // toujours une NoteTextView (construite ci-dessous)
        tv.editor = context.coordinator
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 12)
        tv.textColor = .white
        tv.insertionPointColor = .white
        tv.textContainerInset = NSSize(width: 6, height: 8)
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let editor = context.coordinator
        guard let tv = editor.textView else { return }
        if editor.noteID != note.id {
            editor.noteID = note.id
            editor.undo.removeAllActions()
        }
        if tv.string != note.text {
            tv.string = note.text
            editor.undo.removeAllActions()   // l'historique ne correspond plus au texte affiché
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: NoteEditor) {
        coordinator.end()   // changement d'onglet ou fermeture de l'encoche
    }
}

/// Vue défilante + NoteTextView construites à la main (montage standard : largeur suivie, hauteur extensible).
func makeNoteScrollView() -> NSScrollView {
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    let tv = NoteTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
    tv.minSize = .zero
    tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    tv.isVerticallyResizable = true
    tv.isHorizontallyResizable = false
    tv.autoresizingMask = [.width]
    tv.textContainer?.widthTracksTextView = true
    tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
    scroll.documentView = tv
    return scroll
}

private final class NoteTextView: NSTextView {
    weak var editor: NoteEditor?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        editor?.begin()
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { editor?.end(); return }   // Échap
        if shortcut(event) { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        (window?.firstResponder === self && shortcut(event)) || super.performKeyEquivalent(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { editor?.end() }
    }

    /// Toute combinaison ⌘ est consommée pendant la saisie : ⌘Q, ⌘W, ⌘H… n'atteignent pas le menu de l'app.
    private func shortcut(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        guard mods.contains(.command) else { return false }
        switch (event.charactersIgnoringModifiers?.lowercased(), mods) {
        case ("a", .command): selectAll(nil)
        case ("c", .command): copy(nil)
        case ("v", .command): paste(nil)
        case ("x", .command): cut(nil)
        case ("z", .command): undoManager?.undo()
        case ("z", [.command, .shift]): undoManager?.redo()
        default: break
        }
        return true
    }
}

/// Une édition = begin … end, exactement une fois chacun (garde `editing`).
@MainActor
final class NoteEditor: NSObject, NSTextViewDelegate {
    weak var textView: NSTextView?
    var noteID: UUID?
    let undo = UndoManager()
    private var editing = false
    private weak var window: BoringNotchSkyLightWindow?
    private var resignObserver: NSObjectProtocol?
    private var monitors: [Any] = []
    /// Édition en cours : les fermetures demandées par l'utilisateur la terminent avant de fermer l'encoche.
    static weak var active: NoteEditor?

    func begin() {
        guard !editing, let tv = textView, let w = tv.window as? BoringNotchSkyLightWindow else { return }
        editing = true
        Self.active = self
        window = w
        w.allowsKey = true
        w.makeKey()
        w.makeFirstResponder(tv)
        SharingStateManager.shared.beginInteraction()
        // Perte de la clé : clic dans une autre app, autre fenêtre devenue clé…
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.end() }
        }
        // Clic hors de l'encoche (y compris sur le bureau ou la barre des menus).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.end() }
        }) { monitors.append(m) }
        // Clic dans l'encoche mais hors de la zone de texte (pastilles, onglets…).
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let scroll = self.textView?.enclosingScrollView else { return }
                let inside = event.window === scroll.window
                    && scroll.bounds.contains(scroll.convert(event.locationInWindow, from: nil))
                if !inside { self.end() }
            }
            return event
        }) { monitors.append(m) }
    }

    func end() {
        guard editing else { return }
        editing = false
        if Self.active === self { Self.active = nil }
        if let o = resignObserver { NotificationCenter.default.removeObserver(o) }
        resignObserver = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        NotesStore.shared.saveNow()
        if let w = window {
            w.makeFirstResponder(nil)
            w.resignKey()
            w.allowsKey = false
        }
        window = nil
        SharingStateManager.shared.endInteraction()
    }

    func textDidChange(_ notification: Notification) {
        guard let id = noteID, let tv = textView else { return }
        NotesStore.shared.edit(id, text: tv.string)
    }

    func undoManager(for view: NSTextView) -> UndoManager? { undo }
}
