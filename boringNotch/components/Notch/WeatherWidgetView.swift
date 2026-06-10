//
//  WeatherWidgetView.swift
//  boringNotch
//  Created by Maksymilian Wójcik on 2026-06-09.
//
//  Current-weather panel for the Widgets tab.
//

import Defaults
import SwiftUI

struct WeatherWidgetView: View {
    @ObservedObject var weather = WeatherManager.shared
    @Default(.weatherUnit) var unit
    @Default(.weatherShowForecast) var showForecast

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.caption2)
                Text(weather.locationName.isEmpty ? "Weather" : weather.locationName)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)

            if let temp = weather.temperature {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: weather.symbolName)
                        .font(.system(size: 30))
                        .symbolRenderingMode(.multicolor)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(Int(temp.rounded()))\(unit.rawValue)")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(weather.conditionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(weather.statusMessage ?? "Loading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showForecast && !weather.forecast.isEmpty {
                HStack(spacing: 0) {
                    ForEach(weather.forecast.prefix(3)) { day in
                        VStack(spacing: 2) {
                            Text(day.weekday)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Image(systemName: day.symbolName)
                                .font(.caption)
                                .symbolRenderingMode(.multicolor)
                            Text("\(day.maxTemp)°/\(day.minTemp)°")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .onAppear { weather.start() }
        .onDisappear { weather.stop() }
    }
}
