import AppKit
import SwiftUI
import XCTest
@testable import boringNotch

/// Offscreen layout only: never orders the panel front or constructs app managers.
@MainActor
final class NotchInteractionRegionTests: XCTestCase {
    func testNotificationArrivingDuringIndependentMusicPeekTakesPriority() {
        let showMusic = ClosedMusicPresentation.isVisible(hasMedia: true, persistentEnabled: false,
                                                          transientPeek: true, otherExpansion: false)
        XCTAssertEqual(LiveActivityItem.current(notification: nil, showMusic: showMusic), [.music])
        let notification = SystemNotification(id: "test", appName: nil, bundleID: nil, title: "Message",
                                              subtitle: nil, body: "Body", actions: [], receivedAt: Date())
        XCTAssertEqual(LiveActivityItem.current(notification: notification, showMusic: showMusic), [.notification(notification), .music])
        XCTAssertEqual(LiveActivityItem.current(notification: nil, showMusic: showMusic), [.music])
        XCTAssertEqual(LiveActivityItem.current(notification: nil, showMusic: false), [])
    }

    func testZeroHeightRendersNoPixelsAtBothBackingScales() throws {
        for scale in [CGFloat(1), 2] {
            for hidden in [true, false] {
                let renderer = ImageRenderer(content:
                    Color.black.frame(width: 200, height: 38)
                        .modifier(NotchContentVisibility(hidden: hidden))
                        .frame(width: 640, height: 210, alignment: .top)
                )
                renderer.scale = scale
                let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                var visiblePixels = 0
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 { visiblePixels += 1 }
                    }
                }
                if hidden { XCTAssertEqual(visiblePixels, 0, "Zero height must have no faint edge") }
                else { XCTAssertGreaterThan(visiblePixels, 0, "The rendering check must detect visible content") }
            }
        }
    }

    func testRenderedClosedBoundsExcludeTransparentWindowSides() {
        let panel = BoringNotchSkyLightWindow(contentRect: CGRect(x: 300, y: 300, width: 640, height: 210),
                                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { panel.close(); panel.contentView = nil }
        let host = NSHostingView(rootView:
            Color.black.frame(width: 200, height: 38)
                .background(NotchInteractionRegion())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
        panel.contentView = host
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.interactionRect.width, 200, accuracy: 0.5)
        XCTAssertEqual(panel.interactionRect.height, 38, accuracy: 0.5)
        XCTAssertTrue(panel.acceptsPointer(atScreenPoint: panel.convertPoint(toScreen: CGPoint(x: 320, y: 200))))
        XCTAssertFalse(panel.acceptsPointer(atScreenPoint: panel.convertPoint(toScreen: CGPoint(x: 80, y: 200))))
        XCTAssertFalse(panel.acceptsPointer(atScreenPoint: panel.convertPoint(toScreen: CGPoint(x: 320, y: 100))))
    }

    func testExpandedTransportHeightComesFromLayoutRatherThanStandardHeight() {
        let panel = BoringNotchSkyLightWindow(contentRect: CGRect(x: 300, y: 300, width: 640, height: 210),
                                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { panel.close(); panel.contentView = nil }
        let host = NSHostingView(rootView:
            Color.black.frame(width: 360, height: 170)
                .background(NotchInteractionRegion())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
        panel.contentView = host
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.interactionRect.height, 170, accuracy: 0.5)
        XCTAssertTrue(panel.acceptsPointer(atScreenPoint: panel.convertPoint(toScreen: CGPoint(x: 320, y: 50))))
        XCTAssertFalse(panel.acceptsPointer(atScreenPoint: panel.convertPoint(toScreen: CGPoint(x: 320, y: 20))))
    }
}
