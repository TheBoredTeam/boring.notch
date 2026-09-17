import Foundation

@main
enum CalendarTimelineScaleTests {
    private static var checks = 0

    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let center = date("2026-09-10T12:34:56Z")
        let original = HomeCalendarGeometry.days(centeredOn: center, calendar: calendar)
        let densities = [315.0 / 24, 315.0 / 12, 524.0 / 12, 72.0, 96.0, 240.0]
        expect(CalendarTimelineScale.pointsPerHour(for: -2, fitting: 315) == 315.0 / 12,
               "The minimum scale fits the whole displayed day into the viewport")
        expect(CalendarTimelineScale.pointsPerHour(for: 1) == 96, "The default scale retains the existing timeline density")
        expect(CalendarTimelineScale.pointsPerHour(for: 10) == 240, "The maximum scale stays bounded at 240 points per hour")
        for invalid in [Double.nan, .infinity, -.infinity] {
            expect(CalendarTimelineScale.pointsPerHour(for: invalid) == 96, "Invalid stored scale values fall back to the default")
        }
        verifyFittedDay(start: center)

        for density in densities {
            let scaled = rescale(original, to: density)
            expect(scaled.map(\.id) == original.map(\.id), "Scaling keeps day identities and the loaded date window")
            expect(scaled.map(\.visibleInterval) == original.map(\.visibleInterval), "Scaling keeps cropped daytime bounds")
            expect(close(scaled[3].width, 12 * density), "Only horizontal duration changes with density")
            expect(close(HomeCalendarGeometry.width(of: scaled), 7 * 12 * density + 6 * 18),
                   "Day gaps retain an 18-point width at every scale")
            let halfHour = center.addingTimeInterval(1800)
            expect(close(HomeCalendarGeometry.offset(of: halfHour, in: scaled) - HomeCalendarGeometry.offset(of: center, in: scaled), density / 2),
                   "A half-hour always occupies half the active points per hour")
            for day in scaled {
                for minutes in stride(from: 0.0, to: 12 * 60, by: 17) {
                    let time = day.visibleInterval.start.addingTimeInterval(minutes * 60)
                    let x = HomeCalendarGeometry.offset(of: time, in: scaled)
                    expect(close(HomeCalendarGeometry.date(at: x, in: scaled)!.timeIntervalSince(time), 0),
                           "Pixel/date round trips retain exact minutes at every scale")
                }
            }
            let interval = CalendarTimelineGeometry.Interval(id: "event", start: center, end: halfHour)
            let placement = CalendarTimelineGeometry.layout([interval], in: scaled[3].visibleInterval, pointsPerHour: density)[0]
            expect(close(placement.width, density / 2), "Event blocks use the same scale as the hour ruler")
            expect(placement.hitWidth >= CalendarTimelineGeometry.minimumHitWidth,
                   "Short-event interaction targets remain usable when zoomed out")
        }

        for sourceDensity in densities {
            for destinationDensity in densities {
                let source = rescale(original, to: sourceDensity)
                let destination = rescale(original, to: destinationDensity)
                for viewportWidth in [315.0, 524.0] {
                    let centerX = HomeCalendarGeometry.offset(of: center, in: source)
                    let oldOrigin = centerX - viewportWidth / 2
                    let newOrigin = HomeCalendarGeometry.rebasedOffset(oldOrigin + viewportWidth / 2, from: source, to: destination) - viewportWidth / 2
                    let visibleCenter = HomeCalendarGeometry.date(at: newOrigin + viewportWidth / 2, in: destination)!
                    expect(close(visibleCenter.timeIntervalSince(center), 0), "Zoom keeps the viewport's center time under the same pixel")

                    let nextDay = source[4]
                    for gapOffset in [1.0, 9.0, 17.0] {
                        let sourceGapPixel = HomeCalendarGeometry.offset(of: nextDay.id, in: source) - gapOffset
                        let destinationGapPixel = HomeCalendarGeometry.rebasedOffset(sourceGapPixel, from: source, to: destination)
                        expect(close(HomeCalendarGeometry.offset(of: nextDay.id, in: destination) - destinationGapPixel, gapOffset),
                               "Zooming within an overnight gap preserves its pixel anchor")
                    }
                }
                let nextWindow = HomeCalendarGeometry.days(centeredOn: center.addingTimeInterval(86400), calendar: calendar)
                let shifted = rescale(nextWindow, to: destinationDensity)
                let sourcePosition = HomeCalendarGeometry.offset(of: center, in: source)
                let shiftedPosition = HomeCalendarGeometry.rebasedOffset(sourcePosition, from: source, to: shifted)
                expect(close(HomeCalendarGeometry.date(at: shiftedPosition, in: shifted)!.timeIntervalSince(center), 0),
                       "Simultaneous rolling-window and zoom changes retain the same time")
            }
        }

        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let first = date("2026-11-01T01:30:00-04:00")
        let repeated = date("2026-11-01T01:30:00-05:00")
        let fallBack = HomeCalendarGeometry.days(centeredOn: first, events: [
            .init(id: "repeated-hour", start: first, end: repeated.addingTimeInterval(1800))
        ], calendar: calendar)
        for density in densities {
            let scaled = rescale(fallBack, to: density)
            expect(close(HomeCalendarGeometry.offset(of: repeated, in: scaled) - HomeCalendarGeometry.offset(of: first, in: scaled), density),
                   "DST's repeated hour remains one elapsed hour apart at every scale")
        }
        verifyHourLabels(start: center, densities: densities)
        print("PASS \(checks) calendar horizontal-scale geometry checks")
    }

    private static func verifyFittedDay(start: Date) {
        for viewportWidth in [220.0, 315.0, 524.0] {
            for duration in [12.0, 14.0, 23.0, 23.5, 24.0, 24.5, 25.0] {
                let interval = DateInterval(start: start, duration: duration * 3600)
                let density = CalendarTimelineScale.pointsPerHour(for: 0, fitting: viewportWidth, duration: interval.duration)
                let day = HomeCalendarGeometry.Day(interval: interval, pointsPerHour: density)
                expect(close(day.width, viewportWidth), "Fit day includes all cropped, overnight and DST hours without horizontal overflow")
                expect(density > 0 && density.isFinite, "Fitted geometry always has a usable positive density")
                expect(close(CalendarTimelineScale.pointsPerHour(for: density / 192, fitting: viewportWidth, duration: interval.duration), density),
                       "Requested density below Fit day never makes the timeline smaller than its pane")
                let endX = CalendarTimelineGeometry.position(of: interval.end, in: interval, pointsPerHour: density)
                expect(close(endX, viewportWidth), "The fitted last hour lands exactly at the right pane edge")
            }
        }
        for width in [0.0, -1.0] {
            let density = CalendarTimelineScale.pointsPerHour(for: 0, fitting: width)
            expect(density > 0 && density.isFinite, "Pending or collapsed viewport layout cannot produce division by zero")
        }
    }

    private static func verifyHourLabels(start: Date, densities: [Double]) {
        // Widths sampled from 11-point monospaced 24-hour, 12-hour, Japanese and DST labels.
        for density in densities {
            for duration in [12.0, 12.5, 25.0] {
                let range = DateInterval(start: start, duration: duration * 3600)
                let ticks = CalendarTimelineGeometry.hourTicks(in: range)
                let totalWidth = duration * density
                for width in [34.0, 48.0, 55.0, 75.0, 50.0, 130.0] {
                    let widths = Array(repeating: width, count: ticks.count)
                    for exclusions: [Range<Double>] in [[], [210..<282], [0..<70, (totalWidth - 60)..<totalWidth]] {
                        let labels = CalendarTimelineGeometry.hourLabels(in: range, pointsPerHour: density, widths: widths, avoiding: exclusions)
                        if exclusions.isEmpty {
                            expect(!labels.isEmpty, "Fitted day ranges retain readable time labels at every density")
                        }
                        for label in labels {
                            expect(label.x >= 0 && label.x + label.width <= totalWidth,
                                   "Complete time labels fit within the day at both endpoints")
                            expect(label.width == width, "Labels keep their measured size instead of shrinking")
                            expect(!exclusions.contains { $0.overlaps((label.x - 4)..<(label.x + label.width + 4)) },
                                   "Labels leave space for the current-time capsule and day caption")
                        }
                        for (left, right) in zip(labels, labels.dropFirst()) {
                            expect(right.x - (left.x + left.width) >= 6,
                                   "Adjacent labels keep a six-point gap in all supported formats")
                        }
                        if exclusions.isEmpty {
                            expect(labels.last?.id == range.end, "The final visible hour survives packing near the day boundary")
                        }
                    }
                }
            }
        }
        let tinyRange = DateInterval(start: start, duration: 60)
        expect(CalendarTimelineGeometry.hourLabels(in: tinyRange, pointsPerHour: 72, widths: [34, 34]).isEmpty,
               "A label wider than an entire range is omitted rather than overflowing")
    }

    private static func rescale(_ days: [HomeCalendarGeometry.Day], to density: Double) -> [HomeCalendarGeometry.Day] {
        days.map { .init(interval: $0.interval, visibleInterval: $0.visibleInterval, pointsPerHour: density) }
    }

    private static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private static func close(_ left: Double, _ right: Double) -> Bool { abs(left - right) < 0.00001 }
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }
}
