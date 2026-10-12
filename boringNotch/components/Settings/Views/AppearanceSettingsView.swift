//
//  AppearanceSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.enableLiquidGlass) var enableLiquidGlass
    @Default(.glassRefraction) var glassRefraction
    @Default(.glassBlur) var glassBlur
    @Default(.glassDispersion) var glassDispersion
    @Default(.glassLensHeight) var glassLensHeight
    @Default(.glassCoreHeight) var glassCoreHeight
    @Default(.glassFadeSoftness) var glassFadeSoftness
    @Default(.glassFloorTransparency) var glassFloorTransparency
    @Default(.useCustomAccentColor) var useCustomAccentColor
    @Default(.customAccentColorData) var customAccentColorData
    @State private var customAccentColor: Color = .accentColor
    @State private var selectedPresetColor: PresetAccentColor?
    @State private var showGlassTuning = true

    var body: some View {
        Form {
            accentColorSection
            liquidGlassSection
            notchChromeSection
            idleSection
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Appearance")
        .onAppear {
            initializeAccentColorState()
        }
    }

    private var accentColorSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                // Toggle between system and custom
                Picker("Accent color", selection: $useCustomAccentColor) {
                    Text("System").tag(false)
                    Text("Custom").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: useCustomAccentColor) {
                    if useCustomAccentColor {
                        loadCustomColor()
                    }
                }

                if !useCustomAccentColor {
                    // System accent info
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            AccentCircleButton(
                                isSelected: true,
                                color: .accentColor,
                                isSystemDefault: true
                            ) {}

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Using System Accent")
                                    .font(.body)
                                Text("Your macOS system accent color")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                } else {
                    // Custom color options
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Color Presets")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ForEach(PresetAccentColor.allCases) { preset in
                                AccentCircleButton(
                                    isSelected: selectedPresetColor == preset,
                                    color: preset.color,
                                    isMulticolor: false
                                ) {
                                    selectedPresetColor = preset
                                    customAccentColor = preset.color
                                    saveCustomColor(preset.color)
                                    forceUiUpdate()
                                }
                            }
                            Spacer()
                        }

                        Divider()
                            .padding(.vertical, 4)

                        // Custom color picker
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pick a Color")
                                    .font(.body)
                                Text("Choose any color")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            ColorPicker(selection: Binding(
                                get: { customAccentColor },
                                set: { newColor in
                                    customAccentColor = newColor
                                    selectedPresetColor = nil
                                    saveCustomColor(newColor)
                                    forceUiUpdate()
                                }
                            ), supportsOpacity: false) {
                                ZStack {
                                    Circle()
                                        .fill(customAccentColor)
                                        .frame(width: 32, height: 32)

                                    if selectedPresetColor == nil {
                                        Circle()
                                            .strokeBorder(.primary.opacity(0.3), lineWidth: 2)
                                            .frame(width: 32, height: 32)
                                    }
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Accent color")
        } footer: {
            Text("Choose between your system accent color or customize it with your own selection.")
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private var notchChromeSection: some View {
        Section {
            Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
            Defaults.Toggle(key: .settingsIconInNotch) {
                Text("Show settings icon in notch")
            }
        } header: {
            Text("Notch chrome")
        }
    }

    private var liquidGlassSection: some View {
        Section {
            Defaults.Toggle(key: .enableLiquidGlass) {
                Text(
                    "Liquid Glass background",
                    comment: "Toggle for the Liquid Glass open notch background."
                )
            }
            .disabled(!LiquidGlassAvailability.isSupported)

            if enableLiquidGlass && LiquidGlassAvailability.isSupported {
                DisclosureGroup(isExpanded: $showGlassTuning) {
                    VStack(spacing: 12) {
                        parameterSlider(
                            "Refraction",
                            comment: "Liquid Glass parameter controlling how much the background bends.",
                            value: $glassRefraction,
                            range: LiquidGlassParameters.refractionRange,
                            step: 1,
                            display: "\(Int(glassRefraction))"
                        )
                        parameterSlider(
                            "Blur",
                            comment: "Liquid Glass parameter controlling how much the background is blurred.",
                            value: $glassBlur,
                            range: LiquidGlassParameters.blurRange,
                            step: 0.5,
                            display: String(format: "%.1f", glassBlur)
                        )
                        parameterSlider(
                            "Dispersion",
                            comment: "Liquid Glass parameter controlling the chromatic split along the edge.",
                            value: $glassDispersion,
                            range: LiquidGlassParameters.dispersionRange,
                            step: 1,
                            display: "\(Int(glassDispersion))"
                        )
                        parameterSlider(
                            "Lens height",
                            comment: "Liquid Glass parameter controlling how far the refraction reaches inward.",
                            value: $glassLensHeight,
                            range: LiquidGlassParameters.lensHeightRange,
                            step: 1,
                            display: "\(Int(glassLensHeight)) pt"
                        )
                        parameterSlider(
                            "Camera core height",
                            comment: "Liquid Glass parameter controlling the solid black region over the camera housing.",
                            value: $glassCoreHeight,
                            range: LiquidGlassParameters.coreHeightRange,
                            step: 1,
                            display: "\(Int(glassCoreHeight)) pt"
                        )
                        parameterSlider(
                            "Fade softness",
                            comment: "Liquid Glass parameter controlling how gradually the black region fades out.",
                            value: $glassFadeSoftness,
                            range: LiquidGlassParameters.fadeSoftnessRange,
                            step: 1,
                            display: "\(Int(glassFadeSoftness)) pt"
                        )
                        parameterSlider(
                            "Floor transparency",
                            comment: "Liquid Glass parameter controlling how dark the bottom of the surface stays.",
                            value: $glassFloorTransparency,
                            range: LiquidGlassParameters.floorTransparencyRange,
                            step: 0.01,
                            display: "\(Int(glassFloorTransparency * 100))%"
                        )
                    }
                    .padding(.vertical, 6)
                } label: {
                    Text("Tuning", comment: "Disclosure label for the Liquid Glass parameter sliders.")
                }
            }
        } header: {
            Text("Liquid Glass")
        } footer: {
            Text(
                LiquidGlassAvailability.isSupported
                    ? "Liquid Glass refracts the desktop along the open notch's edge. The closed notch stays black to blend with the camera housing."
                    : "Liquid Glass requires macOS 26 or later.",
                comment: "Footer explaining the Liquid Glass notch background."
            )
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    private func parameterSlider(
        _ title: LocalizedStringKey,
        comment: StaticString,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title, comment: comment)
                Spacer()
                Text(display)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private var idleSection: some View {
        Section {
            Defaults.Toggle(key: .showNotHumanFace) {
                Text("Show cool face animation while inactive")
            }
        } header: {
            Text("Idle state")
        }
    }

    private func forceUiUpdate() {
        // Force refresh the UI
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .accentColorChanged, object: nil)
        }
    }

    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = colorData
            forceUiUpdate()
        }
    }

    private func loadCustomColor() {
        if let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            customAccentColor = Color(nsColor: nsColor)

            // Check if loaded color matches a preset
            selectedPresetColor = nil
            for preset in PresetAccentColor.allCases {
                if colorsAreEqual(Color(nsColor: nsColor), preset.color) {
                    selectedPresetColor = preset
                    break
                }
            }
        }
    }

    private func colorsAreEqual(_ color1: Color, _ color2: Color) -> Bool {
        let nsColor1 = NSColor(color1).usingColorSpace(.sRGB) ?? NSColor(color1)
        let nsColor2 = NSColor(color2).usingColorSpace(.sRGB) ?? NSColor(color2)

        return abs(nsColor1.redComponent - nsColor2.redComponent) < 0.01 &&
               abs(nsColor1.greenComponent - nsColor2.greenComponent) < 0.01 &&
               abs(nsColor1.blueComponent - nsColor2.blueComponent) < 0.01
    }

    private func initializeAccentColorState() {
        if !useCustomAccentColor {
            selectedPresetColor = nil // Multicolor is selected when useCustomAccentColor is false
        } else {
            loadCustomColor()
        }
    }
}

// MARK: - Accent color presets

/// macOS-style accent color presets shared by the Appearance settings.
enum PresetAccentColor: String, CaseIterable, Identifiable {
    case blue = "Blue"
    case purple = "Purple"
    case pink = "Pink"
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case graphite = "Graphite"

    var id: String { self.rawValue }

    var color: Color {
        switch self {
        case .blue: return Color(red: 0.0, green: 0.478, blue: 1.0)
        case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)
        case .pink: return Color(red: 1.0, green: 0.176, blue: 0.333)
        case .red: return Color(red: 1.0, green: 0.271, blue: 0.227)
        case .orange: return Color(red: 1.0, green: 0.584, blue: 0.0)
        case .yellow: return Color(red: 1.0, green: 0.8, blue: 0.0)
        case .green: return Color(red: 0.4, green: 0.824, blue: 0.176)
        case .graphite: return Color(red: 0.557, green: 0.557, blue: 0.576)
        }
    }
}

// MARK: - Accent Circle Button Component
struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    var isSystemDefault: Bool = false
    var isMulticolor: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Color circle
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)

                // Subtle border
                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    .frame(width: 32, height: 32)

                // Apple-style highlight ring around the middle when selected
                if isSelected {
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.5),
                            lineWidth: 2
                        )
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isSystemDefault ? "Use your macOS system accent color" : "")
    }
}
