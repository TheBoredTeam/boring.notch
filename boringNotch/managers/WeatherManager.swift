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
import WeatherKit

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

// MARK: - WeatherManager

@MainActor
class WeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherManager()
    
    @Published var currentWeather: WeatherData?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    
    private let locationManager = CLLocationManager()
    private let weatherService = WeatherService.shared
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
        
        // Prevent multiple simultaneous location requests
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
                // Fetch weather using WeatherKit
                let weather = try await weatherService.weather(for: location)
                
                // Get location name using reverse geocoding
                let placemarks = try? await geocoder.reverseGeocodeLocation(location)
                let locationName = placemarks?.first?.locality ?? placemarks?.first?.name ?? "Unknown"
                
                // Create weather data from WeatherKit response
                let weatherData = WeatherData(
                    temperature: weather.currentWeather.temperature.value,
                    condition: weather.currentWeather.condition.description,
                    symbolName: weather.currentWeather.symbolName,
                    humidity: weather.currentWeather.humidity,
                    windSpeed: weather.currentWeather.wind.speed.value,
                    feelsLike: weather.currentWeather.apparentTemperature.value,
                    high: weather.dailyForecast.first?.highTemperature.value ?? weather.currentWeather.temperature.value,
                    low: weather.dailyForecast.first?.lowTemperature.value ?? weather.currentWeather.temperature.value,
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
                    // Provide a user-friendly error message
                    let errorDescription = error.localizedDescription
                    if errorDescription.contains("DTD") || errorDescription.contains("plist") {
                        self.errorMessage = "Weather service unavailable. Please try again later."
                    } else {
                        self.errorMessage = "Failed to fetch weather: \(errorDescription)"
                    }
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
