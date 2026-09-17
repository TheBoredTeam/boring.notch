#!/usr/bin/env python3
"""Compile extracted banner lifecycle code against inert, in-memory AX stand-ins."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--work-dir", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
work = args.work_dir or Path(tempfile.mkdtemp(prefix="pr1057-banner-"))
work.mkdir(parents=True, exist_ok=True)
source = (root / "BoringNotchXPCHelper/NotificationWatcher.swift").read_text()
opening = block(source, "    var notchOpen: Bool = false")
replay = "                for token in Array(held) {\n                    hold(token: token)\n                }"
assert opening.count(replay) == 1, "Opening must synchronously replay a stable held snapshot"
state = source[source.index("    private var appElement:"):source.index("\n    /// Effective notch-open state")]
state = state.replace("DispatchSourceTimer", "InertTimer")
methods = "\n".join(block(source, marker) for marker in [
    "    func hold(token:", "    func release(token:", "    func stop()",
    "    private func restoreParkedWindow(", "    private func currentWindow(",
    "    private func refreshHeldBanners()", "    private func collapseHeldBanners()",
    "    private func scanImpl()", "    private func rawAction(", "    private func actionLabel(",
])

# No AppKit/ApplicationServices imports. These names resolve only to the local
# classes/functions below; no real AX object, timer, app or window is created.
standins = r'''
import Foundation
import CoreGraphics
typealias CFString = String
typealias CFTypeRef = AnyObject
let kAXWindowsAttribute = "windows", kAXWindowAttribute = "window"
let kAXSubroleAttribute = "subrole", kAXPositionAttribute = "position"
let kAXIdentifierAttribute = "identifier"
let offscreen = CGPoint(x: -5000, y: -5000)
final class Trace {
    static var events: [String] = []
    static var assertions = 0
    static func check(_ condition: Bool, _ message: String) {
        assertions += 1
        if !condition { print("FAIL: \(message)"); exit(1) }
    }
    static func report(_ name: String) {
        print("PASS: \(name) | " + events.joined(separator: " -> "))
        events = []
    }
}
final class AXUIElement {
    let id: UInt
    var attributes: [String: Any] = [:]
    var children: [AXUIElement] = []
    var expanded = false
    var writes: [CGPoint] = []
    init(_ id: UInt) { self.id = id }
    subscript(_ key: String) -> Any? { attributes[key] }
    func cgPointAttribute(_ key: String) -> CGPoint? { attributes[key] as? CGPoint }
}
final class InertTimer {
    var cancelled = false
    func cancel() { cancelled = true }
}
func CFGetTypeID(_ object: CFTypeRef) -> UInt { object is AXUIElement ? 1 : 0 }
func AXUIElementGetTypeID() -> UInt { 1 }
func CFHash(_ element: AXUIElement) -> UInt { element.id }
enum AXValueType { case cgPoint }
func AXValueCreate(_ type: AXValueType, _ point: inout CGPoint) -> CGPoint? { point }
func AXUIElementSetAttributeValue(_ window: AXUIElement, _ key: String, _ point: CGPoint) {
    window.attributes[key] = point
    window.writes.append(point)
    Trace.events.append("\(point == offscreen ? "park" : "restore") window=\(window.id)")
}
func AXUIElementPerformAction(_ banner: AXUIElement, _ action: String) {
    let token = banner[kAXIdentifierAttribute] as! String
    if action.contains("Show Details") {
        banner.expanded = true
        let window = banner[kAXWindowAttribute] as! AXUIElement
        let parked = window.cgPointAttribute(kAXPositionAttribute) == offscreen
        Trace.events.append("expand \(token) parked=\(parked)")
    } else if action.contains("Hide Details") {
        banner.expanded = false
        Trace.events.append("collapse \(token)")
    } else { Trace.events.append("close \(token)") }
}
// Swallow fixture diagnostics instead of sending them to the system log.
func NSLog(_ message: String) {}
final class Watcher {
    var onBanner: ((String) -> Void)?
    var onBannerGone: ((String) -> Void)?
    private var skipLogged: Set<String> = []
    private let refreshInterval: TimeInterval = 2.5
    private func banners(in window: AXUIElement) -> [AXUIElement] { window.children }
    private func capture(_ banner: AXUIElement, token: String) -> String { token }
    private func updatePollCadence() {}
    private func actionNames(of banner: AXUIElement) -> [String] {
        ["Name:\(banner.expanded ? "Hide" : "Show") Details\nTarget:fixture", "Close"]
    }
'''

checks = r'''
}
extension Watcher {
    static func fixture(_ tokens: [String] = ["a"]) -> (Watcher, AXUIElement, [AXUIElement]) {
        Trace.events = []
        let watcher = Watcher(), app = AXUIElement(99), window = AXUIElement(1)
        window.attributes = [kAXSubroleAttribute: "AXSystemDialog",
                             kAXPositionAttribute: CGPoint(x: 120, y: 40)]
        let banners = tokens.enumerated().map { index, token in
            let banner = AXUIElement(UInt(index + 2))
            banner.attributes = [kAXIdentifierAttribute: token, kAXWindowAttribute: window]
            watcher.live[token] = banner
            return banner
        }
        window.children = banners
        app.attributes[kAXWindowsAttribute] = [window]
        watcher.appElement = app
        watcher.pollTimer = InertTimer()
        return (watcher, window, banners)
    }
    func tick() { lastRefresh = .distantPast; refreshHeldBanners() }
    static func run(baseline: Bool) {
        let origin = CGPoint(x: 120, y: 40)
        do {
            let (w, window, banners) = fixture()
            w.hold(token: "a")
            w.tick()
            Trace.check(window.writes.isEmpty && !banners[0].expanded, "closed hold must stay visible and unexpanded")
            Trace.check(w.held == ["a"] && w.skipLogged == ["a"], "closed hold must remain tracked")
            Trace.events.append("closed hold visible")
            w.notchOpen = true
            let parkedBeforeTick = window.cgPointAttribute(kAXPositionAttribute) == offscreen
            w.tick()
            if baseline {
                Trace.check(!parkedBeforeTick && banners[0].expanded && window.writes.isEmpty,
                            "original opening must reproduce expansion without parking")
                print("BASELINE FAILURE REPRODUCED: " + Trace.events.joined(separator: " -> "))
                return
            }
            Trace.check(parkedBeforeTick && banners[0].expanded, "opening must park synchronously before expansion")
            Trace.check(Trace.events == ["closed hold visible", "park window=1", "expand a parked=true"], "parking must precede expansion")
            Trace.check(w.skipLogged.isEmpty, "opening must rearm skip log")
            w.notchOpen = true
            w.hold(token: "a")
            Trace.check(window.writes == [offscreen] && w.parkedWindowOrigins[1] == origin, "repeat open/hold must retain first origin")
            w.release(token: "a")
            w.release(token: "a")
            Trace.check(window.writes == [offscreen, origin], "repeat release must restore only once")
            Trace.check(w.held.isEmpty && w.parkedWindowByToken.isEmpty && w.parkedWindowOrigins.isEmpty, "release clears bookkeeping")
            Trace.report("closed hold opens before expansion; repeat open/hold/release stays balanced")
        }
        do {
            let (w, window, banners) = fixture(["a", "b"])
            for token in ["a", "b"] { w.hold(token: token) }
            w.notchOpen = true
            Trace.check(w.parkedWindowByToken.count == 2 && w.parkedWindowOrigins == [1: origin], "all existing shared-window holds park from snapshot")
            Trace.check(window.writes == [offscreen, offscreen], "both tokens register the same window")
            w.tick()
            Trace.check(banners.allSatisfy { $0.expanded }, "all held banners expand")
            w.release(token: "a")
            Trace.check(window.writes.count == 2 && w.parkedWindowOrigins[1] == origin, "first shared release must not restore")
            w.release(token: "b")
            Trace.check(window.writes == [offscreen, offscreen, origin] && w.parkedWindowOrigins.isEmpty, "final shared release restores first origin")
            Trace.report("two tokens share one origin; only final release restores")
        }
        do {
            let (w, window, banners) = fixture()
            w.hold(token: "a"); w.notchOpen = true; w.tick()
            w.notchOpen = false
            Trace.check(!banners[0].expanded && window.writes == [offscreen], "close collapses without ending park")
            w.notchOpen = false
            w.tick()
            Trace.check(Trace.events.filter { $0 == "collapse a" }.count == 1 && w.skipLogged == ["a"], "repeat close collapses once; closed refresh skips")
            w.notchOpen = true; w.tick()
            Trace.check(banners[0].expanded && window.writes == [offscreen] && w.parkedWindowOrigins[1] == origin, "reopen must not overwrite original position")
            w.release(token: "a")
            Trace.check(window.writes == [offscreen, origin], "release after reopen restores original")
            Trace.report("close collapses once; reopen preserves original position")
        }
        do {
            let (w, window, _) = fixture(["a", "b"])
            for token in ["a", "b"] { w.hold(token: token) }
            w.notchOpen = true
            var gone: [String] = []
            w.onBannerGone = { gone.append($0) }
            window.children.removeFirst()
            w.scanImpl()
            Trace.check(gone == ["a"] && w.live["a"] == nil && window.writes.count == 2, "first gone token must preserve shared park")
            window.children = []
            w.scanImpl()
            Trace.check(gone == ["a", "b"] && w.live.isEmpty && window.writes.last == origin, "last gone token restores existing window")
            Trace.check(w.parkedWindowOrigins.isEmpty && w.parkedWindowByToken.isEmpty, "gone clears park bookkeeping")
            w.notchOpen = false; w.notchOpen = true
            Trace.check(window.writes.count == 3, "stale held tokens with no live banner must not repark")
            w.stop()
            Trace.check(w.held.isEmpty, "stop clears remaining gone holds")
            Trace.report("banner-gone scan restores only final shared hold; stale tokens cannot repark")
        }
        do {
            let (w, window, _) = fixture()
            w.hold(token: "a"); w.notchOpen = true
            w.appElement!.attributes[kAXWindowsAttribute] = [AXUIElement]()
            w.scanImpl()
            Trace.check(window.writes == [offscreen] && w.parkedWindowByToken.isEmpty && w.parkedWindowOrigins.isEmpty, "destroyed window drops bookkeeping without a move")
            Trace.report("destroyed window drops park bookkeeping")
        }
        do {
            let (w, window, _) = fixture(["a", "b"])
            for token in ["a", "b"] { w.hold(token: token) }
            w.notchOpen = true
            let timer = w.pollTimer!
            w.stop(); w.stop()
            Trace.check(window.writes == [offscreen, offscreen, origin], "stop restores shared window once before clearing app")
            Trace.check(timer.cancelled && w.pollTimer == nil && w.appElement == nil, "stop cancels timer and clears app")
            Trace.check(w.held.isEmpty && w.live.isEmpty && w.skipLogged.isEmpty && w.parkedWindowByToken.isEmpty && w.parkedWindowOrigins.isEmpty, "stop clears all lifecycle state")
            Trace.report("repeated stop restores once and clears lifecycle state")
        }
        print("RESULT: 6 scenarios; \(Trace.assertions) assertions; 0 failures")
    }
}
@main struct BannerRegression {
    static func main() { Watcher.run(baseline: __BASELINE__) }
}
'''

print("Stand-ins: in-memory AX attributes/actions/identity and successful position writes; inert timer; flat banner hierarchy; capture/cadence/logging stubbed. Real production lifecycle bodies and Foundation time; refresh clock reset between explicit ticks. No real AX, UI, app, messages or clipboard access.", flush=True)
for baseline in (True, False):
    name = "banner-baseline" if baseline else "banner-regression"
    swift = work / f"{name}.swift"
    # Removing only the added replay reconstructs the original opening behavior;
    # all hold/release/restore/refresh/scan/stop bodies remain identical.
    property_source = opening.replace(replay, "") if baseline else opening
    swift.write_text(standins + state + property_source + "\n" + methods +
                     checks.replace("__BASELINE__", str(baseline).lower()))
    binary = work / name
    subprocess.run(["swiftc", "-module-cache-path", str(work / "module-cache"),
                    "-parse-as-library", str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
