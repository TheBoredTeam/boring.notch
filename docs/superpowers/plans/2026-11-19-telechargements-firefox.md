# Téléchargements : taille et débit — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** afficher la taille reçue et le débit des téléchargements dont le pourcentage est inconnu (Firefox `.part`, Chrome `.crdownload`).

**Architecture:** une petite logique pure `DownloadRate` (Foundation seul, testée par auto-test `swiftc`) calcule le débit
lissé ; `DownloadMonitor` la nourrit à chaque passage (déjà toutes les secondes pendant un téléchargement) et la pastille
l'affiche.

**Tech Stack:** Swift 5 / SwiftUI, Foundation.

**Spec:** `docs/superpowers/specs/2026-11-19-telechargements-firefox-design.md`

## Global Constraints

- Partir de `main` du fork, branche `feature/telechargements-debit`.
- Textes en français ; commentaires en français, `ponytail:` pour une simplification assumée.
- Aucune nouvelle dépendance ; groupes Xcode synchronisés (rien dans `project.pbxproj`).
- Aucun pourcentage ni durée restante inventés.
- Build signé : `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -allowProvisioningUpdates DEVELOPMENT_TEAM=4JQGBGCKQM CODE_SIGN_IDENTITY="Apple Development" build` → `** BUILD SUCCEEDED **`.
- Commits terminés par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Fichier qui rétrécit ou est recréé** (reprise d'un téléchargement) : débit jamais négatif, mesure remise à zéro.
2. **Deux passages à la même seconde** (événement dossier + minuteur) : pas de division par zéro ni débit infini.
3. **Téléchargement en pause** : après 10 s sans croissance, « en pause » au lieu de « 0 o/s ».

---

### Task 1: Débit lissé et affichage

**Files:**
- Create: `boringNotch/modules/Activities/DownloadRate.swift`
- Modify: `boringNotch/modules/Activities/DownloadMonitor.swift` (`progress`, `scan()`, `activity(height:)`)
- Test: `scripts/downloads-selftest/main.swift`

**Interfaces:**
- Produces:
  ```swift
  struct DownloadRate: Equatable {
      private(set) var bytes: Int64 = 0
      /// Ajoute une mesure ; ignore un intervalle < 0,2 s ; taille plus petite = remise à zéro.
      mutating func sample(bytes: Int64, at: Date)
      /// Octets/s lissés sur les 3 derniers intervalles ; nil tant qu'il n'y a pas d'intervalle.
      var perSecond: Double? { get }
      /// Vrai si la taille n'a pas augmenté depuis au moins 10 s.
      func isPaused(now: Date) -> Bool
      /// « 12 Mo · 3,4 Mo/s », « 12 Mo · en pause », « 12 Mo » (sans débit encore).
      func label(now: Date) -> String
  }
  ```

- [ ] **Step 1: Write the failing test** (`scripts/downloads-selftest/main.swift`, en-tête comme `scripts/focus-selftest/main.swift`) :
  ```swift
  let t0 = Date(timeIntervalSince1970: 0)
  var r = DownloadRate()
  r.sample(bytes: 0, at: t0)
  check(r.perSecond == nil, "pas de débit avec une seule mesure")
  r.sample(bytes: 1_000_000, at: t0 + 1)
  check(r.perSecond == 1_000_000, "1 Mo en 1 s")
  r.sample(bytes: 1_000_500, at: t0 + 1.1)
  check(r.perSecond == 1_000_000, "intervalle < 0,2 s ignoré")
  r.sample(bytes: 3_000_000, at: t0 + 2); r.sample(bytes: 6_000_000, at: t0 + 3); r.sample(bytes: 10_000_000, at: t0 + 4)
  check(r.perSecond == 3_000_000, "moyenne des 3 derniers intervalles (2, 3, 4 Mo/s)")
  r.sample(bytes: 500, at: t0 + 5)
  check(r.perSecond == nil && r.bytes == 500, "taille plus petite = remise à zéro")
  var p = DownloadRate(); p.sample(bytes: 10, at: t0); p.sample(bytes: 10, at: t0 + 11)
  check(p.isPaused(now: t0 + 11) && p.label(now: t0 + 11).hasSuffix("en pause"), "pause après 10 s")
  check(r.label(now: t0 + 5).contains("·") == false, "sans débit : taille seule")
  ```
- [ ] **Step 2: Run** `swiftc boringNotch/modules/Activities/DownloadRate.swift scripts/downloads-selftest/main.swift -o "$TMPDIR/downloads-selftest" && "$TMPDIR/downloads-selftest"` — expect compile failure.
- [ ] **Step 3: Implement `DownloadRate`.** Tailles avec `ByteCountFormatter` (`countStyle = .file`), débit = taille formatée + « /s ».
- [ ] **Step 4: Run the selftest, expect `OK`.**
- [ ] **Step 5: Wire `DownloadMonitor`.** Garder un `[String: DownloadRate]` par nom temporaire ; à chaque `scan()`, pour
  une entrée sans fraction (`fraction(...) == nil`), lire la taille (`FileManager.attributesOfItem`, `.size`) et appeler
  `sample`. Retirer les entrées disparues. Dans `activity(height:)`, quand la fraction est inconnue : un seul
  téléchargement → `label(now:)` ; plusieurs → `"\(n) · " + débit total` (somme des `perSecond`). Texte tronqué
  (`lineLimit(1)`, largeur max ≈ 120 pt).
- [ ] **Step 6: Build**, expect `** BUILD SUCCEEDED **`. Vérification à la main : télécharger un gros fichier avec
  Firefox, la pastille montre la taille qui grossit et le débit.
- [ ] **Step 7: Commit** — `git commit -m "Téléchargements : taille reçue et débit quand le pourcentage est inconnu"`
