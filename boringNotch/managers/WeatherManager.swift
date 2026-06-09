//
//  WeatherManager.swift
//  boringNotch
//
//  Created by Maksymilian Wójcik on 2026-06-09.
//
//  Fetches current weather from wttr.in (free, no API key). When "use location"
//  is on it auto-locates by IP (no CoreLocation permission needed); otherwise it
//  uses a manually configured city.
//

import Combine
import Defaults
import Foundation

struct WeatherError: Error { let message: String }

@MainActor
final class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    @Published private(set) var temperature: Double?
    @Published private(set) var conditionText: String = ""
    @Published private(set) var symbolName: String = "thermometer"
    @Published private(set) var locationName: String = ""
    @Published private(set) var statusMessage: String?

    private var timer: Timer?
    private var subscriberCount = 0
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        // wttr.in serves JSON for `format=j1`, but a curl-like UA is the safe path.
        config.httpAdditionalHeaders = ["User-Agent": "curl/8.4.0"]
        session = URLSession(configuration: config)
    }

    /// Begins periodic refresh. Reference-counted across views.
    func start() {
        subscriberCount += 1
        Task { await refresh() }
        guard timer == nil else { return }
        let interval = max(300, Defaults[.weatherUpdateInterval])
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func stop() {
        subscriberCount = max(0, subscriberCount - 1)
        if subscriberCount == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Forces an immediate refresh (e.g. after changing the city in settings).
    func refresh() async {
        do {
            try await fetch()
            statusMessage = nil
        } catch let error as WeatherError {
            statusMessage = error.message
        } catch {
            statusMessage = "Weather unavailable"
        }
    }

    // MARK: - Networking

    private func fetch() async throws {
        // Empty location → wttr.in auto-locates by IP.
        var location = ""
        if !Defaults[.weatherUseLocation] {
            location = Defaults[.weatherManualCity].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard let url = URL(string: "https://wttr.in/\(encoded)?format=j1") else {
            throw WeatherError(message: "Invalid request")
        }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw WeatherError(message: location.isEmpty ? "Location not found" : "City not found")
        }

        let decoded = try JSONDecoder().decode(WttrResponse.self, from: data)
        guard let current = decoded.current_condition.first else {
            throw WeatherError(message: "Weather unavailable")
        }

        let useCelsius = Defaults[.weatherUnit] == .celsius
        temperature = Double(useCelsius ? current.temp_C : current.temp_F)
        let desc = current.weatherDesc.first?.value ?? ""
        conditionText = desc
        symbolName = Self.symbol(for: desc)
        if let area = decoded.nearest_area?.first?.areaName.first?.value, !area.isEmpty {
            locationName = area
        } else if !location.isEmpty {
            locationName = location
        }
    }

    // MARK: - Decodable model (wttr.in j1 format — numbers come as strings)

    private struct WttrResponse: Decodable {
        struct Value: Decodable { let value: String }
        struct Current: Decodable {
            let temp_C: String
            let temp_F: String
            let weatherDesc: [Value]
        }
        struct Area: Decodable {
            let areaName: [Value]
        }
        let current_condition: [Current]
        let nearest_area: [Area]?
    }

    // MARK: - Condition → SF Symbol (keyword based)

    static func symbol(for description: String) -> String {
        let d = description.lowercased()
        if d.contains("thunder") { return "cloud.bolt.rain.fill" }
        if d.contains("snow") || d.contains("blizzard") || d.contains("sleet") || d.contains("ice") {
            return "cloud.snow.fill"
        }
        if d.contains("drizzle") || d.contains("rain") || d.contains("shower") {
            return "cloud.rain.fill"
        }
        if d.contains("fog") || d.contains("mist") || d.contains("haze") {
            return "cloud.fog.fill"
        }
        if d.contains("overcast") { return "cloud.fill" }
        if d.contains("partly") || d.contains("cloud") { return "cloud.sun.fill" }
        if d.contains("clear") || d.contains("sunny") { return "sun.max.fill" }
        return "cloud.fill"
    }
}
