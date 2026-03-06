//
//  WeatherSettingsView.swift
//  boringNotch
//
//  Created by TheBoredTeam on 2026-03-03.
//

import Defaults
import SwiftUI

struct WeatherSettings: View {
    @ObservedObject private var weatherManager = WeatherManager.shared
    @Default(.showWeather) private var showWeather
    @Default(.weatherCity) private var weatherCity
    @Default(.weatherUnit) private var weatherUnit
    @Default(.weatherRefreshMinutes) private var weatherRefreshMinutes
    @Default(.weatherContentPreference) private var weatherContentPreference

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showWeather) {
                    Text("Show weather")
                }
                if showWeather {
                    TextField("City (supports lowercase pinyin)", text: $weatherCity)
                        .onSubmit {
                            weatherManager.refreshForEnteredCity()
                        }

                    if weatherManager.isLoadingCitySuggestions {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching cities...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if !weatherManager.citySuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("City suggestions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(Array(weatherManager.citySuggestions.prefix(8))) { suggestion in
                                Button {
                                    weatherManager.selectCitySuggestion(suggestion)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.displayName)
                                                .lineLimit(1)
                                            if !suggestion.subtitle.isEmpty {
                                                Text(suggestion.subtitle)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Picker("Temperature unit", selection: $weatherUnit) {
                        ForEach(WeatherTemperatureUnit.allCases, id: \.self) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }

                    Picker("Weather content", selection: $weatherContentPreference) {
                        Text("Current weather only")
                            .tag(WeatherContentPreference.currentOnly)
                        Text("Current and forecast")
                            .tag(WeatherContentPreference.currentAndForecast)
                    }
                    .pickerStyle(.segmented)

                    Stepper(value: $weatherRefreshMinutes, in: 5...120, step: 5) {
                        HStack {
                            Text("Weather refresh interval")
                            Spacer()
                            Text("\(weatherRefreshMinutes) min")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("General")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Weather")
    }
}
