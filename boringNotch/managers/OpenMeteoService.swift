//
//  OpenMeteoService.swift
//  boringNotch
//
//  Weather, sunrise and sunset from Open-Meteo (https://open-meteo.com), which
//  needs no API key. The city comes from the built-in list in Settings
//  (CalendarCities.swift), so no location permission is involved. Nothing is requested unless the user picks an
//  option that needs it.
//

import Foundation

// MARK: - Forecast model

struct OpenMeteoForecast: Decodable, Equatable, Sendable {
    struct Current: Decodable, Equatable, Sendable {
        let time: TimeInterval
        let temperature: Double?
        let weatherCode: Int?
        let isDay: Int?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    struct Daily: Decodable, Equatable, Sendable {
        let time: [TimeInterval]
        let weatherCode: [Int?]
        let temperatureMax: [Double?]
        let temperatureMin: [Double?]
        let sunrise: [TimeInterval?]
        let sunset: [TimeInterval?]

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
            case sunrise
            case sunset
        }
    }

    let utcOffsetSeconds: Int
    let current: Current?
    let daily: Daily

    enum CodingKeys: String, CodingKey {
        case utcOffsetSeconds = "utc_offset_seconds"
        case current
        case daily
    }

    /// One day of the forecast, in a shape the view can use directly.
    struct Day: Equatable, Sendable {
        let weatherCode: Int?
        let high: Double?
        let low: Double?
        let sunrise: Date?
        let sunset: Date?
    }

    /// The forecast for the calendar day of `date` as the user sees it locally.
    /// Daily entries are midnights in the place's own time zone, so both sides are
    /// compared as year/month/day rather than as instants.
    func day(for date: Date, localCalendar: Calendar = .current, placeTimeZone: TimeZone? = nil) -> Day? {
        let wanted = localCalendar.dateComponents([.year, .month, .day], from: date)
        var placeCalendar = Calendar(identifier: .gregorian)
        placeCalendar.timeZone = placeTimeZone ?? TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .current

        guard let index = daily.time.firstIndex(where: { time in
            let components = placeCalendar.dateComponents(
                [.year, .month, .day], from: Date(timeIntervalSince1970: time))
            return components.year == wanted.year
                && components.month == wanted.month
                && components.day == wanted.day
        }) else { return nil }

        func value<T>(_ array: [T?]) -> T? {
            array.indices.contains(index) ? array[index] : nil
        }
        return Day(
            weatherCode: value(daily.weatherCode),
            high: value(daily.temperatureMax),
            low: value(daily.temperatureMin),
            sunrise: value(daily.sunrise).map { Date(timeIntervalSince1970: $0) },
            sunset: value(daily.sunset).map { Date(timeIntervalSince1970: $0) }
        )
    }
}

// MARK: - Weather codes

/// WMO weather interpretation codes, as used by Open-Meteo.
enum WeatherCondition {
    static func description(for code: Int?) -> String {
        switch code {
        case 0: String(localized: "Clear sky")
        case 1: String(localized: "Mainly clear")
        case 2: String(localized: "Partly cloudy")
        case 3: String(localized: "Overcast")
        case 45, 48: String(localized: "Fog")
        case 51, 53, 55: String(localized: "Drizzle")
        case 56, 57: String(localized: "Freezing drizzle")
        case 61, 63: String(localized: "Rain")
        case 65: String(localized: "Heavy rain")
        case 66, 67: String(localized: "Freezing rain")
        case 71, 73, 75, 77: String(localized: "Snow")
        case 80, 81: String(localized: "Showers")
        case 82: String(localized: "Heavy showers")
        case 85, 86: String(localized: "Snow showers")
        case 95: String(localized: "Thunderstorm")
        case 96, 99: String(localized: "Thunderstorm with hail")
        default: ""
        }
    }

    static func symbolName(for code: Int?, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55: "cloud.drizzle.fill"
        case 56, 57, 66, 67: "cloud.sleet.fill"
        case 61, 63: "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 80, 81: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95: "cloud.bolt.fill"
        case 96, 99: "cloud.bolt.rain.fill"
        default: "thermometer.medium"
        }
    }

    /// Formats a Celsius value in the unit the user's locale prefers, e.g. "12°".
    static func temperatureText(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

// MARK: - Service

@MainActor
final class OpenMeteoService: ObservableObject {
    static let shared = OpenMeteoService()

    @Published private(set) var forecast: OpenMeteoForecast?
    @Published private(set) var forecastPlace: CalendarPlace?

    private var lastAttempt: Date?
    private var lastAttemptPlace: CalendarPlace?
    private var lastSuccess: Date?
    private var inFlight: Task<Void, Never>?

    /// How long a forecast is reused before it is fetched again.
    private let freshFor: TimeInterval = 30 * 60
    /// After a failure (offline, server error), wait this long before trying again.
    private let retryAfter: TimeInterval = 5 * 60

    private init() {}

    /// The cached forecast if it belongs to `place`.
    func forecast(for place: CalendarPlace) -> OpenMeteoForecast? {
        forecastPlace == place ? forecast : nil
    }

    /// Fetches the forecast for `place` unless a fresh one is already cached,
    /// or a request for it failed only moments ago.
    func refreshIfNeeded(for place: CalendarPlace) {
        let now = Date()
        if forecastPlace == place, let lastSuccess, now.timeIntervalSince(lastSuccess) < freshFor { return }
        if lastAttemptPlace == place, let lastAttempt, now.timeIntervalSince(lastAttempt) < retryAfter,
           forecastPlace != place || lastSuccess != lastAttempt {
            return
        }
        guard inFlight == nil else { return }

        lastAttempt = now
        lastAttemptPlace = place
        inFlight = Task { [weak self] in
            let result: OpenMeteoForecast?
            do {
                result = try await Self.fetchForecast(for: place)
            } catch {
                Log.calendar.debug("Open-Meteo forecast failed: \(error.localizedDescription)")
                result = nil
            }
            guard let self else { return }
            self.inFlight = nil
            if let result {
                self.forecast = result
                self.forecastPlace = place
                self.lastSuccess = now
            } else if self.forecastPlace != place {
                // Don't keep showing another city's forecast.
                self.forecast = nil
                self.forecastPlace = nil
                self.lastSuccess = nil
            }
        }
    }

    // MARK: Requests

    nonisolated static func fetchForecast(for place: CalendarPlace) async throws -> OpenMeteoForecast {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: place.timeZoneIdentifier.isEmpty ? "auto" : place.timeZoneIdentifier),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "16"),
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        let data = try await get(url)
        return try JSONDecoder().decode(OpenMeteoForecast.self, from: data)
    }

    private nonisolated static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
