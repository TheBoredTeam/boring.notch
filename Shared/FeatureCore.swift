// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct FeaturePlace: Codable, Identifiable, Equatable {
    var id: Int
    var name: String
    var latitude: Double
    var longitude: Double
    var country: String?
    var admin1: String?
    static let krasnodar = FeaturePlace(id: 542420, name: "Краснодар", latitude: 45.0448, longitude: 38.976, country: "Россия", admin1: "Краснодарский край")
    var detail: String { [admin1, country].compactMap { $0 }.joined(separator: ", ") }
}
struct FeatureForecast: Codable, Equatable {
    let current: Current
    let hourly: Hourly?
    struct Current: Codable, Equatable {
        let temperature_2m: Double
        let apparent_temperature: Double
        let weather_code: Int
        let wind_speed_10m: Double
        let is_day: Int
    }
    struct Hourly: Codable, Equatable {
        let time: [String]
        let temperature_2m: [Double]
        let weather_code: [Int]
    }
    static func condition(_ code: Int) -> (String, String) {
        switch code {
        case 0: return ("Clear", "sun.max.fill")
        case 1...3: return ("Cloudy", "cloud.sun.fill")
        case 45, 48: return ("Fog", "cloud.fog.fill")
        case 51...67, 80...82: return ("Rain", "cloud.rain.fill")
        case 71...77, 85, 86: return ("Snow", "cloud.snow.fill")
        case 95...99: return ("Thunderstorm", "cloud.bolt.rain.fill")
        default: return ("Weather", "cloud.fill")
        }
    }
}
struct FeatureDevice: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let connected: Bool
}
struct FeatureBridgeState: Codable {
    var devices: [FeatureDevice] = []
    var bluetoothRunning = false
    var error: String?
}
struct FeatureBridgeEvent: Codable {
    var kind: String
    var state: FeatureBridgeState?
}
enum FeatureLayout {
    static func transitions(old: [FeatureDevice], new: [FeatureDevice]) -> [(FeatureDevice, Bool)] {
        let previous = Dictionary(old.map { ($0.id, $0.connected) }, uniquingKeysWith: { _, last in last })
        return new.compactMap { device in
            guard previous[device.id].map({ $0 != device.connected }) ?? device.connected else { return nil }
            return (device, device.connected)
        }
    }
}
