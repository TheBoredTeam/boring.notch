# Dictée : garde-fous contre le texte inventé — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** ne plus jamais coller de texte non prononcé (vocabulaire récité, ajouts du modèle de correction, prise muette).

**Architecture :** les règles pures vivent dans un nouveau fichier Foundation seul, `DictationGuards.swift`, vérifié par un
auto-test `swiftc` ; `TextCleanup` et `Dictation` les appellent. Aucune dépendance ajoutée.

**Tech Stack :** Swift / SwiftUI macOS 26, `Defaults`, `FoundationModels`, `Speech`.

**Spec :** `docs/superpowers/specs/2026-11-16-dictation-guards-design.md`

## Global Constraints

- Aucune nouvelle dépendance. Dossiers `boringNotch/` synchronisés par Xcode : pas d'édition du `.pbxproj`.
- Commentaires et messages en français ; raccourcis assumés marqués `// ponytail:`.
- Seuils pinnés par la spec : récitation = au moins 2 termes du vocabulaire couvrant au moins 50 % des mots ;
  ajouts = moins de 75 % des mots de la sortie présents dans l'entrée → rejet ; silence = RMS max < −50 dBFS (0,00316).
- Les commandes sur la sélection (`TextCleanup.command`) ne subissent pas le refus des ajouts.
- Compilation : `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build` → `** BUILD SUCCEEDED **`.

## Review Focus

1. Phrase qui cite vraiment deux clients (« J'ai appelé Qonto puis Hostinger ce matin ») → gardée (couverture < 50 %). Test Task 1.
2. Correction qui ne fait qu'accorder / ponctuer → acceptée (pas comptée comme ajout). Test Task 1.
3. Terme du vocabulaire dit en minuscules ou sans accent (« qonto ») puis corrigé en « Qonto » par le modèle → accepté (pas un ajout). Test Task 1.
4. Voix faible mais réelle (≈ −40 dBFS) → collée. Seuil en dur, réglable plus tard (`ponytail:`). Vérif manuelle Task 3.
5. Vocabulaire vide → aucune règle de vocabulaire ne s'applique, le reste inchangé. Test Task 1.

Plafond connu : une liste récitée collée sur la même ligne qu'une vraie phrase, produite par la reconnaissance (pas par le
modèle), n'est pas retirée. Le découpage se fait par ligne.

---

### Task 1 : règles pures + auto-test

**Files :**
- Create : `boringNotch/modules/Dictation/DictationGuards.swift`
- Create : `scripts/dictation-selftest/main.swift`
- Modify : `boringNotch/modules/Dictation/TextCleanup.swift` (déplacer `retained` vers `DictationGuards`)

**Interfaces :**
- Produces :
  - `enum DictationGuards`
  - `static let silenceRMS: Float = 0.00316` (−50 dBFS)
  - `static func retained(_ output: String, of input: String) -> Double`, déplacée telle quelle depuis `TextCleanup` ;
    `TextCleanup.plausible` l'appelle désormais.
  - `static func dropRecitation(_ text: String, vocabulary: [String]) -> String` : retire chaque ligne (`\n`) où les
    occurrences de termes sont ≥ 2 et couvrent ≥ 50 % des mots de la ligne.
  - `static func addsVocabulary(_ output: String, to input: String, vocabulary: [String]) -> Bool` : vrai si un terme
    apparaît dans `output` et pas dans `input`.
  - Correspondance d'un terme : mot entier (`(?<![\p{L}\p{N}])…(?![\p{L}\p{N}])`), insensible à la casse et aux accents.
    Un terme de plusieurs mots couvre tous ses mots.

- [ ] **Step 1 : écrire l'auto-test** `scripts/dictation-selftest/main.swift`. En-tête comme `scripts/clipboard-selftest/main.swift`
  (ligne de commande `swiftc boringNotch/modules/Dictation/DictationGuards.swift scripts/dictation-selftest/main.swift -o "$TMPDIR/dictation-selftest" && "$TMPDIR/dictation-selftest"`), avec `check(_:_:)` et ces assertions :

```swift
let vocab = ["Nillor", "Qonto", "Edelweiss", "culottes courtes", "Hostinger", "Rotowash", "HELEBOR", "TAILSCALE", "YOTO"]
let said = "Je voudrais optimiser la prise de notes. Les rendus ne sont pas toujours réels."
let capture = said + "\n\nNillor, Qonto, Edelweiss, culottes courtes, Edelweiss, Hostinger, Rotowash, HELEBOR, Et culottes courtes, TAILSCALE, —-arr, YOTO.."
check(G.dropRecitation(capture, vocabulary: vocab).trimmingCharacters(in: .whitespacesAndNewlines) == said, "liste récitée retirée")
check(G.dropRecitation("J'ai appelé Qonto puis Hostinger ce matin pour le contrat.", vocabulary: vocab) == "J'ai appelé Qonto puis Hostinger ce matin pour le contrat.", "vraie phrase avec deux clients gardée")
check(G.dropRecitation("Qonto", vocabulary: vocab) == "Qonto", "un seul terme : gardé")
check(G.dropRecitation(capture, vocabulary: []) == capture, "vocabulaire vide : rien ne change")
check(G.addsVocabulary(capture, to: said, vocabulary: vocab), "liste ajoutée par le modèle détectée")
check(!G.addsVocabulary("Paiement Qonto reçu.", to: "paiement qonto reçu", vocabulary: vocab), "terme dit puis capitalisé : pas un ajout")
check(G.retained(said, of: capture) < 0.75, "mesure inverse : la sortie contient trop de mots nouveaux")
check(G.retained("Les enfants sont arrivés.", of: "les enfant sont arrivé") >= 0.75, "accords corrigés : pas des ajouts")
print("OK")
```
  (`typealias G = DictationGuards` en tête.)

- [ ] **Step 2 : lancer, constater l'échec** : la commande ci-dessus → erreur de compilation, `DictationGuards.swift` absent.
- [ ] **Step 3 : implémenter `DictationGuards.swift`** (Foundation seul) selon les Interfaces ; déplacer `retained` et
  remplacer son appel dans `TextCleanup.plausible`.
- [ ] **Step 4 : relancer l'auto-test** → `OK`.
- [ ] **Step 5 : commit** `Dictée : règles anti-récitation et anti-ajout, avec auto-test`.

### Task 2 : brancher les règles dans le nettoyage

**Files :**
- Modify : `boringNotch/modules/Dictation/TextCleanup.swift` (`warmSession`, `cleanChunk`, `llm`, `plausible`, `command`)

**Interfaces :**
- Consumes : `DictationGuards.dropRecitation`, `addsVocabulary`, `retained` (Task 1) ; `TextCleanup.vocabulary()` existant.
- Produces : `plausible(_:for:ratio:keep:fresh:)` avec `fresh: Double = 0.75` = part minimale des mots de la sortie
  présents dans l'entrée (`retained(input, of: output) >= fresh`). `command` passe `fresh: 0`.

- [ ] **Step 1 : `cleanChunk`** : appliquer `dropRecitation(_, vocabulary: vocabulary())` au segment brut, avant `spoken`.
- [ ] **Step 2 : `llm`** : rejeter la sortie (garder le segment) si `addsVocabulary(out, to: text, vocabulary: vocabulary())` ; log comme le rejet existant.
- [ ] **Step 3 : `plausible`** : ajouter le paramètre `fresh` ; `command` passe `fresh: 0`.
- [ ] **Step 4 : consigne de `warmSession`** : remplacer `"\nOrthographe à respecter : " + …` par
  `"\nSi l'un de ces mots apparaît mal écrit dans le texte, écris-le ainsi : " + liste + ". N'ajoute jamais ces mots s'ils ne sont pas dans le texte."`
- [ ] **Step 5 : compiler** (commande des Global Constraints) → `** BUILD SUCCEEDED **` ; relancer l'auto-test → `OK`.
- [ ] **Step 6 : commit** `Dictée : la correction ne peut plus ajouter de mots ni réciter le vocabulaire`.

### Task 3 : filtre de silence

**Files :**
- Modify : `boringNotch/modules/Dictation/Dictation.swift` (`LevelMeter`, `MicCapture.captureOutput`, `stop()`)

**Interfaces :**
- Consumes : `DictationGuards.silenceRMS` (Task 1).
- Produces : `LevelMeter.peak: Float` (RMS brut maximal depuis `reset()`), mis à jour par `push(_ x: Float, rms: Float)`.

- [ ] **Step 1 : `LevelMeter`** : ajouter `peak`, remis à 0 dans `reset()`. `captureOutput` passe le RMS brut (avant le gain visuel ×6).
- [ ] **Step 2 : `stop()`** : juste après `TextCleanup.finish(pieces)`, si `meter.peak < DictationGuards.silenceRMS`,
  vider `text` et loguer `prise muette (pic … dBFS) : rien collé`. Rien n'est collé, rien n'entre dans l'historique, pas de
  commande sur la sélection. Commentaire `// ponytail: seuil −50 dBFS en dur (Hex) ; réglage si un micro faible est jeté.`
- [ ] **Step 3 : compiler** → `** BUILD SUCCEEDED **`.
- [ ] **Step 4 : vérification manuelle** (app signée et installée, voir la mémoire « Relaunch app signed ») :
  maintenir le raccourci 3 s sans parler → rien n'est collé ; parler doucement → texte collé ; dicter une phrase
  longue (≥ 2 lignes) → pas de liste de clients en fin.
- [ ] **Step 5 : commit** `Dictée : une prise muette ne colle plus rien`.
