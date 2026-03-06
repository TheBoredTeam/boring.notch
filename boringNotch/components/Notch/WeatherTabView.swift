//
//  WeatherTabView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct WeatherTabView: View {
    private enum WeatherPage: String, CaseIterable, Identifiable {
        case current
        case forecast

        var id: String { self.rawValue }
    }

    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var weatherManager = WeatherManager.shared
    @Default(.showWeather) private var showWeather
    @Default(.weatherCity) private var weatherCity
    @Default(.weatherContentPreference) private var weatherContentPreference
    @State private var selectedPage: WeatherPage = .current

    private var openHeaderHeight: CGFloat {
        let closedDisplayHeight = vm.effectiveClosedNotchHeight == 0 ? 10 : vm.effectiveClosedNotchHeight
        return max(24, closedDisplayHeight)
    }

    private var contentHeight: CGFloat {
        // Keep Weather tab height aligned with ContentView.NotchLayout vertical math:
        // total open height - header - VStack spacing - open bottom inset.
        let notchLayoutSpacing: CGFloat = 8
        let openBottomInset: CGFloat = 12
        let availableHeight = vm.notchSize.height - openHeaderHeight - notchLayoutSpacing - openBottomInset
        return Swift.max(0, availableHeight)
    }

    private var showForecastPage: Bool {
        weatherContentPreference == .currentAndForecast
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !showWeather {
                statePanel {
                    Label(localized("weather_tab.off.title", fallback: "Weather is off"), systemImage: "cloud.slash")
                        .font(.subheadline.weight(.semibold))
                    Text(localized("weather_tab.off.message", fallback: "Turn on Show weather in Settings > Weather."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let snapshot = weatherManager.snapshot {
                weatherCanvas(for: snapshot, staleError: weatherManager.errorMessage)
            } else if weatherManager.isLoading || !weatherManager.hasLoadedAtLeastOnce {
                statePanel {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(localized("weather_tab.loading", fallback: "Loading weather..."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let error = weatherManager.errorMessage {
                statePanel {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(
                        localizedFormat(
                            "weather_tab.current_city_format",
                            fallback: "Current city: %@",
                            weatherCity
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        weatherManager.requestRefresh(replacingCurrent: true)
                    } label: {
                        Label(localized("weather_tab.retry", fallback: "Retry"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }
            } else {
                statePanel {
                    Text(localized("weather_tab.unavailable", fallback: "Weather not available"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: contentHeight, maxHeight: contentHeight, alignment: .topLeading)
        .onAppear {
            if showWeather && weatherManager.snapshot == nil {
                weatherManager.requestRefresh()
            }
        }
        .onChange(of: showWeather) { _, newValue in
            guard newValue else { return }
            weatherManager.requestRefresh()
        }
        .onChange(of: weatherContentPreference) { _, newValue in
            if newValue == .currentOnly {
                selectedPage = .current
            }
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        let value = NSLocalizedString(key, comment: "")
        return value == key ? fallback : value
    }

    private func localizedFormat(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key, fallback: fallback), locale: Locale.current, arguments: arguments)
    }

    private func statePanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func weatherCanvas(for snapshot: WeatherSnapshot, staleError: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            headerBar(for: snapshot, staleError: staleError)

            Group {
                if selectedPage == .current || !showForecastPage {
                    currentWeatherPage(for: snapshot)
                } else {
                    forecastWeatherPage(for: snapshot)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onEnded { value in
                        guard showForecastPage else { return }
                        if value.translation.width < -32 {
                            withAnimation(.smooth(duration: 0.22)) {
                                selectedPage = .forecast
                            }
                        } else if value.translation.width > 32 {
                            withAnimation(.smooth(duration: 0.22)) {
                                selectedPage = .current
                            }
                        }
                    }
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .clipped()
    }

    @ViewBuilder
    private func weatherPageButton(page: WeatherPage) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.2)) {
                selectedPage = page
            }
        } label: {
            Text(
                page == .current
                    ? localized("weather_tab.segment.current", fallback: "Current")
                    : localized("weather_tab.segment.forecast", fallback: "Forecast")
            )
                .font(.caption.weight(.semibold))
                .foregroundStyle(selectedPage == page ? .white : .white.opacity(0.78))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selectedPage == page ? Color.white.opacity(0.16) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func currentWeatherPage(for snapshot: WeatherSnapshot) -> some View {
        HStack(alignment: .top, spacing: 10) {
            heroBlock(for: snapshot, compact: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            metricsGrid(for: snapshot, limit: 4, compact: true, singleColumn: false)
                .frame(width: 236, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func forecastWeatherPage(for snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    localizedFormat(
                        "weather_tab.next_days_format",
                        fallback: "Next %d days",
                        6
                    )
                )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                dailyRow(for: snapshot, limit: 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func dailyRow(for snapshot: WeatherSnapshot, limit: Int) -> some View {
        let points = Array(snapshot.dailyForecast.prefix(max(1, limit)))
        if points.isEmpty {
            Text(localized("weather_tab.no_forecast", fallback: "No forecast data"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
        } else {
            HStack(spacing: 6) {
                ForEach(points) { day in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.dayLabel)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Image(systemName: WeatherCodeMapper.symbolName(for: day.weatherCode, isDay: true))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.92))
                            Text("\(Int(day.minTemperature.rounded()))° / \(Int(day.maxTemperature.rounded()))°")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }

                        if let rain = day.precipitationProbability {
                            Text(
                                localizedFormat(
                                    "weather_tab.rain_value_format",
                                    fallback: "Rain %d%%",
                                    Int(rain.rounded())
                                )
                            )
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private func headerBar(for snapshot: WeatherSnapshot, staleError: String?) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(snapshot.cityName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(
                localizedFormat(
                    "weather_tab.updated_format",
                    fallback: "Updated %@",
                    snapshot.updatedAt.formatted(date: .omitted, time: .shortened)
                )
            )
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(1)

            Spacer()

            if staleError != nil {
                Label(localized("weather_tab.cached_badge", fallback: "Cached"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.86))
            }

            if showForecastPage {
                HStack(spacing: 6) {
                    weatherPageButton(page: .current)
                    weatherPageButton(page: .forecast)
                }
            }

        }
    }

    @ViewBuilder
    private func heroBlock(for snapshot: WeatherSnapshot, compact: Bool) -> some View {
        let temperatureStyle = temperatureGradient(for: snapshot)
        let iconColors = weatherIconPalette(for: snapshot)

        HStack(alignment: .center, spacing: compact ? 12 : 14) {
            HStack(alignment: .center, spacing: compact ? 10 : 12) {
                Text(snapshot.temperatureText)
                    .font(.system(size: compact ? 46 : 52, weight: .bold, design: .rounded))
                    .foregroundStyle(temperatureStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)

                Image(systemName: snapshot.symbolName)
                    .font(.system(size: compact ? 34 : 40, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(iconColors.0, iconColors.1)
                    .shadow(color: iconColors.0.opacity(0.18), radius: 6, x: 0, y: 2)
            }
            .layoutPriority(2)

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.conditionText)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                if let highLow = highLowText(for: snapshot) {
                    Text(highLow)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func metricsGrid(for snapshot: WeatherSnapshot, limit: Int, compact: Bool, singleColumn: Bool) -> some View {
        let metrics: [(String, String, String)] = [
            (localized("weather_tab.metric.feels", fallback: "Feels"), snapshot.feelsLikeText ?? "--", "thermometer.medium"),
            (localized("weather_tab.metric.humidity", fallback: "Humidity"), snapshot.humidityText ?? "--", "humidity.fill"),
            (localized("weather_tab.metric.wind", fallback: "Wind"), snapshot.windSpeedText ?? "--", "wind"),
            (localized("weather_tab.metric.rain", fallback: "Rain"), snapshot.precipitationText ?? "--", "drop.fill")
        ]
        let visibleMetrics = Array(metrics.prefix(max(1, min(limit, metrics.count))))
        let columns = singleColumn ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]

        LazyVGrid(columns: columns, spacing: compact ? 4 : 6) {
            ForEach(visibleMetrics, id: \.0) { metric in
                HStack(spacing: 4) {
                    Image(systemName: metric.2)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.84))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(metric.0)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.78))
                        Text(metric.1)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, compact ? 3 : 5)
                .background(Color.black.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func highLowText(for snapshot: WeatherSnapshot) -> String? {
        guard let high = snapshot.highTemperature, let low = snapshot.lowTemperature else { return nil }
        return localizedFormat(
            "weather_tab.high_low_format",
            fallback: "L %d°  H %d°",
            Int(low.rounded()),
            Int(high.rounded())
        )
    }

    private func temperatureGradient(for snapshot: WeatherSnapshot) -> LinearGradient {
        let celsius = snapshot.unit == .fahrenheit
            ? (snapshot.temperature - 32.0) * 5.0 / 9.0
            : snapshot.temperature

        switch celsius {
        case 32...:
            return LinearGradient(
                colors: [Color(red: 1.00, green: 0.52, blue: 0.44), Color(red: 0.95, green: 0.28, blue: 0.30)],
                startPoint: .top,
                endPoint: .bottom
            )
        case 26..<32:
            return LinearGradient(
                colors: [Color(red: 1.00, green: 0.72, blue: 0.36), Color(red: 1.00, green: 0.52, blue: 0.30)],
                startPoint: .top,
                endPoint: .bottom
            )
        case 18..<26:
            return LinearGradient(
                colors: [Color(red: 0.43, green: 0.86, blue: 0.66), Color(red: 0.33, green: 0.73, blue: 0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
        case 10..<18:
            return LinearGradient(
                colors: [Color(red: 0.60, green: 0.82, blue: 1.00), Color(red: 0.41, green: 0.66, blue: 0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
        default:
            return LinearGradient(
                colors: [Color.white.opacity(0.98), Color(red: 0.86, green: 0.91, blue: 0.98)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func weatherIconPalette(for snapshot: WeatherSnapshot) -> (Color, Color) {
        switch snapshot.weatherCode {
        case 0:
            return snapshot.isDay
                ? (Color(red: 1.00, green: 0.84, blue: 0.34), Color(red: 1.00, green: 0.62, blue: 0.28))
                : (Color(red: 0.76, green: 0.82, blue: 1.00), Color(red: 0.58, green: 0.64, blue: 0.92))
        case 1, 2:
            return snapshot.isDay
                ? (Color(red: 1.00, green: 0.80, blue: 0.36), Color.white.opacity(0.95))
                : (Color(red: 0.66, green: 0.76, blue: 1.00), Color.white.opacity(0.88))
        case 3, 45, 48:
            return (Color.white.opacity(0.94), Color(red: 0.68, green: 0.72, blue: 0.79))
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82:
            return (Color(red: 0.45, green: 0.84, blue: 1.00), Color(red: 0.28, green: 0.60, blue: 0.96))
        case 71, 73, 75, 77, 85, 86:
            return (Color.white.opacity(0.99), Color(red: 0.74, green: 0.90, blue: 1.00))
        case 95, 96, 99:
            return (Color(red: 1.00, green: 0.86, blue: 0.36), Color(red: 0.62, green: 0.60, blue: 1.00))
        default:
            return (Color.white.opacity(0.95), Color.white.opacity(0.76))
        }
    }

}
