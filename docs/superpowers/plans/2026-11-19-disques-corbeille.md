# Éjecter les disques et vider la corbeille — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** deux boutons dans l'onglet Focus : éjecter les volumes externes, vider la corbeille avec confirmation.

**Architecture:** `QuickActions.swift` (AppKit) porte l'éjection, la corbeille et l'état de confirmation ; la logique de
confirmation est pure (`ConfirmGate`, Foundation seul) et testée par auto-test `swiftc`. `FocusView` ajoute une colonne
de deux boutons.

**Tech Stack:** Swift 5 / SwiftUI, AppKit (`NSWorkspace`, `NSAppleScript`).

**Spec:** `docs/superpowers/specs/2026-11-19-disques-corbeille-design.md`

## Global Constraints

- Partir de `main` du fork, branche `feature/disques-corbeille`.
- Textes en français ; commentaires en français, `ponytail:` pour une simplification assumée.
- Aucune nouvelle dépendance ; groupes Xcode synchronisés.
- Jamais de corbeille vidée sans second clic dans les 3 s ; jamais d'éjection d'un volume interne.
- Build signé : `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -allowProvisioningUpdates DEVELOPMENT_TEAM=4JQGBGCKQM CODE_SIGN_IDENTITY="Apple Development" build` → `** BUILD SUCCEEDED **`.
- Commits terminés par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Double clic rapide** sur « Vider la corbeille » : la corbeille n'est vidée que si le second clic arrive après le
   premier, dans les 3 s, et l'état « Confirmer ? » est visible avant (le premier clic ne vide jamais).
2. **Autorisation Automatisation refusée** : aucun plantage, échec visible avec la marche à suivre.
3. **Volume occupé** (fichier ouvert) : les autres volumes sont quand même éjectés, l'échec nomme celui qui reste.
4. **Aucun volume externe** : bouton Éjecter grisé, aucun appel.

---

### Task 1: Vérifier l'éjection et l'Apple Event depuis la sandbox (exploration)

**Files:**
- Modify: `boringNotch/boringNotch.entitlements` (ajouter `com.apple.finder` au tableau
  `com.apple.security.temporary-exception.apple-events`)

- [ ] **Step 1:** Ajouter l'entitlement. Dans un bouton de debug temporaire (non committé) ou un `#if DEBUG` au lancement,
  appeler `NSWorkspace.shared.unmountAndEjectDevice(at:)` sur une clé USB / image disque montée (`hdiutil create -size 10m -fs APFS -volname BNTest /tmp/bntest.dmg && hdiutil attach /tmp/bntest.dmg`), et
  `NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&err)` avec une corbeille
  contenant un fichier de test.
- [ ] **Step 2:** Build signé, installer comme d'habitude (quitter avec `osascript -e 'tell application "Boring Notch" to quit'`,
  `ditto` vers `/Applications/Boring Notch.app`, `open`) et noter le résultat de chaque appel dans le rapport.
  Si l'éjection est refusée par la sandbox : utiliser le repli Finder (`tell application "Finder" to eject disk "<nom>"`)
  dans la tâche 2.
- [ ] **Step 3:** Retirer le code de debug ; commit de l'entitlement seul — `git commit -m "Réglages rapides : autorisation de piloter le Finder"`

### Task 2: Confirmation, éjection, corbeille et boutons

**Files:**
- Create: `boringNotch/modules/Activities/ConfirmGate.swift` (Foundation seul)
- Create: `boringNotch/modules/Activities/QuickActions.swift`
- Modify: `boringNotch/modules/Activities/FocusModule.swift` (`FocusView`, nouvelle colonne)
- Test: `scripts/quick-actions-selftest/main.swift`

**Interfaces:**
- Produces:
  ```swift
  struct ConfirmGate: Equatable {
      let window: TimeInterval          // 3
      private(set) var armedAt: Date?
      /// Premier appel : arme et renvoie false. Appel suivant dans la fenêtre : désarme et renvoie true.
      /// Après la fenêtre : ré-arme et renvoie false.
      mutating func press(at: Date) -> Bool
      func isArmed(at: Date) -> Bool
  }
  @MainActor final class QuickActions: ObservableObject {
      static let shared: QuickActions
      @Published private(set) var ejectable: [URL]
      @Published private(set) var failure: String?     // message affiché 2 s puis nil
      func refresh()
      func ejectAll()
      func emptyTrash()
  }
  ```

- [ ] **Step 1: Write the failing test:**
  ```swift
  let t0 = Date(timeIntervalSince1970: 0)
  var g = ConfirmGate(window: 3)
  check(g.press(at: t0) == false && g.isArmed(at: t0 + 1), "premier clic : arme seulement")
  check(g.press(at: t0 + 1) == true && !g.isArmed(at: t0 + 1), "second clic dans les 3 s : confirme")
  check(g.press(at: t0 + 10) == false, "nouveau premier clic")
  check(g.press(at: t0 + 13.5) == false && g.isArmed(at: t0 + 14), "après 3 s : ré-arme sans confirmer")
  check(!g.isArmed(at: t0 + 17), "désarmé après la fenêtre")
  ```
- [ ] **Step 2: Run** `swiftc boringNotch/modules/Activities/ConfirmGate.swift scripts/quick-actions-selftest/main.swift -o "$TMPDIR/quick-actions-selftest" && "$TMPDIR/quick-actions-selftest"` — expect compile failure.
- [ ] **Step 3: Implement `ConfirmGate`**, run the selftest, expect `OK`.
- [ ] **Step 4: Implement `QuickActions`** selon la spec : volumes via `mountedVolumeURLs` (éjectable ou amovible, jamais
  interne) ; `refresh()` à l'apparition de l'onglet et sur `didMount`/`didUnmount` ; `ejectAll()` éjecte chacun (méthode
  validée en tâche 1), collecte les échecs, `failure = "Impossible d'éjecter : <noms>"` ; `emptyTrash()` exécute l'Apple
  Event hors du main thread et met `failure` en cas d'erreur (`-1743` = autorisation refusée → message de la spec).
- [ ] **Step 5: Boutons dans `FocusView`.** Colonne de largeur ≈ 44 pt à droite de `AwakeTile`, deux boutons icône
  empilés, style `FocusTile`. Corbeille : `@State var gate = ConfirmGate(window: 3)` ; libellé « Confirmer ? » et teinte
  rouge tant que `gate.isArmed(at: now)` (le `TimelineView` de `FocusView` fournit `now`). Échec : bouton rouge 2 s,
  infobulle = `failure`. Réduire au besoin la largeur fixe des tuiles Pomodoro/Éveillé pour tenir.
- [ ] **Step 6: Build signé, installer, vérifier à la main** les quatre cas de la Review Focus (image disque de test,
  corbeille avec un fichier, autorisation refusée puis accordée dans Réglages Système).
- [ ] **Step 7: Commit** — `git commit -m "Réglages rapides : éjecter les disques et vider la corbeille depuis l'onglet Focus"`
