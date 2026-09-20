//
//  CalendarDayNativeScrollTests.swift
//  boringNotch
//

import AppKit

private final class CalendarDayScrollTestDocument: NSView {
    override var isFlipped: Bool { true }
}

@main enum CalendarDayNativeScrollTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let scrollView = CalendarDayNativeScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        let document = CalendarDayScrollTestDocument(frame: NSRect(x: 0, y: 0, width: 2400, height: 1800))
        scrollView.documentView = document
        scrollView.tile()
        defer { scrollView.documentView = nil }

        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        func expectOrigin(_ x: CGFloat, _ y: CGFloat, _ message: String) {
            let actual = scrollView.contentView.bounds.origin
            expect(abs(actual.x - x) < 0.01 && abs(actual.y - y) < 0.01,
                   "\(message): expected (\(x), \(y)), got \(actual)")
        }
        func event(horizontal: Int32 = 0, vertical: Int32 = 0, units: CGScrollEventUnit = .pixel) -> NSEvent {
            guard let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2,
                                        wheel1: vertical, wheel2: horizontal, wheel3: 0),
                  let event = NSEvent(cgEvent: cgEvent) else { preconditionFailure("Invalid scroll event fixture") }
            return event
        }
        let start = NSPoint(x: 800, y: 600)
        func reset() { scrollView.move(to: start) }

        reset()
        expectOrigin(start.x, start.y, "Programmatic positioning works without a window")
        let down = event(vertical: -40)
        expect(down.hasPreciseScrollingDeltas, "Pixel events must exercise precise trackpad routing")
        expect(down.scrollingDeltaX == 0 && down.scrollingDeltaY == -40, "Pixel fixture preserves the vertical delta")
        scrollView.scrollWheel(with: down)
        expectOrigin(800, 640, "Vertical gestures advance days without changing the hour")
        scrollView.scrollWheel(with: event(vertical: 40))
        expectOrigin(800, 600, "Reverse vertical gestures return to the previous day position")

        scrollView.scrollWheel(with: event(horizontal: -30))
        expectOrigin(830, 600, "Horizontal gestures advance hours without changing the day")
        scrollView.scrollWheel(with: event(horizontal: 30))
        expectOrigin(800, 600, "Reverse horizontal gestures restore the original hour")

        scrollView.scrollWheel(with: event(horizontal: -17, vertical: -29))
        expectOrigin(817, 629, "Diagonal gestures retain both independent axes")
        scrollView.scrollWheel(with: event(horizontal: 17, vertical: 29))
        expectOrigin(800, 600, "Opposite diagonal gestures cancel each other")
        scrollView.scrollWheel(with: event(horizontal: 0, vertical: 0))
        expectOrigin(800, 600, "An empty wheel event leaves the viewport unchanged")

        let coarse = event(horizontal: -2, vertical: -3, units: .line)
        expect(!coarse.hasPreciseScrollingDeltas, "Line events must exercise coarse mouse-wheel routing")
        expect(coarse.scrollingDeltaX < 0 && coarse.scrollingDeltaY < 0, "Coarse fixture has two negative deltas")
        scrollView.scrollWheel(with: coarse)
        expectOrigin(start.x - coarse.scrollingDeltaX * 12, start.y - coarse.scrollingDeltaY * 12,
                     "Coarse wheel deltas move twelve points per reported unit on both axes")
        reset()
        let coarseVertical = event(vertical: -1, units: .line)
        scrollView.scrollWheel(with: coarseVertical)
        expectOrigin(start.x, start.y - coarseVertical.scrollingDeltaY * 12,
                     "Coarse vertical scrolling never leaks into the hour axis")
        reset()
        let coarseHorizontal = event(horizontal: -1, units: .line)
        scrollView.scrollWheel(with: coarseHorizontal)
        expectOrigin(start.x - coarseHorizontal.scrollingDeltaX * 12, start.y,
                     "Coarse horizontal scrolling never leaks into the day axis")

        let maximumX = document.frame.width - scrollView.contentView.bounds.width
        let maximumY = document.frame.height - scrollView.contentView.bounds.height
        scrollView.move(to: NSPoint(x: -100, y: -200))
        expectOrigin(0, 0, "Programmatic movement clamps both lower bounds")
        scrollView.scrollWheel(with: event(horizontal: 50, vertical: 50))
        expectOrigin(0, 0, "Outward gestures remain at the lower corner")
        scrollView.move(to: NSPoint(x: 100000, y: 100000))
        expectOrigin(maximumX, maximumY, "Programmatic movement clamps both upper bounds")
        scrollView.scrollWheel(with: event(horizontal: -50, vertical: -50))
        expectOrigin(maximumX, maximumY, "Outward gestures remain at the upper corner")

        scrollView.move(to: NSPoint(x: 4, y: 600))
        scrollView.scrollWheel(with: event(horizontal: 20, vertical: -11))
        expectOrigin(0, 611, "A clamped horizontal axis does not swallow vertical movement")
        scrollView.move(to: NSPoint(x: 800, y: maximumY - 4))
        scrollView.scrollWheel(with: event(horizontal: -13, vertical: -20))
        expectOrigin(813, maximumY, "A clamped vertical axis does not swallow horizontal movement")

        let container = CalendarDayScrollContainer(frame: NSRect(x: 0, y: 0, width: 600, height: 204))
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        expect(container.scrollView.hasVerticalScroller, "The day list exposes a vertical scroller")
        expect(container.gutter.frame == NSRect(x: 0, y: 0, width: 68, height: 204),
               "Day labels retain their fixed 68-point gutter")
        expect(container.scrollView.frame == NSRect(x: 76, y: 0, width: 524, height: 204),
               "The timeline fills the remaining viewport beside the day gutter")

        container.scrollView.documentView = CalendarDayScrollTestDocument(
            frame: NSRect(x: 0, y: 0, width: 2400, height: 1800))
        container.gutter.documentView = CalendarDayScrollTestDocument(
            frame: NSRect(x: 0, y: 0, width: 68, height: 1800))
        container.scrollView.tile()
        container.scrollView.move(to: NSPoint(x: 800, y: 300))
        container.gutter.scroll(to: NSPoint(x: 0, y: 300))
        let frozenGutterX = container.gutter.frame.minX
        container.gutter.scrollWheel(with: event(vertical: -40))
        let afterGutterVertical = container.scrollView.contentView.bounds.origin
        expect(abs(afterGutterVertical.x - 800) < 0.01 && abs(afterGutterVertical.y - 340) < 0.01,
               "Wheel events on the gutter must advance days without changing hours; got \(afterGutterVertical)")
        expect(container.gutter.frame.minX == frozenGutterX,
               "Vertical gutter gestures must preserve the frozen gutter frame")

        container.gutter.scrollWheel(with: event(horizontal: -30))
        let afterGutterHorizontal = container.scrollView.contentView.bounds.origin
        expect(abs(afterGutterHorizontal.x - 830) < 0.01 && abs(afterGutterHorizontal.y - 340) < 0.01,
               "Wheel events on the gutter must advance hours without changing days; got \(afterGutterHorizontal)")
        expect(container.gutter.frame.minX == frozenGutterX,
               "Horizontal gutter gestures must preserve the frozen gutter frame")
        container.scrollView.documentView = nil
        container.gutter.documentView = nil

        var immediateCallbacks: [NSPoint] = []
        scrollView.move(to: NSPoint(x: -100, y: 100000)) {
            immediateCallbacks.append(scrollView.contentView.bounds.origin)
        }
        expect(immediateCallbacks.count == 1, "A sized viewport completes movement exactly once")
        expect(immediateCallbacks.first == NSPoint(x: 0, y: maximumY),
               "The immediate callback observes both axes after clamping")
        scrollView.needsLayout = true
        scrollView.layoutSubtreeIfNeeded()
        expect(immediateCallbacks.count == 1, "A later layout never repeats an immediate callback")

        let initial = CalendarDayNativeScrollView(frame: .zero)
        initial.borderType = .noBorder
        initial.documentView = CalendarDayScrollTestDocument(frame: NSRect(x: 0, y: 0, width: 12 * 96, height: 754))
        var initialCallbacks: [NSPoint] = []
        initial.move(to: NSPoint(x: 12 * 96, y: 330)) {
            initialCallbacks.append(initial.contentView.bounds.origin)
        }
        expect(initial.requestedOrigin == NSPoint(x: 12 * 96, y: 330),
               "A Today reset after 19:00 is retained until the viewport has a size")
        expect(initialCallbacks.isEmpty, "A zero-size viewport does not complete an unapplied movement")
        initial.needsLayout = true
        initial.layoutSubtreeIfNeeded()
        expect(initialCallbacks.isEmpty, "Layout with no viewport size keeps the completion pending")
        initial.frame = NSRect(x: 0, y: 0, width: 524, height: 204)
        initial.needsLayout = true
        initial.layoutSubtreeIfNeeded()
        expect(abs(initial.contentView.bounds.minX - (12 * 96 - initial.contentView.bounds.width)) < 0.01,
               "The first sized layout clamps a late Today reset to the visible daytime window")
        expect(abs(initial.contentView.bounds.minY - 330) < 0.01,
               "Clamping a late hour never moves Today to a different day row")
        expect(initialCallbacks.count == 1, "The first sized layout completes the pending movement exactly once")
        expect(initialCallbacks.first == NSPoint(x: 12 * 96 - initial.contentView.bounds.width, y: 330),
               "A deferred callback observes the final clamped hour and requested day")
        initial.needsLayout = true
        initial.layoutSubtreeIfNeeded()
        expect(initialCallbacks.count == 1, "Further layouts never repeat a deferred callback")
        initial.documentView = nil

        let replacement = CalendarDayNativeScrollView(frame: .zero)
        replacement.borderType = .noBorder
        replacement.documentView = CalendarDayScrollTestDocument(
            frame: NSRect(x: 0, y: 0, width: 12 * 96, height: 754))
        var staleCallbackCount = 0
        var replacementCallbacks: [NSPoint] = []
        replacement.move(to: NSPoint(x: 40, y: 80)) { staleCallbackCount += 1 }
        replacement.move(to: NSPoint(x: 100000, y: -100)) {
            replacementCallbacks.append(replacement.contentView.bounds.origin)
        }
        expect(staleCallbackCount == 0 && replacementCallbacks.isEmpty,
               "Neither pending completion fires before the viewport is sized")
        expect(replacement.requestedOrigin == NSPoint(x: 100000, y: -100),
               "The newest pending movement replaces the stale requested position")
        replacement.frame = NSRect(x: 0, y: 0, width: 524, height: 204)
        replacement.needsLayout = true
        replacement.layoutSubtreeIfNeeded()
        expect(staleCallbackCount == 0 && replacementCallbacks.count == 1,
               "Only the newest pending completion fires when the viewport becomes ready")
        expect(replacementCallbacks.first == NSPoint(x: 12 * 96 - replacement.contentView.bounds.width, y: 0),
               "The replacement callback observes its own clamped coordinates on both axes")
        replacement.needsLayout = true
        replacement.layoutSubtreeIfNeeded()
        expect(staleCallbackCount == 0 && replacementCallbacks.count == 1,
               "Later layouts do not revive stale or already completed callbacks")
        replacement.documentView = nil

        // A tiny document has no secret extra days hiding beyond its edges.
        document.setFrameSize(NSSize(width: 80, height: 60))
        scrollView.move(to: NSPoint(x: 1000, y: 1000))
        expectOrigin(0, 0, "A document smaller than the viewport has no scrollable extent")
        scrollView.scrollWheel(with: event(horizontal: -50, vertical: -50))
        expectOrigin(0, 0, "Wheel gestures keep a small document at the origin")
        scrollView.documentView = nil
        scrollView.move(to: NSPoint(x: 1000, y: 1000))
        expectOrigin(0, 0, "A missing document safely clamps to the origin")

        print("PASS \(checks) windowless native calendar day-scrolling checks")
    }
}
