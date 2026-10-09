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
                if osdReplacementDefault {
                    Defaults.Toggle(key: .inlineOSD) {
                        Text("Use inline style")
                    }
                }
            }

            if osdReplacementDefault {
                Section(header: Text("Control Sources"), footer: Text("Select which provider to use for system controls. BetterDisplay and Lunar require their respective apps to be installed and running.")) {
                    Picker("Brightness Source", selection: $osdBrightnessSourceDefault) {
                        ForEach(OSDControlSource.allCases) { source in
                            Text(source.localizedString).tag(source)
                        }
                    }
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
                    Defaults.Toggle(key: .systemEventIndicatorShadow) {
                        Text("Show shadow")
                    }
                    Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                        Text("Use accent color")
                    }
                }

                Section(header: Text("Visibility")) {
                    Defaults.Toggle(key: .showOpenNotchOSD) {
                        Text("Show OSD in open notch")
                    }
                    if showOpenNotchOSDDefault {
                        Defaults.Toggle(key: .showOpenNotchOSDPercentage) {
                            Text("Show percentage (open notch)")
                        }
                    }
                    Defaults.Toggle(key: .showClosedNotchOSDPercentage) {
                        Text("Show percentage (closed notch)")
                    }
                }

                Section(header: Text("Interaction")) {
                    Picker("Option (⌥) Key Behavior", selection: $optionKeyActionDefault) {
                        ForEach(OptionKeyAction.allCases) { action in
                            Text(action.localizedString).tag(action)
                        }
                    }
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

#Preview {
    OSDSettings()
        .frame(width: 500, height: 600)
}
