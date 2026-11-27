// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Combine
import Foundation

@MainActor
final class NotchFeatures: ObservableObject {
    static let shared = NotchFeatures()
    @Published var place: FeaturePlace { didSet { save(place, "place"); forecast = nil; fetchedAt = nil; Task { await refreshWeather(force: true) } } }
    @Published private(set) var forecast: FeatureForecast?
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var weatherError: String?
    @Published private(set) var loadingWeather = false
    @Published var cityResults: [FeaturePlace] = []
    @Published var searchError: String?
    @Published var bluetoothEnabled: Bool { didSet { UserDefaults.standard.set(bluetoothEnabled, forKey: key("bluetooth")); configureBridge() } }
    @Published var locked = false { didSet { if locked { banner = nil; configureBridge() } else { configureBridge(); Task { await refreshWeather() } } } }
    @Published private(set) var bridge = FeatureBridgeState()
    @Published private(set) var banner: (String, String, String)?
    var bridgeConfigure: ((Bool, Bool) async throws -> Data)?
    private var bridgeTask: Task<Void, Never>?
    private var weatherTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private func key(_ name: String) -> String { "np.features." + name }
    private init() {
        let d = UserDefaults.standard
        func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
            guard let data = d.data(forKey: "np.features." + name) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
        place = read(FeaturePlace.self, "place") ?? .krasnodar
        bluetoothEnabled = d.bool(forKey: "np.features.bluetooth")
        observers.append(NotificationCenter.default.addObserver(forName: .featureBridgeEvent, object: nil, queue: .main) { [weak self] note in
            guard let data = note.object as? Data else { return }
            Task { @MainActor in self?.receive(data) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.configureBridge() }
        })
    }
    func start(configure: @escaping (Bool, Bool) async throws -> Data) {
        bridgeConfigure = configure
        configureBridge()
        guard weatherTask == nil else { return }
        weatherTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshWeather()
                try? await Task.sleep(for: .seconds(1200))
            }
        }
    }
    private func save<T: Encodable>(_ value: T, _ name: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key(name)) }
    }
    func configureBridge() {
        bridgeTask?.cancel()
        guard let configure = bridgeConfigure else { return }
        let bluetooth = bluetoothEnabled, notifications = false
        bridgeTask = Task { [weak self] in
            do {
                guard !Task.isCancelled else { return }
                let data = try await configure(bluetooth, notifications)
                guard !Task.isCancelled else { return }
                self?.receive(data)
            } catch {
                guard !Task.isCancelled else { return }
                self?.bridge.error = "Helper unavailable. Quit and reopen the app."
            }
        }
    }
    func receive(_ data: Data) {
        guard let event = try? JSONDecoder().decode(FeatureBridgeEvent.self, from: data) else { return }
        if let state = event.state {
            for (device, connected) in FeatureLayout.transitions(old: bridge.devices, new: state.devices) where bluetoothEnabled && bridge.bluetoothRunning && !locked {
                showBanner("headphones", device.name, connected ? "Connected" : "Disconnected")
            }
            bridge = state
        }
    }
    private func showBanner(_ icon: String, _ title: String, _ detail: String) {
        guard !locked else { return }
        dismissTask?.cancel(); banner = (icon, title, detail)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }
    func refreshWeather(force: Bool = false) async {
        guard !loadingWeather, force || fetchedAt.map({ Date().timeIntervalSince($0) > 900 }) != false else { return }
        let selected = place
        loadingWeather = true; weatherError = nil
        defer { loadingWeather = false }
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = ["latitude": String(selected.latitude), "longitude": String(selected.longitude),
            "current": "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,is_day",
            "hourly": "temperature_2m,weather_code", "forecast_days": "1", "timezone": "auto"].map { URLQueryItem(name: $0.key, value: $0.value) }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: parts.url!, timeoutInterval: 20))
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 512_000 else { throw URLError(.badServerResponse) }
            let result = try JSONDecoder().decode(FeatureForecast.self, from: data)
            guard selected == place else { Task { await refreshWeather(force: true) }; return }
            forecast = result; fetchedAt = Date()
        } catch { weatherError = "Weather unavailable. Check the connection and try again." }
    }
    func searchCities(_ text: String) {
        searchTask?.cancel(); searchError = nil
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { cityResults = []; return }
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                var parts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
                parts.queryItems = [URLQueryItem(name: "name", value: text), URLQueryItem(name: "count", value: "8"), URLQueryItem(name: "language", value: "ru")]
                let (data, response) = try await URLSession.shared.data(for: URLRequest(url: parts.url!, timeoutInterval: 15))
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 128_000 else { throw URLError(.badServerResponse) }
                struct Results: Decodable { let results: [FeaturePlace]? }
                let result = try JSONDecoder().decode(Results.self, from: data).results ?? []
                guard !Task.isCancelled else { return }
                self?.cityResults = result
                if result.isEmpty { self?.searchError = "No cities found." }
            } catch { if !Task.isCancelled { self?.searchError = "City search unavailable. Try again." } }
        }
    }
}

extension Notification.Name {
    static let featureBridgeEvent = Notification.Name("notch.featureBridgeEvent")
}
