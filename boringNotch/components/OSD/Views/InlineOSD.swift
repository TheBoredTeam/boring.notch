// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

//
//  InlineOSD.swift
//  boringNotch
//
//  Created by Richard Kunkli on 14/09/2024.
//

import SwiftUI
import Defaults

struct InlineOSD: View {
    @EnvironmentObject var vm: BoringViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var accent: Color?
    @Binding var hoverAnimation: Bool
    @Binding var gestureProgress: CGFloat

    var body: some View {
        let width = max(0, 100 - (hoverAnimation ? 0 : 12) + gestureProgress / 2)
        let height = vm.closedNotchSize.height + (hoverAnimation ? 8 : 0)
        NotchActivityHost(
            contentID: "inline-osd",
            safeAreaWidth: vm.closedNotchSize.width,
            height: height,
            maximumWidth: windowSize.width - 2 * cornerRadiusInsets.closed.bottom
        ) {
            InlineOSDLeading(type: type, value: value, icon: icon, accent: accent, width: width, height: height)
        } trailing: {
            InlineOSDTrailing(type: type, value: $value, accent: accent, width: width, height: height)
        }
    }
}

/// OSD content regions intentionally know nothing about the camera safe area.
struct InlineOSDLeading: View {
    let type: SneakContentType
    let value: CGFloat
    let icon: String
    let accent: Color?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 5) {
            OSDIconView(eventType: type, icon: icon, value: value, accent: accent)
            Text(osdTypeName(type))
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .allowsTightening(true)
                .contentTransition(.numericText())
        }
        .frame(width: width, height: height, alignment: .leading)
    }

    func osdTypeName(_ type: SneakContentType) -> String {
        switch type {
            case .volume:
                return NSLocalizedString("Volume", comment: "")
            case .brightness:
                return NSLocalizedString("Brightness", comment: "")
            case .backlight:
                return NSLocalizedString("Backlight", comment: "")
            case .mic:
                return NSLocalizedString("Mic", comment: "")
            default:
                return ""
        }
    }
}

struct InlineOSDTrailing: View {
    let type: SneakContentType
    @Binding var value: CGFloat
    let accent: Color?
    let width: CGFloat
    let height: CGFloat
    @Default(.showClosedNotchOSDPercentage) private var showPercentage

    var body: some View {
        HStack {
            if type == .mic {
                Text(value.isZero ? "muted" : "unmuted")
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentTransition(.interpolate)
            } else {
                DraggableProgressBar(value: $value, onChange: { newValue in
                    if type == .volume {
                        VolumeManager.shared.setAbsolute(Float32(newValue))
                    } else if type == .brightness {
                        BrightnessManager.shared.setAbsolute(value: Float32(newValue))
                    }
                }, accentColor: accent, compact: true)
                .frame(maxWidth: .infinity)
                if type == .volume && value.isZero {
                    Text("muted").modifier(OSDValueStyle())
                } else if showPercentage {
                    Text(value, format: .percent.precision(.fractionLength(0)))
                        .modifier(OSDValueStyle())
                }
            }
        }
        .padding(.trailing, 4)
        .frame(width: width, height: height)
    }
}

private struct OSDValueStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.gray)
            .lineLimit(1)
            .allowsTightening(true)
            .multilineTextAlignment(.trailing)
    }
}

#Preview {
    InlineOSD(type: .constant(.brightness), value: .constant(0.4), icon: .constant(""), accent: .constant(nil), hoverAnimation: .constant(false), gestureProgress: .constant(0))
        .padding(.horizontal, 8)
        .background(Color.black)
        .padding()
        .environmentObject(BoringViewModel(camera: CameraModel()))
}
