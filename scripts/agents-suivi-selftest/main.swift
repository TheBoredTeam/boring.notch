// Auto-test du suivi des agents (file de demandes, tours, statistiques).
// swiftc boringNotch/modules/Agents/AgentSession.swift boringNotch/modules/Agents/PermissionAsk.swift boringNotch/modules/Agents/AgentRequests.swift scripts/agents-suivi-selftest/main.swift -o "$TMPDIR/agents-suivi-selftest" && "$TMPDIR/agents-suivi-selftest"

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

print("OK")
