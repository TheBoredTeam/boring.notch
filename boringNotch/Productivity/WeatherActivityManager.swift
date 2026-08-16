import CoreLocation
import Defaults
import Foundation
import Security
import WeatherKit

nonisolated enum WeatherActivityIssue: Equatable {
    case locationAccess
    case locationUnavailable
    case weatherKitConfiguration
    case serviceUnavailable

    var title: String {
        switch self {
        case .locationAccess: "Location access is off"
        case .locationUnavailable: "Location unavailable"
        case .weatherKitConfiguration: "WeatherKit setup required"
        case .serviceUnavailable: "Weather unavailable"
        }
    }

    var message: String {
        switch self {
        case .locationAccess: "Choose a manual location in Settings."
        case .locationUnavailable: "Check the location and try again."
        case .weatherKitConfiguration: "Use a signed build with WeatherKit enabled."
        case .serviceUnavailable: "The weather service could not be reached."
        }
    }

    var offersSettings: Bool {
        self == .locationAccess
    }

    static func weatherService(error: Error) -> Self {
        let error = error as NSError
        let diagnostic = "\(error.domain) \(error.localizedDescription)".lowercased()
        let configurationMarkers = [
            "weatherdaemon",
            "wdsjwtauth",
            "jwt",
            "entitlement",
            "not authorized",
        ]
        return configurationMarkers.contains(where: diagnostic.contains)
            ? .weatherKitConfiguration
            : .serviceUnavailable
    }
}

nonisolated enum WeatherKitBuildConfiguration {
    static var hasEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.developer.weatherkit" as CFString,
                  nil
              ) as? Bool
        else {
            return false
        }
        return value
    }
}

@MainActor
final class WeatherActivityManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherActivityManager()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var issue: WeatherActivityIssue?
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
            issue = nil
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
            issue = .locationAccess
        @unknown default:
            issue = .locationUnavailable
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
            self?.issue = .locationUnavailable
        }
    }

    private func fetchWeather(at location: CLLocation, locationName: String) {
        refreshTask?.cancel()
        guard WeatherKitBuildConfiguration.hasEntitlement else {
            snapshot = nil
            isLoading = false
            issue = .weatherKitConfiguration
            return
        }

        isLoading = true
        issue = nil

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
                issue = nil
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                issue = .weatherService(error: error)
            }
        }
    }
}
