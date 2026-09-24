#!/usr/bin/env python3
"""Compile actual keyboard brightness classes with inert XPC and OSD dependencies."""

import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--work-dir", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
work = args.work_dir or Path(tempfile.mkdtemp(prefix="pr1057-brightness-"))
work.mkdir(parents=True, exist_ok=True)
path = "boringNotch/components/OSD/Managers/XPC/BrightnessManager.swift"
current = (root / path).read_text()
baseline = subprocess.check_output(["git", "show", f"f4372f5:{path}"], cwd=root, text=True)
marker = "final class KeyboardBacklightManager: ObservableObject {"
assert current.split(marker)[0] == baseline.split(marker)[0], "Screen brightness changed"
print("PASS: screen brightness source is byte-for-byte unchanged (1 assertion)", flush=True)

fixture = r'''
import Foundation
import Combine

@MainActor final class XPCHelperClient {
    nonisolated static let shared = XPCHelperClient()
    nonisolated private init() {}
    var hardware: Float = 0.5
    var available = true
    var accepts = true
    var reads = 0
    var targets: [Float] = []
    var onRead: (() -> Void)?
    var onSet: (() -> Void)?
    func currentKeyboardBrightness() async -> Float? {
        reads += 1
        let callback = onRead
        onRead = nil
        callback?()
        return available ? hardware : nil
    }
    func setKeyboardBrightness(_ value: Float) async -> Bool {
        targets.append(value)
        let callback = onSet
        onSet = nil
        callback?()
        if accepts { hardware = value }
        return accepts
    }
}
enum PeekType { case backlight }
enum Event { case sneakPeek(type: PeekType, value: CGFloat) }
@MainActor enum NotchUIEventBus {
    static let events = Bus()
    final class Bus {
        var values: [Float] = []
        var publishedValues: [Float] = []
        var manager: KeyboardBacklightManager?
        func send(_ event: Event) {
            if case .sneakPeek(_, let value) = event {
                values.append(Float(value))
                publishedValues.append(manager!.rawBrightness)
            }
        }
    }
}
'''

checks = r'''
// Same-file access exposes construction and completion only; production methods
// and the real main-queue publication behavior are compiled without alteration.
extension KeyboardBacklightManager {
    static func fixture() -> KeyboardBacklightManager { KeyboardBacklightManager() }
    @MainActor func waitForFlush() async { await flushTask?.value }
}
@main struct BrightnessRegression {
    @MainActor static var assertions = 0
    @MainActor static var scenarios = 0
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        assertions += 1
        precondition(condition(), label)
    }
    @MainActor static func report(_ label: String) {
        scenarios += 1
        print(label)
    }
    static func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
    @MainActor static func fresh() async -> KeyboardBacklightManager {
        let client = XPCHelperClient.shared
        client.hardware = 0.5
        client.available = true
        client.accepts = true
        client.reads = 0
        client.targets = []
        client.onRead = nil
        client.onSet = nil
        let bus = NotchUIEventBus.events
        bus.values = []
        bus.publishedValues = []
        let manager = KeyboardBacklightManager.fixture()
        bus.manager = manager
        while client.reads == 0 { await Task.yield() }
        await drainMainQueue()
        check(manager.rawBrightness == 0.5, "startup refresh")
        check(manager.lastChangeAt == .distantPast, "refresh must not touch date")
        client.reads = 0
        return manager
    }
    @MainActor static func main() async {
        let original = CommandLine.arguments.contains("--original")
        let client = XPCHelperClient.shared
        let bus = NotchUIEventBus.events

        var manager = await fresh()
        // Re-enter while the first set is in flight, before its publication.
        client.onSet = { manager.setRelative(delta: 0.0625) }
        manager.setRelative(delta: 0.0625)
        await manager.waitForFlush()
        let expected: [Float] = original ? [0.5625, 0.5625] : [0.5625, 0.625]
        check(client.targets == expected, "queued repeat must accumulate")
        check(bus.values == expected, "OSD values match successful targets")
        check(bus.publishedValues == (original ? [0.5, 0.5] : expected), "state published before OSD and next adjustment")
        check(client.reads == (original ? 0 : 2), "each fixed flush reads hardware")
        await drainMainQueue()
        check(manager.rawBrightness == expected.last!, "final working value")
        check(manager.lastChangeAt != .distantPast, "successful relative set touches date")
        report("\(original ? "BEFORE" : "PASS"): repeated +0.0625 from 0.5 -> \(client.targets); state at OSD -> \(bus.publishedValues)")

        manager = await fresh()
        client.hardware = 0.875 // An external change after the app's last refresh.
        manager.setRelative(delta: -0.0625)
        await manager.waitForFlush()
        check(client.targets == [original ? 0.4375 : 0.8125], "external change is adjustment base")
        check(client.reads == (original ? 0 : 1), "fresh read after external change")
        report("\(original ? "BEFORE" : "PASS"): external 0.875 then -0.0625 -> \(client.targets)")
        await drainMainQueue()
        if original {
            print("BASELINE: \(scenarios) scenarios, \(assertions) assertions; both regressions reproduced")
            return
        }

        manager = await fresh()
        manager.setRelative(delta: 0.0625)
        manager.setRelative(delta: 0.0625)
        manager.setRelative(delta: 0.0625)
        await manager.waitForFlush()
        check(client.targets == [0.6875] && client.reads == 1, "pre-flush repeats coalesce")
        report("PASS: three pre-flush repeats coalesce into one read/set -> \(client.targets)")

        manager = await fresh()
        client.onRead = {
            manager.setRelative(delta: 0.0625)
            manager.setRelative(delta: 0.0625)
        }
        manager.setRelative(delta: 0.0625)
        await manager.waitForFlush()
        check(client.targets == [0.5625, 0.6875] && client.reads == 2, "repeats during read coalesce next flush")
        check(bus.publishedValues == client.targets, "each coalesced result publishes synchronously")
        report("PASS: two repeats during read coalesce into the next flush -> \(client.targets)")

        manager = await fresh()
        client.hardware = 0.96875
        manager.setRelative(delta: 0.0625)
        await manager.waitForFlush()
        client.hardware = 0.03125
        manager.setRelative(delta: -0.0625)
        await manager.waitForFlush()
        check(client.targets == [1, 0] && client.reads == 2, "upper and lower clamping")
        check(manager.rawBrightness == 0 && bus.values == [1, 0], "clamped state and OSD")
        report("PASS: external values near bounds clamp to \(client.targets)")

        manager = await fresh()
        client.available = false
        manager.setRelative(delta: 0.0625)
        await manager.waitForFlush()
        await drainMainQueue()
        check(client.targets.isEmpty && bus.values.isEmpty, "unavailable read must not write or show success")
        check(manager.rawBrightness == 0.5 && manager.lastChangeAt == .distantPast, "unavailable read preserves state")
        check(client.reads == 2, "unavailable read follows refresh recovery")
        client.available = true
        client.hardware = 0.75
        manager.setRelative(delta: -0.0625)
        await manager.waitForFlush()
        check(client.targets == [0.6875] && manager.rawBrightness == 0.6875, "read failure does not wedge next adjustment")
        report("PASS: unavailable read performs no write/OSD; next adjustment recovers -> \(client.targets)")

        manager = await fresh()
        client.hardware = 0.875
        client.accepts = false
        manager.setRelative(delta: -0.0625)
        await manager.waitForFlush()
        await drainMainQueue()
        check(client.targets == [0.8125] && bus.values.isEmpty, "failed set must not show success")
        check(client.hardware == 0.875 && manager.rawBrightness == 0.875, "failed set refreshes actual state")
        check(manager.lastChangeAt == .distantPast && client.reads == 2, "failed set preserves date and refreshes")
        client.accepts = true
        manager.setRelative(delta: -0.0625)
        await manager.waitForFlush()
        check(client.targets == [0.8125, 0.8125] && manager.rawBrightness == 0.8125, "set failure does not wedge next adjustment")
        check(bus.publishedValues == [0.8125], "only successful recovered set publishes OSD")
        report("PASS: rejected set refreshes 0.875 without success OSD; next adjustment recovers to 0.8125")

        manager = await fresh()
        manager.setRelative(delta: 0)
        await manager.waitForFlush()
        check(client.reads == 0 && client.targets.isEmpty && bus.values.isEmpty, "zero delta is inert")
        report("PASS: zero delta performs no read, set or OSD")
        print("FIXED: \(scenarios) scenarios, \(assertions) assertions passed")
    }
}
'''

for name, source in [("baseline", baseline), ("fixed", current)]:
    swift = work / f"BrightnessRegression-{name}.swift"
    swift.write_text(fixture + source[source.index(marker):] + checks)
    binary = work / f"brightness-regression-{name}"
    subprocess.run(["swiftc", "-module-cache-path", str(work / "module-cache"),
                    "-parse-as-library", str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary)] + (["--original"] if name == "baseline" else []),
                   check=True, timeout=30)
