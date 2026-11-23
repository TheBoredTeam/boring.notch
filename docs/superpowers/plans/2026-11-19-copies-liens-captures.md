# Copies : liens nettoyés et captures en image — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** retirer automatiquement le pistage des liens copiés et afficher les captures d'écran en image dans l'onglet Copies.

**Architecture:** deux fonctions pures dans un nouveau fichier Foundation seul `ClipRules.swift` (testées par
`scripts/clipboard-selftest`) ; `ClipboardStore.poll` / `read` les appliquent.

**Tech Stack:** Swift 5 / SwiftUI, AppKit (`NSPasteboard`), Foundation (`URLComponents`).

**Spec:** `docs/superpowers/specs/2026-11-19-copies-liens-captures-design.md`

## Global Constraints

- Partir de `main` du fork, branche `feature/copies-liens-captures`.
- Textes en français ; commentaires en français, `ponytail:` pour une simplification assumée.
- Aucune nouvelle dépendance ; groupes Xcode synchronisés.
- Ne jamais modifier un texte qui n'est pas un lien seul ; ne jamais toucher un contenu marqué secret.
- Auto-test : `swiftc boringNotch/modules/Clipboard/Clip.swift boringNotch/modules/Clipboard/ClipRules.swift scripts/clipboard-selftest/main.swift -o "$TMPDIR/clipboard-selftest" && "$TMPDIR/clipboard-selftest"` → `OK` (mettre à jour la commande en tête du fichier).
- Build signé : `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -allowProvisioningUpdates DEVELOPMENT_TEAM=4JQGBGCKQM CODE_SIGN_IDENTITY="Apple Development" build` → `** BUILD SUCCEEDED **`.
- Commits terminés par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Réécriture du presse-papiers** : le lien propre réécrit ne doit pas réapparaître comme une seconde copie (comparer
   au `changeCount` produit par l'app), ni boucler.
2. **Lien avec texte autour** (« voir https://… merci ») : jamais modifié.
3. **Copie web avec texte et image** (types RTF/HTML présents) : reste du texte.
4. **Lien sans pistage** : presse-papiers non réécrit (pas de changement inutile du `changeCount`).

---

### Task 1: Règles pures (liens, ordre de lecture)

**Files:**
- Create: `boringNotch/modules/Clipboard/ClipRules.swift`
- Test: `scripts/clipboard-selftest/main.swift`

**Interfaces:**
- Produces:
  ```swift
  enum ClipRules {
      /// Lien seul http(s) débarrassé du pistage ; nil si le texte n'est pas un lien seul ou n'a rien à retirer.
      static func cleanedLink(_ text: String) -> String?
      /// L'image passe avant le texte : image présente (png/tiff) et pas de texte mis en forme (rtf/html).
      static func prefersImage(types: Set<String>) -> Bool
  }
  ```

- [ ] **Step 1: Write the failing tests** (ajoutés avant `print("OK")`) :
  ```swift
  check(ClipRules.cleanedLink("https://ex.com/a?utm_source=x&id=3&fbclid=y#top") == "https://ex.com/a?id=3#top", "pistage retiré, ordre et fragment gardés")
  check(ClipRules.cleanedLink("https://ex.com/a?UTM_Medium=x") == "https://ex.com/a", "insensible à la casse, plus de ?")
  check(ClipRules.cleanedLink("https://youtu.be/abc?si=XYZ&t=10") == "https://youtu.be/abc?t=10", "si retiré sur YouTube")
  check(ClipRules.cleanedLink("https://ex.com/a?si=1") == nil, "si gardé ailleurs")
  check(ClipRules.cleanedLink("https://ex.com/a?id=3") == nil, "rien à retirer")
  check(ClipRules.cleanedLink("voir https://ex.com/a?utm_source=x merci") == nil, "texte autour : intact")
  check(ClipRules.cleanedLink("  https://ex.com/?gclid=1  ") == "https://ex.com/", "espaces autour tolérés")
  check(ClipRules.cleanedLink("ftp://ex.com/?utm_source=x") == nil, "http(s) seulement")
  check(ClipRules.prefersImage(types: ["public.png", "public.utf8-plain-text"]), "capture : image")
  check(!ClipRules.prefersImage(types: ["public.tiff", "public.html", "public.utf8-plain-text"]), "copie web : texte")
  check(!ClipRules.prefersImage(types: ["public.utf8-plain-text"]), "texte seul")
  ```
- [ ] **Step 2: Run the selftest**, expect compile failure.
- [ ] **Step 3: Implement `ClipRules`** avec `URLComponents` et la liste de paramètres exacte de la spec.
- [ ] **Step 4: Run the selftest, expect `OK`.**
- [ ] **Step 5: Commit** — `git commit -m "Copies : règles de nettoyage des liens et de priorité des images"`

### Task 2: Appliquer dans le presse-papiers et réglage

**Files:**
- Modify: `boringNotch/modules/Clipboard/ClipboardModule.swift` (`poll()`, `read(_:)`)
- Modify: `boringNotch/models/Constants.swift` (clé `cleanCopiedLinks`)
- Modify: `boringNotch/components/Settings/SettingsView.swift` (près de `KeyboardShortcuts.Recorder("Ouvrir les copies :", name: .openClipboard)`, ~l. 1844)

**Interfaces:**
- Consumes: `ClipRules.cleanedLink`, `ClipRules.prefersImage` (tâche 1).
- Produces: `static let cleanCopiedLinks = Key<Bool>("cleanCopiedLinks", default: true)`.

- [ ] **Step 1: Vérifier les types d'une capture** sans écraser le presse-papiers de l'utilisateur : sauvegarder son
  contenu (`pb.pasteboardItems` → copies des données par type), faire ⌘⇧⌃4 sur une petite zone, lister `pb.types`,
  puis restaurer. Noter les types (et ceux de CleanShot/Shottr si installés) dans le rapport et en commentaire au-dessus
  de `read(_:)`.
- [ ] **Step 2: `read(_:)`** : après les fichiers, `if ClipRules.prefersImage(types: Set(pb.types?.map(\.rawValue) ?? [])), let img = NSImage(pasteboard: pb) { return .image(img) }`, puis l'ordre actuel.
- [ ] **Step 3: `poll()`** : pour un contenu `.text(s)`, si `Defaults[.cleanCopiedLinks]` et `ClipRules.cleanedLink(s)`
  renvoie un lien, réécrire `NSPasteboard.general` (`clearContents` + `setString`), mettre `lastChange` au nouveau
  `changeCount`, et enregistrer la copie avec le lien propre. Contenus secrets : inchangé (déjà filtrés avant).
- [ ] **Step 4: Réglage** `Defaults.Toggle("Nettoyer les liens copiés (utm, fbclid…)", key: .cleanCopiedLinks)` dans la
  section du raccourci « Ouvrir les copies ».
- [ ] **Step 5: Build signé, installer, vérifier à la main** : copier `https://example.com/?utm_source=x&a=1` puis ⌘V
  ailleurs → `https://example.com/?a=1`, une seule carte ; ⌘⇧⌃4 → carte image ; copier du texte + image depuis une
  page web → carte texte ; réglage désactivé → lien intact.
- [ ] **Step 6: Commit** — `git commit -m "Copies : liens nettoyés automatiquement, captures affichées en image"`
