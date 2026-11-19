// Auto-test du débit lissé des téléchargements.
// swiftc boringNotch/modules/Activities/DownloadRate.swift scripts/downloads-selftest/main.swift -o "$TMPDIR/downloads-selftest" && "$TMPDIR/downloads-selftest"

import Foundation

func check(_ cond: Bool, _ msg: String) { if !cond { print("FAIL: \(msg)"); exit(1) } }

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
var s1 = DownloadRate(); s1.sample(bytes: 0, at: t0); s1.sample(bytes: 2_000_000, at: t0 + 1)
var z = DownloadRate(); z.sample(bytes: 5, at: t0); z.sample(bytes: 5, at: t0 + 1)
check(DownloadRate.multiLabel(count: 2, rates: [s1, z], now: t0 + 1).contains("/s"), "multi : débit des actifs")
check(DownloadRate.multiLabel(count: 2, rates: [z, z], now: t0 + 1) == "2", "multi : débit nul < 10 s = nombre seul")
check(DownloadRate.multiLabel(count: 2, rates: [p, p], now: t0 + 11) == "2 · en pause", "multi : tous en pause")
check(DownloadRate.multiLabel(count: 2, rates: [], now: t0) == "2", "multi : sans mesure")
print("OK")
