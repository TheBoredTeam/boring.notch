//
//  TodoSettingsView.swift
//  boringNotch
//
//  Created by Sidharth Sangelia on 12/07/26.
//


import Defaults
import SwiftUI

private enum TodoCheckboxPreset: String, CaseIterable, Identifiable {
    case white = "White"
    case lavender = "Lavender"
    case sky = "Sky"
    case mint = "Mint"
    case sage = "Sage"
    case butter = "Butter"
    case peach = "Peach"
    case rose = "Rose"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .white: return .white
        case .lavender: return Color(red: 0.78, green: 0.75, blue: 0.95)
        case .sky: return Color(red: 0.70, green: 0.85, blue: 0.98)
        case .mint: return Color(red: 0.72, green: 0.93, blue: 0.82)
        case .sage: return Color(red: 0.75, green: 0.85, blue: 0.72)
        case .butter: return Color(red: 0.98, green: 0.90, blue: 0.65)
        case .peach: return Color(red: 0.98, green: 0.80, blue: 0.70)
        case .rose: return Color(red: 0.97, green: 0.75, blue: 0.80)
        }
    }
}

struct TodoSettings: View {
    @Default(.showTodosTab) var showTodosTab: Bool
    @Default(.todosCheckboxColor) var todosCheckboxColor: Color
    @Default(.todosAutoRemoveDelay) var todosAutoRemoveDelay: Double

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showTodosTab) {
                    Text("Show Todos tab")
                }

                VStack(alignment: .leading) {
                    Slider(value: $todosAutoRemoveDelay, in: 1...5, step: 0.5) {
                        Text("Auto-remove delay - \(todosAutoRemoveDelay, specifier: "%.1f")s")
                    }
                }
            } header: {
                Text("General")
            } footer: {
                Text(
                    "Checking a todo off removes it automatically after this delay. Unchecking it before then cancels the removal."
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ForEach(TodoCheckboxPreset.allCases) { preset in
                            AccentCircleButton(
                                isSelected: colorsMatch(todosCheckboxColor, preset.color),
                                color: preset.color
                            ) {
                                todosCheckboxColor = preset.color
                            }
                            .help(preset.rawValue)
                        }
                    }

                    Divider()
                        .padding(.vertical, 4)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Custom color")
                                .font(.body)
                            Text("Pick anything")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ColorPicker("", selection: $todosCheckboxColor, supportsOpacity: false)
                            .labelsHidden()
                    }
                }
            } header: {
                Text("Checkbox color")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Todos")
    }

    /// Compares by RGB components rather than Color equality, since a value
    /// round-tripped through Defaults persistence can lose exact identity.
    private func colorsMatch(_ a: Color, _ b: Color) -> Bool {
        let na = NSColor(a).usingColorSpace(.deviceRGB)
        let nb = NSColor(b).usingColorSpace(.deviceRGB)
        guard let na, let nb else { return false }
        return abs(na.redComponent - nb.redComponent) < 0.01
            && abs(na.greenComponent - nb.greenComponent) < 0.01
            && abs(na.blueComponent - nb.blueComponent) < 0.01
    }
}
