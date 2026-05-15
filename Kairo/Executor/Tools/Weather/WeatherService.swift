import Foundation
import CoreLocation

struct WeatherService {
    static let defaultLat = 0.3476
    static let defaultLon = 32.5825

    static func fetch(lat: Double = defaultLat, lon: Double = defaultLon) async throws -> WeatherData {
        let url = URL(string:
            "https://api.open-meteo.com/v1/forecast?" +
            "latitude=\(lat)&longitude=\(lon)" +
            "&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code,apparent_temperature" +
            "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset" +
            "&timezone=auto&forecast_days=7"
        )!

        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let location = (try? await reverseGeocode(lat: lat, lon: lon)) ?? "Here"

        return transform(decoded, location: location)
    }

    private static func reverseGeocode(lat: Double, lon: Double) async throws -> String {
        let loc = CLLocation(latitude: lat, longitude: lon)
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(loc)
        return placemarks.first?.locality ?? placemarks.first?.administrativeArea ?? "Here"
    }

    private static func transform(_ r: OpenMeteoResponse, location: String) -> WeatherData {
        let df = DateFormatter()
        df.dateFormat = "d MMM, h:mm a"

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEE"
        let isoSimple = ISO8601DateFormatter()

        let forecast = zip(r.daily.time, zip(r.daily.temperature_2m_max,
                                              zip(r.daily.temperature_2m_min, r.daily.weather_code)))
            .prefix(7)
            .map { entry -> WeatherData.Forecast in
                let (dateStr, (maxT, (minT, code))) = entry
                let date = isoSimple.date(from: dateStr + "T00:00:00Z") ?? Date()
                return WeatherData.Forecast(
                    day: dayFmt.string(from: date),
                    icon: weatherIcon(for: code),
                    high: Int(maxT.rounded()),
                    low: Int(minT.rounded())
                )
            }

        return WeatherData(
            location: location,
            updatedAt: df.string(from: Date()),
            temp: Int(r.current.temperature_2m.rounded()),
            high: Int((r.daily.temperature_2m_max.first ?? 0).rounded()),
            low: Int((r.daily.temperature_2m_min.first ?? 0).rounded()),
            condition: conditionText(for: r.current.weather_code),
            icon: weatherIcon(for: r.current.weather_code),
            sunrise: parseTime(r.daily.sunrise.first),
            sunset: parseTime(r.daily.sunset.first),
            windKmh: Int(r.current.wind_speed_10m.rounded()),
            humidity: Int(r.current.relative_humidity_2m.rounded()),
            forecast: forecast,
            todayIndex: 0
        )
    }

    private static func parseTime(_ s: String?) -> String {
        guard let s else { return "--:--" }
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let outFmt = DateFormatter()
        outFmt.dateFormat = "h:mm a"
        guard let d = inFmt.date(from: s) else { return "--:--" }
        return outFmt.string(from: d)
    }

    private static func weatherIcon(for code: Int) -> String {
        switch code {
        case 0:       return "☀️"
        case 1, 2:    return "🌤️"
        case 3:       return "☁️"
        case 45, 48:  return "🌫️"
        case 51...57: return "🌦️"
        case 61...67: return "🌧️"
        case 71...77: return "❄️"
        case 80...82: return "🌧️"
        case 85, 86:  return "🌨️"
        case 95...99: return "⛈️"
        default:      return "🌤️"
        }
    }

    private static func conditionText(for code: Int) -> String {
        switch code {
        case 0:       return "Clear Sky"
        case 1, 2:    return "Partly Cloudy"
        case 3:       return "Overcast"
        case 45, 48:  return "Foggy"
        case 51...57: return "Drizzle"
        case 61...67: return "Rainy"
        case 71...77: return "Snowy"
        case 80...82: return "Showers"
        case 85, 86:  return "Snow Showers"
        case 95...99: return "Thunderstorm"
        default:      return "Fair"
        }
    }
}

struct OpenMeteoResponse: Decodable {
    let current: Current
    let daily: Daily

    struct Current: Decodable {
        let temperature_2m: Double
        let relative_humidity_2m: Double
        let wind_speed_10m: Double
        let weather_code: Int
        let apparent_temperature: Double
    }

    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let sunrise: [String]
        let sunset: [String]
    }
}
