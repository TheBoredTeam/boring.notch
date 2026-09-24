//
//  TerminalSettingsView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import Defaults
import SwiftUI

struct TerminalSettingsView: View {
    @Default(.enableTerminalFeature) private var isEnabled
    @Default(.terminalShellPath) private var shellPath
    @Default(.terminalFontFamily) private var fontFamily
    @Default(.terminalFontSize) private var fontSize
    @Default(.terminalOpacity) private var opacity
    @Default(.terminalCursorStyle) private var cursorStyle
    @Default(.terminalBackgroundColor) private var backgroundColor
    @Default(.terminalForegroundColor) private var foregroundColor
    @Default(.terminalCursorColor) private var cursorColor
    @Default(.terminalScrollbackLines) private var scrollbackLines
    @Default(.terminalOptionAsMeta) private var optionAsMeta
    @Default(.terminalMouseReporting) private var mouseReporting
    @Default(.terminalBoldAsBright) private var boldAsBright
    @Default(.terminalMaxHeightFraction) private var maxHeightFraction
    @Default(.terminalStickyMode) private var stickyMode

    private var monospacedFonts: [String] {
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return font.isFixedPitch
                || font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }
        .sorted()
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable terminal", isOn: $isEnabled)
                Toggle("Keep terminal open until clicked outside", isOn: $stickyMode)
                    .disabled(!isEnabled)
                Text("Commands run locally with your macOS account permissions. Only enable this feature on a computer you trust.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shell") {
                TextField("Shell path", text: $shellPath)
                Text("Restart the shell in the notch after changing this setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!isEnabled)

            Section("Appearance") {
                Picker("Font family", selection: $fontFamily) {
                    Text("System Monospaced").tag("")
                    ForEach(monospacedFonts, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                HStack {
                    Text("Font size")
                    Slider(value: $fontSize, in: 8...24, step: 1)
                    Text("\(Int(fontSize)) pt")
                        .monospacedDigit()
                }
                HStack {
                    Text("Maximum height")
                    Slider(value: $maxHeightFraction, in: 0.2...0.5, step: 0.05)
                    Text("\(Int(maxHeightFraction * 100))%")
                        .monospacedDigit()
                }
                HStack {
                    Text("Background opacity")
                    Slider(value: $opacity, in: 0.3...1, step: 0.05)
                    Text("\(Int(opacity * 100))%")
                        .monospacedDigit()
                }
                ColorPicker("Background", selection: $backgroundColor, supportsOpacity: false)
                ColorPicker("Foreground", selection: $foregroundColor, supportsOpacity: false)
                ColorPicker("Cursor", selection: $cursorColor, supportsOpacity: false)
                Picker("Cursor style", selection: $cursorStyle) {
                    ForEach(TerminalCursorStyleOption.allCases, id: \.rawValue) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
            }
            .disabled(!isEnabled)

            Section("Input and scrollback") {
                Toggle("Option as Meta key", isOn: $optionAsMeta)
                Toggle("Allow mouse reporting", isOn: $mouseReporting)
                Toggle("Bold text as bright colors", isOn: $boldAsBright)
                HStack {
                    Text("Scrollback lines")
                    Slider(
                        value: Binding(
                            get: { Double(scrollbackLines) },
                            set: { scrollbackLines = Int($0) }
                        ),
                        in: 100...10000,
                        step: 100
                    )
                    Text("\(scrollbackLines)")
                        .monospacedDigit()
                }
            }
            .disabled(!isEnabled)
        }
        .navigationTitle("Terminal")
        .onChange(of: isEnabled) { _, enabled in
            if !enabled && BoringViewCoordinator.shared.currentView == .terminal {
                BoringViewCoordinator.shared.currentView = .home
            }
        }
        .onChange(of: fontFamily) { _, _ in TerminalSessionManager.applyCurrentSettings() }
        .onChange(of: fontSize) { _, _ in TerminalSessionManager.applyCurrentSettings() }
        .onChange(of: opacity) { _, _ in TerminalSessionManager.applyCurrentSettings() }
        .onChange(of: cursorStyle) { _, _ in TerminalSessionManager.applyCurrentSettings() }
        .onChange(of: backgroundColor) { _, _ in TerminalSessionManager.applyCurrentSettings() }
        .onChange(of: foregroundColor) { _, _ in TerminalSessionManager.applyCurrentSettings() }
        .onChange(of: cursorColor) { _, _ in TerminalSessionManager.applyCurrentSettings() }
        .onChange(of: scrollbackLines) { _, _ in TerminalSessionManager.applyCurrentSettings() }
        .onChange(of: optionAsMeta) { _, _ in TerminalSessionManager.applyCurrentSettings() }
        .onChange(of: mouseReporting) { _, _ in TerminalSessionManager.applyCurrentSettings() }
        .onChange(of: boldAsBright) { _, _ in TerminalSessionManager.applyCurrentSettings() }
    }
}
