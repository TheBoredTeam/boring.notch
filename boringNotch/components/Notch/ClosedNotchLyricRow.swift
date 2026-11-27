import Defaults
import SwiftUI

enum ClosedNotchLyricMetrics {
    static func rowHeight(forFontSize fontSize: Double) -> CGFloat {
        CGFloat(ceil(fontSize * 1.45))
    }
}

private let lyricSilenceThreshold = 5.0
// Show each line this early; the fill sweep still follows the LRC timestamp.
private let lyricAppearLead = 0.15

@MainActor
struct ClosedNotchLyricRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var musicManager: MusicManager
    @ObservedObject private var lyricsService = LyricsService.shared
    @Default(.playerColorTinting) private var playerColorTinting
    @Default(.lyricSyncOffset) private var lyricSyncOffset
    @Default(.lyricFontSize) private var lyricFontSize

    private var rowHeight: CGFloat {
        ClosedNotchLyricMetrics.rowHeight(forFontSize: lyricFontSize)
    }

    private var textColor: Color {
        playerColorTinting
            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
            : .gray
    }

    private var timelineSchedule: LyricTimelineSchedule {
        LyricTimelineSchedule(
            syncedLyrics: lyricsService.syncedLyrics,
            lineTimings: lyricsService.lineTimings,
            elapsedTime: musicManager.elapsedTime,
            timestampDate: musicManager.timestampDate,
            playbackRate: musicManager.playbackRate,
            isPlaying: musicManager.isPlaying,
            songDuration: musicManager.songDuration,
            syncOffset: lyricSyncOffset,
            reduceMotion: reduceMotion
        )
    }

    var body: some View {
        let currentRowHeight = rowHeight
        let currentColor = textColor

        GeometryReader { geometry in
            TimelineView(timelineSchedule) { timeline in
                let elapsed = musicManager.estimatedPlaybackPosition(at: timeline.date) + lyricSyncOffset
                let lyrics = lyricsService.syncedLyrics
                let timings = lyricsService.lineTimings
                if let index = LyricTiming.lyricIndex(in: lyrics, at: elapsed + lyricAppearLead) {
                    let lineStart = lyrics[index].time
                    let timing = timings.indices.contains(index) ? timings[index] : nil
                    let sungSeconds = timing?.sungSeconds
                    let phrases = timing?.phrases
                    let nextIndex = index + 1
                    let nextStart = lyrics.indices.contains(nextIndex)
                        ? lyrics[nextIndex].time : nil
                    ClosedNotchLyricLine(
                        line: lyrics[index].text,
                        width: geometry.size.width,
                        rowHeight: currentRowHeight,
                        fontSize: lyricFontSize,
                        progress: reduceMotion
                            ? 1
                            : lyricFillProgress(
                                elapsed: elapsed,
                                lineStart: lineStart,
                                sungSeconds: sungSeconds,
                                phrases: phrases
                            ),
                        isSilent: lyricIsSilent(
                            elapsed: elapsed,
                            lineStart: lineStart,
                            sungSeconds: sungSeconds,
                            nextStart: nextStart
                        ),
                        color: currentColor
                    )
                    .id(index)
                }
            }
        }
        .frame(height: currentRowHeight)
        .clipped()
    }
}

@MainActor
private struct ClosedNotchLyricLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let line: String
    let width: CGFloat
    let rowHeight: CGFloat
    let fontSize: Double
    let progress: CGFloat
    let isSilent: Bool
    let color: Color

    private var lyricMask: LinearGradient {
        let fill = reduceMotion ? 1 : progress
        return LinearGradient(
            colors: [.white, .white.opacity(0.45)],
            startPoint: UnitPoint(x: fill * 1.3 - 0.3, y: 0.5),
            endPoint: UnitPoint(x: fill * 1.3, y: 0.5)
        )
    }

    var body: some View {
        ClosedNotchLyricText(
            line: line,
            width: width,
            rowHeight: rowHeight,
            fontSize: fontSize,
            color: color
        )
        .equatable()
        .mask { lyricMask }
        .frame(width: width, height: rowHeight)
        .clipped()
        .opacity(isSilent ? 0 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: isSilent)
    }
}

@MainActor
private struct ClosedNotchLyricText: View, Equatable {
    let line: String
    let width: CGFloat
    let rowHeight: CGFloat
    let fontSize: Double
    let color: Color

    private var marqueeFontStyle: NSFont.TextStyle {
        if fontSize <= 11 { return .caption2 }
        if fontSize < 14 { return .body }
        return .title3
    }

    var body: some View {
        let font = Font.system(size: CGFloat(fontSize), weight: .medium, design: .rounded)

        ViewThatFits(in: .horizontal) {
            Text(line)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            MarqueeText(
                line,
                font: font,
                nsFont: marqueeFontStyle,
                color: color,
                delayDuration: 1,
                frameWidth: width
            )
            .lineLimit(1)
            .frame(width: width, height: rowHeight)
            .clipped()
        }
    }
}

private struct LyricTimelineSchedule: TimelineSchedule {
    let syncedLyrics: [(time: Double, text: String)]
    let lineTimings: [LyricLineTiming]
    let elapsedTime: TimeInterval
    let timestampDate: Date
    let playbackRate: Double
    let isPlaying: Bool
    let songDuration: TimeInterval
    let syncOffset: Double
    let reduceMotion: Bool

    private func estimatedElapsed(at date: Date) -> Double {
        guard isPlaying else { return min(elapsedTime, songDuration) + syncOffset }
        let delta = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + delta * playbackRate
        return min(max(0, estimated), songDuration) + syncOffset
    }

    private func stepInterval(at date: Date) -> TimeInterval {
        guard isPlaying, let firstStart = syncedLyrics.first?.time else { return 0.5 }
        let elapsed = estimatedElapsed(at: date)
        let rate = max(0.1, playbackRate)

        guard let index = LyricTiming.lyricIndex(in: syncedLyrics, at: elapsed + lyricAppearLead) else {
            let wait = (firstStart - lyricAppearLead - elapsed) / rate + 0.001
            return min(max(1.0 / 60.0, wait), 0.5)
        }

        let lineStart = syncedLyrics[index].time
        let nextStart = (index + 1 < syncedLyrics.count) ? syncedLyrics[index + 1].time : nil
        let timing = lineTimings.indices.contains(index) ? lineTimings[index] : nil
        let lineSung = timing?.sungSeconds
        let phrases = timing?.phrases
        let position = elapsed - lineStart

        if !reduceMotion, let lineSung, let phrases, !phrases.isEmpty, position < lineSung {
            for phrase in phrases {
                if position < phrase.start {
                    let wait = (lineStart + phrase.start - elapsed) / rate + 0.001
                    return min(max(1.0 / 60.0, wait), 0.5)
                }
                if position < phrase.end {
                    let remaining = (lineStart + phrase.end - elapsed) / rate + 0.001
                    return min(1.0 / 30.0, max(1.0 / 60.0, remaining))
                }
            }
        }

        var nextBoundary: Double?
        if let lineSung {
            let silenceStart = lineStart + lineSung + lyricSilenceThreshold
            if elapsed < silenceStart {
                nextBoundary = silenceStart
            }
        }
        if let nextStart, elapsed < nextStart - lyricAppearLead {
            let nextAppear = nextStart - lyricAppearLead
            nextBoundary = nextBoundary.map { min($0, nextAppear) } ?? nextAppear
        }

        guard let target = nextBoundary else { return 0.5 }
        let wait = (target - elapsed) / rate + 0.001
        return min(max(1.0 / 60.0, wait), 0.5)
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var nextDate = startDate
        return AnyIterator {
            let current = nextDate
            let step = stepInterval(at: current)
            nextDate = current.addingTimeInterval(mode == .lowFrequency ? max(step, 0.25) : step)
            return current
        }
    }
}

private func lyricFillProgress(
    elapsed: Double,
    lineStart: Double,
    sungSeconds: Double?,
    phrases: [LyricPhraseTiming]?
) -> CGFloat {
    guard let sungSeconds, sungSeconds > 0, let phrases, !phrases.isEmpty else { return 1 }
    let position = elapsed - lineStart
    if position <= 0 { return 0 }
    if position >= sungSeconds { return 1 }
    var fraction = 0.0
    for phrase in phrases {
        if position < phrase.start { return CGFloat(fraction) }
        if position < phrase.end {
            let span = phrase.end - phrase.start
            guard span > 0 else { return CGFloat(phrase.endFraction) }
            let progress = (position - phrase.start) / span
            return CGFloat(fraction + (phrase.endFraction - fraction) * progress)
        }
        fraction = phrase.endFraction
    }
    return CGFloat(fraction)
}

private func lyricIsSilent(
    elapsed: Double,
    lineStart: Double,
    sungSeconds: Double?,
    nextStart: Double?
) -> Bool {
    guard let sungSeconds else { return false }
    let silenceStart = lineStart + sungSeconds + lyricSilenceThreshold
    return elapsed >= silenceStart && (nextStart.map { elapsed < $0 } ?? true)
}
