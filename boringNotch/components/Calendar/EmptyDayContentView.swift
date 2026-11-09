//
//  EmptyDayContentView.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// Fills the calendar on a day with no events with whatever the user picked in
/// Settings → Calendar. Falls back to `EmptyEventsView` whenever the chosen option
/// has nothing to show (no city set, offline, no upcoming event, …).
struct EmptyDayView: View {
    let selectedDate: Date

    @Default(.calendarEmptyDayContent) private var content
    @Default(.calendarWeatherPlace) private var weatherPlace
    @Default(.calendarWorldClockPlace) private var worldClockPlace
    @ObservedObject private var weather = OpenMeteoService.shared
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var nextEvent: EventModel?

    var body: some View {
        TimelineView(.everyMinute) { context in
            if let info = info(now: context.date) {
                EmptyDayInfoView(info: info, footer: footer)
            } else {
                EmptyEventsView(selectedDate: selectedDate)
            }
        }
        .task(id: TaskKey(content: content, date: selectedDate, place: weatherPlace, events: calendarManager.events.count)) {
            await refresh()
        }
    }

    private var footer: String {
        Calendar.current.isDateInToday(selectedDate)
            ? String(localized: "No events today")
            : String(localized: "No events")
    }

    private struct TaskKey: Equatable {
        let content: CalendarEmptyDayContent
        let date: Date
        let place: CalendarPlace?
        let events: Int
    }

    private func refresh() async {
        switch content {
        case .weather, .sunriseSunset:
            if let weatherPlace {
                weather.refreshIfNeeded(for: weatherPlace)
            }
        case .nextEvent:
            let startOfSelected = Calendar.current.startOfDay(for: selectedDate)
            nextEvent = await calendarManager.nextUpcomingEvent(after: max(Date(), startOfSelected))
        case .noEventsMessage, .dayProgress, .worldClock:
            break
        }
    }

    private func info(now: Date) -> EmptyDayInfo? {
        switch content {
        case .noEventsMessage: nil
        case .weather: weatherInfo(now: now)
        case .nextEvent: nextEventInfo(now: now)
        case .dayProgress: dayProgressInfo(now: now)
        case .worldClock: worldClockInfo(now: now)
        case .sunriseSunset: sunriseSunsetInfo(now: now)
        }
    }

    // MARK: Weather

    private func weatherInfo(now: Date) -> EmptyDayInfo? {
        guard let place = weatherPlace,
              let forecast = weather.forecast(for: place),
              let day = forecast.day(for: selectedDate, placeTimeZone: place.timeZone)
        else { return nil }

        let highLow = [
            day.high.map { String(localized: "H \(WeatherCondition.temperatureText($0))") },
            day.low.map { String(localized: "L \(WeatherCondition.temperatureText($0))") },
        ].compactMap { $0 }.joined(separator: "  ")

        if Calendar.current.isDate(selectedDate, inSameDayAs: now),
           let current = forecast.current, let temperature = current.temperature {
            let condition = WeatherCondition.description(for: current.weatherCode)
            return EmptyDayInfo(
                symbol: WeatherCondition.symbolName(for: current.weatherCode, isDay: current.isDay != 0),
                title: [WeatherCondition.temperatureText(temperature), condition]
                    .filter { !$0.isEmpty }.joined(separator: " "),
                detail: [highLow, place.name].filter { !$0.isEmpty }.joined(separator: " · ")
            )
        }

        guard day.high != nil || day.weatherCode != nil else { return nil }
        let condition = WeatherCondition.description(for: day.weatherCode)
        return EmptyDayInfo(
            symbol: WeatherCondition.symbolName(for: day.weatherCode),
            title: condition.isEmpty ? highLow : condition,
            detail: [condition.isEmpty ? "" : highLow, place.name].filter { !$0.isEmpty }.joined(separator: " · ")
        )
    }

    // MARK: Next event

    private func nextEventInfo(now: Date) -> EmptyDayInfo? {
        guard let event = nextEvent, event.end > now else { return nil }
        let date = event.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let time = event.isAllDay
            ? String(localized: "All-day")
            : event.start.formatted(date: .omitted, time: .shortened)
        let away = event.start <= now
            ? String(localized: "Now")
            : NextEventFinder.daysAwayDescription(NextEventFinder.daysAway(event.start, from: now))
        return EmptyDayInfo(
            symbol: "calendar.badge.clock",
            title: event.title,
            detail: "\(date), \(time) · \(away)"
        )
    }

    // MARK: Day progress

    private func dayProgressInfo(now: Date) -> EmptyDayInfo {
        let progress = DayProgress(for: selectedDate, now: now)
        let title = String(localized: "Week \(progress.weekOfYear) · Day \(progress.dayOfYear) of \(progress.daysInYear)")
        if let fraction = progress.fractionOfDayElapsed {
            let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
            return EmptyDayInfo(
                symbol: "hourglass",
                title: title,
                detail: String(localized: "\(percent) of today done"),
                progress: fraction
            )
        }
        let days = NextEventFinder.daysAway(selectedDate, from: now)
        let relative = days > 0
            ? NextEventFinder.daysAwayDescription(days)
            : (days == -1 ? String(localized: "Yesterday") : String(localized: "\(-days) days ago"))
        return EmptyDayInfo(symbol: "calendar", title: title, detail: relative)
    }

    // MARK: World clock

    private func worldClockInfo(now: Date) -> EmptyDayInfo? {
        guard let place = worldClockPlace, let zone = place.timeZone else { return nil }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        var detail = WorldClock.offsetDescription(seconds: WorldClock.offset(of: zone, at: now))

        // Mention when it's already tomorrow (or still yesterday) there.
        var remoteCalendar = Calendar.current
        remoteCalendar.timeZone = zone
        let remoteDay = remoteCalendar.dateComponents([.year, .month, .day], from: now)
        let localDay = Calendar.current.dateComponents([.year, .month, .day], from: now)
        if let remote = Calendar.current.date(from: remoteDay), let local = Calendar.current.date(from: localDay) {
            if remote > local {
                detail += " · " + String(localized: "Tomorrow")
            } else if remote < local {
                detail += " · " + String(localized: "Yesterday")
            }
        }

        return EmptyDayInfo(
            symbol: "globe",
            title: "\(now.formatted(style)) \(place.name)",
            detail: detail
        )
    }

    // MARK: Sunrise & sunset

    private func sunriseSunsetInfo(now: Date) -> EmptyDayInfo? {
        guard let place = weatherPlace,
              let forecast = weather.forecast(for: place),
              let day = forecast.day(for: selectedDate, placeTimeZone: place.timeZone),
              let sunrise = day.sunrise, let sunset = day.sunset, sunset > sunrise
        else { return nil }

        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        if let zone = place.timeZone { style.timeZone = zone }
        let title = String(localized: "↑ \(sunrise.formatted(style))   ↓ \(sunset.formatted(style))")
        let dayLength = DaylightStatus.durationText(sunset.timeIntervalSince(sunrise))

        guard Calendar.current.isDate(selectedDate, inSameDayAs: now) else {
            return EmptyDayInfo(
                symbol: "sun.horizon.fill",
                title: title,
                detail: String(localized: "\(dayLength) of daylight · \(place.name)")
            )
        }

        switch DaylightStatus(now: now, sunrise: sunrise, sunset: sunset) {
        case .beforeSunrise(let interval):
            return EmptyDayInfo(
                symbol: "sunrise.fill",
                title: title,
                detail: String(localized: "Sunrise in \(DaylightStatus.durationText(interval))")
            )
        case .daylightLeft(let interval):
            return EmptyDayInfo(
                symbol: "sunset.fill",
                title: title,
                detail: String(localized: "\(DaylightStatus.durationText(interval)) of daylight left")
            )
        case .afterSunset:
            return EmptyDayInfo(
                symbol: "moon.stars.fill",
                title: title,
                detail: String(localized: "\(dayLength) of daylight today")
            )
        }
    }
}

/// The text an empty-day option wants to show.
struct EmptyDayInfo: Equatable {
    let symbol: String
    let title: String
    let detail: String
    /// When set, a thin bar is drawn above the detail line (0…1).
    var progress: Double?
}

/// Same footprint as `EmptyEventsView`: a headline with its icon, one detail line,
/// and a small "No events" line so that information isn't lost.
private struct EmptyDayInfoView: View {
    let info: EmptyDayInfo
    let footer: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: info.symbol)
                    .font(.title3)
                    .symbolRenderingMode(.multicolor)
                    .foregroundColor(Color(white: 0.85))
                Text(info.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let progress = info.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color.effectiveAccent)
                    .frame(maxWidth: 140)
                    .controlSize(.mini)
            }
            Text(info.detail)
                .font(.caption)
                .foregroundColor(Color(white: 0.65))
                .lineLimit(1)
            Text(footer)
                .font(.caption2)
                .foregroundColor(Color(white: 0.45))
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    EmptyDayInfoView(
        info: EmptyDayInfo(symbol: "cloud.sun.fill", title: "12° Partly cloudy", detail: "H 15°  L 8° · London"),
        footer: "No events today"
    )
    .frame(width: 215, height: 80)
    .background(.black)
}
