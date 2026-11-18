# Agents : suivi multi-sessions — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dans l'onglet Agents, reconnaître chaque session (« Projet · Sujet »), ne jamais valider la mauvaise, voir où en
est le tour en cours, et une page Stats (valeur API, modèles, projets, grille d'activité).

**Architecture:** la logique pure vit dans des fichiers Foundation seuls (`AgentRequests.swift`, `AgentTurn.swift`,
`AgentStats.swift`), testés par un auto-test `swiftc` comme `scripts/focus-selftest`. `AgentStore` les branche sur les
événements du socket ; `AgentsView` et un nouveau `AgentStatsView.swift` les affichent. Le titre des fils Delta est
ajouté par le script de hook (hors sandbox) ; les journaux `~/.claude/projects` sont lus par l'app grâce à une exception
de sandbox en lecture seule.

**Tech Stack:** Swift 5 / SwiftUI, macOS, Foundation seul pour la logique, `sh` + `/usr/bin/python3` pour les hooks.

**Spec:** `docs/superpowers/specs/2026-11-18-agents-suivi-design.md`

## Global Constraints

- Hauteur du notch ouvert fixe (190 pt, barre d'onglets comprise) : rien ne déborde, on tronque.
- Aucune barre ni durée restante inventée. La barre « x / n tâches » n'existe que si l'agent a une liste de tâches.
- Textes d'interface en français, comme le reste de l'onglet. « valeur API », jamais « facture » ni « coût ».
- Aucune nouvelle dépendance (ni paquet Swift, ni outil externe à part `delta` déjà installé, appelé par le hook).
- Commentaires dans le style du fichier (français, `ponytail:` pour une simplification assumée et son plafond).
- Nouveaux fichiers : le projet Xcode utilise des groupes synchronisés, rien à ajouter dans `project.pbxproj`.
- Build signé (sinon perte des permissions TCC) :
  `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -allowProvisioningUpdates DEVELOPMENT_TEAM=4JQGBGCKQM CODE_SIGN_IDENTITY="Apple Development" build`
- Auto-test unique de ce chantier : `scripts/agents-suivi-selftest/main.swift`, lancé par
  `swiftc boringNotch/modules/Agents/AgentSession.swift boringNotch/modules/Agents/PermissionAsk.swift boringNotch/modules/Agents/AgentRequests.swift boringNotch/modules/Agents/AgentTurn.swift boringNotch/modules/Agents/AgentStats.swift scripts/agents-suivi-selftest/main.swift -o "$TMPDIR/agents-suivi-selftest" && "$TMPDIR/agents-suivi-selftest"`
  (affiche `OK`, sinon `FAIL: …` et code 1). Chaque tâche ajoute ses `check(...)` ; tant qu'un fichier n'existe pas,
  retirer son chemin de la commande.

## Review Focus

1. **Deux validations de la même session** (sous-agents parallèles) : les deux restent en file, aucune n'efface l'autre,
   l'une répondue libère seulement la sienne. → test dans la tâche 1.
2. **Validation refusée au terminal** : aucun `PostToolUse` ne vient ; la demande doit tomber au prochain
   `UserPromptSubmit`/`Stop`/`SessionEnd` de la session, ou après 600 s (délai du hook). → test dans la tâche 1.
3. **Lignes dupliquées dans les journaux** : Claude Code écrit une ligne par bloc de contenu avec le même `message.id` et
   le même `usage` ; compter une seule fois. → test dans la tâche 5.
4. **Lignes illisibles ou fichier en cours d'écriture** (dernière ligne sans `\n`) : ignorées sans planter, relues
   complètes au passage suivant. → test dans la tâche 5.
5. **Tour très long** (centaines d'actions) : la bande reste à largeur fixe (regroupement en tranches), pas de
   croissance mémoire sans borne (ticks plafonnés). → test dans la tâche 2.

---

### Task 1: File des demandes en attente, par demande

**Files:**
- Create: `boringNotch/modules/Agents/AgentRequests.swift`
- Modify: `boringNotch/modules/Agents/AgentStore.swift` (`responders`, `decide`, `answer`, `respond`, `apply` l. 94-163)
- Modify: `boringNotch/modules/Agents/AgentSession.swift` (retirer `ask`, `questions`, `plan`, `canAnswer` de `AgentSession` ;
  ils passent dans `PendingRequest`)
- Modify: `boringNotch/modules/Agents/AgentsView.swift` (`prompting`, `QuestionCard`, `PermissionCard`, `PlanCard`)
- Test: `scripts/agents-suivi-selftest/main.swift`

**Interfaces:**
- Produces:
  ```swift
  struct PendingRequest: Identifiable, Equatable {
      let id: String            // UUID généré par l'app
      let sessionID: String
      let tool: String
      let toolUseID: String?    // si le payload PermissionRequest en a un
      var ask: PermissionAsk?
      var questions: [AgentQuestion]?
      var plan: String?
      var canAnswer: Bool
      let at: Date
  }
  struct RequestQueue: Equatable {
      private(set) var items: [PendingRequest] = []     // ordre d'arrivée
      var current: PendingRequest? { get }              // items.first
      mutating func add(_ r: PendingRequest)
      mutating func remove(id: String) -> PendingRequest?
      /// Retire les demandes traitées ailleurs ; renvoie leurs ids (pour libérer les hooks).
      mutating func resolve(session: String, event: String, tool: String?, toolUseID: String?) -> [String]
      mutating func expire(now: Date, after: TimeInterval) -> [String]
      func pending(in session: String) -> Bool
  }
  // AgentStore
  @Published private(set) var queue: RequestQueue
  func decide(_ requestID: String, allow: Bool)
  func answer(_ requestID: String, _ answers: [String: String])
  ```

- [ ] **Step 1: Write the failing test** — dans `main.swift` (même en-tête `check` que `scripts/focus-selftest/main.swift`) :
  ```swift
  func req(_ id: String, _ s: String, _ tool: String, _ tu: String? = nil, _ at: Double = 0) -> PendingRequest {
      PendingRequest(id: id, sessionID: s, tool: tool, toolUseID: tu, canAnswer: true, at: Date(timeIntervalSince1970: at))
  }
  var q = RequestQueue()
  q.add(req("a", "S1", "Bash")); q.add(req("b", "S2", "Edit")); q.add(req("c", "S1", "Write"))
  check(q.current?.id == "a", "FIFO : la première arrivée reste affichée")
  check(q.resolve(session: "S1", event: "PreToolUse", tool: "Read", toolUseID: nil).isEmpty, "un PreToolUse voisin n'efface rien")
  check(q.resolve(session: "S1", event: "PostToolUse", tool: "Write", toolUseID: nil) == ["c"], "PostToolUse libère la demande du même outil")
  check(q.items.map(\.id) == ["a", "b"], "la demande sœur reste")
  q.add(req("d", "S3", "Bash", "tu1"))
  check(q.resolve(session: "S3", event: "PostToolUse", tool: "Bash", toolUseID: "tu2").isEmpty, "autre tool_use_id : rien")
  check(q.resolve(session: "S3", event: "PostToolUse", tool: "Bash", toolUseID: "tu1") == ["d"], "même tool_use_id : libérée")
  check(q.resolve(session: "S1", event: "Stop", tool: nil, toolUseID: nil) == ["a"], "Stop libère toute la session")
  check(q.remove(id: "b")?.id == "b" && q.current == nil, "réponse depuis le notch")
  q.add(req("e", "S4", "Bash", nil, 0))
  check(q.expire(now: Date(timeIntervalSince1970: 601), after: 600) == ["e"], "délai du hook dépassé")
  ```
- [ ] **Step 2: Run it, expect a compile failure** (`PendingRequest` inconnu) with the selftest command (sans `AgentTurn.swift` ni `AgentStats.swift`).
- [ ] **Step 3: Implement `AgentRequests.swift`.** `resolve` : `PostToolUse` retire la première demande de la session dont
  `toolUseID` égale celui reçu, ou, si la demande n'a pas de `toolUseID`, la première du même `tool` ;
  `UserPromptSubmit`, `Stop`, `SessionEnd` retirent toutes celles de la session ; tout autre événement ne retire rien.
- [ ] **Step 4: Run the selftest, expect `OK`.**
- [ ] **Step 5: Wire `AgentStore`.** `responders: [String: (String?) -> Void]` indexé par `PendingRequest.id`.
  `PermissionRequest` crée la demande (mêmes règles qu'aujourd'hui pour `ask` / `questions` / `plan` / `canAnswer`) et
  l'ajoute à `queue`, son et état `.waiting` inchangés. Les autres événements appellent `queue.resolve(...)` et libèrent
  (`responders.removeValue(forKey:)?(nil)`) chaque id renvoyé, à la place de la ligne 134. `respond` retire la demande
  de la file. La session reste `.waiting` tant que `queue.pending(in:)` ; sinon `.thinking`. `expire(after: 600)` appelé
  à chaque événement. Tout ce qui lisait `state == .waiting` (pastille, `focusSession`, `needsAttention`) continue de
  marcher sans changement.
- [ ] **Step 6: Cartes.** `prompting` devient `store.queue.current` (+ sa session). Les trois cartes prennent
  `(session: AgentSession, request: PendingRequest)` et appellent `decide(request.id, …)` / `answer(request.id, …)`.
  Quand `queue.items.count > 1`, la carte affiche « 1 / N en attente » à droite de son en-tête (taille 10, `secondary`).
- [ ] **Step 7: Armement des boutons.** Les boutons de décision (Autoriser, Refuser, Approuver, options de question) sont
  désactivés et estompés (opacité 0.4) pendant **0,6 s** après l'apparition de la carte ou un changement de
  `request.id` (`.task(id: request.id) { armed = false; try? await Task.sleep(for: .milliseconds(600)); armed = true }`).
- [ ] **Step 8: Build** (commande des contraintes globales) : `** BUILD SUCCEEDED **`.
- [ ] **Step 9: Commit** — `git add boringNotch/modules/Agents scripts/agents-suivi-selftest && git commit -m "Agents : file de validations par demande, carte figée, 1 / N en attente"`

### Task 2: Tour en cours et liste de tâches (logique pure)

**Files:**
- Create: `boringNotch/modules/Agents/AgentTurn.swift`
- Modify: `boringNotch/modules/Agents/AgentSession.swift` (`ToolInput` : champs de tâches)
- Test: `scripts/agents-suivi-selftest/main.swift`

**Interfaces:**
- Produces:
  ```swift
  enum ActivityKind: String, CaseIterable { case read, edit, run, other, wait }
  extension ActivityKind {
      static func of(tool: String) -> ActivityKind
      var label: String     // "lecture", "écriture", "commandes", "outils", "attente"
  }
  struct ActivityTick: Equatable { let kind: ActivityKind; let at: Date }
  struct TurnActivity: Equatable {
      var startedAt: Date
      var endedAt: Date?
      private(set) var ticks: [ActivityTick]   // plafonné à 2000 (les plus anciens tombent)
      private(set) var files: Set<String>
      private(set) var added: Int, removed: Int
      init(startedAt: Date)
      mutating func record(_ kind: ActivityKind, at: Date)
      mutating func addDiff(file: String, added: Int, removed: Int)
      func elapsed(now: Date) -> TimeInterval              // jusqu'à endedAt si fini
      func buckets(_ n: Int, now: Date) -> [ActivityKind?] // n tranches égales de startedAt à endedAt ?? now
      func phases(now: Date) -> [ActivityKind]             // ≤ 3 dernières phases distinctes, dans l'ordre
  }
  enum TaskStatus: String { case pending, inProgress = "in_progress", completed }
  struct AgentTask: Equatable { var id: String; var title: String; var status: TaskStatus }
  enum AgentTasks {
      /// Applique un appel d'outil de tâches à la liste ; renvoie nil si l'outil n'en est pas un.
      static func apply(tool: String, input: AgentEnvelope.ToolInput?, to list: [AgentTask]) -> [AgentTask]?
  }
  // ToolInput, nouveaux champs décodés
  var todos: [TaskItem]?    // TodoWrite
  var items: [TaskItem]?    // mcp__ccd_turn__update_plan
  var subject: String?      // TaskCreate
  var taskId: String?       // TaskUpdate
  var status: String?       // TaskUpdate
  struct TaskItem: Decodable { var content: String?; var subject: String?; var status: String? }
  ```

- [ ] **Step 1: Write the failing tests:**
  ```swift
  check(ActivityKind.of(tool: "Read") == .read && ActivityKind.of(tool: "Grep") == .read && ActivityKind.of(tool: "Glob") == .read, "lecture")
  check(ActivityKind.of(tool: "Edit") == .edit && ActivityKind.of(tool: "Write") == .edit && ActivityKind.of(tool: "MultiEdit") == .edit, "écriture")
  check(ActivityKind.of(tool: "Bash") == .run, "commandes")
  check(ActivityKind.of(tool: "mcp__x__y") == .other && ActivityKind.of(tool: "Agent") == .other, "outils")
  let t0 = Date(timeIntervalSince1970: 0)
  var t = TurnActivity(startedAt: t0)
  for i in 0..<5 { t.record(.read, at: t0 + Double(i)) }
  for i in 5..<10 { t.record(.edit, at: t0 + Double(i)) }
  t.addDiff(file: "/a", added: 3, removed: 1); t.addDiff(file: "/a", added: 2, removed: 0); t.addDiff(file: "/b", added: 1, removed: 1)
  check(t.files.count == 2 && t.added == 6 && t.removed == 2, "totaux du tour")
  check(t.buckets(2, now: t0 + 10) == [.read, .edit], "tranches dominantes")
  check(t.buckets(4, now: t0 + 20)[3] == nil, "tranche sans activité = nil")
  check(t.phases(now: t0 + 10) == [.read, .edit], "phases")
  t.endedAt = t0 + 10
  check(t.elapsed(now: t0 + 999) == 10, "chrono figé à la fin")
  for i in 0..<5000 { t.record(.run, at: t0 + 10 + Double(i)) }
  check(t.ticks.count == 2000 && t.buckets(28, now: t0 + 5010).count == 28, "tour long borné")
  ```
  Puis, pour les tâches, décoder des `ToolInput` depuis JSON (`JSONDecoder().decode(AgentEnvelope.ToolInput.self, from: Data(#"…"#.utf8))`) :
  ```swift
  // TodoWrite : remplace la liste
  // {"todos":[{"content":"A","status":"completed"},{"content":"B","status":"in_progress"},{"content":"C","status":"pending"}]}
  check(list.map(\.status) == [.completed, .inProgress, .pending] && list[1].title == "B", "TodoWrite")
  // update_plan, même chose avec "items"
  // TaskCreate {"subject":"X"} deux fois puis TaskUpdate {"taskId":"2","status":"completed"}
  check(list.map(\.id) == ["1", "2"] && list[1].status == .completed, "TaskCreate / TaskUpdate")
  // TaskUpdate {"taskId":"1","status":"deleted"} retire la tâche
  check(AgentTasks.apply(tool: "Bash", input: nil, to: []) == nil, "outil étranger")
  ```
- [ ] **Step 2: Run, expect compile failure.**
- [ ] **Step 3: Implement.** `buckets` : tranche i couvre `[start + i·d, start + (i+1)·d)` avec `d = durée / n` ;
  valeur = genre le plus fréquent dans la tranche (égalité : le plus récent), nil si vide. `phases` = suite des valeurs
  non nil de `buckets(28, now:)` sans répétitions consécutives, 3 dernières. `AgentTasks.apply` : `TodoWrite` et
  `mcp__ccd_turn__update_plan` remplacent la liste (`id` = position 1…n, titre = `content ?? subject`) ;
  `TaskCreate` ajoute `id = String(list.count + 1)` en `pending`
  (`ponytail:` ids séquentiels supposés, comme Claude Code les attribue ; lire `tool_response` si ça dérive) ;
  `TaskUpdate` change le statut de `taskId`, `deleted` la retire ; statut inconnu = `pending`.
- [ ] **Step 4: Run the selftest, expect `OK`.**
- [ ] **Step 5: Commit** — `git commit -m "Agents : activité du tour et listes de tâches (logique pure)"`

### Task 3: Brancher le tour, les tâches et le sujet dans la session

**Files:**
- Modify: `boringNotch/modules/Agents/AgentSession.swift` (`AgentSession`, `AgentEnvelope`, `project`)
- Modify: `boringNotch/modules/Agents/AgentStore.swift` (`apply`, `startStep`, `Saved`, `save`, `init`)
- Modify: `scripts/agent-hook.sh`
- Test: `scripts/agents-suivi-selftest/main.swift`

**Interfaces:**
- Consumes: `TurnActivity`, `ActivityKind`, `AgentTasks` (tâche 2).
- Produces:
  ```swift
  // AgentSession
  var topic: String?            // titre du fil Delta (hook), prioritaire sur title
  var turn: TurnActivity?       // tour en cours ou dernier tour
  var tasks: [AgentTask] = []
  var subject: String { get }   // topic ?? title ?? "Nouvelle session"
  static func projectName(_ cwd: String?) -> String   // utilisé par `project` et par les stats
  // AgentEnvelope
  var topic: String?
  ```

- [ ] **Step 1: Write the failing test:**
  ```swift
  check(AgentSession.projectName("/Users/x/Projects/boring.notch/.delta/worktrees/e9kkr72dbhq7/boring.notch") == "boring.notch", "worktree Delta dans le dépôt")
  check(AgentSession.projectName("/Users/x/Library/Application Support/Delta/worktrees/abc/qonto-dash") == "qonto-dash", "worktree Delta global")
  check(AgentSession.projectName("/Users/x/Documents/GitHub/WPDashboard/.claude/worktrees/admin-ui") == "WPDashboard", "worktree Claude")
  check(AgentSession.projectName("/Users/x/Documents/GitHub/WPDashboard/src") == "src", "dossier ordinaire : inchangé")
  check(AgentSession.projectName(nil) == "Sans projet" && AgentSession.projectName("/") == "Sans projet", "sans cwd")
  ```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement `projectName`** (`/.claude/worktrees/` → composant avant `.claude` ; `/worktrees/<id>/<repo>` sous
  `.delta` ou `Delta` → `<repo>` ; sinon dernier composant) et faire de `project` un appel à `projectName(cwd)`.
- [ ] **Step 4: Run the selftest, expect `OK`.**
- [ ] **Step 5: Store.** `UserPromptSubmit` : `turn = TurnActivity(startedAt: .now)`. `PreToolUse` : `turn?.record(.of(tool:))`,
  et `if let l = AgentTasks.apply(...) { tasks = l }`. Le calcul de lignes de `startStep` alimente aussi
  `turn?.addDiff`. `PermissionRequest` : `turn?.record(.wait, at: .now)`. `Stop` : `turn?.endedAt = .now`.
  `env.topic` non vide remplace `topic`. `topic` est sauvegardé dans `Saved` comme `title` ; `turn` et `tasks` non.
- [ ] **Step 6: Hook.** Dans `scripts/agent-hook.sh`, seulement si `DELTA_CURRENT_THREAD_ID` est défini **et** que
  `$IN` contient `"hook_event_name"` valant `UserPromptSubmit` ou `Stop` (grep -E, espaces tolérés), lire le nom du fil
  avec `"$DELTA_CLI" --json thread list` (repli `/Applications/Delta.app/Contents/MacOS/delta`), entrée dont `id`
  égale l'id, via `/usr/bin/python3`, et ajouter `"topic":<json.dumps(nom)>` dans l'enveloppe à côté de `"app"`. Toute
  erreur ou nom vide : pas de champ `topic`. Vérification à la main :
  `DELTA_CURRENT_THREAD_ID="$DELTA_CURRENT_THREAD_ID" sh -x scripts/agent-hook.sh claude <<< '{"session_id":"t","hook_event_name":"Stop"}'`
  doit montrer l'enveloppe avec `"topic":"Fonctionnalités inspirées de Vorssaint"` (ou le fil courant). Mesuré : la
  liste des fils prend ≈ 40 ms.
- [ ] **Step 7: Build, expect `** BUILD SUCCEEDED **`.**
- [ ] **Step 8: Commit** — `git commit -m "Agents : tour en cours, tâches et sujet du fil Delta dans la session"`

### Task 4: Affichage — « Projet · Sujet » et progression

**Files:**
- Modify: `boringNotch/modules/Agents/AgentsView.swift` (`sessionPicker`, `agentHeaderContent`, `stepList` → `turnView`,
  cartes de la tâche 1)

**Interfaces:**
- Consumes: `AgentSession.subject`, `.project`, `.turn`, `.tasks` (tâche 3) ; `ActivityKind.label`, `TurnActivity.buckets/phases/elapsed`.

- [ ] **Step 1: Noms.** Partout où une session est nommée : `project` en `secondary` + « · » + `subject` en blanc, sur une
  ligne, sujet tronqué au milieu. Sélecteur : `"\(project) · \(subject.prefix(52))"`. En-tête : la ligne en 13 pt
  semibold devient `subject`, précédée de `project ·` en `secondary`. Cartes de validation, question, plan : même paire
  dans l'en-tête.
- [ ] **Step 2: Progression.** Quand la session a un `turn`, la vue Progression remplace les 3 dernières étapes
  (`stepList`, hors message au repos qui reste tel quel quand `!isActive`) par :
  ```
  ⏱ 12 min · 6 fichiers +184 −32
  ▮▮▮▯▯▮▮▮▮▮▮▮▮▮▯▮▮▮▮▮▮▮░░░
  lecture → écriture → commandes          (ou : ████░░ 3 / 5 tâches · <titre de la tâche in_progress>)
  ```
  Chrono : `elapsed` formaté « 45 s », « 12 min », « 1 h 05 », rafraîchi par `TimelineView(.periodic(from: .now, by: 1))`.
  Bande : `buckets(28, now:)`, une capsule par tranche, couleur par genre (au choix, distinctes, `wait` = rouge comme
  `tint` d'attente), tranche nil = blanc 0.12. Ligne 3 : si `tasks` non vide et pas toutes `completed`, barre
  `completed / count` + titre de la tâche `inProgress` ; sinon `phases` jointes par « → » avec `label`. Fichiers et
  lignes : du tour (`turn.files.count`, `added`, `removed`), masqués si 0.
- [ ] **Step 3: Build, expect `** BUILD SUCCEEDED **`, puis lancer l'app signée** (quitter avec
  `osascript -e 'tell application "Boring Notch" to quit'`, `ditto` vers `/Applications/Boring Notch.app`, `open`) et
  vérifier à l'œil avec deux sessions en parallèle : noms distincts, chrono qui avance, bande qui se remplit, carte figée
  avec « 1 / 2 en attente » et boutons inactifs 0,6 s.
- [ ] **Step 4: Commit** — `git commit -m "Agents : Projet · Sujet partout, chrono et bande d'activité du tour"`

### Task 5: Statistiques — lecture et agrégation des journaux (logique pure)

**Files:**
- Create: `boringNotch/modules/Agents/AgentStats.swift`
- Test: `scripts/agents-suivi-selftest/main.swift`

**Interfaces:**
- Consumes: `AgentSession.projectName` (tâche 3).
- Produces:
  ```swift
  struct TokenUsage: Equatable { var input, output, cacheWrite, cacheRead: Int }
  struct UsageLine: Equatable { let messageID: String; let day: String; let model: String; let project: String; let usage: TokenUsage }
  enum Pricing {
      /// Valeur API en dollars ; 0 pour un modèle inconnu ou "<synthetic>".
      static func value(model: String, _ u: TokenUsage) -> Double
  }
  struct DayStats: Codable, Equatable { var value = 0.0; var byModel: [String: Double] = [:]; var byProject: [String: Double] = [:] }
  struct StatsBook: Codable, Equatable {
      var days: [String: DayStats] = [:]       // "yyyy-MM-dd", fuseau local
      var offsets: [String: UInt64] = [:]      // chemin de fichier -> octets déjà lus
      var recentIDs: [String: [String]] = [:]  // chemin -> 50 derniers message.id vus (dédoublonnage)
      /// Ajoute les lignes complètes de `chunk` (lu à partir de offsets[path]) ; avance l'offset jusqu'au dernier "\n".
      mutating func ingest(path: String, chunk: Data, calendar: Calendar)
  }
  enum StatsLine { static func parse(_ line: Data, calendar: Calendar) -> UsageLine? }
  struct StatsSummary: Equatable {
      var today: Double
      var trend: Double?                 // today / moyenne des 7 jours précédents - 1 ; nil si cette moyenne vaut 0
      var models: [(name: String, share: Double)]    // 7 derniers jours, part de la valeur, décroissant
      var projects: [(name: String, share: Double)]  // idem, 3 premiers
      var grid: [Double]                 // 84 jours, du plus ancien à aujourd'hui
      static func make(_ book: StatsBook, today: Date, calendar: Calendar) -> StatsSummary
  }
  ```
  (`StatsSummary` : implémenter `Equatable` à la main ou comparer champ par champ dans les tests, les tuples ne sont pas
  `Equatable`.)

- [ ] **Step 1: Write the failing tests** avec des lignes JSONL écrites dans le test :
  - une ligne `{"type":"assistant","timestamp":"2026-11-18T10:00:00.000Z","cwd":"/p/boring.notch/.delta/worktrees/x/boring.notch","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":2000,"cache_read_input_tokens":10000}}}`
    → `parse` donne `project == "boring.notch"`, `model == "claude-opus-5-5"`, `usage == TokenUsage(input: 1000, output: 500, cacheWrite: 2000, cacheRead: 10000)`.
  - `{"type":"user",…}`, `{"type":"assistant",…"model":"<synthetic>"…}`, `not json` → `parse` = nil.
  - `ingest` d'un chunk avec deux lignes `m1` identiques + une ligne `m2` : `days["2026-11-18"]!.value` égale
    `Pricing.value(m1) + Pricing.value(m2)` (une seule fois `m1`).
  - `ingest` d'un chunk dont la dernière ligne n'a pas de `\n` : `offsets[path]` s'arrête après le dernier `\n` ; la
    ligne incomplète n'est pas comptée ; un second `ingest` du reste la compte.
  - `Pricing.value` : `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5`, `claude-fable-5-2` > 0 ;
    `"inconnu"` = 0 ; formule `(input·pIn + output·pOut + cacheWrite·pIn·1.25 + cacheRead·pIn·0.1) / 1_000_000`.
  - `StatsSummary.make` sur un livre fabriqué (7 jours précédents à 10 $, aujourd'hui 12 $) : `today == 12`,
    `trend ≈ 0.2`, `grid.count == 84`, `grid.last == 12`, parts des modèles qui somment à 1.
- [ ] **Step 2: Run, expect compile failure.**
- [ ] **Step 3: Implement.** Tarifs par famille, reconnue par sous-chaîne du nom (`opus`, `sonnet`, `haiku`, `fable`) :
  **charger le skill `claude-api` pour les tarifs actuels par million de tokens** et les recopier avec la date dans un
  commentaire (`ponytail:` grille à la main, à mettre à jour quand les tarifs changent). Jour = `timestamp` ISO 8601
  ramené au jour local de `calendar`. Projet = `AgentSession.projectName(cwd)`.
- [ ] **Step 4: Run the selftest, expect `OK`.**
- [ ] **Step 5: Commit** — `git commit -m "Agents : statistiques depuis les journaux Claude (logique pure)"`

### Task 6: Statistiques — lecture des fichiers, sandbox et page « Stats »

**Files:**
- Modify: `boringNotch/boringNotch.entitlements`
- Create: `boringNotch/modules/Agents/AgentStatsView.swift` (scanner + vue)
- Modify: `boringNotch/modules/Agents/AgentsView.swift` (`Mode`, `header`, `body`)

**Interfaces:**
- Consumes: `StatsBook`, `StatsSummary` (tâche 5).
- Produces:
  ```swift
  @MainActor final class AgentStatsStore: ObservableObject {
      static let shared: AgentStatsStore
      @Published private(set) var summary: StatsSummary?
      func refresh()      // ignore l'appel si le dernier date de moins de 60 s
  }
  struct AgentStatsView: View
  ```

- [ ] **Step 1: Entitlement.** Ajouter
  `com.apple.security.temporary-exception.files.home-relative-path.read-only` = tableau `["/.claude/"]`.
- [ ] **Step 2: Scanner.** Dossier réel (pas le conteneur) : `String(cString: getpwuid(getuid())!.pointee.pw_dir) + "/.claude/projects"`.
  `refresh()` lance une `Task.detached(priority: .utility)` qui énumère récursivement les `*.jsonl`
  (`FileManager.enumerator`), saute les fichiers dont la taille égale l'offset connu, lit avec `FileHandle` à partir de
  l'offset, `ingest`, puis enregistre le livre en JSON dans `Application Support/agent-stats.json` (conteneur de
  l'app) et publie `StatsSummary.make(book, today: .now, calendar: .current)` sur le main actor. Livre chargé au
  premier appel.
- [ ] **Step 3: Vue.** `Mode` gagne `.stats` ; troisième bouton « Stats » (`chart.bar.xaxis`) dans `header`.
  `AgentStatsView` appelle `refresh()` à l'apparition et affiche, dans la hauteur disponible :
  ```
  Aujourd'hui 4,20 $ ▲18 %  valeur API │ Opus 72 % · Sonnet 28 %
  boring.notch 41 % · qonto-dash 22 % · WPDashboard 15 %
  [grille 12 semaines × 7 jours, carrés ≈ 7 pt, intensité = valeur / max de la grille]
  ```
  Tendance : ▲ vert / ▼ rouge, masquée si `trend == nil`. Montant au format monétaire `fr_FR`, en dollars. Pendant le
  premier calcul : `AgentEmptyState(symbol: "chart.bar.xaxis", message: "Calcul des statistiques…")`. Aucun fichier :
  « Aucune session Claude trouvée ».
- [ ] **Step 4: Build signé, installer, ouvrir l'onglet Stats.** Premier calcul sur ≈ 500 Mo sans bloquer l'interface
  (le notch reste fluide), ouvertures suivantes quasi instantanées. Vérifier que les projets et modèles listés
  correspondent aux sessions récentes et que la valeur du jour est plausible.
- [ ] **Step 5: Commit** — `git commit -m "Agents : page Stats (valeur API, modèles, projets, grille d'activité)"`
