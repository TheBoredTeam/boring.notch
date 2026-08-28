//
//  LockScreenWeatherWidgetManager.swift
//  boringNotch
//
//  A compact Open-Meteo powered lock-screen status widget. It combines weather
//  with the battery, audio-route, calendar and Focus information already
//  available to Boring Notch.
//

import AppKit
import Combine
@preconcurrency import CoreLocation
import Defaults
import Foundation
import SwiftUI

@MainActor
final class LockScreenWeatherWidgetManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LockScreenWeatherWidgetManager()

    @Published private(set) var snapshot = LockScreenWeatherSnapshot.placeholder

    private let panel = LockScreenWidgetPanel(allowsInteraction: false)
    private let locationManager = CLLocationManager()
    private let battery = BatteryStatusViewModel.shared
    private let agenda = LockScreenAgendaWidgetManager.shared
    private let focus = LockScreenFocusMonitor.shared
    private var currentLocation: CLLocation?
    private var weather: WeatherData?
    private var lastFetchDate: Date?
    private var isLocked = false
    private var isFetching = false
    private var statusRefreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer

        observeSettings()

        battery.objectWillChange
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
        agenda.objectWillChange
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
        focus.objectWillChange
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
    }

    func screenDidLock() {
        isLocked = true
        startStatusRefreshTimer()
        refresh()
    }

    private func observeSettings() {
        Defaults.publisher(.showOnLockScreen).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        Defaults.publisher(.enableLockScreenWeatherWidget).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        Defaults.publisher(.enableLockScreenFocusWidget).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        Defaults.publisher(.lockScreenWeatherRefreshInterval).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        Defaults.publisher(.lockScreenWeatherShowsLocation).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        Defaults.publisher(.lockScreenWeatherShowsSunrise).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        Defaults.publisher(.lockScreenWeatherWidgetStyle).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        Defaults.publisher(.lockScreenWeatherTemperatureUnit).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        Defaults.publisher(.lockScreenWeatherShowsAQI).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        Defaults.publisher(.lockScreenWeatherVerticalOffset).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        Defaults.publisher(.lockScreenBatteryShowsBatteryGauge).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        Defaults.publisher(.lockScreenBatteryShowsCharging).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        Defaults.publisher(.lockScreenBatteryShowsChargingPercentage).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        Defaults.publisher(.lockScreenBatteryShowsBluetooth).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        Defaults.publisher(.lockScreenShowCalendarEvent).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
    }

    private func startStatusRefreshTimer() {
        statusRefreshTimer?.invalidate()
        statusRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if let statusRefreshTimer {
            RunLoop.main.add(statusRefreshTimer, forMode: .common)
        }
    }

    func screenDidUnlock() {
        isLocked = false
        statusRefreshTimer?.invalidate()
        statusRefreshTimer = nil
        panel.hide()
    }

    func prepareLocationAccess() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            locationManager.requestLocation()
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let isAuthorized = manager.authorizationStatus == .authorizedAlways
        Task { @MainActor [weak self] in
            if isAuthorized {
                self?.locationManager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        Task { @MainActor [weak self] in
            self?.currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            self?.refresh(force: true)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.render()
        }
    }

    func refresh(force: Bool = false) {
        render()
        guard shouldDisplay, !isFetching else { return }

        let interval = Defaults[.lockScreenWeatherRefreshInterval]
        let needsFetch = force || lastFetchDate == nil || Date().timeIntervalSince(lastFetchDate ?? .distantPast) >= interval
        guard needsFetch else { return }

        prepareLocationAccess()
        guard let currentLocation else { return }

        isFetching = true
        let unit = Defaults[.lockScreenWeatherTemperatureUnit]
        Task { [weak self] in
            defer { self?.isFetching = false }
            do {
                let data = try await Self.fetchWeather(for: currentLocation, unit: unit)
                let locationName = await Self.locationName(for: currentLocation)
                guard !Task.isCancelled else { return }
                self?.weather = data.with(locationName: locationName)
                self?.lastFetchDate = Date()
                self?.render()
            } catch {
                self?.render()
            }
        }
    }

    private var shouldDisplay: Bool {
        isLocked && Defaults[.showOnLockScreen] && Defaults[.enableLockScreenWeatherWidget]
    }

    private func render() {
        let newSnapshot = makeSnapshot()
        snapshot = newSnapshot

        guard shouldDisplay, let context = LockScreenDisplayContextProvider.shared.snapshot() else {
            panel.hide()
            return
        }

        let style = Defaults[.lockScreenWeatherWidgetStyle]
        let size = style == .inline
            ? CGSize(width: 500, height: 88)
            : CGSize(width: 160, height: 160)
        let frame = LockScreenWidgetLayout.weather(
            in: context.frame,
            size: size,
            offset: CGFloat(Defaults[.lockScreenWeatherVerticalOffset])
        )
        panel.show(
            LockScreenWeatherWidgetView(snapshot: newSnapshot),
            frame: frame,
            cornerRadius: style == .inline ? 26 : 80
        )
    }

    private func makeSnapshot() -> LockScreenWeatherSnapshot {
        let calendarEvent = agenda.nextCalendarEvent
        let batteryLevel = max(0, min(100, Int(battery.levelBattery.rounded())))
        let showsBattery = Defaults[.lockScreenBatteryShowsBatteryGauge]
        let showBluetooth = Defaults[.lockScreenBatteryShowsBluetooth]
        let bluetoothName = showBluetooth && AudioOutputRouteResolver.shared.isBluetoothOutput
            ? AudioOutputRouteResolver.shared.currentOutputName
            : nil
        let focusName = Defaults[.enableLockScreenFocusWidget] && focus.isActive ? focus.name : nil

        return LockScreenWeatherSnapshot(
            temperature: weather?.temperature,
            unitSymbol: Defaults[.lockScreenWeatherTemperatureUnit].symbol,
            symbolName: weather.map { Self.symbol(for: $0.weatherCode) } ?? "cloud.fill",
            description: weather.map { Self.description(for: $0.weatherCode) }
                ?? LockScreenText.value("Weather unavailable"),
            locationName: Defaults[.lockScreenWeatherShowsLocation] ? weather?.locationName : nil,
            sunrise: Defaults[.lockScreenWeatherShowsSunrise] ? weather?.sunrise : nil,
            aqi: Defaults[.lockScreenWeatherShowsAQI] ? weather?.aqi : nil,
            batteryLevel: showsBattery ? batteryLevel : nil,
            isCharging: battery.isCharging,
            isPluggedIn: battery.isPluggedIn,
            chargingPercentage: Defaults[.lockScreenBatteryShowsChargingPercentage] ? batteryLevel : nil,
            bluetoothName: bluetoothName,
            calendarTitle: Defaults[.lockScreenShowCalendarEvent] ? calendarEvent?.title : nil,
            calendarStart: Defaults[.lockScreenShowCalendarEvent] ? calendarEvent?.start : nil,
            focusName: focusName,
            style: Defaults[.lockScreenWeatherWidgetStyle]
        )
    }

    private static func fetchWeather(
        for location: CLLocation,
        unit: LockScreenWeatherTemperatureUnit
    ) async throws -> WeatherData {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        if unit == .fahrenheit {
            components.queryItems?.append(URLQueryItem(name: "temperature_unit", value: "fahrenheit"))
        }

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let formatter = ISO8601DateFormatter()
        let sunrise = decoded.daily.sunrise.first.flatMap(formatter.date(from:))
        let sunset = decoded.daily.sunset.first.flatMap(formatter.date(from:))
        return WeatherData(
            temperature: decoded.current.temperature,
            weatherCode: decoded.current.weatherCode,
            sunrise: sunrise,
            sunset: sunset,
            aqi: nil,
            locationName: nil
        )
    }

    private static func locationName(for location: CLLocation) async -> String? {
        guard let place = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        return place.locality ?? place.administrativeArea ?? place.country
    }

    private static func symbol(for weatherCode: Int) -> String {
        switch weatherCode {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    private static func description(for weatherCode: Int) -> String {
        switch weatherCode {
        case 0: LockScreenText.value("Clear")
        case 1, 2: LockScreenText.value("Partly cloudy")
        case 3: LockScreenText.value("Overcast")
        case 45, 48: LockScreenText.value("Foggy")
        case 51, 53, 55, 56, 57: LockScreenText.value("Drizzle")
        case 61, 63, 65, 66, 67, 80, 81, 82: LockScreenText.value("Rain")
        case 71, 73, 75, 77, 85, 86: LockScreenText.value("Snow")
        case 95, 96, 99: LockScreenText.value("Thunderstorm")
        default: LockScreenText.value("Weather")
        }
    }
}

@MainActor
private final class LockScreenFocusMonitor: NSObject, ObservableObject {
    static let shared = LockScreenFocusMonitor()

    @Published private(set) var isActive: Bool
    @Published private(set) var name: String
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        isActive = Defaults[.lockScreenFocusActive]
        name = Defaults[.lockScreenFocusName]
        super.init()

        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(
            forName: Notification.Name("_NSDoNotDisturbEnabledNotification"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let focusName = notification.userInfo?["FocusModeName"] as? String
            Task { @MainActor in self?.setFocus(active: true, name: focusName) }
        })
        observers.append(center.addObserver(
            forName: Notification.Name("_NSDoNotDisturbDisabledNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.setFocus(active: false, name: nil) }
        })

        Defaults.publisher(.lockScreenFocusActive)
            .sink { [weak self] change in self?.isActive = change.newValue }
            .store(in: &cancellables)
        Defaults.publisher(.lockScreenFocusName)
            .sink { [weak self] change in self?.name = change.newValue }
            .store(in: &cancellables)
    }

    private func setFocus(active: Bool, name: String?) {
        isActive = active
        if let focusName = name, !focusName.isEmpty {
            self.name = focusName
        }
    }
}

private struct WeatherData: Equatable {
    let temperature: Double
    let weatherCode: Int
    let sunrise: Date?
    let sunset: Date?
    let aqi: Int?
    let locationName: String?

    func with(locationName: String?) -> Self {
        Self(
            temperature: temperature,
            weatherCode: weatherCode,
            sunrise: sunrise,
            sunset: sunset,
            aqi: aqi,
            locationName: locationName
        )
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature: Double
        let weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }

    struct Daily: Decodable {
        let sunrise: [String]
        let sunset: [String]
    }

    let current: Current
    let daily: Daily
}

struct LockScreenWeatherSnapshot: Equatable {
    let temperature: Double?
    let unitSymbol: String
    let symbolName: String
    let description: String
    let locationName: String?
    let sunrise: Date?
    let aqi: Int?
    let batteryLevel: Int?
    let isCharging: Bool
    let isPluggedIn: Bool
    let chargingPercentage: Int?
    let bluetoothName: String?
    let calendarTitle: String?
    let calendarStart: Date?
    let focusName: String?
    let style: LockScreenWeatherWidgetStyle

    static let placeholder = Self(
        temperature: nil, unitSymbol: "°", symbolName: "cloud.fill",
        description: LockScreenText.value("Weather unavailable"),
        locationName: nil, sunrise: nil, aqi: nil, batteryLevel: nil, isCharging: false,
        isPluggedIn: false, chargingPercentage: nil, bluetoothName: nil, calendarTitle: nil,
        calendarStart: nil, focusName: nil, style: .inline
    )
}

private struct LockScreenWeatherWidgetView: View {
    let snapshot: LockScreenWeatherSnapshot

    var body: some View {
        switch snapshot.style {
        case .inline: inlineWidget
        case .circular: circularWidget
        }
    }

    private var inlineWidget: some View {
        LockScreenWidgetCard(cornerRadius: 26) {
            HStack(spacing: 13) {
                Image(systemName: snapshot.symbolName)
                    .font(.system(size: 29, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text(temperatureText)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                    Text(snapshot.locationName ?? snapshot.description)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 106, alignment: .leading)

                Divider().frame(height: 44)
                statusColumn
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 17)
            .frame(width: 500, height: 88)
        }
    }

    private var circularWidget: some View {
        LockScreenWidgetCard(cornerRadius: 80) {
            VStack(spacing: 4) {
                Image(systemName: snapshot.symbolName)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.yellow)
                Text(temperatureText)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                Text(snapshot.locationName ?? snapshot.description)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120)
            }
            .frame(width: 160, height: 160)
        }
    }

    @ViewBuilder
    private var statusColumn: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            alignment: .leading,
            spacing: 5
        ) {
            if let calendarTitle = snapshot.calendarTitle {
                statusRow("calendar", text: calendarTitle, detail: snapshot.calendarStart.map { $0.formatted(date: .omitted, time: .shortened) })
            }
            if let focusName = snapshot.focusName {
                statusRow("moon.zzz.fill", text: focusName, detail: nil)
            }
            if let batteryLevel = snapshot.batteryLevel {
                statusRow(
                    snapshot.isCharging ? "battery.100.bolt" : "battery.100",
                    text: "\(batteryLevel)%",
                    detail: batteryDetail
                )
            }
            if let bluetoothName = snapshot.bluetoothName {
                statusRow("bluetooth", text: bluetoothName, detail: nil)
            }
            if let aqi = snapshot.aqi {
                statusRow("aqi.medium", text: "AQI \(aqi)", detail: nil)
            }
            if let sunrise = snapshot.sunrise {
                statusRow("sunrise.fill", text: sunrise.formatted(date: .omitted, time: .shortened), detail: nil)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .frame(width: 300, alignment: .leading)
    }

    private var batteryDetail: String? {
        guard snapshot.isPluggedIn else { return nil }
        if snapshot.isCharging, let percentage = snapshot.chargingPercentage {
            return String(format: LockScreenText.value("Charging %@"), "\(percentage)%")
        }
        return snapshot.isCharging
            ? LockScreenText.value("Charging")
            : LockScreenText.value("Plugged in")
    }

    private var temperatureText: String {
        guard let temperature = snapshot.temperature else { return "--" }
        return "\(Int(temperature.rounded()))\(snapshot.unitSymbol)"
    }

    private func statusRow(_ icon: String, text: String, detail: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .frame(width: 14)
                .foregroundStyle(.secondary)
            Text(text)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
