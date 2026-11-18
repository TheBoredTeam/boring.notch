// Auto-test du suivi des agents (file de demandes, tours, statistiques).
// swiftc boringNotch/modules/Agents/AgentSession.swift boringNotch/modules/Agents/PermissionAsk.swift boringNotch/modules/Agents/AgentRequests.swift boringNotch/modules/Agents/AgentTurn.swift boringNotch/modules/Agents/AgentStats.swift scripts/agents-suivi-selftest/main.swift -o "$TMPDIR/agents-suivi-selftest" && "$TMPDIR/agents-suivi-selftest"

import Foundation

func check(_ cond: Bool, _ msg: String) { if !cond { print("FAIL: \(msg)"); exit(1) } }

// MARK: File des demandes

func tool(_ json: String) -> AgentEnvelope.ToolInput {
    try! JSONDecoder().decode(AgentEnvelope.ToolInput.self, from: Data(json.utf8))
}

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
check(q.pending(in: "S1") && !q.pending(in: "S3"), "pending(in:)")
check(q.resolve(session: "S1", event: "Stop", tool: nil, toolUseID: nil) == ["a"], "Stop libère toute la session")
check(q.remove(id: "b")?.id == "b" && q.current == nil, "réponse depuis le notch")
q.add(req("e", "S4", "Bash", nil, 0))
check(q.expire(now: Date(timeIntervalSince1970: 601), after: 600) == ["e"], "délai du hook dépassé")
q.add(PendingRequest(id: "f", sessionID: "S5", tool: "Bash", toolUseID: nil, canAnswer: false, at: Date(timeIntervalSince1970: 0)))
q.add(req("g", "S5", "Edit"))
check(q.resolve(session: "S5", event: "PreToolUse", tool: "Read", toolUseID: nil) == ["f"], "PreToolUse libère seulement la demande non bloquante")
check(q.items.map(\.id) == ["g"], "la demande bloquante reste")

// Deux Bash en parallèle sans tool_use_id : seule la commande validée ailleurs est libérée.
var q2 = RequestQueue()
func bash(_ id: String, _ cmd: String) -> PendingRequest {
    PendingRequest(id: id, sessionID: "S6", tool: "Bash", toolUseID: nil, fingerprint: cmd, canAnswer: true, at: Date(timeIntervalSince1970: 0))
}
q2.add(bash("x", "rm -rf build")); q2.add(bash("y", "ls"))
check(q2.resolve(session: "S6", event: "PostToolUse", tool: "Bash", toolUseID: nil, fingerprint: "ls") == ["y"], "empreinte : seule la commande jouée est libérée")
check(q2.items.map(\.id) == ["x"], "empreinte : la demande sœur reste")
check(q2.resolve(session: "S6", event: "PostToolUse", tool: "Bash", toolUseID: nil, fingerprint: "pwd").isEmpty, "empreinte inconnue : rien")
check(q2.resolve(session: "S6", event: "PostToolUseFailure", tool: "Bash", toolUseID: nil, fingerprint: "rm -rf build") == ["x"], "PostToolUseFailure libère comme PostToolUse")
check(tool(#"{"command":"ls","file_path":"/a"}"#).fingerprint == "ls" && tool(#"{"file_path":"/a"}"#).fingerprint == "/a" && tool("{}").fingerprint == nil, "empreinte du tool_input")

// MARK: Tour en cours

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
var w = TurnActivity(startedAt: t0)
w.record(.wait, at: t0); w.record(.read, at: t0 + 10)
check(w.buckets(5, now: t0 + 10) == [.wait, .wait, .wait, .wait, .read], "attente : les tranches vides jusqu'au tick suivant")
var w2 = TurnActivity(startedAt: t0)
w2.record(.wait, at: t0)
check(w2.buckets(4, now: t0 + 8) == [.wait, .wait, .wait, .wait], "attente en cours : jusqu'à maintenant")
var w3 = TurnActivity(startedAt: t0)
w3.record(.read, at: t0)
check(w3.buckets(4, now: t0 + 8) == [.read, nil, nil, nil], "hors attente : tranches vides inchangées")
check(t.buckets(4, now: t0 + 20)[3] == nil, "tranche sans activité = nil")
check(t.phases(now: t0 + 10) == [.read, .edit], "phases")
t.endedAt = t0 + 10
check(t.elapsed(now: t0 + 999) == 10, "chrono figé à la fin")
t.endedAt = nil
for i in 0..<5000 { t.record(.run, at: t0 + 10 + Double(i)) }
check(t.ticks.count == 2000 && t.buckets(28, now: t0 + 5010).count == 28, "tour long borné")
check(t.buckets(28, now: t0 + 5010).last == .run, "tour long : la fin reste visible")

// MARK: Liste de tâches

let plan = #"[{"content":"A","status":"completed"},{"content":"B","status":"in_progress"},{"content":"C","status":"pending"}]"#
var list = AgentTasks.apply(tool: "TodoWrite", input: tool(#"{"todos":\#(plan)}"#), to: [])!
check(list.map(\.status) == [.completed, .inProgress, .pending] && list[1].title == "B", "TodoWrite")
list = AgentTasks.apply(tool: "mcp__ccd_turn__update_plan", input: tool(#"{"items":[{"subject":"A","status":"pending"}]}"#), to: list)!
check(list.count == 1 && list[0].title == "A" && list[0].id == "1", "update_plan remplace la liste")
list = []
for _ in 0..<2 { list = AgentTasks.apply(tool: "TaskCreate", input: tool(#"{"subject":"X"}"#), to: list)! }
list = AgentTasks.apply(tool: "TaskUpdate", input: tool(#"{"taskId":"2","status":"completed"}"#), to: list)!
check(list.map(\.id) == ["1", "2"] && list[1].status == .completed, "TaskCreate / TaskUpdate")
list = AgentTasks.apply(tool: "TaskUpdate", input: tool(#"{"taskId":1,"status":"in_progress"}"#), to: list)!
check(list[0].status == .inProgress, "taskId numérique")
list = AgentTasks.apply(tool: "TaskUpdate", input: tool(#"{"taskId":"1","status":"deleted"}"#), to: list)!
check(list.map(\.id) == ["2"], "deleted retire la tâche")
list = (1...3).map { AgentTask(id: String($0), title: "T", status: .pending) }
list = AgentTasks.apply(tool: "TaskUpdate", input: tool(#"{"taskId":"2","status":"deleted"}"#), to: list)!
list = AgentTasks.apply(tool: "TaskCreate", input: tool(#"{"subject":"N"}"#), to: list)!
check(list.map(\.id) == ["1", "3", "4"], "TaskCreate après suppression : pas de collision")
check(AgentTasks.apply(tool: "TodoWrite", input: tool("{}"), to: list)! == list, "TodoWrite sans liste : inchangée")
check(AgentTasks.apply(tool: "Bash", input: nil, to: []) == nil, "outil étranger")

// MARK: Chrono

check([0, 45.9, 60, 720, 3599, 3900, 7200, -5].map(TurnActivity.clock) == ["0 s", "45 s", "1 min", "12 min", "59 min", "1 h 05", "2 h 00", "0 s"], "chrono lisible")

// MARK: Nom du projet

check(AgentSession.projectName("/Users/x/Projects/boring.notch/.delta/worktrees/e9kkr72dbhq7/boring.notch") == "boring.notch", "worktree Delta dans le dépôt")
check(AgentSession.projectName("/Users/x/Library/Application Support/Delta/worktrees/abc/qonto-dash") == "qonto-dash", "worktree Delta global")
check(AgentSession.projectName("/Users/x/Documents/GitHub/WPDashboard/.claude/worktrees/admin-ui") == "WPDashboard", "worktree Claude")
check(AgentSession.projectName("/Users/x/Documents/GitHub/WPDashboard/src") == "src", "dossier ordinaire : inchangé")
check(AgentSession.projectName(nil) == "Sans projet" && AgentSession.projectName("/") == "Sans projet", "sans cwd")

// MARK: Statistiques

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Europe/Paris")!
func line(_ id: String, model: String = "claude-opus-5-5", ts: String = "2026-11-18T10:00:00.000Z", type: String = "assistant",
          cwd: String = "/p/boring.notch/.delta/worktrees/x/boring.notch", extra: String = "") -> String {
    "{\"type\":\"\(type)\",\"timestamp\":\"\(ts)\",\"cwd\":\"\(cwd)\",\"message\":{\"id\":\"\(id)\",\"model\":\"\(model)\",\"usage\":{\"input_tokens\":1000,\"output_tokens\":500,\"cache_creation_input_tokens\":2000,\"cache_read_input_tokens\":10000\(extra)}}}"
}
let m1 = line("m1")
let p1 = StatsLine.parse(Data(m1.utf8), calendar: cal)
check(p1?.project == "boring.notch" && p1?.model == "claude-opus-5-5" && p1?.day == "2026-11-18", "parse : projet, modèle, jour")
check(p1?.usage == TokenUsage(input: 1000, output: 500, cacheWrite: 2000, cacheRead: 10000), "parse : usage")
check(StatsLine.parse(Data(line("u", type: "user").utf8), calendar: cal) == nil, "parse : ligne user ignorée")
check(StatsLine.parse(Data(line("s", model: "<synthetic>").utf8), calendar: cal) == nil, "parse : <synthetic> ignoré")
check(StatsLine.parse(Data("not json".utf8), calendar: cal) == nil, "parse : pas du JSON")
check(StatsLine.parse(Data(line("n", ts: "2026-11-18T23:30:00.000Z").utf8), calendar: cal)?.day == "2026-11-19", "parse : jour local (Paris)")
check(StatsLine.parse(Data(line("n2", ts: "2026-11-18T23:30:00Z").utf8), calendar: cal)?.day == "2026-11-19", "parse : horodatage sans fraction")
check(StatsLine.parse(Data(line("h", extra: ",\"cache_creation\":{\"ephemeral_1h_input_tokens\":500,\"ephemeral_5m_input_tokens\":1500}").utf8), calendar: cal)?.usage.cacheWrite1h == 500, "parse : cache 1 h")

let v1 = Pricing.value(model: "claude-opus-5-5", p1!.usage)
var book = StatsBook()
let m2 = line("m2", model: "claude-sonnet-5-5")
book.ingest(path: "/a.jsonl", chunk: Data((m1 + "\n" + m1 + "\n" + m2 + "\n").utf8), calendar: cal)
let want = v1 + Pricing.value(model: "claude-sonnet-5-5", p1!.usage)
check(abs(book.days["2026-11-18"]!.value - want) < 1e-12, "ingest : m1 dédoublonné")
check(book.days["2026-11-18"]!.byProject["boring.notch"] != nil && book.days["2026-11-18"]!.byModel.count == 2, "ingest : ventilation modèle/projet")
book.ingest(path: "/a.jsonl", chunk: Data((m1 + "\n").utf8), calendar: cal)
check(abs(book.days["2026-11-18"]!.value - want) < 1e-12, "ingest : dédoublonnage entre deux lectures")
book.ingest(path: "/autre-session.jsonl", chunk: Data((m1 + "\n").utf8), calendar: cal)
check(abs(book.days["2026-11-18"]!.value - want) < 1e-12, "ingest : même id dans un autre fichier compté une seule fois")
var pruned = book
pruned.prune(today: cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 12))!, calendar: cal)
check(pruned.seen.keys.sorted() == ["m1", "m2"], "prune : ids récents conservés")
pruned.prune(today: cal.date(from: DateComponents(year: 2027, month: 3, day: 1, hour: 12))!, calendar: cal)
check(pruned.seen.isEmpty && pruned.days == book.days, "prune : ids de plus de 84 jours oubliés, jours intacts")

var b2 = StatsBook()
let first = line("a1") + "\n" + line("a2")
b2.ingest(path: "/b.jsonl", chunk: Data(first.utf8), calendar: cal)
check(b2.offsets["/b.jsonl"] == UInt64(line("a1").utf8.count + 1), "ingest : offset après le dernier \\n")
check(abs(b2.days["2026-11-18"]!.value - v1) < 1e-12, "ingest : ligne incomplète non comptée")
b2.ingest(path: "/b.jsonl", chunk: Data((line("a2") + "\n").utf8), calendar: cal)
check(abs(b2.days["2026-11-18"]!.value - 2 * v1) < 1e-12, "ingest : le reste complète la ligne")
check(b2.offsets["/b.jsonl"] == UInt64(first.utf8.count + 1), "ingest : offset final")

// Multi-octets : l'offset compte des octets UTF-8, pas des caractères.
var b3 = StatsBook()
let accent = line("e1", cwd: "/p/café-🚀/zé") + "\n" + line("e2", cwd: "/p/café-🚀/zé") + "\n"
let partial = line("e3", cwd: "/p/café-🚀/zé")
b3.ingest(path: "/c.jsonl", chunk: Data((accent + partial).utf8), calendar: cal)
check(b3.offsets["/c.jsonl"] == UInt64(accent.utf8.count) && accent.utf8.count > accent.count, "ingest : offset en octets UTF-8")
check(b3.days["2026-11-18"]!.byProject["zé"] != nil && b3.seen.count == 2, "ingest : cwd accentué lu, ligne incomplète exclue")

for m in ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-2"] {
    check(Pricing.value(model: m, TokenUsage(input: 1000, output: 1000, cacheWrite: 0, cacheRead: 0)) > 0, "tarif \(m)")
}
let u = TokenUsage(input: 1000, output: 500, cacheWrite: 2000, cacheRead: 10000)
check(Pricing.value(model: "inconnu", u) == 0, "modèle inconnu = 0")
func near(_ model: String, _ usage: TokenUsage, _ micro: Double) -> Bool { abs(Pricing.value(model: model, usage) - micro / 1e6) < 1e-12 }
// Opus 5.5 : 4 $ / 20 $ par million ; cache 5 min ×1,25, 1 h ×2, lecture ×0,05.
check(near("claude-opus-5-5", u, 4000 + 10000 + 10000 + 2000), "formule Opus 5.5")
check(near("claude-opus-5-5", TokenUsage(input: 1000, output: 500, cacheWrite: 2000, cacheRead: 10000, cacheWrite1h: 500), 4000 + 10000 + 7500 + 4000 + 2000), "formule avec cache 1 h")
check(near("claude-opus-4-8", u, 5000 + 12500 + 12500 + 5000), "Opus 4.8 : 5 $ / 25 $, lecture ×0,1")
check(near("claude-sonnet-5-5", u, 2000 + 5000 + 5000 + 1000), "Sonnet 5.5 : lecture ×0,05")
check(near("claude-sonnet-4-6", u, 3000 + 7500 + 7500 + 3000), "Sonnet 4.6 : 3 $ / 15 $")
check(near("claude-haiku-5-5", u, 100 + 250 + 250 + 100), "Haiku 5.5 : 0,10 $ / 0,50 $, lecture ×0,1")
check(near("claude-haiku-4-5-20251001", u, 1000 + 2500 + 2500 + 1000), "Haiku 4.5 : 1 $ / 5 $")
check(near("claude-fable-5-2", u, 8000 + 20000 + 20000 + 2000), "Fable 5.2 : 8 $ / 40 $, lecture ×0,025")
check(near("claude-fable-5-1", u, 10000 + 25000 + 25000 + 2500), "Fable 5.1 : 10 $ / 50 $, lecture ×0,025")
check(Pricing.familyName("claude-opus-4-8") == "Opus" && Pricing.familyName("claude-haiku-4-5-20251001") == "Haiku" && Pricing.familyName("inconnu") == "inconnu", "nom de famille")

let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 12))!
var fab = StatsBook()
for i in 1...7 {
    let d = cal.date(byAdding: .day, value: -i, to: today)!
    // la veille : une autre génération d'Opus, repliée dans la même famille
    fab.days[statsDayKey(d, calendar: cal)] = DayStats(value: 10, byModel: [i == 1 ? "claude-opus-4-8" : "claude-opus-5-5": 8, "claude-sonnet-5-5": 2], byProject: ["a": 5, "b": 3, "c": 1, "d": 1])
}
fab.days["2026-11-19"] = DayStats(value: 12, byModel: ["claude-opus-5-5": 12], byProject: ["a": 12])
let sum = StatsSummary.make(fab, today: today, calendar: cal)
check(sum.today == 12 && abs(sum.trend! - 0.2) < 1e-9, "résumé : aujourd'hui et tendance")
check(sum.grid.count == 84 && sum.grid.last == 12 && sum.grid.first == 0, "résumé : grille de 84 jours")
check(sum.grid[76...82].allSatisfy { $0 == 10 } && sum.grid[75] == 0 && sum.grid[83] == 12, "résumé : grille, valeurs intermédiaires")
check(sum.models.map(\.name) == ["Opus", "Sonnet"] && abs(sum.models[0].share - 60.0 / 72) < 1e-9 && abs(sum.models.map(\.share).reduce(0, +) - 1) < 1e-9, "résumé : parts par famille")
check(sum.projects.count == 3 && sum.projects.first?.name == "a", "résumé : 3 premiers projets")
check(StatsSummary.make(StatsBook(), today: today, calendar: cal).trend == nil, "résumé : tendance nil sans historique")

print("OK")
