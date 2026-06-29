//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import Sparkle
import SwiftUI
import SwiftUIIntrospect

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case media
    case ai
    case calendar
    case weather
    case pomodoro
    case osd
    case battery
    case shelf
    case mirror
    case shortcuts
    case advanced
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .media: "Media"
        case .ai: "AI"
        case .calendar: "Calendar"
        case .weather: "Weather"
        case .pomodoro: "Pomodoro"
        case .osd: "OSD"
        case .battery: "Battery"
        case .shelf: "Shelf"
        case .mirror: "Mirror"
        case .shortcuts: "Shortcuts"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"
        case .appearance: "eye"
        case .media: "play.laptopcomputer"
        case .ai: "sparkles"
        case .calendar: "calendar"
        case .weather: "cloud.sun"
        case .pomodoro: "timer"
        case .osd: "dial.medium.fill"
        case .battery: "battery.100.bolt"
        case .shelf: "books.vertical"
        case .mirror: "camera"
        case .shortcuts: "keyboard"
        case .advanced: "gearshape.2"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettings()
                case .appearance:
                    Appearance()
                case .media:
                    Media()
                case .ai:
                    AISettings()
                case .calendar:
                    CalendarSettings()
                case .weather:
                    WeatherSettings()
                case .pomodoro:
                    PomodoroSettings()
                case .osd:
                    OSDSettings()
                case .battery:
                    Charge()
                case .shelf:
                    Shelf()
                case .mirror:
                    MirrorSettings()
                case .shortcuts:
                    Shortcuts()
                case .advanced:
                    Advanced()
                case .about:
                    if let controller = updaterController {
                        About(updaterController: controller)
                    } else {
                        // Fallback with a default controller
                        About(
                            updaterController: SPUStandardUpdaterController(
                                startingUpdater: false, updaterDelegate: nil,
                                userDriverDelegate: nil))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: .accentColorChanged)) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }
}

struct AISettings: View {
    @ObservedObject private var aiManager = AIChatManager.shared

    @Default(.aiChatEnabled) var aiChatEnabled
    @Default(.aiCalendarContextEnabled) var aiCalendarContextEnabled
    @Default(.aiCalendarWriteEnabled) var aiCalendarWriteEnabled
    @Default(.aiServiceBaseURL) var aiServiceBaseURL
    @Default(.aiServiceModel) var aiServiceModel
    @Default(.aiServiceAPIKey) var aiServiceAPIKey
    @Default(.aiSystemPrompt) var aiSystemPrompt
    @Default(.aiChatPanelWidth) var aiChatPanelWidth
    @Default(.aiChatPanelHeight) var aiChatPanelHeight

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .aiChatEnabled) {
                    Text("Enable AI chat")
                }

                TextField("Base URL", text: $aiServiceBaseURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $aiServiceModel)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key", text: $aiServiceAPIKey)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("OpenAI-compatible API")
            } footer: {
                Text("Supports OpenAI-compatible chat completions endpoints such as https://api.openai.com or compatible gateways.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .aiCalendarContextEnabled) {
                    Text("Let AI read calendar context")
                }
                Defaults.Toggle(key: .aiCalendarWriteEnabled) {
                    Text("Let AI create calendar events")
                }
            } header: {
                Text("Calendar integration")
            } footer: {
                Text("The assistant can read selected calendars to avoid conflicts. It only writes events when the user explicitly asks and this setting is enabled.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Width")
                        Spacer()
                        Text("\(Int(aiChatPanelWidth)) px")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $aiChatPanelWidth, in: aiChatPanelMinSize.width...aiChatPanelMaxSize.width, step: 10)

                    HStack {
                        Text("Height")
                        Spacer()
                        Text("\(Int(aiChatPanelHeight)) px")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $aiChatPanelHeight, in: aiChatPanelMinSize.height...aiChatPanelMaxSize.height, step: 10)

                    Button("Reset size") {
                        aiChatPanelWidth = aiChatPanelDefaultSize.width
                        aiChatPanelHeight = aiChatPanelDefaultSize.height
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            } header: {
                Text("AI panel size")
            } footer: {
                Text("The AI panel can also be resized directly from the notch by dragging the right edge, bottom edge, or bottom-right corner.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(aiManager.availablePlugins) { plugin in
                        AIPluginSettingsRow(plugin: plugin)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Agent plugins")
            } footer: {
                Text("The current implementation uses a built-in plugin registry. It does not execute third-party dynamic code.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(aiManager.availableSkills) { skill in
                        AISkillSettingsRow(skill: skill)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Skills")
            } footer: {
                Text("Skills describe task workflows that can be injected into model context when a matching task is routed.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                TextField("System prompt", text: $aiSystemPrompt)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Assistant behavior")
            } footer: {
                Text("This prompt is prepended to each request from the notch chat tab.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("AI")
    }
}

private struct AIPluginSettingsRow: View {
    let plugin: AgentPluginDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name)
                        .font(.headline)
                    Text(plugin.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(plugin.riskLevel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(plugin.riskLevel == "medium" ? .orange : .green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((plugin.riskLevel == "medium" ? Color.orange : Color.green).opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(plugin.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(plugin.typeTags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.effectiveAccent.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Label(plugin.toolNames.joined(separator: ", "), systemImage: "wrench.and.screwdriver")
                Spacer()
                Label(plugin.permission, systemImage: "lock.shield")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AISkillSettingsRow: View {
    let skill: AgentSkillDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(.headline)
                    Text(skill.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(skill.riskLevel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(skill.riskLevel == "medium" ? .orange : .green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((skill.riskLevel == "medium" ? Color.orange : Color.green).opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(skill.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(skill.workflowSteps.joined(separator: " -> "))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Triggers: \(skill.triggerKeywords.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(skill.requiredTools.joined(separator: ", "), systemImage: "link")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WeatherSettings: View {
    @ObservedObject private var weatherManager = WeatherManager.shared

    @Default(.weatherFeatureEnabled) var weatherFeatureEnabled
    @Default(.weatherLocationMode) var weatherLocationMode
    @Default(.weatherCity) var weatherCity
    @Default(.weatherTemperatureUnit) var weatherTemperatureUnit

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .weatherFeatureEnabled) {
                    Text("Enable weather")
                }

                Picker("Source", selection: $weatherLocationMode) {
                    ForEach(WeatherLocationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                if weatherLocationMode == .automatic {
                    HStack {
                        Text("Location access")
                        Spacer()
                        Text(weatherManager.locationAuthorizationDescription)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        if weatherManager.locationAuthorizationStatus == .notDetermined {
                            Button("Allow location access") {
                                Task {
                                    await weatherManager.requestLocationAuthorization()
                                }
                            }
                        } else if !weatherManager.locationServicesEnabled {
                            Button("Open Location Settings") {
                                weatherManager.openLocationSettings()
                            }
                        }

                        if weatherManager.locationAuthorizationStatus == .denied
                            || weatherManager.locationAuthorizationStatus == .restricted
                        {
                            Button("Open Location Settings") {
                                weatherManager.openLocationSettings()
                            }
                        }
                    }
                } else {
                    TextField("City", text: $weatherCity)
                        .textFieldStyle(.roundedBorder)
                }

                Picker("Temperature unit", selection: $weatherTemperatureUnit) {
                    ForEach(WeatherTemperatureUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
            } header: {
                Text("Forecast source")
            } footer: {
                Text("Weather uses Open-Meteo. Automatic mode uses your current location through macOS Location Services. Manual mode uses the city entered here.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Button("Refresh now") {
                    Task {
                        await WeatherManager.shared.refreshWeather(force: true)
                    }
                }
                .disabled(!weatherFeatureEnabled)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Weather")
        .onAppear {
            weatherManager.refreshLocationAccessState()
        }
        .onChange(of: weatherLocationMode) { _, newMode in
            weatherManager.refreshLocationAccessState()

            guard newMode == .automatic else { return }

            Task {
                if weatherManager.locationAuthorizationStatus == .notDetermined {
                    await weatherManager.requestLocationAuthorization()
                } else {
                    await weatherManager.refreshWeather(force: true)
                }
            }
        }
    }
}

struct PomodoroSettings: View {
    @Default(.pomodoroEnabled) var pomodoroEnabled
    @Default(.pomodoroFocusMinutes) var pomodoroFocusMinutes
    @Default(.pomodoroShortBreakMinutes) var pomodoroShortBreakMinutes
    @Default(.pomodoroLongBreakMinutes) var pomodoroLongBreakMinutes
    @Default(.pomodoroLongBreakInterval) var pomodoroLongBreakInterval
    @Default(.pomodoroAutoStartNextPhase) var pomodoroAutoStartNextPhase

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .pomodoroEnabled) {
                    Text("Enable Pomodoro timer")
                }

                Defaults.Toggle(key: .pomodoroAutoStartNextPhase) {
                    Text("Auto-start next phase")
                }
                .disabled(!pomodoroEnabled)
            } header: {
                Text("Timer behavior")
            } footer: {
                Text("The Pomodoro timer runs locally inside the app. No external API is used.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Stepper(value: $pomodoroFocusMinutes, in: 1 ... 120) {
                    Text("Focus duration: \(pomodoroFocusMinutes) min")
                }

                Stepper(value: $pomodoroShortBreakMinutes, in: 1 ... 60) {
                    Text("Short break: \(pomodoroShortBreakMinutes) min")
                }

                Stepper(value: $pomodoroLongBreakMinutes, in: 1 ... 90) {
                    Text("Long break: \(pomodoroLongBreakMinutes) min")
                }

                Stepper(value: $pomodoroLongBreakInterval, in: 2 ... 8) {
                    Text("Long break every \(pomodoroLongBreakInterval) focus sessions")
                }
            } header: {
                Text("Durations")
            } footer: {
                Text("The notch tab lets users start, pause, skip, and reset the current cycle.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .disabled(!pomodoroEnabled)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Pomodoro")
    }
}
