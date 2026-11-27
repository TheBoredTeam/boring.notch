//
//  OSDSettingsView.swift
//  boringNotch
//
//  Created by Alexander on 2026-02-07.
//

import SwiftUI
import Defaults
import CoreGraphics

struct OSDSettings: View {
    // Defaults-backed storage
    @Default(.osdReplacement) private var osdReplacementDefault
    @Default(.showOpenNotchOSD) private var showOpenNotchOSDDefault
    @Default(.optionKeyAction) private var optionKeyActionDefault
    @Default(.osdBrightnessSource) private var osdBrightnessSourceDefault
    @Default(.osdVolumeSource) private var osdVolumeSourceDefault
    @State private var isAccessibilityAuthorized = true
    @State private var menuBarBrightnessSupported = true
    @ObservedObject private var xpcClient = XPCHelperClient.shared

    var body: some View {
        Form {
            Section(header: Text("General")) {
                Defaults.Toggle(key: .osdReplacement) {
                    Text("Replace System OSD")
                }
                .settingsSearchAnchor(SearchKey.replaceSystemOSD)
                if osdReplacementDefault {
                    Defaults.Toggle(key: .inlineOSD) {
                        Text("Use inline style")
                    }
                    .settingsSearchAnchor(SearchKey.inlineStyle)
                }
            }

            if osdReplacementDefault {
                Section(header: Text("Control Sources"), footer: Text("Select which provider to use for system controls. BetterDisplay and Lunar require their respective apps to be installed and running.")) {
                    Picker("Brightness Source", selection: $osdBrightnessSourceDefault) {
                        ForEach(OSDControlSource.allCases) { source in
                            Text(source.localizedString).tag(source)
                        }
                    }
                    .settingsSearchAnchor(SearchKey.brightnessSource)
                    if osdBrightnessSourceDefault == .builtin {
                        HelpText("Only Apple displays are supported. In multi-display setups, the brightness OSD appears on the active display if supported, or on another supported display otherwise.")
                    }
                    if osdBrightnessSourceDefault == .betterDisplay && !BetterDisplayManager.shared.isBetterDisplayAvailable {
                        HelpText("BetterDisplay is not installed or not running")
                    }
                    if osdBrightnessSourceDefault == .lunar && !LunarManager.shared.isLunarAvailable {
                        HelpText("Lunar is not installed or not reachable")
                    }

                    Picker("Volume Source", selection: $osdVolumeSourceDefault) {
                        // Lunar does not support volume control so hide it from the picker
                        ForEach(OSDControlSource.allCases.filter { $0 != .lunar }) { source in
                            Text(source.localizedString).tag(source)
                        }
                    }
                    .settingsSearchAnchor(SearchKey.volumeSource)
                    if osdVolumeSourceDefault == .betterDisplay && !BetterDisplayManager.shared.isBetterDisplayAvailable {
                        HelpText("BetterDisplay is not installed or not running")
                    }

                    LabeledContent("Keyboard Source") {
                        Text(OSDControlSource.builtin.localizedString)
                            .foregroundStyle(.secondary)
                    }
                    HelpText("Keyboard brightness currently supports the built-in source only.")
                    if !xpcClient.helperAvailable {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title)
                                .foregroundStyle(.yellow)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "Helper Service Unavailable"))
                                    .font(.headline)
                                Text(String(localized: "The background helper crashed or was closed by macOS. It restarts automatically on the next OSD event."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    if !isAccessibilityAuthorized {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: AccessibilityPermission.systemImageName)
                                .font(.title)
                                .foregroundStyle(Color.effectiveAccent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(AccessibilityPermission.displayName) Required")
                                    .font(.headline)
                                Text("Grant \(AccessibilityPermission.displayName) so built-in keyboard brightness controls can be intercepted.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Grant Access") {
                                Task {
                                    let granted = await MediaKeyInterceptor.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
                                    await MainActor.run {
                                        isAccessibilityAuthorized = granted
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(header: Text("Appearance")) {
                    Defaults.Toggle(key: .enableGradient) {
                        Text("Enable gradient")
                    }
                    .settingsSearchAnchor(SearchKey.gradient)
                    Defaults.Toggle(key: .systemEventIndicatorShadow) {
                        Text("Show shadow")
                    }
                    .settingsSearchAnchor(SearchKey.shadow)
                    Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                        Text("Use accent color")
                    }
                    .settingsSearchAnchor(SearchKey.accentColor)
                }

                Section(header: Text("Visibility")) {
                    Defaults.Toggle(key: .showOpenNotchOSD) {
                        Text("Show OSD in open notch")
                    }
                    .settingsSearchAnchor(SearchKey.openNotchOSD)
                    if showOpenNotchOSDDefault {
                        Defaults.Toggle(key: .showOpenNotchOSDPercentage) {
                            Text("Show percentage (open notch)")
                        }
                        .settingsSearchAnchor(SearchKey.openNotchPercentage)
                    }
                    Defaults.Toggle(key: .showClosedNotchOSDPercentage) {
                        Text("Show percentage (closed notch)")
                    }
                    .settingsSearchAnchor(SearchKey.closedNotchPercentage)
                }

                Section(header: Text("Interaction")) {
                    Picker("Option (⌥) Key Behavior", selection: $optionKeyActionDefault) {
                        ForEach(OptionKeyAction.allCases) { action in
                            Text(action.localizedString).tag(action)
                        }
                    }
                    .settingsSearchAnchor(SearchKey.optionKeyBehavior)
                    HelpText("Define what happens when you hold the Option key while pressing media keys.")
                }
            }
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
        .task(id: osdReplacementDefault) {
            guard osdReplacementDefault else { return }
            isAccessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notif in
            if let granted = notif.userInfo?["granted"] as? Bool {
                isAccessibilityAuthorized = granted
            }
        }
        .task(id: osdBrightnessSourceDefault) {
            if osdBrightnessSourceDefault == .builtin {
                if let displayID = await XPCHelperClient.shared.displayIDForBrightness() {
                    let menuID = NSScreen.main?.cgDisplayID ?? CGMainDisplayID()
                    menuBarBrightnessSupported = (displayID == menuID)
                } else {
                    menuBarBrightnessSupported = false
                }
            } else {
                menuBarBrightnessSupported = true
            }
        }
    }
}

extension OSDSettings {
    enum SearchKey: String, SettingsSearchKey {
        case replaceSystemOSD
        case inlineStyle
        case brightnessSource
        case volumeSource
        case gradient
        case shadow
        case accentColor
        case openNotchOSD
        case openNotchPercentage
        case closedNotchPercentage
        case optionKeyBehavior

        static let tab = SettingsTab.osd

        var definition: SettingsSearchDefinition<Self> {
            switch self {
            case .replaceSystemOSD:
                .init(
                    "Replace System OSD", section: "General",
                    keywords: [.init("HUD", comment: "Search keyword for the OSD settings."), "Volume", "Brightness"])
            case .inlineStyle: .init("Use inline style", section: "General", revealedBy: .replaceSystemOSD)
            case .brightnessSource:
                .init("Brightness Source", section: "Control Sources", revealedBy: .replaceSystemOSD)
            case .volumeSource:
                .init("Volume Source", section: "Control Sources", revealedBy: .replaceSystemOSD)
            case .gradient: .init("Enable gradient", section: "Appearance", revealedBy: .replaceSystemOSD)
            case .shadow: .init("Show shadow", section: "Appearance", revealedBy: .replaceSystemOSD)
            case .accentColor: .init("Use accent color", section: "Appearance", revealedBy: .replaceSystemOSD)
            case .openNotchOSD:
                .init("Show OSD in open notch", section: "Visibility", revealedBy: .replaceSystemOSD)
            case .openNotchPercentage:
                .init("Show percentage (open notch)", section: "Visibility", revealedBy: .openNotchOSD)
            case .closedNotchPercentage:
                .init("Show percentage (closed notch)", section: "Visibility", revealedBy: .replaceSystemOSD)
            case .optionKeyBehavior:
                .init("Option (⌥) Key Behavior", section: "Interaction", revealedBy: .replaceSystemOSD)
            }
        }
    }
}

#Preview {
    OSDSettings()
        .frame(width: 500, height: 600)
}
