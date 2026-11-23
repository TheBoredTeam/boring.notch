# Inspirations Oriel — Spotify Connect, Codex pas à pas, Focus (minuteur + Pomodoro + rester éveillé) — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** reprendre trois idées d'Oriel 3.0 dans le fork : voir/déplacer la lecture Spotify vers un autre appareil, suivre Codex outil par outil comme Claude Code, et un onglet « Focus » qui réunit minuteur, Pomodoro et « Rester éveillé ».

**Architecture :** trois chantiers indépendants, fichiers disjoints, exécutables en parallèle (un agent par tâche, worktrees séparés). Chaque chantier isole sa logique pure dans un fichier Foundation-only testé par un auto-test `swiftc` (convention de `scripts/sonos-selftest/`) ou un auto-test shell ; l'UI s'appuie sur l'existant (`UpNextPanelView`, `AgentStore`, `ActivityPill`, `NotchModule`). Les dossiers `boringNotch/` sont synchronisés par Xcode : aucune édition du `.pbxproj`.

**Tech Stack :** Swift / SwiftUI macOS, `Defaults`, `URLSession`, IOKit (`IOPMAssertion`), Python 3 système dans le hook Codex.

**Spec :** pas de spec séparée — décisions prises dans la conversation du 2026-11-04 (analyse d'Oriel). Backlog des idées écartées : `docs/idees-futures.md`.

## Global Constraints

- Aucune nouvelle dépendance (SPM ou autre).
- Hors périmètre : textos, appels, écran verrouillé, widgets, Shazam, ajout d'événement en langage naturel (→ `docs/idees-futures.md`). Les rappels cochables existent déjà (`ReminderToggle`), on n'y touche pas.
- Textes d'interface en français, ton des écrans existants.
- Le dépôt a des modifications non commitées (`components/Calendar/BoringCalendar.swift`) : chaque commit ajoute **uniquement** les chemins de sa tâche (`git add <chemins>`, jamais `git add -A`).
- Ne pas réactiver Sparkle ; ne pas toucher à l'OAuth existant hormis l'ajout du scope.
- Build de vérification : `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5` → `** BUILD SUCCEEDED **`.
- Relance pour essai manuel : build signé équipe `4JQGBGCKQM`, installé dans `/Applications` (une signature ad hoc perd les permissions).

## Review Focus

1. **Spotify connecté avant l'ajout du scope** : `GET /me/player/devices` marche mais `PUT /me/player` répond 403 ; le transfert doit échouer sans planter, `lastError` renseigné, et les Réglages invitent à se reconnecter. → vérif. manuelle (Tâche 1, step 7).
2. **Lecture sur ce Mac** : aucune ligne « Lecture sur … » ne doit apparaître ; et si Sonos est actif, la ligne Sonos l'emporte (pas deux lignes). → test `remoteActive` avec l'appareil local actif (Tâche 1).
3. **Appareil restreint ou sans id** (enceinte non pilotable, `is_restricted: true` / `id: null`) : absent du menu de transfert. → test `controllable` (Tâche 1).
4. **Hook Codex face à une entrée invalide ou un événement inconnu** : sortie 0, rien sur stdout, Codex jamais bloqué ni ralenti (pas de lecture du transcript sur chaque outil). → test fixture « garbage » et fixture PreToolUse sans `transcript_path` (Tâche 2).
5. **Pomodoro interrompu** : « Arrêter » pendant une pause stoppe tout le cycle ; lancer un minuteur simple pendant un Pomodoro remplace le Pomodoro ; le cycle suivant repart au tour 1. → test `FocusCycle.next` + vérif. manuelle (Tâche 3).

---

### Task 1 : Spotify Connect — où ça joue, et déplacer la lecture

**Files :**
- Create : `boringNotch/modules/Spotify/SpotifyConnect.swift` (Foundation seulement)
- Create : `scripts/spotify-selftest/main.swift`
- Modify : `boringNotch/modules/Spotify/SpotifyWebAPI.swift` (scope, `call` avec corps, `devices()`, `transfer(to:)`)
- Modify : `boringNotch/modules/Spotify/UpNextPanelView.swift` (ligne d'appareil)

**Interfaces — Produces :**
```swift
struct SpotifyDevice: Decodable, Equatable, Identifiable {
    let id: String?; let name: String; let type: String   // "Computer", "Smartphone", "Speaker"…
    let is_active: Bool; let is_restricted: Bool
}
enum SpotifyConnect {
    static func decode(_ data: Data) -> [SpotifyDevice]?            // {"devices":[…]}
    static func controllable(_ d: [SpotifyDevice]) -> [SpotifyDevice] // id != nil && !is_restricted
    static func remoteActive(_ d: [SpotifyDevice], localName: String) -> SpotifyDevice? // actif ET nom ≠ localName (insensible casse/accents)
    static func symbol(for type: String) -> String                  // "Smartphone"→"iphone", "Speaker"→"hifispeaker", "Computer"→"laptopcomputer", défaut "speaker.wave.2"
}
// SpotifyWebAPI
func devices() async -> [SpotifyDevice]?          // nil si non connecté / erreur
func transfer(to deviceID: String) async -> Bool   // PUT me/player {"device_ids":[id],"play":true}
```

- [ ] **Step 1 : écrire `scripts/spotify-selftest/main.swift`** (asserts, imprime `OK`). Cas :
  - `decode` d'un JSON à 3 appareils (`"MacBook de Côme"` Computer actif, `"iPhone"` Smartphone, `"Cuisine"` Speaker `is_restricted: true`) → 3 éléments ; `decode(Data("{}".utf8))` → `nil`.
  - `controllable` → exclut `Cuisine` et tout appareil `id: null`.
  - `remoteActive(…, localName: "macbook de come")` → `nil` (actif = local, accents/casse ignorés) ; même liste avec `iPhone` actif → `iPhone`.
  - `symbol(for: "Smartphone") == "iphone"`, `symbol(for: "TV") == "speaker.wave.2"`.
- [ ] **Step 2 : lancer, constater l'échec** — `swiftc boringNotch/modules/Spotify/SpotifyConnect.swift scripts/spotify-selftest/main.swift -o "$TMPDIR/spotify-selftest" && "$TMPDIR/spotify-selftest"` → erreur de compilation (types absents).
- [ ] **Step 3 : implémenter `SpotifyConnect.swift`** selon l'interface. Comparaison de noms : `compare(_, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame`.
- [ ] **Step 4 : relancer** → `OK`.
- [ ] **Step 5 : `SpotifyWebAPI`** — ajouter `user-modify-playback-state` à `scopes` ; ajouter un paramètre `body: Data? = nil` à `call` (pose `Content-Type: application/json` quand présent, transmis au retry 401) ; `devices()` = `call("GET", "me/player/devices")` + `SpotifyConnect.decode` ; `transfer(to:)` = `call("PUT", "me/player", body:)` != nil (204 → `Data()` vide, donc succès).
- [ ] **Step 6 : `UpNextPanelView`** — `@State private var devices: [SpotifyDevice] = []`, rechargés dans `load()` avec la file. Quand `!sonos.isActive` :
  - si `remoteActive(devices, localName: Host.current().localizedName ?? "")` existe : ligne en bas (même gabarit que `sonosLine`) « Lecture sur <nom> » avec `symbol(for:)`, et un `Menu` listant `controllable(devices)` (« Ce Mac » = l'appareil au nom local) ;
  - sinon, si `controllable(devices).count > 1` : seulement un petit bouton `Menu` icône `hifispeaker.2` dans la même ligne, sans texte.
  - Choisir un appareil → `transfer(to:)`, puis `load()` après 1 s.
- [ ] **Step 7 : build** (commande des Global Constraints) → `BUILD SUCCEEDED`. Vérif. manuelle par l'utilisateur : se reconnecter à Spotify dans Réglages (nouveau scope), lancer la lecture sur l'iPhone → la ligne « Lecture sur iPhone » apparaît ; « Ce Mac » ramène la lecture ; avec l'ancien jeton, le transfert échoue proprement (Review Focus 1).
- [ ] **Step 8 : commit**
```bash
git add boringNotch/modules/Spotify/SpotifyConnect.swift scripts/spotify-selftest/main.swift boringNotch/modules/Spotify/SpotifyWebAPI.swift boringNotch/modules/Spotify/UpNextPanelView.swift
git commit -m "Spotify : appareil de lecture affiché et transfert Spotify Connect depuis le lecteur"
```

---

### Task 2 : Codex pas à pas (outils et validations)

Aujourd'hui `scripts/codex-hook.sh` n'est branché (dans `~/.codex/hooks.json`) que sur `SessionStart`, `UserPromptSubmit`, `Stop` : la session apparaît, mais aucune étape. `AgentStore.apply` sait déjà traiter `PreToolUse` / `PostToolUse` / `PermissionRequest` au format Claude Code ; on normalise donc côté hook (ponytail : un seul décodeur côté Swift, aucune modif Swift prévue).

**Files :**
- Modify : `scripts/codex-hook.sh` (normalisation + limites lues seulement hors événements d'outil + mode `BN_DRY`)
- Create : `scripts/codex-hook-selftest/run.sh` + fixtures `scripts/codex-hook-selftest/*.json`
- Hors dépôt (étape manuelle, après sauvegarde) : `~/.codex/hooks.json`

**Interfaces :**
- Consumes : format attendu par `AgentEnvelope.Payload` (`AgentSession.swift`) : `session_id`, `hook_event_name`, `cwd`, `tool_name`, `tool_use_id`, `tool_input.{command,file_path,description}`.
- Produces : `BN_DRY=1 scripts/codex-hook.sh < payload.json` imprime sur stdout les lignes JSON qui auraient été envoyées au socket (une par envoi), au lieu de les envoyer.

- [ ] **Step 1 : relevé terrain des événements Codex 0.166.** Sauvegarder `cp ~/.codex/hooks.json ~/.codex/hooks.json.bak-$(date +%Y%m%d)`, ajouter temporairement pour `PreToolUse`, `PostToolUse` et `PermissionRequest` un hook `cat >> "$TMPDIR/codex-events.jsonl"`, lancer `codex exec "liste les fichiers puis crée /tmp/bn-test.txt"` dans un dossier jetable (Codex demande d'approuver les nouveaux hooks : accepter). Noter quels événements arrivent et leurs champs ; copier un exemple de chaque dans `scripts/codex-hook-selftest/` (`pre.json`, `post.json`, `permission.json` si l'événement existe, `patch.json` pour un `apply_patch`). **Si aucun événement d'outil n'existe dans cette version : arrêter la tâche et le signaler** (pas de contournement par lecture du transcript).
- [ ] **Step 2 : écrire `scripts/codex-hook-selftest/run.sh`** : pour chaque fixture, `BN_DRY=1 sh scripts/codex-hook.sh < fixture | python3 -c …` et vérifie :
  - `pre.json` → une seule ligne, `payload.hook_event_name == "PreToolUse"`, `payload.tool_use_id` non vide, `tool_name` présent ; **aucune** ligne `kind: statusline` (pas de lecture du transcript sur un outil).
  - `patch.json` → `tool_name == "Edit"`, `tool_input.file_path` = premier chemin `*** Update File:` / `*** Add File:` du patch.
  - `printf 'pas du json' | BN_DRY=1 sh scripts/codex-hook.sh` → code 0, stdout vide.
  - Imprime `OK`.
- [ ] **Step 3 : lancer, constater l'échec** — `sh scripts/codex-hook-selftest/run.sh` → échec (pas de `BN_DRY`, pas de normalisation).
- [ ] **Step 4 : modifier `codex-hook.sh`** :
  - `BN_DRY=1` → `send` imprime au lieu d'envoyer ;
  - `normalize(p) -> dict` : renomme les champs Codex relevés au Step 1 vers les noms Claude ci-dessus ; un appel `apply_patch` devient `tool_name: "Edit"` + `file_path` extrait du patch ; un shell devient `tool_name: "Bash"` + `tool_input.command` (chaîne, liste jointe par espaces) ;
  - lecture du transcript (`rate_limits`) seulement pour `SessionStart`, `UserPromptSubmit`, `Stop`.
- [ ] **Step 5 : relancer** → `OK`.
- [ ] **Step 6 : brancher pour de bon** — dans `~/.codex/hooks.json`, remplacer les hooks temporaires par `scripts/codex-hook.sh` sur `PreToolUse`, `PostToolUse` (et `PermissionRequest` s'il existe), à côté des entrées existantes (ne pas toucher aux entrées `notchi-codex-hook.sh`). Vérif. manuelle : une session Codex affiche ses étapes dans l'onglet Agents, et le `!` rouge si une validation est demandée.
- [ ] **Step 7 : commit**
```bash
git add scripts/codex-hook.sh scripts/codex-hook-selftest
git commit -m "Agents : Codex suivi outil par outil (hooks PreToolUse/PostToolUse normalisés)"
```

---

### Task 3 : Onglet Focus — minuteur, Pomodoro, rester éveillé

Aujourd'hui minuteur et « Rester éveillé » ne se règlent que depuis la barre des menus (préréglages fixes). On ajoute un onglet du notch qui les réunit, et un mode Pomodoro : focus → pause courte, une pause longue tous les 4 focus, enchaînement automatique avec le son de fin à chaque changement.

**Files :**
- Create : `boringNotch/modules/Activities/FocusCycle.swift` (Foundation seulement)
- Create : `scripts/focus-selftest/main.swift`
- Create : `boringNotch/modules/Activities/FocusModule.swift` (module + vue de l'onglet)
- Modify : `boringNotch/modules/Activities/NotchTimer.swift` (mode Pomodoro, pastille par phase)
- Modify : `boringNotch/modules/NotchModule.swift` (ajout de `FocusModule()` à `NotchModules.all`, après `CalendarModule()`)
- Modify : `boringNotch/models/Constants.swift` (clés Defaults)
- Modify : `boringNotch/modules/Activities/ActivitiesSettings.swift` (durées Pomodoro)

**Interfaces — Produces :**
```swift
enum FocusPhase: Equatable { case focus(round: Int), shortBreak(round: Int), longBreak }
enum FocusCycle {
    static func next(after: FocusPhase, longEvery: Int) -> FocusPhase
    static func minutes(_ p: FocusPhase, focus: Int, short: Int, long: Int) -> Int
}
// NotchTimer (existant, étendu)
@Published private(set) var phase: FocusPhase?      // nil = minuteur simple
func start(minutes: Int)                             // inchangé ; annule un Pomodoro en cours (phase = nil)
func startPomodoro()                                 // phase = .focus(round: 1)
func stop()                                          // arrête tout, phase = nil
// Defaults (Constants.swift)
pomodoroFocusMinutes = 25, pomodoroShortMinutes = 5, pomodoroLongMinutes = 15, pomodoroLongEvery = 4
```

- [ ] **Step 1 : écrire `scripts/focus-selftest/main.swift`** (asserts, imprime `OK`) :
  - `next(after: .focus(round: 1), longEvery: 4) == .shortBreak(round: 1)` ; `next(after: .shortBreak(round: 1), longEvery: 4) == .focus(round: 2)` ;
  - `next(after: .focus(round: 4), longEvery: 4) == .longBreak` ; `next(after: .longBreak, longEvery: 4) == .focus(round: 1)` ;
  - `longEvery: 1` : `next(after: .focus(round: 1), longEvery: 1) == .longBreak` ;
  - `minutes(.shortBreak(round: 2), focus: 25, short: 5, long: 15) == 5`, `minutes(.longBreak, …) == 15`.
- [ ] **Step 2 : lancer, constater l'échec** — `swiftc boringNotch/modules/Activities/FocusCycle.swift scripts/focus-selftest/main.swift -o "$TMPDIR/focus-selftest" && "$TMPDIR/focus-selftest"` → erreur de compilation.
- [ ] **Step 3 : implémenter `FocusCycle.swift`** → relancer → `OK`.
- [ ] **Step 4 : `NotchTimer`** — `finish()` : si `phase != nil`, joue le son, passe à `FocusCycle.next` et relance avec ses minutes (lues dans Defaults) au lieu de l'état « Terminé ». Pastille : focus = `brain.head.profile` orange, pauses = `cup.and.saucer` vert, aide « Pomodoro — focus 2/4 — cliquer pour arrêter ». `TimerMenu` gagne une entrée « Pomodoro ».
- [ ] **Step 5 : `FocusModule`** (`id "focus"`, `label "Focus"`, `icon "timer"`) — trois blocs empilés, même style que les autres onglets :
  - **Minuteur** : temps restant si actif, sinon puces des `NotchTimer.presets` + `Slider` 1–120 min (pas 1) avec bouton « Lancer » ; « Arrêter » si actif.
  - **Pomodoro** : bouton « Démarrer » / phase en cours + tour (`2/4`) + « Arrêter ».
  - **Rester éveillé** : 1 h / 2 h / 4 h / Indéfiniment, `Defaults.Toggle("Garder l'écran allumé", key: .stayAwakeDisplay)`, temps restant + « Arrêter » si actif.
- [ ] **Step 6 : `ActivitiesSettings`** — section « Pomodoro » : quatre `Stepper` sur les clés Defaults (focus 5–90, courte 1–30, longue 5–60, longue tous les 2–8).
- [ ] **Step 7 : build** → `BUILD SUCCEEDED`. Vérif. manuelle (durées réduites à 1 min dans les Réglages) : focus → son → pause → son → focus 2 ; « Arrêter » pendant une pause stoppe tout ; « Lancer » un minuteur simple pendant un Pomodoro le remplace (Review Focus 5) ; Rester éveillé depuis l'onglet → `pmset -g assertions | grep "Boring Notch"` affiche l'assertion.
- [ ] **Step 8 : commit**
```bash
git add boringNotch/modules/Activities/FocusCycle.swift scripts/focus-selftest/main.swift boringNotch/modules/Activities/FocusModule.swift boringNotch/modules/Activities/NotchTimer.swift boringNotch/modules/NotchModule.swift boringNotch/models/Constants.swift boringNotch/modules/Activities/ActivitiesSettings.swift
git commit -m "Focus : onglet minuteur, Pomodoro et rester éveillé dans le notch"
```

---

## Ordre et parallélisme

Les trois tâches touchent des fichiers disjoints : elles peuvent tourner en parallèle (un agent par tâche, worktree isolé), puis une revue de branche globale. Seule la Tâche 2 dépend d'un relevé terrain (Step 1) et peut s'arrêter tôt si Codex 0.166 n'expose pas d'événements d'outil.
