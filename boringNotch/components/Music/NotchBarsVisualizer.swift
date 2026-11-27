//
//  NotchBarsVisualizer.swift
//  boringNotch
//
//  Spectrum visualizer that hangs from the bottom edge of the closed notch while
//  real-time audio capture is running. Raw band levels come from AudioCaptureManager;
//  this file adds auto-gain, volume scaling, beat pulses, peak caps, mirroring,
//  four drawing styles, a moving two-colour album-art palette, lyrics in a centre
//  gap, and the beat signal that makes the notch "breathe".
//

import AppKit
import Defaults
import SwiftUI

enum NotchVisualizerStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case bars
    case dots
    case wave
    case liquid

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .bars: String(localized: "Bars")
        case .dots: String(localized: "Dots")
        case .wave: String(localized: "Wave")
        case .liquid: String(localized: "Liquid")
        }
    }
}

struct NotchBarsVisualizer: View {
    /// Height of a full-scale bar.
    static let fullHeight: CGFloat = 16
    /// Frame height; the extra room lets beat pulses overshoot `fullHeight`.
    static let totalHeight: CGFloat = 20

    @ObservedObject var musicManager = MusicManager.shared
    @Default(.notchVisualizerAlbumColors) var albumColors
    @Default(.notchVisualizerColorMotion) var colorMotion
    @Default(.notchVisualizerStyle) var style
    @Default(.notchVisualizerSensitivity) var sensitivity
    @Default(.notchVisualizerMirrored) var mirrored
    @Default(.notchVisualizerPeakCaps) var peakCaps
    @Default(.notchVisualizerBeatPulse) var beatPulse
    @Default(.notchVisualizerLyrics) var lyricsInGap
    @Default(.notchVisualizerBreathing) var breathing
    @ObservedObject private var lyrics = LyricsService.shared

    @State private var engine = VisualizerEngine()

    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 2
    private let minHeight: CGFloat = 2
    /// How far a beat stretches the bars (fraction of their height).
    private let beatStretch: CGFloat = 0.25

    var body: some View {
        let primary: NSColor? = albumColors ? (musicManager.vibrantColor ?? musicManager.avgColor) : nil
        let secondary: NSColor? = albumColors ? musicManager.vibrantSecondaryColor : nil
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let lyric = lyricsInGap && !lyrics.syncedLyrics.isEmpty
                    ? GapLyric.current(at: timeline.date, musicManager: musicManager, lyrics: lyrics)
                    : nil
                let gapTarget: CGFloat = lyric.map {
                    min(geometry.size.width * 0.62, max(56, LyricMetrics.width(of: $0.text) + 16))
                } ?? 0
                let gap = engine.stepGap(now: now, target: gapTarget)

                ZStack(alignment: .top) {
                    Canvas { context, size in
                        let count = max(1, Int((size.width + spacing) / (barWidth + spacing)))
                        let frame = engine.step(
                            now: now,
                            bandsDB: AudioCaptureManager.shared.latestDetailedBandsDB(),
                            volumeGain: Self.volumeGain(),
                            sensitivity: Float(sensitivity),
                            barCount: count,
                            mirrored: mirrored,
                            beatEnabled: beatPulse,
                            gapHalfFraction: Float(gap / max(1, size.width)),
                            colorMotion: colorMotion
                        )
                        let palette = VisualizerPalette(
                            primary: primary, secondary: secondary, hueShift: CGFloat(frame.hueShift), beat: frame.beat)
                        if breathing {
                            // Follow the notch's swelling bottom edge so the bars stay attached.
                            context.translateBy(
                                x: 0, y: CGFloat(NotchPulse.shared.breath) * NotchBreathing<Rectangle>.maxBottomGrowth)
                        }
                        draw(frame, palette: palette, count: count, in: &context, size: size)
                    }
                    GapLyricView(
                        lyric: lyric,
                        gapWidth: gap,
                        beat: engine.lastBeat,
                        palette: VisualizerPalette(
                            primary: primary, secondary: secondary, hueShift: CGFloat(engine.lastHueShift), beat: 0)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.totalHeight)
    }

    // MARK: - Drawing

    private func draw(
        _ frame: VisualizerFrame, palette: VisualizerPalette, count: Int,
        in context: inout GraphicsContext, size: CGSize
    ) {
        let used = CGFloat(count) * barWidth + CGFloat(count - 1) * spacing
        let originX = (size.width - used) / 2
        let stretch = 1 + beatStretch * CGFloat(frame.beat)
        func x(_ index: Int) -> CGFloat { originX + CGFloat(index) * (barWidth + spacing) }
        func height(_ level: Float) -> CGFloat {
            min(size.height, (minHeight + (Self.fullHeight - minHeight) * CGFloat(level)) * stretch)
        }

        var shape = Path()
        switch style {
        case .bars:
            for i in 0..<count where frame.visible[i] {
                let rect = CGRect(x: x(i), y: 0, width: barWidth, height: height(frame.levels[i]))
                shape.addPath(
                    UnevenRoundedRectangle(bottomLeadingRadius: barWidth / 2, bottomTrailingRadius: barWidth / 2)
                        .path(in: rect))
            }
        case .dots:
            let pitch = barWidth + 1
            for i in 0..<count where frame.visible[i] {
                let lit = max(1, Int((height(frame.levels[i]) / pitch).rounded()))
                for d in 0..<lit {
                    shape.addEllipse(in: CGRect(x: x(i), y: CGFloat(d) * pitch, width: barWidth, height: barWidth))
                }
            }
        case .wave:
            shape = wavePath(frame, count: count, x: { x($0) + barWidth / 2 }, height: height)
        case .liquid:
            // Slightly fat bars plus a thin "pool" along the notch edge; blurring and then
            // thresholding the alpha melts them into one gooey shape (see the fill below).
            for run in Self.visibleRuns(frame.visible) {
                shape.addRect(CGRect(x: x(run.lowerBound) - 1, y: -2, width: x(run.upperBound) - x(run.lowerBound) + barWidth + 2, height: 4.5))
            }
            for i in 0..<count where frame.visible[i] {
                let rect = CGRect(x: x(i) - 0.75, y: -1, width: barWidth + 1.5, height: height(frame.levels[i]) + 1.5)
                shape.addRoundedRect(in: rect, cornerSize: CGSize(width: (barWidth + 1.5) / 2, height: (barWidth + 1.5) / 2))
            }
        }

        // Fades out as the device volume goes down, so volume changes are visible at a glance.
        context.opacity = 0.45 + 0.55 * Double(frame.gain)
        // Low frequencies take the primary album colour, high ones the secondary.
        let colors = mirrored
            ? [palette.secondary, palette.primary, palette.secondary]
            : [palette.primary, palette.secondary]
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: colors),
            startPoint: CGPoint(x: originX, y: 0),
            endPoint: CGPoint(x: originX + used, y: 0)
        )
        // Brightens the tips a touch so the bars read as lit from the notch.
        let highlight = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [.white.opacity(0), .white.opacity(0.28)]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: Self.fullHeight)
        )

        // Soft glow underneath makes the colour read even over busy wallpapers.
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 3))
            glow.opacity = 0.55 + 0.35 * Double(frame.beat)
            glow.fill(shape, with: .color(palette.glow))
        }

        if style == .wave {
            var area = Path()
            for run in Self.visibleRuns(frame.visible) {
                var segment = wavePath(frame, count: count, x: { x($0) + barWidth / 2 }, height: height, only: run)
                segment.addLine(to: CGPoint(x: x(run.upperBound) + barWidth / 2, y: 0))
                segment.addLine(to: CGPoint(x: x(run.lowerBound) + barWidth / 2, y: 0))
                segment.closeSubpath()
                area.addPath(segment)
            }
            var fill = context
            fill.opacity *= 0.45
            fill.fill(area, with: shading)
            context.stroke(shape, with: shading, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        } else if style == .liquid {
            var liquid = context
            liquid.clipToLayer { mask in
                // Filters apply in reverse order of adding: blur first, then threshold.
                mask.addFilter(.alphaThreshold(min: 0.5, color: .black))
                mask.addFilter(.blur(radius: 2.2))
                mask.fill(shape, with: .color(.black))
            }
            let bounds = Path(CGRect(origin: .zero, size: size))
            liquid.fill(bounds, with: shading)
            liquid.blendMode = .plusLighter
            liquid.fill(bounds, with: highlight)
        } else {
            context.fill(shape, with: shading)
            var lit = context
            lit.blendMode = .plusLighter
            lit.fill(shape, with: highlight)
        }

        if peakCaps && style != .wave {
            var caps = Path()
            for i in 0..<count where frame.visible[i] && frame.peaks[i] > 0.04 {
                let y = height(frame.peaks[i]) + 1
                guard y + 1.5 <= size.height else { continue }
                if style == .liquid {
                    // Little droplets instead of flat caps.
                    caps.addEllipse(in: CGRect(x: x(i) + 0.25, y: y + 0.5, width: 2.5, height: 2.5))
                } else {
                    caps.addRoundedRect(
                        in: CGRect(x: x(i), y: y, width: barWidth, height: 1.5),
                        cornerSize: CGSize(width: 0.75, height: 0.75))
                }
            }
            context.fill(caps, with: .color(palette.cap))
        }
    }

    /// Smooth curve through the visible bar tips (midpoint quadratic smoothing), one
    /// sub-path per contiguous run so the curve breaks around the lyric gap.
    private func wavePath(
        _ frame: VisualizerFrame, count: Int, x: (Int) -> CGFloat, height: (Float) -> CGFloat,
        only runOnly: ClosedRange<Int>? = nil
    ) -> Path {
        var path = Path()
        let runs = runOnly.map { [$0] } ?? Self.visibleRuns(frame.visible)
        for run in runs {
            let points = run.map { CGPoint(x: x($0), y: height(frame.levels[$0])) }
            path.move(to: points[0])
            guard points.count > 1 else { continue }
            for i in 1..<points.count {
                let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
                path.addQuadCurve(to: mid, control: points[i - 1])
            }
            path.addLine(to: points[points.count - 1])
        }
        return path
    }

    private static func visibleRuns(_ visible: [Bool]) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for i in visible.indices {
            if visible[i] {
                if start == nil { start = i }
            } else if let s = start {
                runs.append(s...(i - 1))
                start = nil
            }
        }
        if let s = start { runs.append(s...(visible.count - 1)) }
        return runs
    }

    /// The process tap captures audio before system volume is applied, so scale by the
    /// output volume ourselves: 0 when muted, 1 at full volume, slightly concave so low
    /// volumes stay visible. Devices without a volume control get 1.
    private static func volumeGain() -> Float {
        let volume = VolumeManager.shared
        guard volume.hasVolumeControl else { return 1 }
        if volume.isMuted { return 0 }
        return powf(max(0, min(1, volume.rawVolume)), 0.75)
    }
}

// MARK: - Palette

/// Turns the album-art colours into a punchy two-colour palette: saturation and brightness
/// are pushed up, and `hueShift` lets the whole palette drift with the music.
private struct VisualizerPalette {
    /// Bass side.
    let primary: Color
    /// Treble side: the artwork's second colour, or a neighbouring hue if it has none.
    let secondary: Color
    let glow: Color
    let cap: Color
    /// Lyric text: a pale tint of the album colour so it stays readable.
    let text: Color

    init(primary base: NSColor?, secondary second: NSColor?, hueShift: CGFloat, beat: Float) {
        let flash = CGFloat(beat) * 0.35
        guard let (hue, saturation) = Self.hueAndSaturation(base), saturation >= 0.1 else {
            // No artwork colour (or monochrome artwork): clean white-to-silver, no fake tint.
            primary = Self.color(hue: 0, saturation: 0, brightness: 1, flash: 0)
            secondary = Self.color(hue: 0, saturation: 0, brightness: 0.78, flash: flash)
            glow = .white.opacity(0.5)
            cap = .white
            text = .white
            return
        }

        let vivid = min(1, max(0.8, saturation * 1.5))
        let mainHue = Self.wrap(hue + hueShift)
        let otherHue: CGFloat
        let otherSaturation: CGFloat
        if let (h2, s2) = Self.hueAndSaturation(second), s2 >= 0.1 {
            otherHue = Self.wrap(h2 + hueShift)
            otherSaturation = min(1, max(0.75, s2 * 1.5))
        } else {
            otherHue = Self.wrap(mainHue + 0.08)
            otherSaturation = vivid * 0.9
        }

        primary = Self.color(hue: mainHue, saturation: vivid, brightness: 1, flash: flash * 0.6)
        secondary = Self.color(hue: otherHue, saturation: otherSaturation, brightness: 1, flash: flash)
        glow = Self.color(hue: mainHue, saturation: vivid, brightness: 1, flash: 0).opacity(0.9)
        cap = Self.color(hue: otherHue, saturation: 0.3, brightness: 1, flash: 0)
        text = Self.color(hue: mainHue, saturation: vivid, brightness: 1, flash: 0.6)
    }

    private static func hueAndSaturation(_ color: NSColor?) -> (CGFloat, CGFloat)? {
        guard let rgb = color?.usingColorSpace(.deviceRGB) else { return nil }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return (hue, saturation)
    }

    private static func wrap(_ hue: CGFloat) -> CGFloat {
        let h = hue.truncatingRemainder(dividingBy: 1)
        return h < 0 ? h + 1 : h
    }

    /// `flash` blends toward white for beat highlights.
    private static func color(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, flash: CGFloat) -> Color {
        let base = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        guard flash > 0.001, let blended = base.blended(withFraction: flash, of: .white) else {
            return Color(nsColor: base)
        }
        return Color(nsColor: blended)
    }
}

// MARK: - Engine

private struct VisualizerFrame {
    var levels: [Float]
    var peaks: [Float]
    /// False for bars hidden behind the lyric gap.
    var visible: [Bool]
    /// 0…1 pulse that spikes on a detected beat and decays over ~200 ms.
    var beat: Float
    /// Smoothed volume gain, 0…1.
    var gain: Float
    /// Palette hue offset (fraction of the colour wheel) that drifts with the music.
    var hueShift: Float
}

/// Beat signal shared with the notch so it can "breathe". Written by the visualizer each
/// frame on the main thread, read by `NotchBreathing`.
final class NotchPulse: @unchecked Sendable {
    static let shared = NotchPulse()
    /// Smoothed 0…1 beat, already scaled by volume.
    var breath: Float = 0
}

/// Gently grows the notch on strong beats while the visualizer is showing.
///
/// Nothing inside the notch is scaled (that squashed the content and corners). Instead a
/// black copy of the notch shape behind it grows a few points, which reads as the notch
/// itself swelling while its content and corner radii stay exactly as they are.
struct NotchBreathing<S: Shape>: ViewModifier {
    let active: Bool
    let shape: S

    /// Maximum growth in points at a full-strength beat.
    static var maxSideGrowth: CGFloat { 3 }
    static var maxBottomGrowth: CGFloat { 2 }

    func body(content: Content) -> some View {
        content.background(alignment: .top) {
            if active {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
                    let b = CGFloat(NotchPulse.shared.breath)
                    shape
                        .fill(.black)
                        .padding(.horizontal, -Self.maxSideGrowth * b)
                        .padding(.bottom, -Self.maxBottomGrowth * b)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

/// Per-view analysis state. Everything is time-based so it behaves the same at any frame rate.
private final class VisualizerEngine {
    /// Below this, a band counts as silence and never lights up or moves the auto-gain.
    private static let silenceDB: Float = -72
    /// Auto-gain reference limits: never boost quieter than this or attenuate past 0 dBFS.
    private static let minReferenceDB: Float = -40
    private static let maxReferenceDB: Float = 0
    /// How fast the reference relaxes after a loud passage.
    private static let referenceReleaseDBPerSecond: Float = 4
    private static let peakHoldSeconds: Double = 0.45
    private static let peakFallPerSecond: Float = 0.9
    private static let minBeatInterval: Double = 0.22

    private var bandLevels: [Float] = []
    private var reference: Float = -24
    private var bassAverage: Float = -60
    private var beat: Float = 0
    private var lastBeatTime: Double = 0
    private var gain: Float = 1
    private var bars: [Float] = []
    private var peaks: [Float] = []
    private var peakHoldUntil: [Double] = []
    private var visible: [Bool] = []
    private var lastTime: Double?
    private var gapWidth: CGFloat = 0
    private var lastGapTime: Double?
    /// Beat value from the most recent frame, for the lyric text to pulse with.
    private(set) var lastBeat: Float = 0
    private(set) var lastHueShift: Float = 0
    private var colorPhase: Double = 0
    private var colorPhaseTarget: Double = 0
    private var breath: Float = 0

    /// Eases the lyric gap open/closed (~250 ms) so the bars part smoothly.
    func stepGap(now: Double, target: CGFloat) -> CGFloat {
        let dt = min(0.1, max(0.001, now - (lastGapTime ?? now - 1.0 / 60.0)))
        lastGapTime = now
        gapWidth += (target - gapWidth) * CGFloat(1 - pow(1 - 0.12, dt * 60))
        if abs(target - gapWidth) < 0.3 { gapWidth = target }
        return gapWidth
    }

    func step(
        now: Double, bandsDB: [Float]?, volumeGain: Float, sensitivity: Float,
        barCount: Int, mirrored: Bool, beatEnabled: Bool, gapHalfFraction: Float = 0,
        colorMotion: Bool = false
    ) -> VisualizerFrame {
        let dt = Float(min(0.1, max(0.001, now - (lastTime ?? now - 1.0 / 60.0))))
        lastTime = now
        let frames = dt * 60
        /// Converts a per-60fps-frame easing coefficient to this frame's duration.
        func ease(_ perFrame: Float) -> Float { 1 - powf(1 - perFrame, frames) }

        gain += (volumeGain - gain) * ease(0.18)
        var beatHit = false

        if let db = bandsDB, !db.isEmpty {
            if bandLevels.count != db.count { bandLevels = [Float](repeating: 0, count: db.count) }
            let frameMax = db.max() ?? Self.silenceDB
            let audible = frameMax > Self.silenceDB

            // Auto-gain: the reference jumps up to loud moments and drifts down slowly, so
            // quiet tracks still fill the space and loud masters don't sit pinned at the top.
            if audible {
                if frameMax > reference {
                    reference += (frameMax - reference) * ease(0.3)
                } else {
                    reference -= Self.referenceReleaseDBPerSecond * dt
                }
                reference = min(Self.maxReferenceDB, max(Self.minReferenceDB, reference))
            }
            let window: Float = 44 - 18 * sensitivity
            let top = reference - 1.5
            let bottom = top - window

            for i in db.indices {
                let target: Float = db[i] < Self.silenceDB ? 0 : min(1, max(0, (db[i] - bottom) / window))
                let coefficient: Float = target > bandLevels[i] ? 0.6 : 0.16
                bandLevels[i] += (target - bandLevels[i]) * ease(coefficient)
            }

            // Beat: bass jumping well above its own recent average.
            let bassCount = min(4, db.count)
            let bass = db.prefix(bassCount).reduce(0, +) / Float(bassCount)
            let threshold: Float = 7 - 4 * sensitivity
            if beatEnabled, audible, bass - bassAverage > threshold, now - lastBeatTime > Self.minBeatInterval {
                beat = 1
                beatHit = true
                lastBeatTime = now
            }
            if audible { bassAverage += (bass - bassAverage) * ease(0.05) }
        } else {
            for i in bandLevels.indices { bandLevels[i] *= powf(0.85, frames) }
        }
        beat = beatEnabled ? beat * powf(0.87, frames) : 0

        // Colour motion: the palette hue sways faster when the music is louder and gets a
        // nudge on every beat.
        let energy = bandLevels.isEmpty ? 0 : bandLevels.reduce(0, +) / Float(bandLevels.count)
        colorPhaseTarget += Double(dt) * (0.3 + 2.2 * Double(energy * gain)) + (beatHit ? 0.6 : 0)
        colorPhase += (colorPhaseTarget - colorPhase) * Double(ease(0.08))
        lastHueShift = colorMotion ? Float(0.05 * sin(colorPhase)) : 0

        // Breathing follows the beat with a short attack so the notch swells rather than jumps.
        let breathTarget = beat * gain
        breath += (breathTarget - breath) * ease(breathTarget > breath ? 0.45 : 0.12)
        NotchPulse.shared.breath = breath

        if bars.count != barCount {
            bars = [Float](repeating: 0, count: barCount)
            peaks = [Float](repeating: 0, count: barCount)
            peakHoldUntil = [Double](repeating: 0, count: barCount)
            visible = [Bool](repeating: true, count: barCount)
        }
        // Half the gap as a fraction of half the width (0 = no gap).
        let gap = min(0.9, max(0, gapHalfFraction))
        for i in 0..<barCount {
            let u = barCount > 1 ? Float(i) / Float(barCount - 1) : 0.5
            let fromCenter = abs(u - 0.5) * 2
            if gap > 0, fromCenter < gap {
                visible[i] = false
                bars[i] = 0
                peaks[i] = 0
                continue
            }
            visible[i] = true
            let position: Float
            if mirrored && barCount > 2 {
                // Bass in the middle (or right beside the lyric), treble toward both edges.
                position = (fromCenter - gap) / (1 - gap)
            } else if gap > 0 {
                // Left half covers the lower bands, right half the upper ones.
                let half = (fromCenter - gap) / (1 - gap) / 2
                position = u < 0.5 ? 0.5 - half : 0.5 + half
            } else {
                position = u
            }
            let level = Self.sample(bandLevels, at: position) * gain
            bars[i] = level
            if level >= peaks[i] {
                peaks[i] = level
                peakHoldUntil[i] = now + Self.peakHoldSeconds
            } else if now > peakHoldUntil[i] {
                peaks[i] = max(level, peaks[i] - Self.peakFallPerSecond * dt)
            }
        }
        lastBeat = beat * gain
        return VisualizerFrame(
            levels: bars, peaks: peaks, visible: visible, beat: beat * gain, gain: gain, hueShift: lastHueShift)
    }

    /// Cosine-interpolates `bands` at `position` (0…1 across the band list).
    private static func sample(_ bands: [Float], at position: Float) -> Float {
        guard bands.count > 1 else { return bands.first ?? 0 }
        let scaled = position * Float(bands.count - 1)
        let lower = min(Int(scaled), bands.count - 1)
        let upper = min(lower + 1, bands.count - 1)
        let t = (1 - cos((scaled - Float(lower)) * .pi)) / 2
        return bands[lower] * (1 - t) + bands[upper] * t
    }
}

// MARK: - Lyrics in the gap

/// The synced lyric line to show right now, if any.
private struct GapLyric {
    let text: String
    let start: Double
    let end: Double?
    let elapsed: Double
    /// True during the intro: the first line is shown dimmed until it is actually sung.
    let isUpcoming: Bool

    /// Fade the text out just before the next line, so lines never hard-cut.
    var showText: Bool {
        guard let end, end - start > 0.9 else { return true }
        return elapsed < end - 0.22
    }

    /// 0…1 through the line's time slot (drives scrolling of long lines).
    var progress: Double {
        guard !isUpcoming else { return 0 }
        let duration = (end ?? start + 4) - start
        guard duration > 1.4 else { return 0 }
        return min(1, max(0, (elapsed - start - 0.6) / (duration - 1.4)))
    }

    @MainActor
    static func current(at date: Date, musicManager: MusicManager, lyrics: LyricsService) -> GapLyric? {
        guard !lyrics.isFetchingLyrics, !lyrics.syncedLyrics.isEmpty else { return nil }
        let elapsed = musicManager.estimatedPlaybackPosition(at: date)
        let context = lyrics.lyricLineContext(at: elapsed)
        let text = context.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }  // instrumental break
        if context.endTime == nil && elapsed - context.startTime > 8 { return nil }  // song outro
        return GapLyric(
            text: text, start: context.startTime, end: context.endTime, elapsed: elapsed,
            isUpcoming: context.startTime > elapsed)
    }
}

@MainActor
private enum LyricMetrics {
    static let fontSize: CGFloat = 10.5
    private static var cachedText = ""
    private static var cachedWidth: CGFloat = 0

    static func usesArabicScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
    }

    static func font(for text: String) -> Font {
        usesArabicScript(text)
            ? .custom("Vazirmatn-Regular", size: fontSize)
            : .system(size: fontSize, weight: .semibold, design: .rounded)
    }

    static func width(of text: String) -> CGFloat {
        if text == cachedText { return cachedWidth }
        let base = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let nsFont: NSFont = usesArabicScript(text)
            ? (NSFont(name: "Vazirmatn-Regular", size: fontSize) ?? base)
            : (base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fontSize) } ?? base)
        cachedText = text
        cachedWidth = ceil((text as NSString).size(withAttributes: [.font: nsFont]).width)
        return cachedWidth
    }
}

private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

/// The lyric line between the two bar groups. Lines fade in from a blur while drifting up,
/// fade out drifting up again, pulse slightly on the beat, and scroll if too long.
private struct GapLyricView: View {
    let lyric: GapLyric?
    let gapWidth: CGFloat
    let beat: Float
    let palette: VisualizerPalette

    private static let lineTransition = AnyTransition.asymmetric(
        insertion: .opacity
            .combined(with: .offset(y: 5))
            .combined(with: .scale(scale: 0.9))
            .combined(with: .modifier(active: BlurModifier(radius: 5), identity: BlurModifier(radius: 0))),
        removal: .opacity
            .combined(with: .offset(y: -4))
            .combined(with: .scale(scale: 0.96))
            .combined(with: .modifier(active: BlurModifier(radius: 4), identity: BlurModifier(radius: 0)))
    )

    private var available: CGFloat { max(0, gapWidth - 8) }

    var body: some View {
        let key = lyric.map { "\($0.start)|\($0.showText)|\($0.isUpcoming)" } ?? "none"
        ZStack {
            if let lyric, lyric.showText, available > 24 {
                line(lyric)
                    .opacity(lyric.isUpcoming ? 0.45 : 1)
                    .id(lyric.start)
                    .transition(Self.lineTransition)
            }
        }
        .frame(width: available, height: NotchBarsVisualizer.fullHeight)
        .scaleEffect(1 + 0.05 * CGFloat(beat))
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: key)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func line(_ lyric: GapLyric) -> some View {
        let textWidth = max(1, LyricMetrics.width(of: lyric.text))
        let fitScale = min(1, available / textWidth)
        let text = Text(lyric.text)
            .font(LyricMetrics.font(for: lyric.text))
            .foregroundStyle(palette.text)
            .shadow(color: palette.glow.opacity(0.6), radius: 3)
            .lineLimit(1)
            .fixedSize()

        if fitScale >= 0.82 {
            text.scaleEffect(fitScale)
        } else {
            // Too long even when shrunk: scroll across the line's time slot, edges faded.
            let scale: CGFloat = 0.82
            let overflow = textWidth * scale - available
            text
                .scaleEffect(scale)
                .offset(x: overflow / 2 - overflow * CGFloat(lyric.progress))
                .frame(width: available)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.1),
                            .init(color: .black, location: 0.9),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing)
                )
        }
    }
}
