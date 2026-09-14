//
//  PanGestureScrollRoutingTests.swift
//  boringNotch
//
//  Focused calendar regression checks.
//

import AppKit
import Defaults
import SwiftUI

extension Defaults.Keys {
    static let normalizeGestureDirection = Key<Bool>("panRoutingTestNormalizeDirection", default: false)
}

private struct ScrollRoutingFixture: View {
    private let days = HomeCalendarGeometry.days(centeredOn: Date())

    var body: some View {
        HStack(spacing: 0) {
            Color.gray.frame(width: 250, height: 130)
            HomeCalendarScrollView(days: days, targetDay: Date(), targetDate: Date(), resetID: 0, height: 100, onScroll: { _ in }) {
                Color.blue.frame(width: HomeCalendarGeometry.width(of: days), height: 100)
            }
            .frame(width: 315, height: 100)
        }
        .frame(width: 565, height: 130)
        .panGesture(direction: .up) { _, _ in }
        .panGesture(direction: .down) { _, _ in }
        .panGesture(direction: .left) { _, _ in }
        .panGesture(direction: .right) { _, _ in }
    }
}

@main enum PanGestureScrollRoutingTests {
    @MainActor static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 565, height: 130), styleMask: .borderless, backing: .buffered, defer: false)
        let host = NSHostingView(rootView: ScrollRoutingFixture())
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.08))
        host.layoutSubtreeIfNeeded()

        let scrollView = fixture(descendants(host).compactMap { $0 as? HomeCalendarNativeScrollView }.first)
        var checks = 0
        func event(at point: NSPoint) -> NSEvent {
            fixture(NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 0, pressure: 0))
        }
        // Exercise the actual nested SwiftUI hosting view, clip view, and native scroll view.
        for x in [1.0, 100, 200, 314] {
            for y in [1.0, 50, 99] {
                let point = scrollView.convert(NSPoint(x: x, y: y), to: nil)
                precondition(PanGestureScrollRouting.targetsScrollView(event(at: point)), "Calendar point must keep wheel ownership: \(x),\(y)")
                checks += 1
            }
        }
        for point in [NSPoint(x: 40, y: 60), NSPoint(x: 200, y: 60), NSPoint(x: 400, y: 125)] {
            precondition(!PanGestureScrollRouting.targetsScrollView(event(at: point)), "Music/header must retain notch gestures")
            checks += 1
        }

        scrollView.move(to: 1000)
        let initial = scrollView.contentView.bounds.minX
        for delta: Int32 in [-50, 50] {
            let wheel = fixture(NSEvent(cgEvent: fixture(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                                wheel1: delta, wheel2: 0, wheel3: 0))))
            let old = scrollView.contentView.bounds.minX
            scrollView.scrollWheel(with: wheel)
            let new = scrollView.contentView.bounds.minX
            precondition(delta < 0 ? new > old : new < old, "Wheel must move in both directions")
            checks += 1
        }
        precondition(abs(scrollView.contentView.bounds.minX - initial) < 0.01, "Opposite wheel deltas must return to the original time")
        checks += 1
        let frozenGutter = NSClipView(frame: NSRect(x: 0, y: 0, width: 47, height: 100))
        frozenGutter.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 47, height: 700))
        host.addSubview(frozenGutter)
        for x in [1.0, 23, 46] {
            for y in [1.0, 99] {
                let point = frozenGutter.convert(NSPoint(x: x, y: y), to: nil)
                precondition(PanGestureScrollRouting.targetsScrollView(event(at: point)), "Frozen day labels must keep wheel ownership")
                checks += 1
            }
        }
        let today = Date()
        let days = HomeCalendarGeometry.days(centeredOn: today)
        let late = fixture(Calendar.current.date(bySettingHour: 23, minute: 30, second: 0, of: today))
        scrollView.position(on: today, near: late, in: days)
        let expected = HomeCalendarGeometry.viewportOffset(near: late, on: today, viewportWidth: scrollView.contentView.bounds.width, in: days)
        precondition(abs(scrollView.contentView.bounds.minX - expected) < 0.01, "After-hours Today must clamp the existing viewport inside today")
        precondition(Calendar.current.isDate(fixture(HomeCalendarGeometry.date(at: scrollView.contentView.bounds.midX, in: days)), inSameDayAs: today), "After-hours Today must not show tomorrow")
        checks += 2

        let initialScroll = HomeCalendarNativeScrollView(frame: .zero)
        initialScroll.borderType = .noBorder
        initialScroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: HomeCalendarGeometry.width(of: days), height: 100))
        initialScroll.position(on: today, near: late, in: days)
        initialScroll.frame = NSRect(x: 0, y: 0, width: 315, height: 100)
        initialScroll.needsLayout = true
        initialScroll.layoutSubtreeIfNeeded()
        let initialExpected = HomeCalendarGeometry.viewportOffset(near: late, on: today, viewportWidth: initialScroll.contentView.bounds.width, in: days)
        precondition(abs(initialScroll.contentView.bounds.minX - initialExpected) < 0.01, "Initial reset must wait for the viewport width before clamping")
        precondition(Calendar.current.isDate(fixture(HomeCalendarGeometry.date(at: initialScroll.contentView.bounds.midX, in: days)), inSameDayAs: today), "Initial after-hours view must remain on today")
        checks += 2
        initialScroll.documentView = nil

        let centeredScroll = HomeCalendarNativeScrollView(frame: .zero)
        centeredScroll.borderType = .noBorder
        centeredScroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: HomeCalendarGeometry.width(of: days), height: 100))
        var completed = 0
        var reportedScrolls = 0
        centeredScroll.didScroll = { reportedScrolls += 1 }
        centeredScroll.position(on: today, near: late, in: days, centered: true) {
            precondition(abs(centeredScroll.contentView.bounds.midX - fixture(HomeCalendarGeometry.currentTimeOffset(of: late, in: days))) < 0.01,
                         "Position completion must run after the hidden-time marker is centered")
            completed += 1
        }
        precondition(completed == 0, "A zero-width initial layout must defer the Today highlight callback")
        centeredScroll.frame = NSRect(x: 0, y: 0, width: 315, height: 100)
        centeredScroll.layoutSubtreeIfNeeded()
        precondition(completed == 1, "Position completion fires once after native layout resolves the viewport")
        centeredScroll.position(on: today, near: late, in: days, centered: true) { completed += 1 }
        precondition(completed == 2, "Today completion retriggers even when already centered at the same time")
        centeredScroll.needsLayout = true
        centeredScroll.layoutSubtreeIfNeeded()
        precondition(completed == 2, "Ordinary native relayout must not retrigger the highlight")
        precondition(reportedScrolls == 0, "Programmatic Today centering must preserve the selected day rather than report the adjacent gap date")
        checks += 6
        centeredScroll.documentView = nil
        print("PASS \(checks) native calendar wheel-routing checks")
    }
}

private func fixture<T>(_ value: T?) -> T {
    guard let value else { fatalError("Missing native calendar test fixture") }
    return value
}
