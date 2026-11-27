//
//  NotchSettingsView.swift
//  boringNotch
//
//  Created by Alexander on 2026-09-21.
//

import Defaults
import SwiftUI

struct NotchSettingsView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.enableOpeningAnimation) var enableOpeningAnimation
    @Default(.animationSpeedMultiplier) var animationSpeedMultiplier

    var body: some View {
        Form {
            sizingSection
            behaviorSection
            gesturesSection
            windowSection
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
        .navigationTitle("Notch")
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    private var sizingSection: some View {
        Section {
            Picker(
                selection: $notchHeightMode,
                label:
                    Text("Notch height on notch displays")
            ) {
                Text("Match real notch height")
                    .tag(WindowHeightMode.matchRealNotchSize)
                Text("Match menu bar height")
                    .tag(WindowHeightMode.matchMenuBar)
                Text("Custom height")
                    .tag(WindowHeightMode.custom)
            }
            .onChange(of: notchHeightMode) {
                switch notchHeightMode {
                case .matchRealNotchSize:
                    // Get the actual notch height from the built-in display
                    notchHeight = getRealNotchHeight()
                case .matchMenuBar:
                    notchHeight = getMenuBarHeight(hasNotch: true)
                case .custom:
                    notchHeight = 38
                }
                NotificationCenter.default.post(
                    name: Notification.Name.notchHeightChanged, object: nil)
            }
            .settingsSearchAnchor(SearchKey.notchHeight)
            if notchHeightMode == .custom {
                Slider(value: $notchHeight, in: 15...45, step: 1) {
                    Text(
                        "Custom notch size - \(notchHeight, format: .number.precision(.fractionLength(0)))",
                        comment: "Slider label showing the custom notch height."
                    )
                }
                .onChange(of: notchHeight) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
            Picker("Notch height on non-notch displays", selection: $nonNotchHeightMode) {
                Text("Match menu bar height")
                    .tag(WindowHeightMode.matchMenuBar)
                Text("Custom height")
                    .tag(WindowHeightMode.custom)
            }
            .onChange(of: nonNotchHeightMode) {
                switch nonNotchHeightMode {
                case .matchMenuBar:
                    nonNotchHeight = getMenuBarHeight(hasNotch: false)
                case .matchRealNotchSize, .custom:
                    nonNotchHeight = 23
                }
                NotificationCenter.default.post(
                    name: Notification.Name.notchHeightChanged, object: nil)
            }
            .settingsSearchAnchor(SearchKey.nonNotchHeight)
            if nonNotchHeightMode == .custom {
                // Custom binding to skip values 1-14 (jump from 0 to 10)
                let sliderValue = Binding<Double>(
                    get: {
                        nonNotchHeight == 0 ? 0 : nonNotchHeight - 14
                    },
                    set: { newValue in
                        let oldValue = nonNotchHeight
                        nonNotchHeight = newValue == 0 ? 0 : newValue + 14
                        if oldValue != nonNotchHeight {
                            NotificationCenter.default.post(
                                name: Notification.Name.notchHeightChanged, object: nil)
                        }
                    }
                )

                Slider(value: sliderValue, in: 0...26, step: 1) {
                    Text(
                        "Custom notch size - \(nonNotchHeight, format: .number.precision(.fractionLength(0)))",
                        comment: "Slider label showing the custom notch height."
                    )
                }
            }
        } header: {
            Text("Sizing")
        }
    }

    private var behaviorSection: some View {
        Section {
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("Open notch on hover")
            }
            .settingsSearchAnchor(SearchKey.openOnHover)
            Defaults.Toggle(key: .enableHaptics) {
                Text("Enable haptic feedback")
            }
            .settingsSearchAnchor(SearchKey.haptics)
            Toggle("Remember last tab", isOn: $coordinator.openLastTabByDefault)
                .settingsSearchAnchor(SearchKey.rememberLastTab)
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Hover delay")
                        Spacer()
                        Text(
                            Measurement(
                                value: minimumHoverDuration,
                                unit: UnitDuration.seconds
                            ),
                            format: .measurement(
                                width: .narrow,
                                usage: .asProvided,
                                numberFormatStyle: .number.precision(
                                    .fractionLength(1)
                                )
                            )
                        )
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                .settingsSearchAnchor(SearchKey.hoverDelay)
            }
            Toggle("Notch animation", isOn: $enableOpeningAnimation)
                .settingsSearchAnchor(SearchKey.animation)
            if enableOpeningAnimation {
                Slider(value: $animationSpeedMultiplier, in: 0.1...2.01, step: 0.1) {
                    HStack {
                        Text("Animation speed")
                        Spacer()
                        Text(
                            "\(animationSpeedMultiplier, format: .number.precision(.fractionLength(1)))x",
                            comment: "Animation speed multiplier."
                        )
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsSearchAnchor(SearchKey.animationSpeed)
            }
            Defaults.Toggle(key: .compactMode) {
                Text("Compact mode")
            }
            .settingsSearchAnchor(SearchKey.compactMode)
        } header: {
            Text("Behavior")
        } footer: {
            Text("Shows a smaller opened notch with just the music player — no tabs, calendar or mirror.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var gesturesSection: some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Text("Enable gestures")
            }
                .disabled(!openNotchOnHover)
                .settingsSearchAnchor(SearchKey.gestures)
            if enableGestures {
                Defaults.Toggle(key: .enableHorizontalMediaGestures) {
                    Text("Change media with horizontal gestures")
                }
                .settingsSearchAnchor(SearchKey.horizontalMediaGestures)
                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text("Close gesture")
                }
                .settingsSearchAnchor(SearchKey.closeGesture)
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("Gesture sensitivity")
                        Spacer()
                        Text(
                            Defaults[.gestureSensitivity] == 100
                                ? "High" : Defaults[.gestureSensitivity] == 200 ? "Medium" : "Low"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                .settingsSearchAnchor(SearchKey.gestureSensitivity)
            }
            Defaults.Toggle(key: .normalizeGestureDirection) {
                Text("Normalize gesture direction")
            }
            .settingsSearchAnchor(SearchKey.normalizeGestureDirection)
        } header: {
            HStack {
                Text("Gestures")
                customBadge(text: "Beta")
            }
        } footer: {
            Text(
                "Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled"
            )
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    private var windowSection: some View {
        Section {
            Defaults.Toggle(key: .enableShadow) {
                Text("Enable window shadow")
            }
            .settingsSearchAnchor(SearchKey.shadow)
            Defaults.Toggle(key: .cornerRadiusScaling) {
                Text("Scale corner radius for closed notch")
            }
            .settingsSearchAnchor(SearchKey.cornerRadiusScaling)
            Defaults.Toggle(key: .extendHoverArea) {
                Text("Extend hover area")
            }
            .settingsSearchAnchor(SearchKey.extendHoverArea)
            Defaults.Toggle(key: .hideTitleBar) {
                Text("Hide title bar")
            }
            .settingsSearchAnchor(SearchKey.hideTitleBar)
            Defaults.Toggle(key: .showOnLockScreen) {
                Text("Show notch on lock screen")
            }
            .settingsSearchAnchor(SearchKey.showOnLockScreen)
            Defaults.Toggle(key: .hideFromScreenRecording) {
                Text("Hide from screen recording")
            }
            .settingsSearchAnchor(SearchKey.hideFromScreenRecording)
            Defaults.Toggle(key: .hideNonNotchedFromMissionControl) {
                Text("Hide windows on non-notch displays from Mission Control")
            }
            .settingsSearchAnchor(SearchKey.hideNonNotchedFromMissionControl)
        } header: {
            Text("Window")
        }
    }
}

extension NotchSettingsView {
    enum SearchKey: String, SettingsSearchKey {
        case notchHeight
        case nonNotchHeight
        case openOnHover
        case haptics
        case rememberLastTab
        case hoverDelay
        case animation
        case animationSpeed
        case compactMode
        case gestures
        case horizontalMediaGestures
        case closeGesture
        case gestureSensitivity
        case normalizeGestureDirection
        case shadow
        case cornerRadiusScaling
        case extendHoverArea
        case hideTitleBar
        case showOnLockScreen
        case hideFromScreenRecording
        case hideNonNotchedFromMissionControl

        static let tab = SettingsTab.notch

        var definition: SettingsSearchDefinition<Self> {
            switch self {
            case .notchHeight: .init("Notch height on notch displays", section: "Sizing")
            case .nonNotchHeight: .init("Notch height on non-notch displays", section: "Sizing")
            case .openOnHover: .init("Open notch on hover", section: "Behavior")
            case .haptics: .init("Enable haptic feedback", section: "Behavior")
            case .rememberLastTab: .init("Remember last tab", section: "Behavior")
            case .hoverDelay: .init("Hover delay", section: "Behavior", revealedBy: .openOnHover)
            case .animation: .init("Notch animation", section: "Behavior")
            case .animationSpeed: .init("Animation speed", section: "Behavior", revealedBy: .animation)
            case .compactMode: .init("Compact mode", section: "Behavior")
            case .gestures: .init("Enable gestures", section: "Gestures")
            case .horizontalMediaGestures:
                .init("Change media with horizontal gestures", section: "Gestures", revealedBy: .gestures)
            case .closeGesture: .init("Close gesture", section: "Gestures", revealedBy: .gestures)
            case .gestureSensitivity: .init("Gesture sensitivity", section: "Gestures", revealedBy: .gestures)
            case .normalizeGestureDirection: .init("Normalize gesture direction", section: "Gestures")
            case .shadow: .init("Enable window shadow", section: "Window")
            case .cornerRadiusScaling: .init("Scale corner radius for closed notch", section: "Window")
            case .extendHoverArea: .init("Extend hover area", section: "Window")
            case .hideTitleBar: .init("Hide title bar", section: "Window")
            case .showOnLockScreen: .init("Show notch on lock screen", section: "Window")
            case .hideFromScreenRecording: .init("Hide from screen recording", section: "Window")
            case .hideNonNotchedFromMissionControl:
                .init("Hide windows on non-notch displays from Mission Control", section: "Window")
            }
        }
    }
}
