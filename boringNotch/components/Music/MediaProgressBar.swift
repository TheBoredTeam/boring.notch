//
//  MediaProgressBar.swift
//  boringNotch
//
//  Adds a minimal media playback progress indicator that traces the bottom
//  outline of the notch and tapers to a point at both ends.
//  Relates to #1333
//

import Defaults
import SwiftUI

/// A thin progress indicator that hugs the notch's bottom edge and fills
/// left-to-right as the current track plays. Both bottom corners taper to a
/// fine point; the moving leading edge stays full thickness mid-song and only
/// tapers as it reaches the right corner. Tinted with the playing media's
/// average color (the same source the audio visualizer uses), so it visually
/// matches the rest of the live activity.
///
/// Designed to be used as an `.overlay` on the notch so it aligns with the
/// clipped notch shape; pass the same corner radii the notch is using.
struct MediaProgressBar: View {
    @ObservedObject private var musicManager = MusicManager.shared

    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    /// Whether the bar is currently shown. When false, the periodic timeline is
    /// torn down so it stops waking twice a second while hidden (open notch /
    /// paused); a single static frame is rendered instead so the fade-out still
    /// shows the bar at its last position.
    var isVisible: Bool = true

    /// Thickness of the line, in points. Controlled by a slider in Settings → Media.
    @Default(.mediaProgressBarThickness) private var thickness

    /// Where the bar's color comes from. Controlled by a picker in Settings → Media.
    @Default(.mediaProgressBarColor) private var colorSource

    private var tint: Color {
        switch colorSource {
        case .albumArt:
            return Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
        case .white:
            return .white
        case .accent:
            return .effectiveAccent
        }
    }

    var body: some View {
        // Only drive the periodic timeline while visible. The bar advances well
        // under a pixel per 0.5s step, so stepping straight to each new value
        // (no per-frame interpolation) looks identical while avoiding a full
        // geometry rebuild on every display frame.
        if isVisible {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                ribbon(at: context.date)
            }
        } else {
            ribbon(at: .now)
        }
    }

    @ViewBuilder
    private func ribbon(at date: Date) -> some View {
        let duration = musicManager.songDuration
        let position = musicManager.estimatedPlaybackPosition(at: date)
        let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0

        TaperedNotchProgress(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius,
            thickness: CGFloat(thickness),
            fraction: CGFloat(fraction)
        )
        .fill(tint)
    }
}

/// Fills the bottom contour of the notch (up the left corner, across the bottom,
/// up the right corner) from the start to `fraction` of its length, as a ribbon
/// whose half-width ramps to zero at both ends of the full contour, so it tapers
/// up around each corner. The moving leading edge keeps full thickness until it
/// nears the right corner.
struct TaperedNotchProgress: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var thickness: CGFloat
    var fraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let f = min(max(fraction, 0), 1)
        guard f > 0, thickness > 0 else { return Path() }

        let tcr = topCornerRadius
        let bcr = bottomCornerRadius

        // Centerline control points (same contour as the notch's bottom edge).
        let start = CGPoint(x: rect.minX + tcr, y: rect.maxY - bcr)
        let blEnd = CGPoint(x: rect.minX + tcr + bcr, y: rect.maxY)
        let blCtl = CGPoint(x: rect.minX + tcr, y: rect.maxY)
        let brStart = CGPoint(x: rect.maxX - tcr - bcr, y: rect.maxY)
        let end = CGPoint(x: rect.maxX - tcr, y: rect.maxY - bcr)
        let brCtl = CGPoint(x: rect.maxX - tcr, y: rect.maxY)

        // 1. Sample the contour into a dense polyline.
        var pts: [CGPoint] = []
        func quad(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, steps: Int, includeFirst: Bool) {
            for i in (includeFirst ? 0 : 1) ... steps {
                let t = CGFloat(i) / CGFloat(steps)
                let mt = 1 - t
                pts.append(CGPoint(
                    x: mt * mt * p0.x + 2 * mt * t * c.x + t * t * p1.x,
                    y: mt * mt * p0.y + 2 * mt * t * c.y + t * t * p1.y
                ))
            }
        }
        func line(_ p0: CGPoint, _ p1: CGPoint, steps: Int) {
            for i in 1 ... steps {
                let t = CGFloat(i) / CGFloat(steps)
                pts.append(CGPoint(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t))
            }
        }
        // A ~1-5pt ribbon needs far fewer samples than the geometry can produce;
        // the coarse outline deviates from the fine one by ~0.1pt worst case.
        quad(start, blCtl, blEnd, steps: 12, includeFirst: true)
        line(blEnd, brStart, steps: 16)
        quad(brStart, brCtl, end, steps: 12, includeFirst: false)

        // 2. Cumulative arc length, and the target length for the current fraction.
        var cum: [CGFloat] = [0]
        for i in 1 ..< pts.count {
            cum.append(cum[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y))
        }
        guard let total = cum.last, total > 0 else { return Path() }
        let target = f * total

        // 3. Centerline points up to `target` (interpolating the final point).
        var center: [CGPoint] = []
        var arc: [CGFloat] = []
        for i in 0 ..< pts.count {
            if cum[i] <= target {
                center.append(pts[i]); arc.append(cum[i])
            } else {
                let prev = i - 1
                let seg = cum[i] - cum[prev]
                let u = seg > 0 ? (target - cum[prev]) / seg : 0
                center.append(CGPoint(
                    x: pts[prev].x + (pts[i].x - pts[prev].x) * u,
                    y: pts[prev].y + (pts[i].y - pts[prev].y) * u
                ))
                arc.append(target)
                break
            }
        }
        guard center.count >= 2 else { return Path() }

        // 4. Offset each side by a half-width that tapers to zero at both the
        //    start and the very end of the *full* contour, so the bar tapers up
        //    around each corner symmetrically. Because the taper-out is anchored
        //    to the contour's end (not the current progress point), the moving
        //    leading edge stays full thickness mid-song and only narrows as it
        //    reaches the right corner.
        let halfMax = thickness / 2
        let taper = min(14, total / 2)
        func halfWidth(at s: CGFloat) -> CGFloat {
            guard taper > 0 else { return halfMax }
            let rampIn = min(s / taper, 1)
            let rampOut = min((total - s) / taper, 1)
            return halfMax * max(0, min(rampIn, rampOut))
        }

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in 0 ..< center.count {
            let a = center[max(0, i - 1)]
            let b = center[min(center.count - 1, i + 1)]
            var tx = b.x - a.x, ty = b.y - a.y
            let len = hypot(tx, ty)
            if len > 0 { tx /= len; ty /= len }
            let hw = halfWidth(at: arc[i])
            left.append(CGPoint(x: center[i].x - ty * hw, y: center[i].y + tx * hw))
            right.append(CGPoint(x: center[i].x + ty * hw, y: center[i].y - tx * hw))
        }

        // 5. Build the ribbon: forward along one edge, back along the other.
        var path = Path()
        path.move(to: left[0])
        for p in left.dropFirst() { path.addLine(to: p) }
        for p in right.reversed() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }
}
