//
//  WeatherDashboardView.swift
//  boringNotch
//
//  Created by Codex on 2026-06-30.
//

import Defaults
import Foundation
import SwiftUI

struct WeatherDashboardView: View {
    @Default(.weatherFeatureEnabled) private var weatherFeatureEnabled

    @ObservedObject private var manager = WeatherManager.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !weatherFeatureEnabled {
                featureState(
                    title: "天气已关闭",
                    subtitle: "在设置 > Weather 中开启后即可获取实时天气。"
                )
            } else if let snapshot = manager.snapshot {
                weatherContent(snapshot: snapshot)
            } else if manager.isRefreshing {
                loadingState
            } else {
                featureState(
                    title: "天气不可用",
                    subtitle: manager.lastError ?? "检查设置里的城市后再试一次。"
                )
            }
        }
        .task {
            await manager.refreshWeather(force: false)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("天气")
                    .font(.headline)
                Text(
                    (manager.snapshot?.locationName).flatMap { $0.isEmpty ? nil : $0 }
                        ?? {
                            let city = Defaults[.weatherCity].trimmingCharacters(in: .whitespacesAndNewlines)
                            return city.isEmpty ? defaultWeatherCityName() : city
                        }()
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            if manager.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task {
                    await manager.refreshWeather(force: true)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("刷新天气")
        }
    }

    private func weatherContent(snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                WeatherConditionIcon(symbolName: snapshot.current.symbolName, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(temperatureLabel(snapshot.current.temperature, unit: snapshot.current.unitSymbol))
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text(snapshot.current.condition)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Text("体感 \(temperatureLabel(snapshot.current.feelsLike, unit: snapshot.current.unitSymbol))")
                        if let high = snapshot.current.highTemperature, let low = snapshot.current.lowTemperature {
                            Text("最高 \(temperatureLabel(high, unit: snapshot.current.unitSymbol))")
                            Text("最低 \(temperatureLabel(low, unit: snapshot.current.unitSymbol))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let high = snapshot.current.highTemperature, let low = snapshot.current.lowTemperature {
                WeatherRangeBar(
                    low: low,
                    high: high,
                    current: snapshot.current.temperature,
                    unit: snapshot.current.unitSymbol
                )
            }

            LazyVGrid(columns: columns, spacing: 8) {
                WeatherMetricTile(systemImage: "humidity.fill", title: "湿度", value: "\(snapshot.current.humidity)%")
                WeatherMetricTile(systemImage: "wind", title: "风速", value: "\(Int(snapshot.current.windSpeed.rounded())) \(snapshot.current.windUnit)")
                WeatherMetricTile(systemImage: "drop.fill", title: "降水", value: precipitationLabel(snapshot.current.precipitation))
                WeatherMetricTile(systemImage: "clock", title: "更新", value: refreshLabel(snapshot.updatedAt))
            }

            if !snapshot.hourly.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(snapshot.hourly) { entry in
                            WeatherHourChip(entry: entry)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            if let lastError = manager.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在获取最新天气...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func featureState(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("打开设置") {
                SettingsWindowController.shared.showWindow()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func temperatureLabel(_ value: Double, unit: String) -> String {
        "\(Int(value.rounded()))\(unit)"
    }

    private func precipitationLabel(_ value: Double) -> String {
        "\(String(format: "%.1f", value)) mm"
    }

    private func refreshLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct WeatherMetricTile: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.effectiveAccent)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WeatherHourChip: View {
    let entry: WeatherSnapshot.HourlyEntry

    var body: some View {
        VStack(spacing: 5) {
            Text(entry.timeLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            WeatherConditionIcon(symbolName: entry.symbolName, size: 22, cornerRadius: 6)
            Text("\(Int(entry.temperature.rounded()))\(entry.unitSymbol)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
            if let probability = entry.precipitationProbability {
                HStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                    Text("\(probability)%")
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .frame(width: 68)
        .frame(minHeight: 76)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WeatherConditionIcon: View {
    let symbolName: String
    let size: CGFloat
    var cornerRadius: CGFloat = 10

    var body: some View {
        let palette = weatherSymbolPalette(for: symbolName)

        Image(systemName: symbolName)
            .symbolRenderingMode(.palette)
            .font(.system(size: size * 0.58, weight: .semibold))
            .foregroundStyle(palette.primary, palette.secondary)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [
                        palette.primary.opacity(0.22),
                        palette.secondary.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct WeatherRangeBar: View {
    let low: Double
    let high: Double
    let current: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("今日温度")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(low.rounded()))\(unit) - \(Int(high.rounded()))\(unit)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let width = max(proxy.size.width - 8, 1)
                let ratio = normalizedCurrentTemperature

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .orange, .pink, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .offset(x: width * ratio)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var normalizedCurrentTemperature: Double {
        guard high > low else { return 0.5 }
        return min(max((current - low) / (high - low), 0), 1)
    }
}

private func weatherSymbolPalette(for symbolName: String) -> (primary: Color, secondary: Color) {
    if symbolName.contains("sun") {
        return (.yellow, .orange)
    }
    if symbolName.contains("moon") {
        return (.indigo, .cyan)
    }
    if symbolName.contains("bolt") {
        return (.yellow, .purple)
    }
    if symbolName.contains("snow") {
        return (.cyan, .blue)
    }
    if symbolName.contains("rain") || symbolName.contains("drizzle") {
        return (.cyan, .blue)
    }
    if symbolName.contains("fog") {
        return (.gray, .white.opacity(0.8))
    }
    return (.gray, .blue)
}
