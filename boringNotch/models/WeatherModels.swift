import Foundation

struct WeatherResponse: Decodable {
    let current: CurrentWeather
    let currentUnits: CurrentUnits

    enum CodingKeys: String, CodingKey {
        case current
        case currentUnits = "current_units"
    }
}

struct CurrentWeather: Decodable {
    let temperature2m: Double
    let weatherCode: Int

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case weatherCode = "weather_code"
    }
}

struct CurrentUnits: Decodable {
    let temperature2m: String

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
    }
}

/// WMO Weather Code → SF Symbol name
func sfSymbolForWeatherCode(_ code: Int, isNight: Bool = false) -> String {
    switch code {
    case 0: return isNight ? "moon.stars.fill" : "sun.max.fill"
    case 1: return isNight ? "moon.fill" : "sun.max.fill"
    case 2: return isNight ? "cloud.moon.fill" : "cloud.sun.fill"
    case 3: return "cloud.fill"
    case 45, 48: return "cloud.fog.fill"
    case 51, 53, 55: return "cloud.drizzle.fill"
    case 61, 63, 65: return "cloud.rain.fill"
    case 66, 67: return "cloud.sleet.fill"
    case 71, 73, 75: return "cloud.snow.fill"
    case 77: return "snowflake"
    case 80, 81, 82: return "cloud.heavyrain.fill"
    case 85, 86: return "cloud.snow.fill"
    case 95: return "cloud.bolt.fill"
    case 96, 99: return "cloud.bolt.rain.fill"
    default: return isNight ? "moon.stars.fill" : "sun.max.fill"
    }
}

/// WMO Weather Code → human-readable description
func descriptionForWeatherCode(_ code: Int) -> String {
    switch code {
    case 0: return "Clear"
    case 1: return "Mostly Clear"
    case 2: return "Partly Cloudy"
    case 3: return "Overcast"
    case 45, 48: return "Fog"
    case 51, 53, 55: return "Drizzle"
    case 61, 63, 65: return "Rain"
    case 66, 67: return "Freezing Rain"
    case 71, 73, 75: return "Snow"
    case 77: return "Snow Grains"
    case 80, 81, 82: return "Rain Showers"
    case 85, 86: return "Snow Showers"
    case 95: return "Thunderstorm"
    case 96, 99: return "Thunderstorm + Hail"
    default: return "Unknown"
    }
}

/// IP Geolocation response model
struct IPGeoResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let city: String?
}
