//
//  WeatherManager.swift
//  boringNotch
//

import Foundation
import Combine
import Defaults

struct WeatherSnapshot {
    let cityName: String
    let temperature: Double
    let unit: WeatherTemperatureUnit
    let weatherCode: Int
    let isDay: Bool
    let highTemperature: Double?
    let lowTemperature: Double?
    let precipitationProbability: Double?
    let apparentTemperature: Double?
    let humidity: Int?
    let windSpeed: Double?
    let dailyForecast: [WeatherDailyPoint]
    let updatedAt: Date

    var temperatureText: String {
        "\(Int(temperature.rounded()))°\(unit.symbol)"
    }

    var conditionText: String {
        WeatherCodeMapper.description(for: weatherCode)
    }

    var symbolName: String {
        WeatherCodeMapper.symbolName(for: weatherCode, isDay: isDay)
    }

    var precipitationText: String? {
        guard let precipitationProbability else { return nil }
        return "Rain \(Int(precipitationProbability.rounded()))%"
    }

    var feelsLikeText: String? {
        guard let apparentTemperature else { return nil }
        return "\(Int(apparentTemperature.rounded()))°\(unit.symbol)"
    }

    var humidityText: String? {
        guard let humidity else { return nil }
        return "\(humidity)%"
    }

    var windSpeedText: String? {
        guard let windSpeed else { return nil }
        return "\(Int(windSpeed.rounded())) km/h"
    }
}

struct WeatherDailyPoint: Identifiable {
    let id: String
    let dayLabel: String
    let weatherCode: Int
    let maxTemperature: Double
    let minTemperature: Double
    let precipitationProbability: Double?
}

struct CitySuggestion: Identifiable, Equatable {
    let id: String
    let displayName: String
    let subtitle: String
    let queryText: String
}

@MainActor
final class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoadedAtLeastOnce = false
    @Published private(set) var citySuggestions: [CitySuggestion] = []
    @Published private(set) var isLoadingCitySuggestions = false

    private let session: URLSession
    private var cancellables: Set<AnyCancellable> = []
    private var refreshLoopTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var citySuggestionTask: Task<Void, Never>?
    private var suppressNextCitySuggestionSearch = false
    private var geocodeCache: [String: GeocodingResult] = [:]
    private var dateFormatterCache: [String: DateFormatter] = [:]
    private var calendarCache: [String: Calendar] = [:]

    private init(session: URLSession = .shared) {
        self.session = session
        bindDefaults()

        if Defaults[.showWeather] {
            startRefreshLoop()
            requestRefresh()
        }
    }

    deinit {
        refreshLoopTask?.cancel()
        refreshTask?.cancel()
        citySuggestionTask?.cancel()
        cancellables.forEach { $0.cancel() }
    }

    func requestRefresh(replacingCurrent: Bool = false) {
        if replacingCurrent {
            refreshTask?.cancel()
            refreshTask = nil
        } else if refreshTask != nil {
            return
        }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshTask = nil }
            await self.refreshWeather()
        }
    }

    func refreshForEnteredCity() {
        clearCitySuggestions()
        requestRefresh(replacingCurrent: true)
    }

    func selectCitySuggestion(_ suggestion: CitySuggestion) {
        clearCitySuggestions()
        let newQuery = normalizedCityKey(suggestion.queryText)
        let currentQuery = normalizedCityKey(Defaults[.weatherCity])
        suppressNextCitySuggestionSearch = (newQuery != currentQuery)
        Defaults[.weatherCity] = suggestion.queryText
        requestRefresh(replacingCurrent: true)
    }

    private func bindDefaults() {
        Defaults.publisher(.showWeather, options: [])
            .sink { [weak self] change in
                Task { @MainActor in
                    self?.handleEnabledChange(change.newValue)
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.weatherCity, options: [])
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self else { return }
                    guard Defaults[.showWeather] else { return }
                    if self.suppressNextCitySuggestionSearch {
                        self.suppressNextCitySuggestionSearch = false
                        self.clearCitySuggestions(cancelTask: false)
                        return
                    }
                    self.scheduleCitySuggestionSearch(for: change.newValue)
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.weatherUnit, options: [])
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard Defaults[.showWeather] else { return }
                    self?.requestRefresh(replacingCurrent: true)
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.weatherRefreshMinutes, options: [])
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard Defaults[.showWeather] else { return }
                    self?.startRefreshLoop()
                }
            }
            .store(in: &cancellables)
    }

    private func handleEnabledChange(_ enabled: Bool) {
        if enabled {
            startRefreshLoop()
            requestRefresh()
            return
        }

        refreshLoopTask?.cancel()
        refreshLoopTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        clearCitySuggestions()
        suppressNextCitySuggestionSearch = false
        isLoading = false
        errorMessage = nil
        snapshot = nil
        hasLoadedAtLeastOnce = false
    }

    private func startRefreshLoop() {
        refreshLoopTask?.cancel()
        refreshLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                let minutes = max(5, min(120, Defaults[.weatherRefreshMinutes]))
                try? await Task.sleep(for: .seconds(Double(minutes * 60)))
                guard !Task.isCancelled else { break }
                await self?.refreshWeather()
            }
        }
    }

    private func refreshWeather() async {
        guard Defaults[.showWeather] else { return }

        let city = sanitizedCity(Defaults[.weatherCity])
        let unit = Defaults[.weatherUnit]

        isLoading = true
        defer { isLoading = false }

        do {
            let location = try await geocodeCity(city)
            let forecast = try await fetchWeatherForecastWithRetry(
                latitude: location.latitude,
                longitude: location.longitude,
                unit: unit
            )
            snapshot = try makeWeatherSnapshot(
                from: forecast,
                location: location,
                unit: unit
            )
            errorMessage = nil
            hasLoadedAtLeastOnce = true
        } catch is CancellationError {
            return
        } catch let error as WeatherServiceError {
            errorMessage = error.userMessage
            hasLoadedAtLeastOnce = true
        } catch {
            errorMessage = WeatherServiceError.invalidResponse.userMessage
            hasLoadedAtLeastOnce = true
        }
    }

    private func sanitizedCity(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Cupertino" : trimmed
    }

    private func geocodeCity(_ city: String) async throws -> GeocodingResult {
        let cacheKey = normalizedCityKey(city)
        if let cached = geocodeCache[cacheKey] {
            return cached
        }

        let rankedResults = try await searchCitiesRanked(query: city, count: 8)
        guard let result = rankedResults.first else {
            throw WeatherServiceError.locationNotFound
        }
        if geocodeCache.count > 32 {
            geocodeCache.removeAll(keepingCapacity: true)
        }
        geocodeCache[cacheKey] = result
        return result
    }

    private func scheduleCitySuggestionSearch(for rawQuery: String) {
        citySuggestionTask?.cancel()
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shouldSearchSuggestions(for: query) else {
            citySuggestions = []
            isLoadingCitySuggestions = false
            return
        }

        citySuggestionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await self?.fetchCitySuggestions(query: query)
        }
    }

    private func clearCitySuggestions(cancelTask: Bool = true) {
        if cancelTask {
            citySuggestionTask?.cancel()
            citySuggestionTask = nil
        }
        citySuggestions = []
        isLoadingCitySuggestions = false
    }

    private func shouldSearchSuggestions(for query: String) -> Bool {
        if query.range(of: "\\p{Han}", options: .regularExpression) != nil {
            return true
        }
        return query.count >= 2
    }

    private func fetchCitySuggestions(query: String) async {
        isLoadingCitySuggestions = true
        defer { isLoadingCitySuggestions = false }

        do {
            let results = try await searchCitiesRanked(query: query, count: 8)
            let suggestions = results.prefix(8).map(makeCitySuggestion(from:))
            citySuggestions = suggestions
        } catch is CancellationError {
            return
        } catch {
            citySuggestions = []
        }
    }

    private func searchCitiesRanked(
        query: String,
        count: Int
    ) async throws -> [GeocodingResult] {
        let queries = geocodingQueryVariants(for: query)
        let languages = geocodingLanguageOrder(for: query)
        guard !queries.isEmpty else { return [] }

        var combinedResults: [GeocodingResult] = []
        var firstError: Error?

        for language in languages {
            for queryVariant in queries {
                do {
                    let results = try await searchCities(query: queryVariant, count: count, language: language)
                    if !results.isEmpty {
                        combinedResults.append(contentsOf: results)
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
        }

        let ranked = rankCityResults(deduplicateCityResults(combinedResults), for: query)
        if !ranked.isEmpty {
            return ranked
        }

        if let firstError {
            throw firstError
        }

        return []
    }

    private func searchCities(
        query: String,
        count: Int,
        language: String
    ) async throws -> [GeocodingResult] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "\(count)"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components?.url else {
            throw WeatherServiceError.invalidRequest
        }

        let (data, response) = try await session.data(for: URLRequest(url: url))
        try validateHTTPResponse(response)
        let decoded = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        return decoded.results ?? []
    }

    private func makeCitySuggestion(from result: GeocodingResult) -> CitySuggestion {
        let identifier = cityIdentifier(for: result)
        let name = preferredDisplayName(for: result)
        let subtitleParts = [result.admin2, result.admin1, result.country]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        return CitySuggestion(
            id: identifier,
            displayName: name,
            subtitle: subtitleParts.joined(separator: " · "),
            queryText: name
        )
    }

    private func preferredDisplayName(for result: GeocodingResult) -> String {
        let name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.countryCode?.uppercased() == "CN" else {
            return name
        }
        if containsHanCharacters(name) {
            return name
        }
        if let admin2 = result.admin2?.trimmingCharacters(in: .whitespacesAndNewlines),
           !admin2.isEmpty, containsHanCharacters(admin2) {
            return admin2
        }
        if let admin1 = result.admin1?.trimmingCharacters(in: .whitespacesAndNewlines),
           !admin1.isEmpty, containsHanCharacters(admin1) {
            return admin1
        }
        return name
    }

    private func containsHanCharacters(_ text: String) -> Bool {
        text.range(of: "\\p{Han}", options: .regularExpression) != nil
    }

    private func normalizedCityKey(_ city: String) -> String {
        city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func geocodingQueryVariants(for query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let compact = trimmed.replacingOccurrences(
            of: "[\\s'’\\-_.]",
            with: "",
            options: .regularExpression
        )
        let withCitySuffix: String? = {
            guard containsHanCharacters(trimmed) else { return nil }
            guard !trimmed.hasSuffix("市") else { return nil }
            return "\(trimmed)市"
        }()

        var variants: [String] = []
        var seenKeys: Set<String> = []
        for candidate in [trimmed, compact, withCitySuffix].compactMap({ $0 }) {
            let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            let key = normalizedCityKey(cleaned)
            if seenKeys.insert(key).inserted {
                variants.append(cleaned)
            }
        }
        return variants
    }

    private func geocodingLanguageOrder(for query: String) -> [String] {
        containsHanCharacters(query) ? ["zh", "en"] : ["en", "zh"]
    }

    private func deduplicateCityResults(_ results: [GeocodingResult]) -> [GeocodingResult] {
        var seen: Set<String> = []
        return results.filter { seen.insert(cityIdentifier(for: $0)).inserted }
    }

    private func cityIdentifier(for result: GeocodingResult) -> String {
        result.id.map(String.init) ?? "\(result.latitude),\(result.longitude)"
    }

    private func rankCityResults(_ results: [GeocodingResult], for query: String) -> [GeocodingResult] {
        let normalizedQuery = normalizedSearchToken(query)
        return results.sorted { lhs, rhs in
            let lhsScore = cityMatchScore(for: lhs, normalizedQuery: normalizedQuery)
            let rhsScore = cityMatchScore(for: rhs, normalizedQuery: normalizedQuery)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            let lhsPopulation = lhs.population ?? 0
            let rhsPopulation = rhs.population ?? 0
            if lhsPopulation != rhsPopulation {
                return lhsPopulation > rhsPopulation
            }

            let lhsName = preferredDisplayName(for: lhs)
            let rhsName = preferredDisplayName(for: rhs)
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    private func cityMatchScore(for result: GeocodingResult, normalizedQuery: String) -> Int {
        guard !normalizedQuery.isEmpty else { return 0 }

        let primary = normalizedSearchToken(result.name)
        let secondary = [result.admin2, result.admin1, result.country]
            .compactMap { $0 }
            .map(normalizedSearchToken)
            .filter { !$0.isEmpty }

        var score = 0
        if primary == normalizedQuery {
            score += 120
        } else if primary.hasPrefix(normalizedQuery) {
            score += 90
        } else if primary.contains(normalizedQuery) {
            score += 60
        }

        if secondary.contains(normalizedQuery) {
            score += 40
        } else if secondary.contains(where: { $0.hasPrefix(normalizedQuery) }) {
            score += 30
        } else if secondary.contains(where: { $0.contains(normalizedQuery) }) {
            score += 20
        }

        return score
    }

    private func normalizedSearchToken(_ text: String) -> String {
        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: .current
        )
        return folded.replacingOccurrences(
            of: "[\\s'’\\-_.]",
            with: "",
            options: .regularExpression
        )
    }

    private func makeWeatherSnapshot(
        from forecast: WeatherForecastResponse,
        location: GeocodingResult,
        unit: WeatherTemperatureUnit
    ) throws -> WeatherSnapshot {
        guard let current = forecast.resolvedCurrent else {
            throw WeatherServiceError.invalidResponse
        }

        let weatherTimeZone = forecast.resolvedTimeZone ?? .current
        let dailyForecast = buildDailyForecast(
            from: forecast.daily,
            timeZone: weatherTimeZone
        )
        let today = dailyForecast.first

        return WeatherSnapshot(
            cityName: preferredDisplayName(for: location),
            temperature: current.temperature,
            unit: unit,
            weatherCode: current.weatherCode,
            isDay: current.isDay == 1,
            highTemperature: today?.maxTemperature,
            lowTemperature: today?.minTemperature,
            precipitationProbability: today?.precipitationProbability,
            apparentTemperature: current.apparentTemperature,
            humidity: current.relativeHumidity.map { Int($0.rounded()) },
            windSpeed: current.windSpeed,
            dailyForecast: dailyForecast,
            updatedAt: Date()
        )
    }

    private func buildDailyForecast(
        from daily: DailyWeather?,
        timeZone: TimeZone
    ) -> [WeatherDailyPoint] {
        guard let daily,
              let dates = daily.time,
              let maxTemperatures = daily.temperatureMax,
              let minTemperatures = daily.temperatureMin else {
            return []
        }

        let weatherCodes = daily.weatherCode ?? []
        let precipitation = daily.precipitationProbabilityMax ?? []
        let count = min(dates.count, maxTemperatures.count, minTemperatures.count)
        guard count > 0 else { return [] }

        return (0..<count).map { index in
            let dateRaw = dates[index]
            let parsedDate = parseDateString(dateRaw, timeZone: timeZone)
            let code = index < weatherCodes.count ? weatherCodes[index] : 0
            let rain = index < precipitation.count ? precipitation[index] : nil

            return WeatherDailyPoint(
                id: dateRaw,
                dayLabel: weekdayLabel(for: parsedDate, index: index, timeZone: timeZone),
                weatherCode: code,
                maxTemperature: maxTemperatures[index],
                minTemperature: minTemperatures[index],
                precipitationProbability: rain
            )
        }
    }

    private func weekdayLabel(
        for date: Date?,
        index: Int,
        timeZone: TimeZone
    ) -> String {
        if index == 0 {
            return l10n("weather_relative_today", fallback: "Today")
        }
        if index == 1 {
            return l10n("weather_relative_tomorrow", fallback: "Tomorrow")
        }
        guard let date else {
            return l10nFormat("weather_relative_day_format", fallback: "Day %d", index + 1)
        }

        let timeAwareCalendar = calendar(for: timeZone)
        let weekday = timeAwareCalendar.component(.weekday, from: date)
        return timeAwareCalendar.shortWeekdaySymbols[max(0, min(weekday - 1, timeAwareCalendar.shortWeekdaySymbols.count - 1))]
    }

    private func parseDateString(_ raw: String, timeZone: TimeZone) -> Date? {
        dayFormatter(for: timeZone).date(from: raw)
    }

    private func dayFormatter(for timeZone: TimeZone) -> DateFormatter {
        formatter(dateFormat: "yyyy-MM-dd", locale: Locale(identifier: "en_US_POSIX"), timeZone: timeZone)
    }

    private func formatter(dateFormat: String, locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let key = "\(dateFormat)|\(locale.identifier)|\(timeZone.identifier)"
        if let cached = dateFormatterCache[key] {
            return cached
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = dateFormat
        dateFormatterCache[key] = formatter
        return formatter
    }

    private func calendar(for timeZone: TimeZone) -> Calendar {
        if let cached = calendarCache[timeZone.identifier] {
            return cached
        }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        calendarCache[timeZone.identifier] = calendar
        return calendar
    }

    private func fetchWeatherForecastWithRetry(
        latitude: Double,
        longitude: Double,
        unit: WeatherTemperatureUnit
    ) async throws -> WeatherForecastResponse {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                return try await fetchWeatherForecast(
                    latitude: latitude,
                    longitude: longitude,
                    unit: unit
                )
            } catch {
                lastError = error
                guard attempt == 0 else { break }
                try? await Task.sleep(for: .milliseconds(450))
            }
        }
        throw lastError ?? WeatherServiceError.invalidResponse
    }

    private func fetchWeatherForecast(
        latitude: Double,
        longitude: Double,
        unit: WeatherTemperatureUnit
    ) async throws -> WeatherForecastResponse {
        do {
            let modern = try await fetchWeatherForecastModern(
                latitude: latitude,
                longitude: longitude,
                unit: unit
            )
            if modern.resolvedCurrent != nil {
                return modern
            }
        } catch {
            // fall through to legacy request as compatibility fallback
        }

        return try await fetchWeatherForecastLegacy(
            latitude: latitude,
            longitude: longitude,
            unit: unit
        )
    }

    private func fetchWeatherForecastModern(
        latitude: Double,
        longitude: Double,
        unit: WeatherTemperatureUnit
    ) async throws -> WeatherForecastResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: "\(latitude)"),
            URLQueryItem(name: "longitude", value: "\(longitude)"),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day,apparent_temperature,relative_humidity_2m,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "temperature_unit", value: unit.rawValue),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]

        guard let url = components?.url else {
            throw WeatherServiceError.invalidRequest
        }

        let (data, response) = try await session.data(for: URLRequest(url: url))
        try validateHTTPResponse(response, data: data)
        return try decodeWeatherForecast(from: data)
    }

    private func fetchWeatherForecastLegacy(
        latitude: Double,
        longitude: Double,
        unit: WeatherTemperatureUnit
    ) async throws -> WeatherForecastResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: "\(latitude)"),
            URLQueryItem(name: "longitude", value: "\(longitude)"),
            URLQueryItem(name: "current_weather", value: "true"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "temperature_unit", value: unit.rawValue),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]

        guard let url = components?.url else {
            throw WeatherServiceError.invalidRequest
        }

        let (data, response) = try await session.data(for: URLRequest(url: url))
        try validateHTTPResponse(response, data: data)
        return try decodeWeatherForecast(from: data)
    }

    private func decodeWeatherForecast(from data: Data) throws -> WeatherForecastResponse {
        do {
            return try JSONDecoder().decode(WeatherForecastResponse.self, from: data)
        } catch {
            throw WeatherServiceError.invalidResponse
        }
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let bodyText = data.flatMap { String(data: $0, encoding: .utf8) }
            throw WeatherServiceError.httpStatus(code: (response as? HTTPURLResponse)?.statusCode ?? -1, responseText: bodyText)
        }
    }
}

private func l10n(_ key: String, fallback: String) -> String {
    let localized = NSLocalizedString(key, comment: "")
    return localized == key ? fallback : localized
}

private func l10nFormat(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
    String(format: l10n(key, fallback: fallback), locale: Locale.current, arguments: arguments)
}

private enum WeatherServiceError: Error {
    case invalidRequest
    case invalidResponse
    case locationNotFound
    case httpStatus(code: Int, responseText: String?)

    var userMessage: String {
        switch self {
        case .invalidRequest, .invalidResponse:
            return l10n("weather_error_unavailable", fallback: "Weather unavailable")
        case .locationNotFound:
            return l10n("weather_error_location_not_found", fallback: "Location not found")
        case let .httpStatus(code, _):
            return l10nFormat(
                "weather_error_service_unavailable_format",
                fallback: "Weather service unavailable (%d)",
                code
            )
        }
    }
}

private struct GeocodingResponse: Decodable {
    let results: [GeocodingResult]?
}

private struct GeocodingResult: Decodable {
    let id: Int?
    let name: String
    let latitude: Double
    let longitude: Double
    let population: Int?
    let countryCode: String?
    let country: String?
    let admin1: String?
    let admin2: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case latitude
        case longitude
        case population
        case countryCode = "country_code"
        case country
        case admin1
        case admin2
    }
}

private struct WeatherForecastResponse: Decodable {
    let current: CurrentWeatherModern?
    let currentWeather: CurrentWeather?
    let daily: DailyWeather?
    let timezone: String?

    var resolvedCurrent: ResolvedCurrentWeather? {
        if let current {
            return ResolvedCurrentWeather(
                temperature: current.temperature2m,
                weatherCode: current.weatherCode,
                isDay: current.isDay,
                apparentTemperature: current.apparentTemperature,
                relativeHumidity: current.relativeHumidity2m,
                windSpeed: current.windSpeed10m
            )
        }
        if let currentWeather {
            return ResolvedCurrentWeather(
                temperature: currentWeather.temperature,
                weatherCode: currentWeather.weatherCode,
                isDay: currentWeather.isDay,
                apparentTemperature: nil,
                relativeHumidity: nil,
                windSpeed: currentWeather.windSpeed
            )
        }
        return nil
    }

    var resolvedTimeZone: TimeZone? {
        guard let timezone else { return nil }
        return TimeZone(identifier: timezone)
    }

    enum CodingKeys: String, CodingKey {
        case current
        case currentWeather = "current_weather"
        case daily
        case timezone
    }
}

private struct ResolvedCurrentWeather {
    let temperature: Double
    let weatherCode: Int
    let isDay: Int
    let apparentTemperature: Double?
    let relativeHumidity: Double?
    let windSpeed: Double?
}

private struct CurrentWeatherModern: Decodable {
    let temperature2m: Double
    let weatherCode: Int
    let isDay: Int
    let apparentTemperature: Double?
    let relativeHumidity2m: Double?
    let windSpeed10m: Double?

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case weatherCode = "weather_code"
        case isDay = "is_day"
        case apparentTemperature = "apparent_temperature"
        case relativeHumidity2m = "relative_humidity_2m"
        case windSpeed10m = "wind_speed_10m"
    }
}

private struct DailyWeather: Decodable {
    let time: [String]?
    let weatherCode: [Int]?
    let temperatureMax: [Double]?
    let temperatureMin: [Double]?
    let precipitationProbabilityMax: [Double]?

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperatureMax = "temperature_2m_max"
        case temperatureMin = "temperature_2m_min"
        case precipitationProbabilityMax = "precipitation_probability_max"
    }
}

private struct CurrentWeather: Decodable {
    let temperature: Double
    let windSpeed: Double?
    let weatherCode: Int
    let isDay: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case windSpeed = "windspeed"
        case weatherCode = "weathercode"
        case isDay = "is_day"
    }
}

enum WeatherCodeMapper {
    static func description(for code: Int) -> String {
        let (key, fallback) = descriptionResource(for: code)
        return l10n(key, fallback: fallback)
    }

    private static func descriptionResource(for code: Int) -> (key: String, fallback: String) {
        switch code {
        case 0:
            return ("weather_condition_clear", "Clear")
        case 1:
            return ("weather_condition_mainly_clear", "Mainly clear")
        case 2:
            return ("weather_condition_partly_cloudy", "Partly cloudy")
        case 3:
            return ("weather_condition_cloudy", "Cloudy")
        case 45, 48:
            return ("weather_condition_fog", "Fog")
        case 51, 53, 55:
            return ("weather_condition_drizzle", "Drizzle")
        case 56, 57:
            return ("weather_condition_freezing_drizzle", "Freezing drizzle")
        case 61, 63, 65:
            return ("weather_condition_rain", "Rain")
        case 66, 67:
            return ("weather_condition_freezing_rain", "Freezing rain")
        case 71, 73, 75, 77:
            return ("weather_condition_snow", "Snow")
        case 80, 81, 82:
            return ("weather_condition_rain_showers", "Rain showers")
        case 85, 86:
            return ("weather_condition_snow_showers", "Snow showers")
        case 95:
            return ("weather_condition_thunderstorm", "Thunderstorm")
        case 96, 99:
            return ("weather_condition_thunderstorm_hail", "Thunderstorm with hail")
        default:
            return ("weather_condition_unknown", "Unknown")
        }
    }

    static func symbolName(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0:
            return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2:
            return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:
            return "cloud.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51, 53, 55:
            return "cloud.drizzle.fill"
        case 56, 57, 66, 67:
            return "cloud.sleet.fill"
        case 61, 63, 65:
            return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86:
            return "cloud.snow.fill"
        case 80, 81, 82:
            return "cloud.heavyrain.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }
}
