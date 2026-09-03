import SwiftUI
import Defaults

/// Compact weather display for the closed notch
struct WeatherView: View {
    @ObservedObject var weatherManager = WeatherManager.shared
    @Default(.showWeather) var showWeather

    var body: some View {
        if showWeather, let temp = weatherManager.temperature, let code = weatherManager.weatherCode {
            HStack(spacing: 6) {
                Image(systemName: sfSymbolForWeatherCode(code))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(weatherIconColor(code))
                Text("\(Int(temp.rounded()))°")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 4)
        }
    }

    func weatherIconColor(_ code: Int) -> Color {
        switch code {
        case 0, 1: return .yellow
        case 2, 3: return .white.opacity(0.7)
        case 45, 48: return .white.opacity(0.5)
        case 51...55, 61...67: return .blue
        case 71...77, 85, 86: return .cyan
        case 80...82: return .blue.opacity(0.7)
        case 95, 96, 99: return .yellow
        default: return .white
        }
    }
}
