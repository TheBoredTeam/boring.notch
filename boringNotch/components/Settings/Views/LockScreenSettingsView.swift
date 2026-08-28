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
                    Text(LockScreenText.value("Show notch on lock screen", "在锁定屏幕显示刘海"))
                }
                Text(LockScreenText.value(
                    "Widgets are only visible while the Mac is locked. Enable the widgets you want below.",
                    "小组件只会在 Mac 锁定时显示。请在下方启用需要的组件。"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(LockScreenText.value("Lock Screen", "锁定屏幕"))
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenMediaWidget) {
                    Text(LockScreenText.value("Show media widget", "显示媒体小组件"))
                }
                Defaults.Toggle(key: .enableLockScreenWeatherWidget) {
                    Text(LockScreenText.value("Show weather and status widget", "显示天气与状态小组件"))
                }
                Defaults.Toggle(key: .enableLockScreenTimerWidget) {
                    Text(LockScreenText.value("Show timer widget", "显示计时器小组件"))
                }
                Defaults.Toggle(key: .enableLockScreenReminderWidget) {
                    Text(LockScreenText.value("Show reminder widget", "显示提醒事项小组件"))
                }
                Defaults.Toggle(key: .enableLockScreenFocusWidget) {
                    Text(LockScreenText.value("Show Focus status", "显示专注模式状态"))
                }
            } header: {
                Text(LockScreenText.value("Widgets", "小组件"))
            }
            .disabled(!showOnLockScreen)

            Section {
                Picker(LockScreenText.value("Appearance", "外观"), selection: $appearance) {
                    ForEach(LockScreenWidgetAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(LockScreenText.value("Appearance", "外观"))
            }
            .disabled(!showOnLockScreen)

            Section {
                Picker(LockScreenText.value("Style", "样式"), selection: $weatherStyle) {
                    ForEach(LockScreenWeatherWidgetStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Picker(LockScreenText.value("Temperature", "温度单位"), selection: $temperatureUnit) {
                    ForEach(LockScreenWeatherTemperatureUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }

                Toggle(LockScreenText.value("Show location", "显示位置"), isOn: $showLocation)
                Toggle(LockScreenText.value("Show sunrise", "显示日出时间"), isOn: $showSunrise)
                Toggle(LockScreenText.value("Show air quality", "显示空气质量"), isOn: $showAQI)

                HStack {
                    Text(LockScreenText.value("Vertical offset", "垂直偏移"))
                    Slider(value: $weatherOffset, in: -160...160, step: 2)
                    Text("\(Int(weatherOffset)) \(LockScreenText.value("px", "像素"))")
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }

                Button(LockScreenText.value("Allow location access", "允许访问位置")) {
                    LockScreenWeatherWidgetManager.shared.prepareLocationAccess()
                }
            } header: {
                Text(LockScreenText.value("Weather", "天气"))
            } footer: {
                Text(LockScreenText.value(
                    "Weather is provided by Open-Meteo. Boring Notch asks for your location only after you allow it.",
                    "天气数据由 Open-Meteo 提供。只有在你允许后，Boring Notch 才会请求位置。"
                ))
            }
            .disabled(!showOnLockScreen || !enableWeather)

            Section {
                Toggle(LockScreenText.value("Show Mac battery", "显示 Mac 电池"), isOn: $showBattery)
                Toggle(LockScreenText.value("Show charging state", "显示充电状态"), isOn: $showCharging)
                    .disabled(!showBattery)
                Toggle(LockScreenText.value("Show charging percentage", "显示充电百分比"), isOn: $showChargingPercentage)
                    .disabled(!showBattery || !showCharging)
                Toggle(LockScreenText.value("Show Bluetooth audio output", "显示蓝牙音频输出"), isOn: $showBluetooth)
                Toggle(LockScreenText.value("Show next calendar event", "显示下一个日历事件"), isOn: $showCalendarEvent)

                HStack {
                    Text(LockScreenText.value("Calendar look-ahead", "日历预览范围"))
                    Slider(value: $calendarLookaheadHours, in: 0.25...24, step: 0.25)
                    Text("\(calendarLookaheadHours, specifier: "%.2g") \(LockScreenText.value("h", "小时"))")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            } header: {
                Text(LockScreenText.value("Status rows", "状态信息"))
            }
            .disabled(!showOnLockScreen || !enableWeather)

            Section {
                HStack {
                    Text(LockScreenText.value("Duration", "时长"))
                    Spacer()
                    TextField(LockScreenText.value("Minutes", "分钟"), value: $timerMinutes, format: .number)
                        .frame(width: 72)
                    Text(LockScreenText.value("minutes", "分钟"))
                        .foregroundStyle(.secondary)
                }
                Button(timer.isTimerActive
                    ? LockScreenText.value("Restart timer", "重新开始计时")
                    : LockScreenText.value("Start timer", "开始计时")) {
                    timer.start(minutes: timerMinutes)
                }
                .disabled(timerMinutes <= 0)

                if timer.isTimerActive {
                    HStack {
                        Text("\(LockScreenText.value("Remaining", "剩余时间"))：\(timer.formattedRemainingTime)")
                        Spacer()
                        Button(LockScreenText.value("Cancel", "取消"), role: .destructive) { timer.cancel() }
                    }
                }

                HStack {
                    Text(LockScreenText.value("Vertical offset", "垂直偏移"))
                    Slider(value: $timerOffset, in: -160...160, step: 2)
                    Text("\(Int(timerOffset)) \(LockScreenText.value("px", "像素"))")
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
                HStack {
                    Text(LockScreenText.value("Width", "宽度"))
                    Slider(value: $timerWidth, in: 260...520, step: 10)
                    Text("\(Int(timerWidth)) \(LockScreenText.value("px", "像素"))")
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            } header: {
                Text(LockScreenText.value("Timer", "计时器"))
            }
            .disabled(!showOnLockScreen || !enableTimer)

            Section {
                Picker(LockScreenText.value("Alignment", "对齐方式"), selection: $reminderAlignment) {
                    ForEach(LockScreenReminderAlignment.allCases) { alignment in
                        Text(alignment.title).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text(LockScreenText.value("Vertical offset", "垂直偏移"))
                    Slider(value: $reminderOffset, in: -160...160, step: 2)
                    Text("\(Int(reminderOffset)) \(LockScreenText.value("px", "像素"))")
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            } header: {
                Text(LockScreenText.value("Reminders", "提醒事项"))
            } footer: {
                Text(LockScreenText.value(
                    "Displays the next incomplete reminder that is due within the calendar look-ahead window.",
                    "显示日历预览范围内下一条未完成且到期的提醒事项。"
                ))
            }
            .disabled(!showOnLockScreen || !enableReminder)

            Section {
                Toggle(LockScreenText.value("Focus is active", "专注模式已开启"), isOn: $focusActive)
                TextField(LockScreenText.value("Focus name", "专注模式名称"), text: $focusName)
            } header: {
                Text(LockScreenText.value("Focus", "专注模式"))
            } footer: {
                Text(LockScreenText.value(
                    "Boring Notch also listens for macOS Focus notifications. These controls are a manual fallback when macOS does not expose a mode name.",
                    "Boring Notch 也会监听 macOS 的专注模式通知。当系统未提供模式名称时，可在这里手动设置。"
                ))
            }
            .disabled(!showOnLockScreen || !enableFocus)
        }
        .formStyle(.grouped)
        .navigationTitle(LockScreenText.value("Lock Screen", "锁定屏幕"))
    }
}
