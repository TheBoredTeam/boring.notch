#!/usr/bin/env python3
"""Compile the complete production display manager with inert dependencies.

No AppKit/SwiftUI, real windows, event monitors, preferences, or app launch.
The baseline uses the same fixtures against the actual class at f4372f5.
"""

import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MANAGER = "boringNotch/managers/NotchWindowManager.swift"

STANDINS = r'''
import Foundation

// All app/UI dependencies below are in-memory stand-ins. The complete manager
// is appended unchanged apart from removing its two unavailable module imports.
struct Point: Hashable { var x: Double; var y: Double }
struct Size: Hashable { var width: Double; var height: Double }
struct Rect: Hashable {
    var origin: Point
    var size: Size
    init(x: Double, y: Double, width: Double, height: Double) {
        origin = Point(x: x, y: y); size = Size(width: width, height: height)
    }
    var width: Double { size.width }
    var height: Double { size.height }
    var midX: Double { origin.x + width / 2 }
    var maxY: Double { origin.y + height }
}
typealias NSRect = Rect
typealias CGRect = Rect
typealias NSPoint = Point
let windowSize = Size(width: 600, height: 200)
let openNotchSize = Size(width: 600, height: 200)
func getClosedNotchSize(screenUUID: String?) -> Size { Size(width: 200, height: 30) }
func syncNotchHeightIfNeeded() {}

@MainActor enum Defaults {
    enum Key: Hashable {
        case showOnLockScreen, showOnAllDisplays, automaticallySwitchDisplay
        case expandedDragDetection, boringShelf
    }
    static var values: [Key: Bool] = [:]
    static subscript(key: Key) -> Bool {
        get { values[key] ?? false }
        set { values[key] = newValue }
    }
}
@MainActor final class NSScreen: Equatable {
    static var screens: [NSScreen] = []
    static var main: NSScreen? { screens.first }
    let displayUUID: String?
    let frame: Rect
    init(_ uuid: String, x: Double = 0, width: Double = 1440) {
        displayUUID = uuid; frame = Rect(x: x, y: 0, width: width, height: 900)
    }
    static func screen(withUUID uuid: String) -> NSScreen? {
        screens.first { $0.displayUUID == uuid }
    }
    nonisolated static func == (lhs: NSScreen, rhs: NSScreen) -> Bool { lhs === rhs }
}
@MainActor class NSWindow: Hashable {
    struct StyleMask: OptionSet {
        let rawValue: Int
        static let borderless = Self(rawValue: 1)
        static let nonactivatingPanel = Self(rawValue: 2)
        static let utilityWindow = Self(rawValue: 4)
        static let hudWindow = Self(rawValue: 8)
    }
    enum Backing { case buffered }
    static let didChangeScreenNotification = "fixture-screen-change"
    var frame: Rect
    var screen: NSScreen?
    var contentView: Any?
    var alphaValue: Double = 1
    var isVisible = false
    var closed = false
    init(contentRect: Rect, styleMask: StyleMask, backing: Backing, defer: Bool) {
        frame = contentRect
    }
    func close() { closed = true; isVisible = false }
    func orderFrontRegardless() { isVisible = true }
    func orderOut(_ sender: Any?) { isVisible = false }
    func setFrameOrigin(_ point: Point) {
        frame.origin = point
        screen = NSScreen.screens.first {
            point.x >= $0.frame.origin.x && point.x < $0.frame.origin.x + $0.frame.width
        }
    }
    nonisolated static func == (lhs: NSWindow, rhs: NSWindow) -> Bool { lhs === rhs }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
@MainActor final class BoringNotchSkyLightWindow: NSWindow {
    func enableSkyLight() {}
    func disableSkyLight() {}
}
struct ContentView {
    func environmentObject(_ model: BoringViewModel) -> Self { self }
}
struct NSHostingView { init(rootView: ContentView) {} }
// Notification registration is inert; DispatchQueue executes synchronously.
// Drag callbacks still traverse the manager's real Swift Task/MainActor code.
@MainActor final class NotificationCenter {
    static let `default` = NotificationCenter()
    enum Queue { case main }
    func addObserver(forName: String, object: NSWindow, queue: Queue,
                     using: @escaping (Int) -> Void) -> Any { NSObject() }
    func removeObserver(_ observer: Any) {}
}
@MainActor enum DispatchQueue {
    static let main = Self.queue
    case queue
    func async(execute work: () -> Void) { work() }
}
@MainActor final class BoringViewModel {
    enum State { case closed, open }
    var screenUUID: String?
    var notchSize = Size(width: 200, height: 30)
    var notchState = State.closed
    init(screenUUID: String? = nil) { self.screenUUID = screenUUID }
    func open() -> Bool { notchState = .open; return true }
    func close() { notchState = .closed }
}
@MainActor final class BoringViewCoordinator {
    static let shared = BoringViewCoordinator()
    enum View { case home, shelf }
    var preferredScreenUUID: String?
    var selectedScreenUUID = ""
    var currentView = View.home
    func applyOSDSources() {}
}
@MainActor final class NotchSpaceManager {
    static let shared = NotchSpaceManager()
    struct Space { var windows = Set<NSWindow>() }
    var notchSpace = Space()
}
@MainActor final class DragDetector {
    final class Weak { weak var value: DragDetector?; init(_ value: DragDetector) { self.value = value } }
    static var instances: [Weak] = []
    static var live: [DragDetector] { instances.compactMap(\.value) }
    static var active: [DragDetector] { live.filter(\.monitoring) }
    var monitoring = false
    var stops = 0
    var onDragEntersNotchRegion: (() -> Void)?
    let notchRegion: Rect
    init(notchRegion: Rect) { self.notchRegion = notchRegion; Self.instances.append(Weak(self)) }
    func startMonitoring() { monitoring = true }
    func stopMonitoring() { monitoring = false; stops += 1 }
}
'''

CHECKS = r'''
@main struct DisplayRegression {
    @MainActor static var assertions = 0
    @MainActor static var scenarios = 0
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }
    @MainActor static func pass(_ message: String) {
        scenarios += 1; print("PASS: \(message)")
    }
    @MainActor static func reset(all: Bool = false, enabled: Bool = true) -> NotchWindowManager {
        check(DragDetector.active.isEmpty, "previous scenario leaked active detector")
        NSScreen.screens = [NSScreen("A"), NSScreen("B", x: 1440)]
        Defaults.values = [.showOnAllDisplays: all, .expandedDragDetection: enabled,
                           .automaticallySwitchDisplay: true, .boringShelf: true]
        BoringViewCoordinator.shared.preferredScreenUUID = "A"
        BoringViewCoordinator.shared.selectedScreenUUID = "A"
        BoringViewCoordinator.shared.currentView = .home
        NotchSpaceManager.shared.notchSpace.windows.removeAll()
        return NotchWindowManager()
    }
    // These are the actual operation orders used by AppDelegate's observers.
    @MainActor static func select(_ uuid: String, _ manager: NotchWindowManager) {
        BoringViewCoordinator.shared.preferredScreenUUID = uuid
        manager.adjustWindowPosition(changeAlpha: true)
        manager.setupDragDetectors()
    }
    @MainActor static func toggle(_ all: Bool, _ manager: NotchWindowManager) {
        Defaults[.showOnAllDisplays] = all
        manager.cleanupWindows(shouldInvert: true)
        manager.adjustWindowPosition(changeAlpha: true)
        manager.setupDragDetectors()
    }
    @MainActor static func enterA(_ manager: NotchWindowManager) async {
        manager.contexts["A"]!.dragDetector!.onDragEntersNotchRegion!()
        for _ in 0..<100 where manager.viewModels["A"]!.notchState != .open {
            await Task.yield()
        }
        check(manager.viewModels["A"]!.notchState == .open, "A callback must open A")
    }
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--baseline") {
            let manager = reset()
            select("A", manager); select("B", manager)
            check(manager.contexts.count == 2, "baseline must contaminate contexts")
            print("BEFORE single A→B: contexts=[A,B], both models=primary, both screenUUID=B")
            check(manager.viewModels.values.allSatisfy { $0 === manager.primaryViewModel && $0.screenUUID == "B" }, "baseline primary alias")
            toggle(true, manager)
            check(manager.viewModels["A"] === manager.viewModels["B"], "baseline models alias")
            await enterA(manager)
            check(manager.viewModels["B"]!.notchState == .open, "baseline opens B too")
            print("BEFORE all displays, drag A: A=open, B=open, A.screenUUID=B, B.screenUUID=B")
            manager.cleanupDragDetectors()
            check(manager.contexts.values.filter { $0.dragDetector != nil }.count == 2, "baseline retains stopped detectors")
            check(DragDetector.active.isEmpty, "baseline detectors were stopped")
            print("BEFORE cleanup: active=0, stored multi detectors=2")
            manager.cleanup()
            let noWindow = reset()
            noWindow.setupDragDetectors(); noWindow.cleanupWindows()
            check(noWindow.primaryWindow == nil && DragDetector.active.count == 1, "baseline cleanup without window leaks detector")
            print("BEFORE single cleanup without window: active=1, stored contexts=1")
            noWindow.cleanup()
            print("Baseline reproduced 4 failures against actual f4372f5 manager")
            return
        }

        let manager = reset()
        select("A", manager)
        let originalDetector = DragDetector.active.first!
        select("B", manager)
        check(!originalDetector.monitoring, "switch stops A detector")
        check(manager.contexts.isEmpty, "single mode never populates per-display contexts")
        check(manager.primaryViewModel.screenUUID == "B", "primary follows B")
        toggle(true, manager)
        check(manager.primaryWindow == nil, "single window removed on toggle")
        check(Set(manager.contexts.keys) == ["A", "B"], "all displays creates both contexts")
        check(manager.viewModels["A"] !== manager.viewModels["B"], "models are separate")
        check(manager.viewModels.values.allSatisfy { $0 !== manager.primaryViewModel }, "per-display models never alias primary")
        check(manager.viewModels["A"]!.screenUUID == "A" && manager.viewModels["B"]!.screenUUID == "B", "correct screen identities")
        check(DragDetector.active.count == 2, "exactly one detector per display")
        pass("single A→B→all: single contexts=0; all models distinct with UUIDs A,B")

        let bSize = manager.viewModels["B"]!.notchSize
        await enterA(manager)
        check(manager.viewModels["B"]!.notchState == .closed, "opening A leaves B closed")
        check(manager.viewModels["B"]!.notchSize == bSize, "opening A leaves B size unchanged")
        check(manager.viewModels["B"]!.screenUUID == "B", "opening A leaves B identity unchanged")
        check(manager.primaryViewModel.notchState == .closed, "opening A leaves primary closed")
        check(BoringViewCoordinator.shared.currentView == .shelf, "drag selects shelf")
        pass("drag callback on A: A=open, B=closed, B.screenUUID=B, primary=closed")

        for _ in 0..<3 {
            let oldMulti = DragDetector.active
            toggle(false, manager)
            check(oldMulti.allSatisfy { !$0.monitoring }, "toggle stops all old multi detectors")
            check(manager.contexts.isEmpty && manager.primaryWindow != nil, "single owns only primary window")
            check(DragDetector.active.count == 1, "one primary detector after toggle")
            let primary = DragDetector.active[0]
            toggle(true, manager)
            check(!primary.monitoring, "toggle stops primary detector")
            check(DragDetector.active.count == 2 && manager.primaryWindow == nil, "all owns two detectors")
            check(manager.viewModels["A"] !== manager.viewModels["B"], "toggle keeps model isolation")
        }
        pass("3 repeated all→single→all toggles stop old detectors and preserve isolated models")

        let releasedMulti = DragDetector.Weak(manager.contexts["A"]!.dragDetector!)
        manager.cleanupDragDetectors()
        check(manager.contexts.values.allSatisfy { $0.dragDetector == nil }, "cleanup nils stored context detectors")
        check(releasedMulti.value == nil, "cleanup releases multi detector")
        check(DragDetector.active.isEmpty, "cleanup stops all detectors")
        manager.cleanupDragDetectors()
        check(manager.contexts.count == 2, "detector cleanup preserves display windows/models")
        manager.cleanup()
        pass("multi cleanup: active=0, stored detectors=0, stopped references released; repeated cleanup safe")

        for all in [false, true] {
            let closing = reset(all: all)
            closing.prepareInitialWindows()
            let detectors = DragDetector.active
            let windows = Array(closing.windows.values) + [closing.primaryWindow].compactMap { $0 }
            closing.cleanupWindows()
            check(detectors.allSatisfy { !$0.monitoring && $0.stops == 1 }, "window cleanup itself stops detectors")
            check(windows.allSatisfy(\.closed), "window cleanup closes every window")
            check(closing.contexts.isEmpty && closing.primaryWindow == nil, "window cleanup removes owned windows and contexts")
            check(NotchSpaceManager.shared.notchSpace.windows.isEmpty, "window cleanup removes space registrations")
            closing.cleanupDragDetectors()
            check(detectors.allSatisfy { $0.stops == 1 }, "window cleanup already cleared stored detector references")
        }
        pass("cleanupWindows in both modes stops and clears detectors immediately, closes windows and clears space registrations")

        let missing = reset(all: true)
        missing.setupDragDetectors()
        check(missing.contexts.isEmpty && DragDetector.active.isEmpty, "setup cannot invent missing contexts")
        missing.adjustWindowPosition(); missing.setupDragDetectors()
        check(missing.contexts.count == 2 && DragDetector.active.count == 2, "setup works after windows established")
        missing.cleanup()
        pass("all-display setup before windows creates no contexts or monitors; setup after windows creates two")

        let removal = reset(all: true)
        removal.prepareInitialWindows()
        let oldBModel = removal.viewModels["B"]!
        let oldBWindow = removal.windows["B"]!
        let oldBDetector = removal.contexts["B"]!.dragDetector!
        NSScreen.screens.removeLast()
        removal.adjustWindowPosition(); removal.setupDragDetectors()
        check(removal.contexts["B"] == nil && oldBWindow.closed && !oldBDetector.monitoring, "removed display completely cleaned")
        check(DragDetector.active.count == 1, "only A monitored after removal")
        NSScreen.screens.append(NSScreen("B", x: 1440))
        removal.adjustWindowPosition(); removal.setupDragDetectors()
        check(removal.viewModels["B"] !== oldBModel, "reconnected display gets fresh model")
        check(removal.viewModels["B"]!.screenUUID == "B" && DragDetector.active.count == 2, "reconnected display setup correct")
        removal.noteInitialScreens()
        let priorDetectors = DragDetector.active
        NSScreen.screens = [NSScreen("B", x: 1440)]
        removal.screenConfigurationDidChange()
        check(priorDetectors.allSatisfy { !$0.monitoring }, "configuration callback stops old detectors")
        check(Set(removal.contexts.keys) == ["B"] && DragDetector.active.count == 1, "configuration callback rebuilds surviving display")
        removal.cleanup()
        pass("display removal/reconnect and configuration callback stop old monitors and rebuild correct contexts")

        for all in [false, true] {
            let disabled = reset(all: all)
            disabled.prepareInitialWindows()
            let released = DragDetector.Weak(DragDetector.active.first!)
            Defaults[.expandedDragDetection] = false
            disabled.setupDragDetectors()
            check(DragDetector.active.isEmpty && released.value == nil, "disabling releases and stops detectors")
            check(disabled.contexts.values.allSatisfy { $0.dragDetector == nil }, "disabled retains no context detector")
            disabled.setupDragDetectors()
            check(DragDetector.active.isEmpty, "disabled setup starts no detector")
            Defaults[.expandedDragDetection] = true
            disabled.setupDragDetectors()
            check(DragDetector.active.count == (all ? 2 : 1), "reenabling restores exact detector count")
            disabled.cleanup()
        }
        pass("disabled monitoring stops, releases and clears references in both modes; reenabling restores monitoring")

        // NotificationCenter is inert: unlock must restore monitoring itself.
        for all in [false, true] {
            for enabled in [true, false] {
                let locking = reset(all: all, enabled: enabled)
                Defaults[.showOnLockScreen] = false
                locking.prepareInitialWindows()
                let expectedDetectors = enabled ? (all ? 2 : 1) : 0
                check(DragDetector.active.count == expectedDetectors, "initial lock scenario detector count")
                for _ in 0..<2 {
                    let beforeLock = DragDetector.active
                    locking.screenLocked()
                    check(locking.isScreenLocked && DragDetector.active.isEmpty, "lock stops every detector")
                    check(beforeLock.allSatisfy { !$0.monitoring }, "old detectors stopped during lock")
                    check(locking.primaryWindow == nil && locking.contexts.isEmpty, "lock removes windows and contexts")
                    locking.screenUnlocked()
                    check(!locking.isScreenLocked && DragDetector.active.count == expectedDetectors, "unlock restores exact detector count without notifications")
                    check(Defaults[.expandedDragDetection] == enabled, "unlock preserves monitoring preference")
                    if all {
                        check(Set(locking.contexts.keys) == ["A", "B"], "unlock restores both displays")
                        check(locking.viewModels["A"] !== locking.viewModels["B"], "unlock preserves model isolation")
                        check(locking.viewModels["A"]!.screenUUID == "A" && locking.viewModels["B"]!.screenUUID == "B", "unlock restores screen identities")
                        check(locking.primaryWindow == nil, "all-display unlock keeps primary window absent")
                        if enabled {
                            await enterA(locking)
                            check(locking.viewModels["B"]!.notchState == .closed, "post-unlock drag A leaves B closed")
                        } else {
                            check(locking.contexts.values.allSatisfy { $0.dragDetector == nil }, "disabled unlock creates no stored detectors")
                        }
                    } else {
                        check(locking.contexts.isEmpty, "single unlock creates no per-display contexts")
                        check(locking.primaryWindow?.screen?.displayUUID == "A" && locking.primaryViewModel.screenUUID == "A", "single unlock restores A window and model")
                        if enabled {
                            DragDetector.active[0].onDragEntersNotchRegion!()
                            for _ in 0..<100 where locking.primaryViewModel.notchState != .open {
                                await Task.yield()
                            }
                            check(locking.primaryViewModel.notchState == .open, "post-unlock primary drag callback works")
                            locking.primaryViewModel.close()
                        }
                    }
                    let beforeRepeatedUnlock = DragDetector.active
                    locking.screenUnlocked()
                    check(beforeRepeatedUnlock.allSatisfy { !$0.monitoring }, "repeated unlock stops replaced monitors")
                    check(DragDetector.active.count == expectedDetectors, "repeated unlock creates no duplicate monitors")
                }
                locking.cleanup()
                pass("lock/unlock \(all ? "all" : "single") \(enabled ? "enabled" : "disabled"): active=\(expectedDetectors)→0→\(expectedDetectors); 2 cycles and repeated unlocks preserve display state without screen notifications")
            }
        }

        let noWindow = reset()
        noWindow.setupDragDetectors()
        check(noWindow.primaryWindow == nil && noWindow.contexts.isEmpty && DragDetector.active.count == 1, "fallback setup has separate primary detector")
        let releasedPrimary = DragDetector.Weak(DragDetector.active.first!)
        noWindow.cleanupWindows()
        check(DragDetector.active.isEmpty && releasedPrimary.value == nil, "single cleanup without window stops and releases primary detector")
        noWindow.cleanupWindows()
        check(noWindow.contexts.isEmpty, "single cleanup never creates contexts")
        pass("single cleanup without window: active=0, contexts=0, primary detector released")
        print("PASS: \(scenarios) scenarios, \(assertions) assertions; no real windows, monitors, preferences or app launch")
    }
}
'''


def compile_and_run(source: str, name: str, work: Path, baseline: bool = False):
    imports = "import Defaults\nimport SwiftUI"
    assert source.count(imports) == 1, "Expected production module imports"
    production = source.replace(imports, "", 1)
    swift = work / f"{name}.swift"
    swift.write_text(STANDINS + production + CHECKS)
    binary = work / name
    subprocess.run([
        "xcrun", "swiftc", "-module-cache-path", str(work / "module-cache"),
        "-parse-as-library", str(swift), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)] + (["--baseline"] if baseline else []), check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path)
    args = parser.parse_args()
    work = args.work_dir or Path(tempfile.mkdtemp(prefix="pr1057-display-"))
    work.mkdir(parents=True, exist_ok=True)
    print("Production: complete NotchWindowManager class; only its module imports removed.", flush=True)
    print("Stand-ins: geometry, NSScreen, NSWindow/SkyLight/SwiftUI hosting, Defaults, view model/coordinator, NotchSpaceManager, DragDetector, inert NotificationCenter, inline DispatchQueue, notch size helpers. Swift Task/MainActor remains real.", flush=True)
    baseline = subprocess.check_output(["git", "show", f"f4372f5:{MANAGER}"], cwd=ROOT, text=True)
    compile_and_run(baseline, "display-before", work, baseline=True)
    compile_and_run((ROOT / MANAGER).read_text(), "display-after", work)


if __name__ == "__main__":
    main()
