import CoreLocation
import Defaults
import Foundation
import WeatherKit

@MainActor
final class WeatherActivityManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherActivityManager()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()
    private let weatherService = WeatherService.shared
    private var refreshTask: Task<Void, Never>?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = locationManager.authorizationStatus

        if Defaults[.weatherEnabled] {
            refresh()
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    func refresh() {
        guard Defaults[.weatherEnabled] else {
            snapshot = nil
            errorMessage = nil
            return
        }

        if Defaults[.weatherUseCurrentLocation] {
            requestCurrentLocation()
        } else {
            fetchWeather(
                at: CLLocation(
                    latitude: Defaults[.weatherLatitude],
                    longitude: Defaults[.weatherLongitude]
                ),
                locationName: Defaults[.weatherLocationName]
            )
        }
    }

    func requestCurrentLocation() {
        authorizationStatus = locationManager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            errorMessage = "Location access is off. Use a manual location in Settings."
        @unknown default:
            errorMessage = "Location is unavailable."
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = status
            if status == .authorized
                || status == .authorizedAlways
            {
                self.locationManager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.fetchWeather(at: location, locationName: "Current Location")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.isLoading = false
            self?.errorMessage = error.localizedDescription
        }
    }

    private func fetchWeather(at location: CLLocation, locationName: String) {
        refreshTask?.cancel()
        isLoading = true
        errorMessage = nil

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let current = try await weatherService.weather(for: location, including: .current)
                guard !Task.isCancelled else { return }

                snapshot = WeatherSnapshot(
                    temperatureCelsius: current.temperature.converted(to: .celsius).value,
                    apparentTemperatureCelsius: current.apparentTemperature.converted(to: .celsius).value,
                    symbolName: current.symbolName,
                    condition: String(describing: current.condition)
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized,
                    locationName: locationName,
                    fetchedAt: Date()
                )
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
