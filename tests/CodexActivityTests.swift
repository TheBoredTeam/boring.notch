//
//  CodexActivityTests.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import Combine
import SwiftUI

@main
enum CodexActivityTests {
    @MainActor static func main() throws {
        let now = Date(timeIntervalSince1970: 100)
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        func phase(service: String = "boringnotch-codex-activity", version: Int = 1,
                   updated: Double = 100, count: Int = 1, status: CodexActivityPhase = .active) -> CodexActivityPhase {
            CodexActivitySnapshot(service: service, version: version, phase: status,
                                  updatedAt: updated, activeCount: count).validatedPhase(at: now)
        }
        expect(phase() == .active, "Fresh active metadata animates")
        expect(phase(service: "unrelated-service") == .offline, "Another service is not trusted")
        expect(phase(version: 2) == .offline, "Unknown schemas remain still")
        expect(phase(updated: 90) == .offline, "Stale data remains still")
        expect(phase(updated: 110) == .offline, "Future data remains still")
        expect(phase(count: -1) == .offline, "Negative counts are invalid")
        expect(phase(count: 0) == .offline, "Active status requires an unfinished task")
        expect(phase(status: .idle) == .offline, "Idle status cannot contain active tasks")
        let data = Data("{\"service\":\"boringnotch-codex-activity\",\"version\":1,\"phase\":\"waiting\",\"updatedAt\":100,\"activeCount\":1}".utf8)
        let decoded = try JSONDecoder().decode(CodexActivitySnapshot.self, from: data)
        expect(decoded.validatedPhase(at: now) == .waiting, "Waiting tasks remain in progress")
        for state in [CodexActivityPhase.active, .waiting] {
            expect(state.isInProgress, "Running and waiting tasks animate")
        }
        for state in [CodexActivityPhase.idle, .offline, .error] {
            expect(!state.isInProgress, "Completed, disconnected and error states remain still")
        }

        let boundaries: [(Int, Int, CodexActivityTier, CodexAvatarStyle)] = [
            (Int.min, 0, .smile, .smile), (-1, 0, .smile, .smile), (0, 0, .smile, .smile),
            (1, 1, .syncing, .lines), (2, 2, .syncing, .lines), (3, 3, .spin, .orbit),
            (4, 4, .iris, .colorfulOrbit), (8, 8, .iris, .colorfulOrbit),
            (1_000_000, 1_000_000, .iris, .colorfulOrbit), (Int.max, Int.max, .iris, .colorfulOrbit)
        ]
        for (input, count, tier, style) in boundaries {
            let level = CodexActivityLevel(activeCount: input)
            expect(level.activeCount == count, "Counts normalize without overflow")
            expect(level.tier == tier, "Each task-count boundary selects the expected tier")
            expect(CodexAvatarStyle.selected(manual: .smile, level: level, followsActivity: true) == style,
                   "Live selection overrides the saved manual avatar")
            expect(level.speedMultiplier.isFinite && level.speedMultiplier <= 2.5, "Speed stays finite and bounded")
            if count < 4 { expect(level.speedMultiplier == 1, "Only the colorful orbit accelerates") }
        }
        for (count, speed) in [(4, 1.15), (5, 1.342857142857), (8, 1.69), (10, 1.825)] {
            expect(abs(CodexActivityLevel(activeCount: count).speedMultiplier - speed) < 1e-10,
                   "The colorful orbit follows the specified speed curve")
        }
        var previousSpeed = 1.0
        for count in [4, 5, 8, 10, 100, 1_000_000, Int.max] {
            let speed = CodexActivityLevel(activeCount: count).speedMultiplier
            expect(speed >= previousSpeed, "Speed increases smoothly toward the saturation limit")
            previousSpeed = speed
        }
        let busyLevel = CodexActivityLevel(activeCount: 8)
        for manual in CodexAvatarStyle.allCases {
            expect(CodexAvatarStyle.selected(manual: manual, level: busyLevel, followsActivity: false) == manual,
                   "Disabling live monitoring preserves the manual choice")
            expect(CodexAvatarStyle.selected(manual: manual, level: busyLevel, followsActivity: true, previewing: true) == manual,
                   "Preview temporarily overrides automatic selection")
            expect(CodexAvatarStyle.selected(manual: manual, level: busyLevel, followsActivity: true) == .colorfulOrbit,
                   "Ending a preview restores the live workload tier")
        }

        func snapshot(service: String = "boringnotch-codex-activity", version: Int = 1,
                      updated: Double = 100, count: Int = 1, status: CodexActivityPhase = .active) -> CodexActivitySnapshot {
            CodexActivitySnapshot(service: service, version: version, phase: status, updatedAt: updated, activeCount: count)
        }
        for updated in [92.0, 102.0] {
            expect(snapshot(updated: updated).validatedActiveCount(at: now) == 1, "Freshness boundaries remain valid")
        }
        let manager = CodexActivityManager.shared
        var publishedCounts = [Int]()
        let observation = manager.$activeCount.dropFirst().sink { publishedCounts.append($0) }
        manager.apply(snapshot(), at: now)
        manager.apply(snapshot(count: 2), at: now)
        expect(manager.phase == .active && manager.activeCount == 2, "Count updates independently of an unchanged active phase")
        expect(publishedCounts == [1, 2], "Same-phase workload changes publish to the UI")
        manager.apply(snapshot(count: 4, status: .waiting), at: now)
        expect(manager.activeCount == 4 && manager.level.tier == .iris && manager.isActive,
               "Waiting tasks remain in progress and contribute to the automatic avatar")
        let resetCases: [(CodexActivitySnapshot?, CodexActivityPhase)] = [
            (nil, .offline), (snapshot(count: 0, status: .idle), .idle),
            (snapshot(count: 0, status: .error), .error), (snapshot(count: 0, status: .offline), .offline),
            (snapshot(updated: 91.999), .offline), (snapshot(updated: 102.001), .offline),
            (snapshot(service: "unrelated-service"), .offline), (snapshot(version: 2), .offline),
            (snapshot(count: -1), .offline), (snapshot(count: 0), .offline),
            (snapshot(count: 5, status: .idle), .offline), (snapshot(count: 5, status: .error), .offline)
        ]
        for (invalid, expectedPhase) in resetCases {
            manager.apply(snapshot(count: 8), at: now)
            manager.apply(invalid, at: now)
            expect(manager.activeCount == 0 && manager.level.tier == .smile, "Unavailable or completed state clears any stale count")
            expect(manager.phase == expectedPhase, "Resetting the avatar preserves the appropriate status badge")
        }
        let overflowing = Data("{\"service\":\"boringnotch-codex-activity\",\"version\":1,\"phase\":\"active\",\"updatedAt\":100,\"activeCount\":9223372036854775808}".utf8)
        let overflowSnapshot = try? JSONDecoder().decode(CodexActivitySnapshot.self, from: overflowing)
        expect(overflowSnapshot == nil, "An overflowing count cannot enter the activity policy")
        manager.apply(snapshot(count: 3), at: now)
        manager.apply(overflowSnapshot, at: now)
        expect(manager.activeCount == 0, "Invalid decoding clears the previous workload")
        manager.apply(snapshot(count: 3), at: now)
        manager.stopMonitoring()
        expect(manager.activeCount == 0 && manager.phase == .offline, "Stopping monitoring clears the live count")
        observation.cancel()

        var clock = CodexAvatarRotationClock()
        expect(clock.turns(at: 100) == 0, "A new idle glyph starts at its visible resting frame")
        clock.update(isActive: true, speedMultiplier: 1.15, at: 100)
        let beforeSpeedChange = clock.turns(at: 101)
        clock.update(isActive: true, speedMultiplier: 1.69, at: 101)
        expect(clock.turns(at: 101) == beforeSpeedChange, "Adding tasks preserves the current orientation")
        expect(abs(clock.turns(at: 102) - (beforeSpeedChange + 1.69 / 6)) < 1e-10,
               "Subsequent frames advance at the new speed")
        let beforeSlowdown = clock.turns(at: 102)
        clock.update(isActive: true, speedMultiplier: 1.15, at: 102)
        expect(clock.turns(at: 102) == beforeSlowdown, "Completing tasks does not jump backward")
        let beforePause = clock.turns(at: 102.5)
        clock.update(isActive: false, speedMultiplier: 1.15, at: 102.5)
        expect(clock.turns(at: 200) == beforePause, "Reduce Motion pauses at the current angle")
        clock.update(isActive: true, speedMultiplier: 1, at: 200)
        expect(clock.turns(at: 200) == beforePause, "Resuming motion preserves the paused angle")
        let beforeWaiting = clock.turns(at: 200.5)
        clock.update(isActive: true, speedMultiplier: 1, at: 200.5)
        expect(clock.turns(at: 200.5) == beforeWaiting, "Active-to-waiting transitions retain the current phase")
        let wrapped = clock.turns(at: 1_000)
        expect(wrapped >= 0 && wrapped < 1, "Long-running animation wraps into a bounded rotation")

        for count in [0, 1, 2, 3, 4, 8, Int.max] {
            let level = CodexActivityLevel(activeCount: count)
            let style = CodexAvatarStyle.selected(manual: .smile, level: level, followsActivity: true)
            let frame: [UInt8]
            if style == .smile {
                frame = try pixels(AnimatedFace())
            } else {
                frame = try pixels(CodexActivityGlyph(style: style, turns: level.speedMultiplier / 6))
            }
            expect(brightness(frame) > 0.04, "Every automatic workload tier renders visible artwork")
        }

        for style in [CodexAvatarStyle.orbit, .lines, .colorfulOrbit] {
            let idle = try pixels(CodexAvatarAnimation(style: style, isActive: false, reduceMotion: false))
            let reduced = try pixels(CodexAvatarAnimation(style: style, isActive: true, reduceMotion: true))
            expect(idle == reduced, "Reduce Motion and idle must render identical artwork")
            let start = try pixels(CodexActivityGlyph(style: style))
            let rotated = try pixels(CodexActivityGlyph(style: style, turns: 0.25))
            let startBrightness = brightness(start)
            let rotatedBrightness = brightness(rotated)
            expect(startBrightness > 0.04, "Every glyph must have a visible resting frame")
            expect(abs(startBrightness - rotatedBrightness) / startBrightness < 0.06,
                   "Rotation must preserve the visible amount of ink")
            expect(start != rotated, "Active motion must change the glyph's orientation")
        }
        print("\(checks) Codex activity and original artwork checks passed")
    }

    @MainActor private static func pixels(_ view: some View) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view.frame(width: 30, height: 24).background(.black))
        renderer.scale = 4
        guard let image = renderer.cgImage else { throw RenderError.noImage }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw RenderError.noContext }
        return bytes
    }

    private static func brightness(_ pixels: [UInt8]) -> Double {
        let sum = stride(from: 0, to: pixels.count, by: 4).reduce(0.0) { value, index in
            value + 0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])
        }
        return sum / Double(pixels.count / 4) / 255
    }

    private enum RenderError: Error { case noImage, noContext }
}
