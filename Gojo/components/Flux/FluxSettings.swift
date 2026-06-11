//
//  FluxSettings.swift
//  Gojo
//
//  Settings tab for the Flux night shift feature.
//

import Defaults
import SwiftUI

struct FluxSettings: View {
    @ObservedObject var fluxManager = FluxManager.shared
    @ObservedObject var locationManager = FluxLocationManager.shared
    @Default(.fluxEnabled) var fluxEnabled
    @Default(.fluxLocation) var fluxLocation
    @Default(.fluxBedtimeMinutes) var bedtimeMinutes
    @Default(.fluxWindDownMinutes) var windDownMinutes
    @Default(.fluxDayKelvin) var dayKelvin
    @Default(.fluxSunsetKelvin) var sunsetKelvin
    @Default(.fluxBedtimeKelvin) var bedtimeKelvin

    @State private var locationQuery = ""
    @State private var selectedPhase: FluxEditablePhase = .daytime

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .fluxEnabled) {
                    Text("Enable night shift")
                }
                if fluxEnabled {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(statusDescription)
                            .foregroundStyle(.secondary)
                    }
                    if fluxManager.isPaused {
                        Button("Resume now") {
                            fluxManager.resume()
                        }
                    } else {
                        Button("Disable for one hour") {
                            fluxManager.pause()
                        }
                    }
                }
                Defaults.Toggle(key: .fluxShowInNotch) {
                    Text("Show toggle in notch")
                }
                Defaults.Toggle(key: .fluxStartAtLogin) {
                    Text("Start night shift at login")
                }
                Text("Turns night shift on whenever Gojo starts. Pair with “Launch at login” in General settings so Gojo starts with your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("General")
            }

            Section {
                HStack {
                    Text("Location")
                    Spacer()
                    Text(fluxLocation?.name ?? "Not set — assuming 7 AM sunrise / 7 PM sunset")
                        .foregroundStyle(.secondary)
                }
                if let solarDescription {
                    HStack {
                        Text("Today")
                        Spacer()
                        Text(solarDescription)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    TextField("City or ZIP code", text: $locationQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submitLocationQuery)
                    Button("Set") {
                        submitLocationQuery()
                    }
                    .disabled(locationQuery.trimmingCharacters(in: .whitespaces).isEmpty || locationManager.isResolving)
                }
                HStack {
                    Button("Use Current Location") {
                        locationManager.requestCurrentLocation()
                    }
                    .disabled(locationManager.isResolving)
                    if locationManager.isResolving {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                    if fluxLocation != nil {
                        Button("Clear") {
                            locationManager.clearLocation()
                        }
                    }
                }
                if let error = locationManager.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Your location is only used to calculate sunrise and sunset times and never leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Location")
            }

            Section {
                DatePicker("Bedtime", selection: bedtimeBinding, displayedComponents: .hourAndMinute)
                Picker("Wind-down duration", selection: $windDownMinutes) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("45 minutes").tag(45)
                    Text("1 hour").tag(60)
                    Text("1.5 hours").tag(90)
                }
                Text("The screen gradually warms from the evening temperature to the bedtime temperature as bedtime approaches, then holds it until sunrise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Schedule")
            }

            Section {
                VStack(alignment: .leading, spacing: 14) {
                    FluxKelvinSlider(kelvin: selectedKelvinBinding)

                    Picker("Phase", selection: $selectedPhase) {
                        ForEach(FluxEditablePhase.allCases) { phase in
                            Text(phase.rawValue).tag(phase)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    .frame(maxWidth: .infinity)

                    Text(phaseStatusDescription)
                        .font(.callout)
                        .foregroundStyle(Color.effectiveAccent)
                        .frame(maxWidth: .infinity, alignment: .center)

                    // The dot tracks the schedule (same source as the curve), not the
                    // eased on-screen temperature, so it follows the slider live.
                    FluxScheduleChart(
                        samples: curveSamples,
                        nowMinute: nowMinute,
                        nowKelvin: currentScheduleKelvin,
                        sunlightLabel: sunlightHoursLabel
                    )
                    .frame(height: 130)
                }
                .padding(.vertical, 6)
            } header: {
                Text("Color Temperature")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Night Shift")
    }

    private var statusDescription: String {
        if let pausedUntil = fluxManager.pausedUntil, fluxManager.isPaused {
            return "Paused until \(pausedUntil.formatted(date: .omitted, time: .shortened))"
        }
        return "\(fluxManager.currentPhase.rawValue) · \(Int(fluxManager.currentKelvin.rounded()))K"
    }

    private var solarDescription: String? {
        guard let events = FluxManager.solarEventsToday() else { return nil }
        switch events {
        case .regular(let sunriseMinutes, let sunsetMinutes):
            return "Sunrise \(formatMinutes(sunriseMinutes)) · Sunset \(formatMinutes(sunsetMinutes))"
        case .polarDay:
            return "Sun is up all day (polar day)"
        case .polarNight:
            return "Sun is down all day (polar night)"
        }
    }

    private var bedtimeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: bedtimeMinutes / 60,
                minute: bedtimeMinutes % 60,
                second: 0,
                of: Date()
            ) ?? Date()
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            bedtimeMinutes = (components.hour ?? 23) * 60 + (components.minute ?? 0)
        }
    }

    private func submitLocationQuery() {
        let query = locationQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        locationManager.setLocation(query: query)
        locationQuery = ""
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let date = Calendar.current.date(
            bySettingHour: (total / 60) % 24, minute: total % 60, second: 0, of: Date()
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Temperature editor helpers

    private var selectedKelvinBinding: Binding<Double> {
        switch selectedPhase {
        case .daytime: return $dayKelvin
        case .sunset: return $sunsetKelvin
        case .bedtime: return $bedtimeKelvin
        }
    }

    private var scheduleConfig: FluxScheduleConfig {
        // The @Default properties above keep the view re-rendering on changes
        FluxManager.currentConfig
    }

    private var curveSamples: [FluxCurveSample] {
        FluxScheduleChart.sampleCurve(config: scheduleConfig, solar: FluxManager.solarEventsToday())
    }

    private var nowMinute: Double {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    private var currentScheduleKelvin: Double {
        FluxScheduleEngine.evaluate(
            nowMinutes: nowMinute, solar: FluxManager.solarEventsToday(), config: scheduleConfig
        ).kelvin
    }

    /// f.lux-style context line, e.g. "Sunrise: 6 hours ago (6500K)".
    private var phaseStatusDescription: String {
        let (eventName, eventMinutes, kelvin): (String, Double?, Double)
        let solar = FluxManager.solarEventsToday()
        switch selectedPhase {
        case .daytime:
            if case .regular(let rise, _)? = solar {
                (eventName, eventMinutes, kelvin) = ("Sunrise", rise, dayKelvin)
            } else {
                (eventName, eventMinutes, kelvin) =
                    ("Sunrise", solar == nil ? FluxScheduleEngine.fallbackSunriseMinutes : nil, dayKelvin)
            }
        case .sunset:
            if case .regular(_, let set)? = solar {
                (eventName, eventMinutes, kelvin) = ("Sunset", set, sunsetKelvin)
            } else {
                (eventName, eventMinutes, kelvin) =
                    ("Sunset", solar == nil ? FluxScheduleEngine.fallbackSunsetMinutes : nil, sunsetKelvin)
            }
        case .bedtime:
            (eventName, eventMinutes, kelvin) = ("Bedtime", Double(bedtimeMinutes), bedtimeKelvin)
        }

        guard let eventMinutes else {
            // Polar day/night: there is no sunrise/sunset today
            return "\(eventName): not today (\(Int(kelvin))K)"
        }
        let total = Int(eventMinutes.rounded())
        let eventDate = Calendar.current.date(
            bySettingHour: (total / 60) % 24, minute: total % 60, second: 0, of: Date()
        ) ?? Date()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: eventDate, relativeTo: Date())
        return "\(eventName): \(relative) (\(Int(kelvin))K)"
    }

    private var sunlightHoursLabel: String {
        switch FluxManager.solarEventsToday() {
        case .regular(let rise, let set):
            let minutes = set - rise >= 0 ? set - rise : set - rise + 1440
            let hours = (minutes / 60).rounded()
            return "\(Int(hours)) sunlight hours"
        case .polarDay:
            return "24 sunlight hours (polar day)"
        case .polarNight:
            return "0 sunlight hours (polar night)"
        case nil:
            return "12 sunlight hours (assumed — no location set)"
        }
    }
}

#Preview {
    FluxSettings()
}
