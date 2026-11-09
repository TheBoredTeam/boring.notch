//
//  CalendarCities.swift
//  boringNotch
//
//  The cities offered in Settings → Calendar for the weather, sunrise & sunset
//  and world clock options. Shipping a fixed list means no lookup service and
//  no location permission: each city carries its own coordinates and time zone.
//

import Foundation

enum CityRegion: String, CaseIterable, Identifiable {
    case europe
    case middleEastAfrica
    case asia
    case oceania
    case americas

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .europe: String(localized: "Europe")
        case .middleEastAfrica: String(localized: "Middle East & Africa")
        case .asia: String(localized: "Asia")
        case .oceania: String(localized: "Oceania")
        case .americas: String(localized: "Americas")
        }
    }
}

struct City: Identifiable, Hashable, Sendable {
    let name: String
    /// ISO 3166-1 region code; the country name is localized from it.
    let countryCode: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String

    var id: String { "\(name)|\(countryCode)" }

    var place: CalendarPlace {
        CalendarPlace(
            name: name,
            detail: Locale.current.localizedString(forRegionCode: countryCode) ?? countryCode,
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    /// Whether a saved place is this city (the country name may have been saved in another language).
    func matches(_ place: CalendarPlace?) -> Bool {
        guard let place else { return false }
        return place.name == name && place.timeZoneIdentifier == timeZoneIdentifier
    }
}

extension City {
    static func cities(in region: CityRegion) -> [City] {
        all[region] ?? []
    }

    static var allCities: [City] {
        CityRegion.allCases.flatMap { cities(in: $0) }
    }

    private static let all: [CityRegion: [City]] = [
        .europe: [
            City(name: "Amsterdam", countryCode: "NL", latitude: 52.37, longitude: 4.90, timeZoneIdentifier: "Europe/Amsterdam"),
            City(name: "Athens", countryCode: "GR", latitude: 37.98, longitude: 23.73, timeZoneIdentifier: "Europe/Athens"),
            City(name: "Barcelona", countryCode: "ES", latitude: 41.39, longitude: 2.17, timeZoneIdentifier: "Europe/Madrid"),
            City(name: "Berlin", countryCode: "DE", latitude: 52.52, longitude: 13.40, timeZoneIdentifier: "Europe/Berlin"),
            City(name: "Brussels", countryCode: "BE", latitude: 50.85, longitude: 4.35, timeZoneIdentifier: "Europe/Brussels"),
            City(name: "Copenhagen", countryCode: "DK", latitude: 55.68, longitude: 12.57, timeZoneIdentifier: "Europe/Copenhagen"),
            City(name: "Dublin", countryCode: "IE", latitude: 53.35, longitude: -6.26, timeZoneIdentifier: "Europe/Dublin"),
            City(name: "Helsinki", countryCode: "FI", latitude: 60.17, longitude: 24.94, timeZoneIdentifier: "Europe/Helsinki"),
            City(name: "Istanbul", countryCode: "TR", latitude: 41.01, longitude: 28.98, timeZoneIdentifier: "Europe/Istanbul"),
            City(name: "Kyiv", countryCode: "UA", latitude: 50.45, longitude: 30.52, timeZoneIdentifier: "Europe/Kiev"),
            City(name: "Lisbon", countryCode: "PT", latitude: 38.72, longitude: -9.14, timeZoneIdentifier: "Europe/Lisbon"),
            City(name: "London", countryCode: "GB", latitude: 51.51, longitude: -0.13, timeZoneIdentifier: "Europe/London"),
            City(name: "Madrid", countryCode: "ES", latitude: 40.42, longitude: -3.70, timeZoneIdentifier: "Europe/Madrid"),
            City(name: "Milan", countryCode: "IT", latitude: 45.46, longitude: 9.19, timeZoneIdentifier: "Europe/Rome"),
            City(name: "Moscow", countryCode: "RU", latitude: 55.76, longitude: 37.62, timeZoneIdentifier: "Europe/Moscow"),
            City(name: "Munich", countryCode: "DE", latitude: 48.14, longitude: 11.58, timeZoneIdentifier: "Europe/Berlin"),
            City(name: "Oslo", countryCode: "NO", latitude: 59.91, longitude: 10.75, timeZoneIdentifier: "Europe/Oslo"),
            City(name: "Paris", countryCode: "FR", latitude: 48.86, longitude: 2.35, timeZoneIdentifier: "Europe/Paris"),
            City(name: "Prague", countryCode: "CZ", latitude: 50.08, longitude: 14.44, timeZoneIdentifier: "Europe/Prague"),
            City(name: "Rome", countryCode: "IT", latitude: 41.90, longitude: 12.50, timeZoneIdentifier: "Europe/Rome"),
            City(name: "Stockholm", countryCode: "SE", latitude: 59.33, longitude: 18.07, timeZoneIdentifier: "Europe/Stockholm"),
            City(name: "Vienna", countryCode: "AT", latitude: 48.21, longitude: 16.37, timeZoneIdentifier: "Europe/Vienna"),
            City(name: "Warsaw", countryCode: "PL", latitude: 52.23, longitude: 21.01, timeZoneIdentifier: "Europe/Warsaw"),
            City(name: "Zurich", countryCode: "CH", latitude: 47.38, longitude: 8.54, timeZoneIdentifier: "Europe/Zurich"),
        ],
        .middleEastAfrica: [
            City(name: "Abu Dhabi", countryCode: "AE", latitude: 24.45, longitude: 54.38, timeZoneIdentifier: "Asia/Dubai"),
            City(name: "Addis Ababa", countryCode: "ET", latitude: 9.03, longitude: 38.74, timeZoneIdentifier: "Africa/Addis_Ababa"),
            City(name: "Algiers", countryCode: "DZ", latitude: 36.75, longitude: 3.06, timeZoneIdentifier: "Africa/Algiers"),
            City(name: "Amman", countryCode: "JO", latitude: 31.95, longitude: 35.93, timeZoneIdentifier: "Asia/Amman"),
            City(name: "Baghdad", countryCode: "IQ", latitude: 33.31, longitude: 44.36, timeZoneIdentifier: "Asia/Baghdad"),
            City(name: "Beirut", countryCode: "LB", latitude: 33.89, longitude: 35.50, timeZoneIdentifier: "Asia/Beirut"),
            City(name: "Cairo", countryCode: "EG", latitude: 30.04, longitude: 31.24, timeZoneIdentifier: "Africa/Cairo"),
            City(name: "Cape Town", countryCode: "ZA", latitude: -33.92, longitude: 18.42, timeZoneIdentifier: "Africa/Johannesburg"),
            City(name: "Casablanca", countryCode: "MA", latitude: 33.57, longitude: -7.59, timeZoneIdentifier: "Africa/Casablanca"),
            City(name: "Doha", countryCode: "QA", latitude: 25.29, longitude: 51.53, timeZoneIdentifier: "Asia/Qatar"),
            City(name: "Dubai", countryCode: "AE", latitude: 25.20, longitude: 55.27, timeZoneIdentifier: "Asia/Dubai"),
            City(name: "Jeddah", countryCode: "SA", latitude: 21.49, longitude: 39.19, timeZoneIdentifier: "Asia/Riyadh"),
            City(name: "Johannesburg", countryCode: "ZA", latitude: -26.20, longitude: 28.05, timeZoneIdentifier: "Africa/Johannesburg"),
            City(name: "Kuwait City", countryCode: "KW", latitude: 29.38, longitude: 47.99, timeZoneIdentifier: "Asia/Kuwait"),
            City(name: "Lagos", countryCode: "NG", latitude: 6.52, longitude: 3.38, timeZoneIdentifier: "Africa/Lagos"),
            City(name: "Manama", countryCode: "BH", latitude: 26.23, longitude: 50.59, timeZoneIdentifier: "Asia/Bahrain"),
            City(name: "Mecca", countryCode: "SA", latitude: 21.39, longitude: 39.86, timeZoneIdentifier: "Asia/Riyadh"),
            City(name: "Muscat", countryCode: "OM", latitude: 23.59, longitude: 58.41, timeZoneIdentifier: "Asia/Muscat"),
            City(name: "Nairobi", countryCode: "KE", latitude: -1.29, longitude: 36.82, timeZoneIdentifier: "Africa/Nairobi"),
            City(name: "Riyadh", countryCode: "SA", latitude: 24.71, longitude: 46.68, timeZoneIdentifier: "Asia/Riyadh"),
            City(name: "Tehran", countryCode: "IR", latitude: 35.69, longitude: 51.39, timeZoneIdentifier: "Asia/Tehran"),
            City(name: "Tripoli", countryCode: "LY", latitude: 32.89, longitude: 13.19, timeZoneIdentifier: "Africa/Tripoli"),
            City(name: "Tunis", countryCode: "TN", latitude: 36.81, longitude: 10.18, timeZoneIdentifier: "Africa/Tunis"),
        ],
        .asia: [
            City(name: "Bangkok", countryCode: "TH", latitude: 13.76, longitude: 100.50, timeZoneIdentifier: "Asia/Bangkok"),
            City(name: "Beijing", countryCode: "CN", latitude: 39.90, longitude: 116.41, timeZoneIdentifier: "Asia/Shanghai"),
            City(name: "Bengaluru", countryCode: "IN", latitude: 12.97, longitude: 77.59, timeZoneIdentifier: "Asia/Kolkata"),
            City(name: "Delhi", countryCode: "IN", latitude: 28.61, longitude: 77.21, timeZoneIdentifier: "Asia/Kolkata"),
            City(name: "Dhaka", countryCode: "BD", latitude: 23.81, longitude: 90.41, timeZoneIdentifier: "Asia/Dhaka"),
            City(name: "Ho Chi Minh City", countryCode: "VN", latitude: 10.82, longitude: 106.63, timeZoneIdentifier: "Asia/Ho_Chi_Minh"),
            City(name: "Hong Kong", countryCode: "HK", latitude: 22.32, longitude: 114.17, timeZoneIdentifier: "Asia/Hong_Kong"),
            City(name: "Jakarta", countryCode: "ID", latitude: -6.21, longitude: 106.85, timeZoneIdentifier: "Asia/Jakarta"),
            City(name: "Karachi", countryCode: "PK", latitude: 24.86, longitude: 67.01, timeZoneIdentifier: "Asia/Karachi"),
            City(name: "Kuala Lumpur", countryCode: "MY", latitude: 3.14, longitude: 101.69, timeZoneIdentifier: "Asia/Kuala_Lumpur"),
            City(name: "Manila", countryCode: "PH", latitude: 14.60, longitude: 120.98, timeZoneIdentifier: "Asia/Manila"),
            City(name: "Mumbai", countryCode: "IN", latitude: 19.08, longitude: 72.88, timeZoneIdentifier: "Asia/Kolkata"),
            City(name: "Osaka", countryCode: "JP", latitude: 34.69, longitude: 135.50, timeZoneIdentifier: "Asia/Tokyo"),
            City(name: "Seoul", countryCode: "KR", latitude: 37.57, longitude: 126.98, timeZoneIdentifier: "Asia/Seoul"),
            City(name: "Shanghai", countryCode: "CN", latitude: 31.23, longitude: 121.47, timeZoneIdentifier: "Asia/Shanghai"),
            City(name: "Singapore", countryCode: "SG", latitude: 1.35, longitude: 103.82, timeZoneIdentifier: "Asia/Singapore"),
            City(name: "Taipei", countryCode: "TW", latitude: 25.03, longitude: 121.57, timeZoneIdentifier: "Asia/Taipei"),
            City(name: "Tashkent", countryCode: "UZ", latitude: 41.30, longitude: 69.24, timeZoneIdentifier: "Asia/Tashkent"),
            City(name: "Tokyo", countryCode: "JP", latitude: 35.68, longitude: 139.69, timeZoneIdentifier: "Asia/Tokyo"),
        ],
        .oceania: [
            City(name: "Auckland", countryCode: "NZ", latitude: -36.85, longitude: 174.76, timeZoneIdentifier: "Pacific/Auckland"),
            City(name: "Brisbane", countryCode: "AU", latitude: -27.47, longitude: 153.03, timeZoneIdentifier: "Australia/Brisbane"),
            City(name: "Melbourne", countryCode: "AU", latitude: -37.81, longitude: 144.96, timeZoneIdentifier: "Australia/Melbourne"),
            City(name: "Perth", countryCode: "AU", latitude: -31.95, longitude: 115.86, timeZoneIdentifier: "Australia/Perth"),
            City(name: "Sydney", countryCode: "AU", latitude: -33.87, longitude: 151.21, timeZoneIdentifier: "Australia/Sydney"),
        ],
        .americas: [
            City(name: "Anchorage", countryCode: "US", latitude: 61.22, longitude: -149.90, timeZoneIdentifier: "America/Anchorage"),
            City(name: "Atlanta", countryCode: "US", latitude: 33.75, longitude: -84.39, timeZoneIdentifier: "America/New_York"),
            City(name: "Bogotá", countryCode: "CO", latitude: 4.71, longitude: -74.07, timeZoneIdentifier: "America/Bogota"),
            City(name: "Boston", countryCode: "US", latitude: 42.36, longitude: -71.06, timeZoneIdentifier: "America/New_York"),
            City(name: "Buenos Aires", countryCode: "AR", latitude: -34.60, longitude: -58.38, timeZoneIdentifier: "America/Argentina/Buenos_Aires"),
            City(name: "Chicago", countryCode: "US", latitude: 41.88, longitude: -87.63, timeZoneIdentifier: "America/Chicago"),
            City(name: "Dallas", countryCode: "US", latitude: 32.78, longitude: -96.80, timeZoneIdentifier: "America/Chicago"),
            City(name: "Denver", countryCode: "US", latitude: 39.74, longitude: -104.99, timeZoneIdentifier: "America/Denver"),
            City(name: "Honolulu", countryCode: "US", latitude: 21.31, longitude: -157.86, timeZoneIdentifier: "Pacific/Honolulu"),
            City(name: "Houston", countryCode: "US", latitude: 29.76, longitude: -95.37, timeZoneIdentifier: "America/Chicago"),
            City(name: "Lima", countryCode: "PE", latitude: -12.05, longitude: -77.04, timeZoneIdentifier: "America/Lima"),
            City(name: "Los Angeles", countryCode: "US", latitude: 34.05, longitude: -118.24, timeZoneIdentifier: "America/Los_Angeles"),
            City(name: "Mexico City", countryCode: "MX", latitude: 19.43, longitude: -99.13, timeZoneIdentifier: "America/Mexico_City"),
            City(name: "Miami", countryCode: "US", latitude: 25.76, longitude: -80.19, timeZoneIdentifier: "America/New_York"),
            City(name: "Montreal", countryCode: "CA", latitude: 45.50, longitude: -73.57, timeZoneIdentifier: "America/Toronto"),
            City(name: "New York", countryCode: "US", latitude: 40.71, longitude: -74.01, timeZoneIdentifier: "America/New_York"),
            City(name: "Phoenix", countryCode: "US", latitude: 33.45, longitude: -112.07, timeZoneIdentifier: "America/Phoenix"),
            City(name: "Rio de Janeiro", countryCode: "BR", latitude: -22.91, longitude: -43.17, timeZoneIdentifier: "America/Sao_Paulo"),
            City(name: "San Francisco", countryCode: "US", latitude: 37.77, longitude: -122.42, timeZoneIdentifier: "America/Los_Angeles"),
            City(name: "Santiago", countryCode: "CL", latitude: -33.45, longitude: -70.67, timeZoneIdentifier: "America/Santiago"),
            City(name: "São Paulo", countryCode: "BR", latitude: -23.55, longitude: -46.63, timeZoneIdentifier: "America/Sao_Paulo"),
            City(name: "Seattle", countryCode: "US", latitude: 47.61, longitude: -122.33, timeZoneIdentifier: "America/Los_Angeles"),
            City(name: "Toronto", countryCode: "CA", latitude: 43.65, longitude: -79.38, timeZoneIdentifier: "America/Toronto"),
            City(name: "Vancouver", countryCode: "CA", latitude: 49.28, longitude: -123.12, timeZoneIdentifier: "America/Vancouver"),
            City(name: "Washington", countryCode: "US", latitude: 38.91, longitude: -77.04, timeZoneIdentifier: "America/New_York"),
        ],
    ]
}
