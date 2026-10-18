// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

//
//  InlineHUDs.swift
//  boringNotch
//
//  Created by Richard Kunkli on 14/09/2024.
//

import SwiftUI
import Defaults

struct InlineHUD: View {
    @EnvironmentObject var vm: BoringViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var hoverAnimation: Bool
    @Binding var gestureProgress: CGFloat
    var body: some View {
        let width = max(0, 100 - (hoverAnimation ? 0 : 12) + gestureProgress / 2)
        let height = vm.closedNotchSize.height + (hoverAnimation ? 8 : 0)
        NotchActivityHost(
            contentID: "inline-hud",
            safeAreaWidth: vm.closedNotchSize.width,
            height: height,
            maximumWidth: windowSize.width - 2 * cornerRadiusInsets.closed.bottom
        ) {
            InlineHUDLeading(type: type, value: value, icon: icon, width: width, height: height)
        } trailing: {
            InlineHUDTrailing(type: type, value: $value, width: width, height: height)
        }
    }
}

/// System content supplies two bounded regions; the host owns camera clearance.
struct InlineHUDLeading: View {
    let type: SneakContentType
    let value: CGFloat
    let icon: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 5) {
            Group {
                switch type {
                case .volume:
                    if icon.isEmpty {
                        Image(systemName: speakerSymbol)
                            .contentTransition(.interpolate)
                            .symbolVariant(value > 0 ? .none : .slash)
                    } else {
                        Image(systemName: icon)
                            .contentTransition(.interpolate)
                            .opacity(value.isZero ? 0.6 : 1)
                            .scaleEffect(value.isZero ? 0.85 : 1)
                    }
                case .brightness:
                    Image(systemName: value > 0.6 ? "sun.max" : "sun.min")
                        .contentTransition(.interpolate)
                case .backlight:
                    Image(systemName: value > 0.5 ? "light.max" : "light.min")
                        .contentTransition(.interpolate)
                case .mic:
                    Image(systemName: "mic")
                        .symbolRenderingMode(.hierarchical)
                        .symbolVariant(value > 0 ? .none : .slash)
                        .contentTransition(.interpolate)
                default:
                    EmptyView()
                }
            }
            .frame(width: 20, height: 15)
            .foregroundStyle(.white)
            .symbolVariant(.fill)
            .accessibilityHidden(true)

            Text(typeName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .allowsTightening(true)
                .contentTransition(.numericText())
        }
        .frame(width: width, height: height, alignment: .leading)
    }

    private var speakerSymbol: String {
        switch value {
        case 0: "speaker"
        case 0...0.3: "speaker.wave.1"
        case 0.3...0.8: "speaker.wave.2"
        case 0.8...1: "speaker.wave.3"
        default: "speaker.wave.2"
        }
    }

    private var typeName: String {
        switch type {
        case .volume: "Volume"
        case .brightness: "Brightness"
        case .backlight: "Backlight"
        case .mic: "Mic"
        default: ""
        }
    }
}

struct InlineHUDTrailing: View {
    let type: SneakContentType
    @Binding var value: CGFloat
    let width: CGFloat
    let height: CGFloat
    @Default(.showClosedNotchHUDPercentage) private var showPercentage

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
                })
                .frame(maxWidth: .infinity)
                if type == .volume && value.isZero {
                    Text("muted").modifier(HUDValueStyle())
                } else if showPercentage {
                    Text("\(Int(value * 100))%").modifier(HUDValueStyle())
                }
            }
        }
        .padding(.trailing, 4)
        .frame(width: width, height: height)
    }
}

private struct HUDValueStyle: ViewModifier {
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
    InlineHUD(type: .constant(.brightness), value: .constant(0.4), icon: .constant(""), hoverAnimation: .constant(false), gestureProgress: .constant(0))
        .padding(.horizontal, 8)
        .background(Color.black)
        .padding()
        .environmentObject(BoringViewModel())
}
