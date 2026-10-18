// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import AppKit
import SwiftUI
import XCTest
@testable import boringNotch

@MainActor
final class LockedLiveActivityViewTests: XCTestCase {
    func testLockedRendererCannotConstructDesktopViews() throws {
        let center = LiveActivityCenter()
        let desktop = try center.register(AnyNotchLiveActivity(
            descriptor: LiveActivityDescriptor(id: .init(namespace: "test", name: "private"), priority: 1000,
                                               presentation: .interrupt),
            leading: { _ in XCTFail("desktop content reached locked renderer"); return Color.red.frame(width: 24, height: 24) },
            trailing: { _ in XCTFail("desktop content reached locked renderer"); return EmptyView() }
        ))
        let locked = try center.register(AnyNotchLiveActivity(
            descriptor: LiveActivityDescriptor(id: .init(namespace: "test", name: "public"), surface: .lockScreen),
            leading: { _ in EmptyView() },
            trailing: { context in
                XCTAssertEqual(context.surface, .lockScreen)
                XCTAssertEqual(context.maximumSideWidth, 207.5)
                return Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1).frame(width: 24, height: 24)
            }
        ))
        defer { desktop.unregister(); locked.unregister() }
        center.updateSession(locked: true)
        let image = try render(center)
        XCTAssertGreaterThan(countGreenPixels(image), 20)
        let columns = try visibleColumns(image)
        let scale = CGFloat(image.pixelsWide) / 640
        let margin = CGFloat(try XCTUnwrap(columns.opaque.last) - XCTUnwrap(columns.green.last)) / scale
        XCTAssertEqual(margin, 12, accuracy: 1 / scale)
        locked.unregister()
        let empty = try visibleColumns(render(center, evidenceName: "empty-locked-shape"))
        XCTAssertTrue(empty.green.isEmpty)
        let emptyWidth = CGFloat(try XCTUnwrap(empty.opaque.last) - XCTUnwrap(empty.opaque.first) + 1) / scale
        XCTAssertEqual(emptyWidth, 185 + 16 + 24, accuracy: 1 / scale)
    }

    func testOversizedProvidersPreserveOuterMarginsAndCameraGap() throws {
        let center = LiveActivityCenter()
        let registration = try center.register(AnyNotchLiveActivity(
            descriptor: LiveActivityDescriptor(id: .init(namespace: "test", name: "wide"), surface: .lockScreen),
            leading: { _ in Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1).frame(width: 900, height: 38) },
            trailing: { _ in Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1).frame(width: 900, height: 38) }
        ))
        defer { registration.unregister() }
        center.updateSession(locked: true)
        let image = try render(center, evidenceName: "oversized-providers")
        let columns = try visibleColumns(image)
        let scale = CGFloat(image.pixelsWide) / 640
        let firstGreen = CGFloat(try XCTUnwrap(columns.green.first)) / scale
        let lastGreen = CGFloat(try XCTUnwrap(columns.green.last)) / scale
        XCTAssertEqual(firstGreen, 12, accuracy: 1 / scale)
        XCTAssertEqual(lastGreen, 640 - 12, accuracy: 1 / scale)
        XCTAssertFalse(columns.green.contains { abs(CGFloat($0) / scale - 320) < (185 + 16) / 2 - 1 / scale })
    }

    func testLockedRendererDoesNotConstructProvidersWhileAsleepInactiveOrUnlocked() throws {
        let center = LiveActivityCenter()
        let registration = try center.register(AnyNotchLiveActivity(
            descriptor: LiveActivityDescriptor(id: .init(namespace: "test", name: "public"), surface: .lockScreen),
            leading: { _ in
                XCTFail("hidden session constructed a provider")
                return Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1).frame(width: 24, height: 24)
            },
            trailing: { _ in EmptyView() }
        ))
        defer { registration.unregister() }
        for state in [LiveActivitySessionState(isLocked: false),
                      LiveActivitySessionState(isLocked: true, isAwake: false),
                      LiveActivitySessionState(isLocked: true, isSessionActive: false)] {
            center.updateSession(locked: state.isLocked, awake: state.isAwake, active: state.isSessionActive)
            XCTAssertEqual(countGreenPixels(try render(center)), 0)
        }
    }

    func testSessionVisibilityResumesOnlyWhenAllGatesAllowIt() {
        let center = LiveActivityCenter()
        center.updateSession(locked: true)
        XCTAssertTrue(center.session.canPresentOnLockScreen)
        center.updateSession(awake: false)
        XCTAssertFalse(center.session.canPresentOnLockScreen)
        center.updateSession(awake: true, active: false)
        XCTAssertFalse(center.session.canPresentOnLockScreen)
        center.updateSession(active: true)
        XCTAssertTrue(center.session.canPresentOnLockScreen)
        center.updateSession(locked: false)
        XCTAssertFalse(center.session.canPresentOnLockScreen)
    }

    private func render(_ center: LiveActivityCenter, evidenceName: String? = nil) throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let view = LockedLiveActivityView(center: center, displayID: "display", safeAreaWidth: 185,
                                          height: 38, maximumWidth: 640, showsEmptyShape: true)
            .frame(width: 640, height: 38)
            .transaction { $0.disablesAnimations = true }
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 640, height: 38),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hostingView
        window.orderBack(nil)
        defer { window.orderOut(nil); window.close() }
        // The shared host measures its two sides through native layout preferences.
        // ImageRenderer does not run that AppKit layout cycle.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        hostingView.layoutSubtreeIfNeeded()
        let image = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: image)
        if let directory = ProcessInfo.processInfo.environment["BN_LOCKED_ACTIVITY_RENDER_DIRECTORY"],
           let png = image.representation(using: .png, properties: [:]) {
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let state = center.session
            let name = evidenceName ?? "locked-\(state.isLocked)-awake-\(state.isAwake)-active-\(state.isSessionActive)"
            try png.write(to: root.appendingPathComponent("\(name).png"))
        }
        return image
    }

    private func visibleColumns(_ image: NSBitmapImageRep) throws -> (opaque: [Int], green: [Int]) {
        let normalized = try XCTUnwrap(image.converting(to: .sRGB, renderingIntent: .default))
        var opaque: [Int] = []
        var green: [Int] = []
        var pixel = [Int](repeating: 0, count: normalized.samplesPerPixel)
        let scale = CGFloat((1 << normalized.bitsPerSample) - 1)
        for x in 0..<normalized.pixelsWide {
            normalized.getPixel(&pixel, atX: x, y: normalized.pixelsHigh / 2)
            guard !normalized.hasAlpha || CGFloat(pixel[3]) / scale > 0.5 else { continue }
            opaque.append(x)
            if CGFloat(pixel[1]) / scale > 0.4 && CGFloat(pixel[0]) / scale < 0.2 { green.append(x) }
        }
        return (opaque, green)
    }

    private func countGreenPixels(_ image: NSBitmapImageRep) -> Int {
        // Native caches inherit the display profile. Normalize the bitmap,
        // rather than colorAt(), which can label Display P3 bytes as generic RGB.
        guard let normalized = image.converting(to: .sRGB, renderingIntent: .default) else {
            XCTFail("Could not normalize native render to sRGB")
            return 0
        }
        var count = 0
        var pixel = [Int](repeating: 0, count: normalized.samplesPerPixel)
        let scale = CGFloat((1 << normalized.bitsPerSample) - 1)
        for y in stride(from: 0, to: normalized.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: normalized.pixelsWide, by: 2) {
                normalized.getPixel(&pixel, atX: x, y: y)
                if CGFloat(pixel[1]) / scale > 0.4 && CGFloat(pixel[0]) / scale < 0.2 &&
                    (!normalized.hasAlpha || CGFloat(pixel[3]) / scale > 0.5) { count += 1 }
            }
        }
        return count
    }
}
