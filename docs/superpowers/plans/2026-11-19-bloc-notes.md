# Bloc-notes dans l'encoche — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** un onglet « Notes » où l'on écrit directement dans l'encoche, jusqu'à 5 notes sauvegardées automatiquement.

**Architecture:** modèle pur `NotesBook` (Foundation seul, testé par auto-test `swiftc`) ; `NotesStore` (sauvegarde
différée JSON) ; `NotesModule` + vue ; la fenêtre de l'encoche gagne une autorisation de clavier temporaire
(`allowsKey`), activée au clic dans le texte et retirée en fin d'édition.

**Tech Stack:** Swift 5 / SwiftUI, AppKit (`NSPanel`, `NSTextView` si besoin).

**Spec:** `docs/superpowers/specs/2026-11-19-bloc-notes-design.md`

## Global Constraints

- Partir de `main` du fork, branche `feature/bloc-notes`.
- Encoche ouverte : 640 × 190 pt barre d'onglets comprise ; rien ne déborde.
- L'encoche ne prend le clavier qu'après un clic dans la zone de texte ; elle le rend en fin d'édition.
- Jamais de perte de texte (sauvegarde différée 1 s + immédiate en fin d'édition et à la fermeture de l'app).
- Textes en français ; commentaires en français, `ponytail:` pour une simplification assumée.
- Aucune nouvelle dépendance ; groupes Xcode synchronisés.
- Auto-test : `swiftc boringNotch/modules/Notes/NotesBook.swift scripts/notes-selftest/main.swift -o "$TMPDIR/notes-selftest" && "$TMPDIR/notes-selftest"` → `OK`.
- Build signé : `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -allowProvisioningUpdates DEVELOPMENT_TEAM=4JQGBGCKQM CODE_SIGN_IDENTITY="Apple Development" build` → `** BUILD SUCCEEDED **`.
- Installer pour vérifier : quitter avec `osascript -e 'tell application "Boring Notch" to quit'`, `ditto` le produit vers `/Applications/Boring Notch.app`, `open` (un build ad hoc perd les permissions).
- Commits terminés par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Le clavier revient à l'app d'avant** après Échap / fermeture de l'encoche, sans clic : taper dans le terminal juste
   après doit fonctionner.
2. **Survol sans clic** : ouvrir l'encoche et aller sur l'onglet Notes ne vole jamais la frappe.
3. **Quitter l'app pendant la frappe** : le dernier texte est sur disque au relancement.
4. **`notes.json` corrompu** : renommé en `.bak`, l'app démarre avec des notes vides, pas de plantage.
5. **Écran sans encoche / plusieurs écrans** : le comportement clavier est le même sur la fenêtre de chaque écran.

---

### Task 1: Exploration — rendre la fenêtre de l'encoche clé sans activer l'app

**Files:**
- Modify: `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift` (`canBecomeKey`, l. 129)
- Modify: `boringNotch/components/Notch/BoringNotchWindow.swift` (`canBecomeKey`, l. 43) si cette fenêtre est utilisée

**Interfaces:**
- Produces: sur les deux classes de fenêtre, `var allowsKey = false` ; `override var canBecomeKey: Bool { allowsKey }`.

- [ ] **Step 1:** Ajouter `allowsKey`. Prototype jetable (non committé) : un `TextField` dans un onglet existant qui, au
  clic, fait `window.allowsKey = true; window.makeKey()` et, sur Échap, `window.resignKey(); window.allowsKey = false`.
- [ ] **Step 2:** Build signé, installer, vérifier : (a) la frappe arrive dans le champ alors que l'app d'avant reste au
  premier plan (son menu reste affiché) ; (b) après Échap, taper dans l'app d'avant marche sans clic ; (c) au survol
  seul, aucune frappe n'est captée. Noter le résultat dans le rapport.
- [ ] **Step 3: Décision.** Si (a)-(c) passent : garder `allowsKey` (retirer le prototype), commit
  `git commit -m "Encoche : autorisation de clavier temporaire (allowsKey)"`. Sinon : **repli spec** — les tâches 3-4
  ouvrent une petite fenêtre flottante normale (`NSPanel` titré, 360 × 240 pt, sous l'encoche) pour l'édition,
  l'onglet montrant l'aperçu des notes ; écrire ce choix dans le rapport et continuer sans redemander.

### Task 2: Modèle des notes (pur)

**Files:**
- Create: `boringNotch/modules/Notes/NotesBook.swift`
- Test: `scripts/notes-selftest/main.swift`

**Interfaces:**
- Produces:
  ```swift
  struct Note: Codable, Identifiable, Equatable { let id: UUID; var text: String; var updatedAt: Date
      var title: String { get }   // première ligne non vide, espaces retirés ; "Nouvelle note" si vide
  }
  struct NotesBook: Codable, Equatable {
      static let limit = 5
      private(set) var notes: [Note]          // jamais vide : au moins une note
      var selected: UUID
      init()                                  // une note vide sélectionnée
      var canAdd: Bool { get }
      @discardableResult mutating func add(now: Date) -> Note?      // nil à la limite ; la nouvelle est sélectionnée
      mutating func update(_ id: UUID, text: String, now: Date)
      mutating func remove(_ id: UUID)        // la dernière restante est vidée, pas supprimée ; sélection sur la voisine
      static func decode(_ data: Data) -> NotesBook?   // nil si illisible
  }
  ```

- [ ] **Step 1: Write the failing test:**
  ```swift
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
  ```
- [ ] **Step 2: Run the selftest**, expect compile failure.
- [ ] **Step 3: Implement `NotesBook`.**
- [ ] **Step 4: Run the selftest, expect `OK`.**
- [ ] **Step 5: Commit** — `git commit -m "Notes : modèle des notes (limite 5, titres, JSON)"`

### Task 3: Sauvegarde et onglet Notes

**Files:**
- Create: `boringNotch/modules/Notes/NotesModule.swift` (module, `NotesStore`, vue)
- Modify: `boringNotch/modules/NotchModule.swift` (`NotchModules.all` : ajouter `NotesModule()` après `ClipboardModule()`)

**Interfaces:**
- Consumes: `NotesBook` (tâche 2), `allowsKey` (tâche 1).
- Produces:
  ```swift
  struct NotesModule: NotchModule   // id "notes", label "Notes", icon "note.text"
  @MainActor final class NotesStore: ObservableObject {
      static let shared: NotesStore
      @Published private(set) var book: NotesBook
      func load()                    // au start() du module ; illisible → renomme en notes.json.bak, livre neuf
      func edit(_ id: UUID, text: String)   // met à jour + sauvegarde différée 1 s
      func saveNow()                 // écriture atomique immédiate
  }
  ```

- [ ] **Step 1: `NotesStore`.** Fichier `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  .appendingPathComponent("notes.json")` (conteneur de l'app), écriture `.atomic`. Différé : annuler/relancer un
  `Task` de 1 s à chaque `edit`. `saveNow()` aussi sur `NSApplication.willTerminateNotification`.
- [ ] **Step 2: Vue** selon la spec : rangée de pastilles (titre tronqué, sélection en accent) + « + » grisé si
  `!canAdd` ; menu contextuel « Supprimer » (alerte de confirmation si texte non vide) ; zone de texte défilante 12 pt.
- [ ] **Step 3: Clavier.** Au clic dans la zone de texte : `allowsKey = true`, `makeKey()`, focus sur le texte,
  `SharingStateManager.shared.beginInteraction()`. Fin d'édition (Échap, clic hors de l'encoche, changement d'onglet,
  fermeture de l'encoche, perte de clé) : `saveNow()`, `resignKey()`, `allowsKey = false`, `endInteraction()` — une
  seule fois par édition (garde booléenne). La fenêtre se trouve via `NSApp.windows` (la fenêtre de l'encoche qui
  contient la vue) ou un `NSViewRepresentable` qui lit `view.window`.
- [ ] **Step 4: Build signé, installer, vérifier à la main** les cinq points de la Review Focus, plus : ⌘A/⌘C/⌘V/⌘Z
  dans le texte ; l'encoche ne se ferme pas pendant la frappe ; 5 notes max ; suppression.
- [ ] **Step 5: Commit** — `git commit -m "Notes : onglet bloc-notes dans l'encoche, sauvegarde automatique"`
