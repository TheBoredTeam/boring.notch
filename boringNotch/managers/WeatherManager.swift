import Defaults
import Foundation
import OSLog

final class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    private static let logger = Logger(subsystem: "theboringteam.boringnotch", category: "Weather")

    @Published var temperature: Double?
    @Published var weatherCode: Int?
    @Published var cityName: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var timer: Timer?
    private let session: URLSession
    private var isFetching = false

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)

        if Defaults[.showWeather] {
            start()
        }
    }

    func start() {
        guard timer == nil else { return }
        Task { await fetchWeather() }
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { await self?.fetchWeather() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func fetchWeather() async {
        guard !isFetching else { return }
        isFetching = true
        await MainActor.run { isLoading = true; errorMessage = nil }

        defer { Task { @MainActor in isFetching = false; isLoading = false } }

        let lat = Defaults[.weatherLatitude]
        let lon = Defaults[.weatherLongitude]

        // If no coordinates set, try IP geolocation first
        if lat == 0 && lon == 0 {
            await resolveLocation()
        }

        let resolvedLat = Defaults[.weatherLatitude]
        let resolvedLon = Defaults[.weatherLongitude]

        guard resolvedLat != 0 || resolvedLon != 0 else {
            await MainActor.run { errorMessage = "Location not set" }
            return
        }

        let unit = Defaults[.weatherTemperatureUnit]
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(resolvedLat)&longitude=\(resolvedLon)&current=temperature_2m,weather_code&temperature_unit=\(unit)&timezone=auto") else {
            await MainActor.run { errorMessage = "Invalid URL" }
            return
        }

        do {
            let (data, _) = try await session.data(for: URLRequest(url: url))
            let response = try JSONDecoder().decode(WeatherResponse.self, from: data)
            await MainActor.run {
                self.temperature = response.current.temperature2m
                self.weatherCode = response.current.weatherCode
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func resolveLocation() async {
        guard let url = URL(string: "https://ipapi.co/json/") else { return }
        do {
            let (data, _) = try await session.data(for: URLRequest(url: url))
            let geo = try JSONDecoder().decode(IPGeoResponse.self, from: data)
            await MainActor.run {
                Defaults[.weatherLatitude] = geo.latitude
                Defaults[.weatherLongitude] = geo.longitude
                self.cityName = geo.city
            }
        } catch {
            Self.logger.warning("IP geolocation failed: \(error)")
        }
    }

    deinit {
        timer?.invalidate()
    }
}
