//
//  LockScreenSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct LockScreenSettings: View {
    @Default(.showOnLockScreen) private var showOnLockScreen
    @Default(.enableLockScreenMediaWidget) private var enableMedia
    @Default(.enableLockScreenWeatherWidget) private var enableWeather
    @Default(.enableLockScreenTimerWidget) private var enableTimer
    @Default(.enableLockScreenReminderWidget) private var enableReminder
    @Default(.enableLockScreenFocusWidget) private var enableFocus
    @Default(.lockScreenWidgetAppearance) private var appearance
    @Default(.lockScreenWeatherWidgetStyle) private var weatherStyle
    @Default(.lockScreenWeatherTemperatureUnit) private var temperatureUnit
    @Default(.lockScreenWeatherShowsLocation) private var showLocation
    @Default(.lockScreenWeatherShowsSunrise) private var showSunrise
    @Default(.lockScreenWeatherShowsAQI) private var showAQI
    @Default(.lockScreenWeatherVerticalOffset) private var weatherOffset
    @Default(.lockScreenBatteryShowsBatteryGauge) private var showBattery
    @Default(.lockScreenBatteryShowsCharging) private var showCharging
    @Default(.lockScreenBatteryShowsChargingPercentage) private var showChargingPercentage
    @Default(.lockScreenBatteryShowsBluetooth) private var showBluetooth
    @Default(.lockScreenShowCalendarEvent) private var showCalendarEvent
    @Default(.lockScreenCalendarEventLookaheadHours) private var calendarLookaheadHours
    @Default(.lockScreenReminderWidgetHorizontalAlignment) private var reminderAlignment
    @Default(.lockScreenReminderWidgetVerticalOffset) private var reminderOffset
    @Default(.lockScreenTimerVerticalOffset) private var timerOffset
    @Default(.lockScreenTimerWidgetWidth) private var timerWidth
    @Default(.lockScreenFocusActive) private var focusActive
    @Default(.lockScreenFocusName) private var focusName

    @ObservedObject private var timer = LockScreenTimerWidgetManager.shared
    @State private var timerMinutes = 10.0

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text(LockScreenText.value("Show notch on lock screen"))
                }
                Text(LockScreenText.value("Widgets are only visible while the Mac is locked. Enable the widgets you want below."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(LockScreenText.value("Lock Screen"))
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenMediaWidget) {
                    Text(LockScreenText.value("Show media widget"))
                }
                Defaults.Toggle(key: .enableLockScreenWeatherWidget) {
                    Text(LockScreenText.value("Show weather and status widget"))
                }
                Defaults.Toggle(key: .enableLockScreenTimerWidget) {
                    Text(LockScreenText.value("Show timer widget"))
                }
                Defaults.Toggle(key: .enableLockScreenReminderWidget) {
                    Text(LockScreenText.value("Show reminder widget"))
                }
                Defaults.Toggle(key: .enableLockScreenFocusWidget) {
                    Text(LockScreenText.value("Show Focus status"))
                }
            } header: {
                Text(LockScreenText.value("Widgets"))
            }
            .disabled(!showOnLockScreen)

            Section {
                Picker(LockScreenText.value("Appearance"), selection: $appearance) {
                    ForEach(LockScreenWidgetAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(LockScreenText.value("Appearance"))
            }
            .disabled(!showOnLockScreen)

            Section {
                Picker(LockScreenText.value("Style"), selection: $weatherStyle) {
                    ForEach(LockScreenWeatherWidgetStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Picker(LockScreenText.value("Temperature"), selection: $temperatureUnit) {
                    ForEach(LockScreenWeatherTemperatureUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }

                Toggle(LockScreenText.value("Show location"), isOn: $showLocation)
                Toggle(LockScreenText.value("Show sunrise"), isOn: $showSunrise)
                Toggle(LockScreenText.value("Show air quality"), isOn: $showAQI)

                HStack {
                    Text(LockScreenText.value("Vertical offset"))
                    Slider(value: $weatherOffset, in: -160...160, step: 2)
                    Text("\(Int(weatherOffset)) \(LockScreenText.value("px"))")
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }

                Button(LockScreenText.value("Allow location access")) {
                    LockScreenWeatherWidgetManager.shared.prepareLocationAccess()
                }
            } header: {
                Text(LockScreenText.value("Weather"))
            } footer: {
                Text(LockScreenText.value("Weather is provided by Open-Meteo. Boring Notch asks for your location only after you allow it."))
            }
            .disabled(!showOnLockScreen || !enableWeather)

            Section {
                Toggle(LockScreenText.value("Show Mac battery"), isOn: $showBattery)
                Toggle(LockScreenText.value("Show charging state"), isOn: $showCharging)
                    .disabled(!showBattery)
                Toggle(LockScreenText.value("Show charging percentage"), isOn: $showChargingPercentage)
                    .disabled(!showBattery || !showCharging)
                Toggle(LockScreenText.value("Show Bluetooth audio output"), isOn: $showBluetooth)
                Toggle(LockScreenText.value("Show next calendar event"), isOn: $showCalendarEvent)

                HStack {
                    Text(LockScreenText.value("Calendar look-ahead"))
                    Slider(value: $calendarLookaheadHours, in: 0.25...24, step: 0.25)
                    Text("\(calendarLookaheadHours, specifier: "%.2g") \(LockScreenText.value("h"))")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            } header: {
                Text(LockScreenText.value("Status rows"))
            }
            .disabled(!showOnLockScreen || !enableWeather)

            Section {
                HStack {
                    Text(LockScreenText.value("Duration"))
                    Spacer()
                    TextField(LockScreenText.value("Minutes"), value: $timerMinutes, format: .number)
                        .frame(width: 72)
                    Text(LockScreenText.value("minutes"))
                        .foregroundStyle(.secondary)
                }
                Button(timer.isTimerActive
                    ? LockScreenText.value("Restart timer")
                    : LockScreenText.value("Start timer")) {
                    timer.start(minutes: timerMinutes)
                }
                .disabled(timerMinutes <= 0)

                if timer.isTimerActive {
                    HStack {
                        Text("\(LockScreenText.value("Remaining")): \(timer.formattedRemainingTime)")
                        Spacer()
                        Button(LockScreenText.value("Cancel"), role: .destructive) { timer.cancel() }
                    }
                }

                HStack {
                    Text(LockScreenText.value("Vertical offset"))
                    Slider(value: $timerOffset, in: -160...160, step: 2)
                    Text("\(Int(timerOffset)) \(LockScreenText.value("px"))")
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
                HStack {
                    Text(LockScreenText.value("Width"))
                    Slider(value: $timerWidth, in: 260...520, step: 10)
                    Text("\(Int(timerWidth)) \(LockScreenText.value("px"))")
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            } header: {
                Text(LockScreenText.value("Timer"))
            }
            .disabled(!showOnLockScreen || !enableTimer)

            Section {
                Picker(LockScreenText.value("Alignment"), selection: $reminderAlignment) {
                    ForEach(LockScreenReminderAlignment.allCases) { alignment in
                        Text(alignment.title).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text(LockScreenText.value("Vertical offset"))
                    Slider(value: $reminderOffset, in: -160...160, step: 2)
                    Text("\(Int(reminderOffset)) \(LockScreenText.value("px"))")
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            } header: {
                Text(LockScreenText.value("Reminders"))
            } footer: {
                Text(LockScreenText.value("Displays the next incomplete reminder that is due within the calendar look-ahead window."))
            }
            .disabled(!showOnLockScreen || !enableReminder)

            Section {
                Toggle(LockScreenText.value("Focus is active"), isOn: $focusActive)
                TextField(LockScreenText.value("Focus name"), text: $focusName)
            } header: {
                Text(LockScreenText.value("Focus"))
            } footer: {
                Text(LockScreenText.value("Boring Notch also listens for macOS Focus notifications. These controls are a manual fallback when macOS does not expose a mode name."))
            }
            .disabled(!showOnLockScreen || !enableFocus)
        }
        .formStyle(.grouped)
        .navigationTitle(LockScreenText.value("Lock Screen"))
    }
}
