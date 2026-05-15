//
//  KairoServices.swift
//  Kairo — Weather + Home live data services
//

import SwiftUI

// ═══════════════════════════════════════════
// MARK: - Weather Service
// ═══════════════════════════════════════════

class KairoWeatherService: ObservableObject {
    static let shared = KairoWeatherService()
    @Published var temp: Double = 0
    @Published var condition: String = ""
    @Published var willRain: Bool = false
    @Published var humidity: Int = 0
    @Published var isLoaded: Bool = false

    var sfSymbol: String {
        let c = condition.lowercased()
        if c.contains("thunder") { return "cloud.bolt.rain.fill" }
        if c.contains("rain") || c.contains("drizzle") { return "cloud.rain.fill" }
        if c.contains("snow") { return "snowflake" }
        if c.contains("fog") || c.contains("mist") { return "cloud.fog.fill" }
        if c.contains("cloud") { return "cloud.fill" }
        return "sun.max.fill"
    }

    func fetch() async {
        let key = ProcessInfo.processInfo.environment["OPENWEATHER_KEY"] ?? ""
        guard !key.isEmpty, let url = URL(string: "https://api.openweathermap.org/data/2.5/weather?q=Kampala&appid=\(key)&units=metric") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let main = json["main"] as? [String: Any],
               let weather = json["weather"] as? [[String: Any]], let w = weather.first {
                await MainActor.run {
                    self.temp = main["temp"] as? Double ?? 0
                    self.humidity = main["humidity"] as? Int ?? 0
                    self.condition = w["description"] as? String ?? ""
                    self.isLoaded = true
                }
            }
        } catch {}
    }
}

// ═══════════════════════════════════════════
// MARK: - Home Service (HA)
// ═══════════════════════════════════════════

class KairoHomeService: ObservableObject {
    static let shared = KairoHomeService()
    @Published var roomTemp: Double? = nil
    @Published var humidity: Double? = nil
    @Published var acOn: Bool = false
    @Published var lightsOnCount: Int = 0

    func fetchStatus() async {
        let haURL = ProcessInfo.processInfo.environment["HA_URL"] ?? ""
        let haToken = ProcessInfo.processInfo.environment["HA_TOKEN"] ?? ""
        guard !haURL.isEmpty, !haToken.isEmpty, let url = URL(string: "\(haURL)/api/states") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(haToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let states = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                var temp: Double? = nil, hum: Double? = nil, ac = false, lights = 0
                for state in states {
                    let id = state["entity_id"] as? String ?? ""
                    let val = state["state"] as? String ?? ""
                    if id.contains("temperature") && id.contains("sensor") { temp = Double(val) }
                    if id.contains("humidity") { hum = Double(val) }
                    if id.contains("climate") && (val == "cool" || val == "on" || val == "heat") { ac = true }
                    if id.hasPrefix("light.") && val == "on" { lights += 1 }
                }
                await MainActor.run { self.roomTemp = temp; self.humidity = hum; self.acOn = ac; self.lightsOnCount = lights }
            }
        } catch {}
    }

    func startAutoRefresh() {
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { await self?.fetchStatus() } }
    }
}

