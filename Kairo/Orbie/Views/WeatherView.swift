import SwiftUI

struct WeatherData: Hashable {
    let location: String
    let updatedAt: String
    let temp: Int
    let high: Int
    let low: Int
    let condition: String
    let icon: String
    let sunrise: String
    let sunset: String
    let windKmh: Int
    let humidity: Int
    let forecast: [Forecast]
    let todayIndex: Int?

    struct Forecast: Hashable {
        let day: String
        let icon: String
        let high: Int
        let low: Int
    }
}

struct WeatherView: View {
    let data: WeatherData

    var body: some View {
        HStack(spacing: 20) {
            leftPanel
            rightPanel
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundColor(Kairo.Palette.text)
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Text(data.icon).font(.system(size: 72)).shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(data.temp)°C")
                        .font(.system(size: 56, weight: .bold)).tracking(-1.2)
                    Text("H \(data.high)° | L \(data.low)°")
                        .font(.system(size: 14)).foregroundColor(Kairo.Palette.textDim)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(data.condition.uppercased().split(separator: " "), id: \.self) { w in
                    Text(String(w)).font(.system(size: 32, weight: .heavy)).tracking(-0.3)
                }
            }
            Spacer()
            HStack(spacing: 24) {
                StatItem(icon: "wind", label: "WIND", value: "\(data.windKmh) Km/h")
                StatItem(icon: "humidity.fill", label: "HUMIDITY", value: "\(data.humidity)%")
            }
            HStack(spacing: 24) {
                StatItem(icon: "sunrise.fill", label: "", value: data.sunrise)
                StatItem(icon: "sunset.fill", label: "", value: data.sunset)
            }.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(data.location.uppercased())
                    .font(.system(size: 11)).tracking(1.2).foregroundColor(Kairo.Palette.textDim)
                Spacer()
                Text(data.updatedAt)
                    .font(.system(size: 11)).tracking(0.5).foregroundColor(Kairo.Palette.textDim)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(Array(data.forecast.enumerated()), id: \.offset) { i, d in
                    ForecastCell(day: d, isToday: i == data.todayIndex)
                }
            }
        }
    }
}

private struct StatItem: View {
    let icon: String; let label: String; let value: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                if !label.isEmpty {
                    Text(label).font(.system(size: 10)).tracking(1.0)
                        .foregroundColor(Kairo.Palette.textDim)
                }
                Text(value).font(.system(size: 13, weight: .semibold))
            }
        }
    }
}

private struct ForecastCell: View {
    let day: WeatherData.Forecast; let isToday: Bool
    var body: some View {
        VStack(spacing: 4) {
            Text(day.icon).font(.system(size: 28))
            Text(day.day).font(.system(size: 13, weight: .semibold))
            VStack(spacing: 1) {
                Text("\(day.high)°").font(.system(size: 11))
                Text("\(day.low)°").font(.system(size: 11)).foregroundColor(Kairo.Palette.textDim)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .fill(isToday ? Kairo.Palette.surfaceHi : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                        .stroke(Kairo.Palette.hairline.opacity(isToday ? 1 : 0), lineWidth: 1)
                )
        )
    }
}
