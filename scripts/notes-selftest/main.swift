// Auto-test du modèle des notes (limite, titres, suppression, JSON) et du Markdown léger.
// swiftc boringNotch/modules/Notes/NotesBook.swift boringNotch/modules/Notes/NoteMarkdown.swift scripts/notes-selftest/main.swift -o "$TMPDIR/notes-selftest" && "$TMPDIR/notes-selftest"

import Foundation

func check(_ cond: Bool, _ msg: String) { if !cond { print("FAIL: \(msg)"); exit(1) } }

var b = NotesBook()
check(b.notes.count == 1 && b.notes[0].title == "Nouvelle note", "une note vide au départ")
let t0 = Date(timeIntervalSince1970: 0)
for _ in 0..<4 { b.add(now: t0) }
check(b.notes.count == 5 && !b.canAdd && b.add(now: t0) == nil, "limite de 5")
let id = b.notes[2].id
b.update(id, text: "\n  Courses  \nlait", now: t0 + 1)
check(b.notes[2].title == "Courses" && b.notes[2].updatedAt == t0 + 1, "titre = première ligne non vide")
b.selected = id; b.remove(id)
check(b.notes.count == 4 && b.selected != id && b.notes.contains { $0.id == b.selected }, "suppression, sélection voisine")
var one = NotesBook(); one.update(one.notes[0].id, text: "x", now: t0); one.remove(one.notes[0].id)
check(one.notes.count == 1 && one.notes[0].text == "", "la dernière note est vidée, pas supprimée")
let data = try! JSONEncoder().encode(b)
check(NotesBook.decode(data) == b, "aller-retour JSON")
check(NotesBook.decode(Data("pas du json".utf8)) == nil, "fichier illisible : nil")

// Titres sans marques Markdown.
func title(_ t: String) -> String { Note(id: UUID(), text: t, updatedAt: t0).title }
check(title("## Courses") == "Courses", "titre sans #")
check(title("- [ ] Appeler **Paul**") == "Appeler Paul", "titre sans case ni gras")
check(title("#hashtag") == "#hashtag", "un # collé n'est pas un titre")

// Markdown : styles et plages.
func styles(_ t: String) -> [MarkStyle] { NoteMarkdown.spans(t).map(\.style) }
func has(_ t: String, _ st: MarkStyle, _ sub: String) -> Bool {
    let r = (t as NSString).range(of: sub)
    return NoteMarkdown.spans(t).contains { $0.style == st && $0.range == r }
}
check(has("# Titre", .heading(1), "# Titre") && has("# Titre", .marker, "#"), "titre niveau 1")
check(has("### Petit", .heading(3), "### Petit"), "titre niveau 3")
check(has("du **gras** ici", .bold, "**gras**"), "gras")
check(has("un *mot* là", .italic, "*mot*") && has("un _mot_ là", .italic, "_mot_"), "italique")
check(!styles("snake_case_name").contains(.italic), "pas d'italique dans un identifiant")
check(!styles("**gras**").contains(.italic), "le gras n'est pas de l'italique")
check(has("lance `npm test`", .code, "`npm test`"), "code")
check(!styles("`**pas gras**`").contains(.bold), "pas de gras dans le code")
let md = "voir [la doc](https://example.com/a) !"
check(has(md, .link(URL(string: "https://example.com/a")!), "la doc"), "lien Markdown sur le libellé")
check(has(md, .linkTarget, "](https://example.com/a)"), "l'adresse du lien est atténuée")
check(NoteMarkdown.spans(md).filter { if case .link = $0.style { return true }; return false }.count == 1, "lien Markdown non doublé par la détection")
check(styles("va sur https://apple.com/fr maintenant").contains(.link(URL(string: "https://apple.com/fr")!)), "lien nu détecté")
check(has("- [x] fait", .task(done: true), "[x]") && has("- [x] fait", .done, "fait"), "tâche cochée")
check(has("- [ ] à faire", .task(done: false), "[ ]") && !styles("- [ ] à faire").contains(.done), "tâche à faire")
check(has("- [ ] x", .hidden, "- ") && !styles("- [ ] x").contains(.listMarker), "tiret de tâche masqué")
check(has("  - item", .listMarker, "-") && has("12. item", .listMarker, "12."), "puces")
check(has("> cité", .quote, "> cité"), "citation")
check(NoteMarkdown.spans("texte simple").isEmpty, "texte simple sans style")

// Case à cocher : clic.
let tasks = "courses\n- [ ] lait\n- [x] pain"
let box1 = (tasks as NSString).range(of: "[ ]")
check(NoteMarkdown.taskToggle(in: tasks, at: box1.location + 1).map { $0.range == box1 && $0.replacement == "[x]" } == true, "cocher")
let box2 = (tasks as NSString).range(of: "[x]")
check(NoteMarkdown.taskToggle(in: tasks, at: box2.location).map { $0.replacement == "[ ]" } == true, "décocher")
check(NoteMarkdown.taskToggle(in: tasks, at: 2) == nil, "clic hors case")

// Entrée dans une liste.
check(NoteMarkdown.continuation(forLine: "- lait") == .prefix("- "), "puce continuée")
check(NoteMarkdown.continuation(forLine: "  * lait") == .prefix("  * "), "indentation gardée")
check(NoteMarkdown.continuation(forLine: "9. lait") == .prefix("10. "), "numéro suivant")
check(NoteMarkdown.continuation(forLine: "- [x] lait") == .prefix("- [ ] "), "nouvelle tâche vide")
check(NoteMarkdown.continuation(forLine: "- ") == .endList && NoteMarkdown.continuation(forLine: "- [ ] ") == .endList, "puce vide : fin de liste")
check(NoteMarkdown.continuation(forLine: "texte") == nil, "pas de liste")
print("OK")
