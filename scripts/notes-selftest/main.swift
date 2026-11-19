// Auto-test du modèle des notes (limite, titres, suppression, JSON).
// swiftc boringNotch/modules/Notes/NotesBook.swift scripts/notes-selftest/main.swift -o "$TMPDIR/notes-selftest" && "$TMPDIR/notes-selftest"

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
print("OK")
