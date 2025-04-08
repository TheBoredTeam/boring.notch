//
//  BoringWeather.swift
//  boringNotch
//
//  Created by John Patch on 4/8/25.
//
import SwiftUI
import CoreLocation
import Defaults

struct BoringWeather: View {
    @State private var weatherIcon: String = "🌥"  // Default icon for cloudy
    @State private var temperature: String = "--"  // Default temperature value
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        HStack() {
            Text(temperature)
                .font(.system(size: 12))
                .foregroundStyle(Color(.white))
//                .frame(width: 35)
            Text(weatherIcon)
                .font(.system(size: 16))
                
//                .frame(width: 20)
        }
        .onAppear {
            locationManager.requestLocation()  // Request location once
        }
        .onChange(of: locationManager.location, initial: true) { oldLocation, newLocation in
            // Only fetch weather when location is updated
            fetchWeather()
        }
        .padding(4)
    }

    func fetchWeather() {
        guard let location = locationManager.location else {
            weatherIcon = "⚠️"  // Location is unavailable
            temperature = "--"
            return
        }

        if Defaults[.weatherAPIToken] == "" {
            weatherIcon = "❌"  // No API key found
            temperature = "--"
            print("No API Key")
            return
        }
        let apiKey = Defaults[.weatherAPIToken]

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        let urlStr = "https://api.openweathermap.org/data/2.5/weather?lat=\(lat)&lon=\(lon)&appid=\(apiKey)&units=metric"
        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    weatherIcon = "❌"
                    temperature = "--"
                }
                return
            }

            if let weatherData = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let weather = weatherData["weather"] as? [[String: Any]],
               let condition = weather.first?["main"] as? String,
               let main = weatherData["main"] as? [String: Any],
               let temp = main["temp"] as? Double {
                DispatchQueue.main.async {
                    weatherIcon = icon(for: condition)
                    if Defaults[.temperatureCelsius] {
                        temperature = String(format: "%.1f ºC", temp)
                    } else {
                        let fahrenheit = (temp * 9/5) + 32
                        temperature = String(format: "%.0f ºF", fahrenheit)
                    }
 // Set temperature to one decimal place
                }
            }
        }.resume()
    }

    func icon(for condition: String) -> String {
        print(condition)
        switch condition.lowercased() {
        case "clear": return "☀️" // Sunny
        case "clouds": return "☁️" // Cloudy
        case "rain": return "🌧" // Rainy
        case "drizzle": return "🌦" // Drizzle
        case "thunderstorm": return "⛈" // Thunderstorm
        case "snow": return "❄️" // Snowy
        case "mist", "fog", "haze": return "🌫" // Mist/Fog/Haze
        case "smoke": return "💨" // Smoke
        case "sand": return "🏜" // Sand
        case "dust": return "🌪" // Dust
        case "ash": return "🌋" // Ash
        case "squall": return "🌬" // Squall
        case "tornado": return "🌪" // Tornado
        default: return "❓" // Unknown or other condition
        }
    }
}
