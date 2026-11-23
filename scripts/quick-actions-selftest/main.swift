// Auto-test de la confirmation à double clic (vider la corbeille).
// swiftc boringNotch/modules/Activities/ConfirmGate.swift scripts/quick-actions-selftest/main.swift -o "$TMPDIR/quick-actions-selftest" && "$TMPDIR/quick-actions-selftest"

import Foundation

func check(_ cond: Bool, _ msg: String) { if !cond { print("FAIL: \(msg)"); exit(1) } }

let t0 = Date(timeIntervalSince1970: 0)
var g = ConfirmGate(window: 3)
check(g.press(at: t0) == false && g.isArmed(at: t0 + 1), "premier clic : arme seulement")
check(g.press(at: t0 + 1) == true && !g.isArmed(at: t0 + 1), "second clic dans les 3 s : confirme")
check(g.press(at: t0 + 10) == false, "nouveau premier clic")
check(g.press(at: t0 + 13.5) == false && g.isArmed(at: t0 + 14), "après 3 s : ré-arme sans confirmer")
check(!g.isArmed(at: t0 + 17), "désarmé après la fenêtre")

// Double clic réflexe : un second appui trop proche n'est pas une confirmation et laisse armé.
var h = ConfirmGate(window: 3)
check(h.press(at: t0) == false, "arme")
check(h.press(at: t0 + 0.1) == false && h.isArmed(at: t0 + 0.2), "appui à 0,1 s ignoré, reste armé")
check(h.press(at: t0 + 1) == true && !h.isArmed(at: t0 + 1), "puis confirme à 1 s (armedAt d'origine conservé)")

print("OK")
