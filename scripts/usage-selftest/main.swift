// Auto-test de la validité des limites d'usage.
// swiftc boringNotch/modules/Agents/AgentSession.swift boringNotch/modules/Agents/PermissionAsk.swift boringNotch/modules/Agents/AgentTurn.swift scripts/usage-selftest/main.swift -o "$TMPDIR/usage-selftest" && "$TMPDIR/usage-selftest"

import Foundation

func check(_ cond: Bool, _ msg: String) { if !cond { print("FAIL: \(msg)"); exit(1) } }

let now = Date()
let old = now.addingTimeInterval(-7 * 3600)
let week = RateLimit(usedPercent: 54, resetsAt: now.addingTimeInterval(35 * 3600))
let fiveGone = RateLimit(usedPercent: 80, resetsAt: now.addingTimeInterval(-3600))
let u = UsageLimits(fiveHour: fiveGone, sevenDay: week, updatedAt: old)
check(u.current(at: now)?.sevenDay == week, "semaine valable jusqu'à sa réinitialisation, même mesurée il y a 7 h")
check(u.current(at: now)?.fiveHour == nil, "fenêtre 5 h réinitialisée masquée")
check(UsageLimits(fiveHour: fiveGone, sevenDay: nil, updatedAt: now).current(at: now) == nil, "rien de valable -> nil")
check(UsageLimits(fiveHour: RateLimit(usedPercent: 3, resetsAt: nil), updatedAt: old).current(at: now) == nil, "sans date : 6 h max")
// Message de scripts/claude-usage.sh (get_usage du CLI, comme T3 Code).
let probe = #"{"source": "claude", "kind": "usage", "payload": {"rate_limits": {"five_hour": {"used_percentage": 35, "resets_at": 1793800200.370378}, "seven_day": {"used_percentage": 59, "resets_at": 1793916000.3704}}}}"#
let env = try! JSONDecoder().decode(AgentEnvelope.self, from: Data(probe.utf8))
check(env.payload.rate_limits?.five_hour?.used_percentage == 35, "sonde : 5 h décodée")
check(env.payload.rate_limits?.seven_day?.resets_at?.date == Date(timeIntervalSince1970: 1793916000.3704), "sonde : réinitialisation décodée")
check(env.payload.session_id == nil, "sonde : pas de session créée")
print("OK")
