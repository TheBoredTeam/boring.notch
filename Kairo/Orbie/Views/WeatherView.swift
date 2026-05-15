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

/// Card-sized weather view shown when Kairo answers a weather query.
/// Two-pane layout: hero stat block on the left (icon + temp + condition),
/// 7-day forecast on the right.
struct WeatherView: View {
    let data: WeatherData

    var body: some View {
        HStack(alignment: .top, spacing: Kairo.Space.xl) {
            leftPanel
            rightPanel
        }
        .padding(Kairo.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Left panel (hero)

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Kairo.Space.lg) {
                Text(data.icon)
                    .font(.system(size: 72))
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: Kairo.Space.xs) {
                    Text("\(data.temp)°C")
                        .font(.system(size: 56, weight: .bold, design: .default))
                        .tracking(-1.2)
                        .foregroundStyle(Kairo.Palette.text)
                    HStack(spacing: Kairo.Space.xs) {
                        Label("\(data.high)°", systemImage: "arrow.up")
                            .labelStyle(InlineTempStyle())
                            .foregroundStyle(Kairo.Palette.text)
                        Text("·").foregroundStyle(Kairo.Palette.textFaint)
                        Label("\(data.low)°", systemImage: "arrow.down")
                            .labelStyle(InlineTempStyle())
                            .foregroundStyle(Kairo.Palette.textDim)
                    }
                    .font(Kairo.Typography.bodySmall)
                }
            }

            Spacer(minLength: Kairo.Space.lg)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(data.condition.uppercased().split(separator: " "), id: \.self) { w in
                    Text(String(w))
                        .font(.system(size: 32, weight: .heavy, design: .default))
                        .tracking(-0.3)
                        .foregroundStyle(Kairo.Palette.text)
                }
            }

            Spacer(minLength: Kairo.Space.lg)

            VStack(alignment: .leading, spacing: Kairo.Space.md) {
                HStack(spacing: Kairo.Space.xl) {
                    StatItem(icon: "wind",          label: "WIND",     value: "\(data.windKmh) km/h")
                    StatItem(icon: "humidity.fill", label: "HUMIDITY", value: "\(data.humidity)%")
                }
                HStack(spacing: Kairo.Space.xl) {
                    StatItem(icon: "sunrise.fill", label: "SUNRISE", value: data.sunrise)
                    StatItem(icon: "sunset.fill",  label: "SUNSET",  value: data.sunset)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Right panel (forecast)

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.md) {
            HStack {
                Text(data.location.uppercased())
                    .font(Kairo.Typography.captionStrong)
                    .tracking(1.2)
                    .foregroundStyle(Kairo.Palette.textDim)
                Spacer()
                Text(data.updatedAt)
                    .font(Kairo.Typography.monoSmall)
                    .foregroundStyle(Kairo.Palette.textFaint)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Kairo.Space.sm), count: 4),
                spacing: Kairo.Space.sm
            ) {
                ForEach(Array(data.forecast.enumerated()), id: \.offset) { i, d in
                    ForecastCell(day: d, isToday: i == data.todayIndex)
                }
            }
        }
        .frame(maxWidth: 380)
    }
}

// MARK: - Styles

private struct InlineTempStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
                .font(.system(size: 9, weight: .semibold))
            configuration.title
        }
    }
}

// MARK: - Sub-views

private struct StatItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: Kairo.Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Kairo.Palette.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                if !label.isEmpty {
                    Text(label)
                        .font(Kairo.Typography.caption)
                        .tracking(1.0)
                        .foregroundStyle(Kairo.Palette.textDim)
                }
                Text(value)
                    .font(Kairo.Typography.bodyEmphasis)
                    .foregroundStyle(Kairo.Palette.text)
            }
        }
    }
}

private struct ForecastCell: View {
    let day: WeatherData.Forecast
    let isToday: Bool

    var body: some View {
        VStack(spacing: Kairo.Space.xs) {
            Text(day.icon).font(.system(size: 26))
            Text(day.day)
                .font(Kairo.Typography.captionStrong)
                .foregroundStyle(isToday ? Kairo.Palette.text : Kairo.Palette.textDim)
            VStack(spacing: 1) {
                Text("\(day.high)°")
                    .font(Kairo.Typography.bodySmall)
                    .foregroundStyle(Kairo.Palette.text)
                Text("\(day.low)°")
                    .font(Kairo.Typography.bodySmall)
                    .foregroundStyle(Kairo.Palette.textDim)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Kairo.Space.md)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                            .fill(Kairo.Palette.glassTint)
                    }
            }
        }
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                    .strokeBorder(Kairo.Palette.glassStroke, lineWidth: 0.5)
            }
        }
    }
}
