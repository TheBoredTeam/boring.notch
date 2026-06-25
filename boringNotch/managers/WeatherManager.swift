//
//  WeatherManager.swift
//  boringNotch
//
//  Created by Arsh Anwar on 26/12/25.
//

import Foundation
import CoreLocation
import SwiftUI
import Combine

// MARK: - Weather Models

struct WeatherData {
    let temperature: Double
    let condition: String
    let symbolName: String
    let humidity: Double
    let windSpeed: Double
    let feelsLike: Double
    let high: Double
    let low: Double
    let location: String
    let lastUpdated: Date

    var temperatureString: String {
        return String(format: "%.0f°", temperature)
    }

    var systemIconName: String {
        return symbolName
    }

    var humidityInt: Int {
        return Int(humidity * 100)
    }
}

// MARK: - Open-Meteo Response Models

private struct OpenMeteoResponse: Decodable {
    let current: CurrentWeather
    let daily: DailyForecast

    struct CurrentWeather: Decodable {
        let temperature2m: Double
        let relativeHumidity2m: Int
        let apparentTemperature: Double
        let weatherCode: Int
        let windSpeed10m: Double

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case relativeHumidity2m = "relative_humidity_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
            case windSpeed10m = "wind_speed_10m"
        }
    }

    struct DailyForecast: Decodable {
        let temperature2mMax: [Double]
        let temperature2mMin: [Double]

        enum CodingKeys: String, CodingKey {
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
        }
    }
}

// MARK: - WMO Weather Code Helpers

private func wmoSymbol(for code: Int) -> String {
    switch code {
    case 0:
        return "sun.max.fill"
    case 1:
        return "sun.max.fill"
    case 2:
        return "cloud.sun.fill"
    case 3:
        return "cloud.fill"
    case 45, 48:
        return "cloud.fog.fill"
    case 51, 53, 55:
        return "cloud.drizzle.fill"
    case 56, 57:
        return "cloud.sleet.fill"
    case 61, 63, 65:
        return "cloud.rain.fill"
    case 66, 67:
        return "cloud.sleet.fill"
    case 71, 73, 75, 77:
        return "cloud.snow.fill"
    case 80, 81, 82:
        return "cloud.heavyrain.fill"
    case 85, 86:
        return "cloud.snow.fill"
    case 95:
        return "cloud.bolt.fill"
    case 96, 99:
        return "cloud.bolt.rain.fill"
    default:
        return "cloud.fill"
    }
}

private func wmoCondition(for code: Int) -> String {
    switch code {
    case 0:
        return String(localized: "Clear Sky")
    case 1:
        return String(localized: "Mainly Clear")
    case 2:
        return String(localized: "Partly Cloudy")
    case 3:
        return String(localized: "Overcast")
    case 45:
        return String(localized: "Foggy")
    case 48:
        return String(localized: "Icy Fog")
    case 51:
        return String(localized: "Light Drizzle")
    case 53:
        return String(localized: "Drizzle")
    case 55:
        return String(localized: "Heavy Drizzle")
    case 56, 57:
        return String(localized: "Freezing Drizzle")
    case 61:
        return String(localized: "Light Rain")
    case 63:
        return String(localized: "Rain")
    case 65:
        return String(localized: "Heavy Rain")
    case 66, 67:
        return String(localized: "Freezing Rain")
    case 71:
        return String(localized: "Light Snow")
    case 73:
        return String(localized: "Snow")
    case 75:
        return String(localized: "Heavy Snow")
    case 77:
        return String(localized: "Snow Grains")
    case 80:
        return String(localized: "Light Showers")
    case 81:
        return String(localized: "Rain Showers")
    case 82:
        return String(localized: "Heavy Showers")
    case 85, 86:
        return String(localized: "Snow Showers")
    case 95:
        return String(localized: "Thunderstorm")
    case 96, 99:
        return String(localized: "Thunderstorm with Hail")
    default:
        return String(localized: "Unknown")
    }
}

// MARK: - WeatherManager

@MainActor
class WeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherManager()

    @Published var currentWeather: WeatherData?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let geocoder = CLGeocoder()
    private var isRequestingLocation = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func checkLocationAuthorization() {
        locationAuthorizationStatus = locationManager.authorizationStatus

        switch locationAuthorizationStatus {
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            startUpdatingWeather()
        case .denied, .restricted:
            errorMessage = "Location access denied"
        @unknown default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            locationAuthorizationStatus = manager.authorizationStatus

            if locationAuthorizationStatus == .authorizedAlways {
                startUpdatingWeather()
            }
        }
    }

    func startUpdatingWeather() {
        fetchWeather()

        // Update weather every 30 minutes
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.fetchWeather()
        }
    }

    func stopUpdatingWeather() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    func fetchWeather() {
        guard locationAuthorizationStatus == .authorizedAlways else {
            return
        }

        guard !isRequestingLocation else {
            return
        }

        isRequestingLocation = true
        locationManager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        Task { @MainActor in
            isRequestingLocation = false
            fetchWeatherData(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            isRequestingLocation = false
            errorMessage = "Failed to get location: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func fetchWeatherData(for location: CLLocation) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let lat = location.coordinate.latitude
                let lon = location.coordinate.longitude

                var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
                components.queryItems = [
                    URLQueryItem(name: "latitude", value: String(lat)),
                    URLQueryItem(name: "longitude", value: String(lon)),
                    URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m"),
                    URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
                    URLQueryItem(name: "timezone", value: "auto"),
                    URLQueryItem(name: "forecast_days", value: "1"),
                ]

                let (data, _) = try await URLSession.shared.data(from: components.url!)
                let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

                let placemarks = try? await geocoder.reverseGeocodeLocation(location)
                let locationName = placemarks?.first?.locality ?? placemarks?.first?.name ?? "Unknown"

                let current = response.current
                let weatherData = WeatherData(
                    temperature: current.temperature2m,
                    condition: wmoCondition(for: current.weatherCode),
                    symbolName: wmoSymbol(for: current.weatherCode),
                    humidity: Double(current.relativeHumidity2m) / 100.0,
                    windSpeed: current.windSpeed10m,
                    feelsLike: current.apparentTemperature,
                    high: response.daily.temperature2mMax.first ?? current.temperature2m,
                    low: response.daily.temperature2mMin.first ?? current.temperature2m,
                    location: locationName,
                    lastUpdated: Date()
                )

                await MainActor.run {
                    self.currentWeather = weatherData
                    self.errorMessage = nil
                    self.isLoading = false
                }

            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to fetch weather: \(error.localizedDescription)"
                    self.isLoading = false
                    print("Weather fetch error: \(error)")
                }
            }
        }
    }

    nonisolated deinit {
        Task { @MainActor in
            stopUpdatingWeather()
        }
    }
}
