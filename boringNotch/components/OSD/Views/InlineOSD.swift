//
//  InlineOSD.swift
//  boringNotch
//
//  Created by Richard Kunkli on 14/09/2024.
//

import Defaults
import SwiftUI

struct InlineOSDLeadingView: View {
    let type: SneakContentType
    let value: CGFloat
    let icon: String
    let accent: Color?

    var body: some View {
        HStack(spacing: 5) {
            OSDIconView(eventType: type, icon: icon, value: value, accent: accent)

            Text(type.localizedOSDName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .allowsTightening(true)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InlineOSDTrailingView: View {
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    let accent: Color?

    var body: some View {
        Group {
            if type == .mic {
                Text(value.isZero ? "muted" : "unmuted")
                    .foregroundStyle(.gray)
                    .contentTransition(.interpolate)
            } else {
                HStack {
                    DraggableProgressBar(
                        value: $value,
                        onChange: updateSystemValue,
                        accentColor: accent,
                        compact: true
                    )
                    .frame(maxWidth: .infinity)

                    valueLabel
                }
            }
        }
        .lineLimit(1)
        .allowsTightening(true)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 4)
    }

    @ViewBuilder
    private var valueLabel: some View {
        if type == .volume && value.isZero {
            Text("muted")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.gray)
        } else if Defaults[.showClosedNotchOSDPercentage] {
            Text("\(Int(value * 100))%")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.gray)
        }
    }

    private func updateSystemValue(_ newValue: CGFloat) {
        switch type {
        case .volume:
            VolumeManager.shared.setAbsolute(Float32(newValue))
        case .brightness:
            BrightnessManager.shared.setAbsolute(value: Float32(newValue))
        default:
            break
        }
    }
}

private extension SneakContentType {
    var localizedOSDName: String {
        switch self {
        case .volume:
            NSLocalizedString("Volume", comment: "")
        case .brightness:
            NSLocalizedString("Brightness", comment: "")
        case .backlight:
            NSLocalizedString("Backlight", comment: "")
        case .mic:
            NSLocalizedString("Mic", comment: "")
        default:
            ""
        }
    }
}
