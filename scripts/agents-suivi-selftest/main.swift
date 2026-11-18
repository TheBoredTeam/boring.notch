// Auto-test du suivi des agents (file de demandes, tours, statistiques).
// swiftc boringNotch/modules/Agents/AgentSession.swift boringNotch/modules/Agents/PermissionAsk.swift boringNotch/modules/Agents/AgentRequests.swift boringNotch/modules/Agents/AgentTurn.swift scripts/agents-suivi-selftest/main.swift -o "$TMPDIR/agents-suivi-selftest" && "$TMPDIR/agents-suivi-selftest"

import Foundation

func check(_ cond: Bool, _ msg: String) { if !cond { print("FAIL: \(msg)"); exit(1) } }

// MARK: File des demandes

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
check(t.buckets(4, now: t0 + 20)[3] == nil, "tranche sans activité = nil")
check(t.phases(now: t0 + 10) == [.read, .edit], "phases")
t.endedAt = t0 + 10
check(t.elapsed(now: t0 + 999) == 10, "chrono figé à la fin")
for i in 0..<5000 { t.record(.run, at: t0 + 10 + Double(i)) }
check(t.ticks.count == 2000 && t.buckets(28, now: t0 + 5010).count == 28, "tour long borné")

// MARK: Liste de tâches

func tool(_ json: String) -> AgentEnvelope.ToolInput {
    try! JSONDecoder().decode(AgentEnvelope.ToolInput.self, from: Data(json.utf8))
}
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
check(AgentTasks.apply(tool: "Bash", input: nil, to: []) == nil, "outil étranger")

print("OK")
