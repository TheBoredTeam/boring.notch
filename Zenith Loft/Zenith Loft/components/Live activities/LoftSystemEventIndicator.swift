//
//  LoftSystemEventIndicator.swift
//  Zenith Loft (LoftOS)
//
//  Clean-room replacement of `SystemEventIndicatorModifier.swift`.
//  - No `Defaults` dependency (uses @AppStorage keys with safe defaults)
//  - No `BoringViewModel` dependency
//  - Same external API (bindings + sendEventBack closure)
//

import SwiftUI
import AppKit

// MARK: - AppStorage-backed prefs (replace defaults to taste)
private enum LoftSysEventPrefs {
    @AppStorage("loft_enableGradient")              static var enableGradient: Bool = true
    @AppStorage("loft_indicatorUseAccent")          static var useAccent: Bool = true
    @AppStorage("loft_indicatorShadow")             static var showShadow: Bool = true
    @AppStorage("loft_inlineHUD")                   static var inlineHUD: Bool = true
}

// Utility so we can lighten a color a bit if needed
private extension Color {
    func ensureMinimumBrightness(factor: CGFloat) -> Color {
        // simple blend towards white to guarantee minimum brightness
        let f = max(0, min(1, factor))
        return self.opacity(1 - f).overlay(Color.white.opacity(f))
    }
}

// MARK: - Main indicator view (formerly SystemEventIndicatorModifier)
/// Bindings + callback match the original so you can use it the same way.
struct LoftSystemEventIndicator: View {
    @Binding var eventType: SneakContentType
    @Binding var value: CGFloat {
        didSet {
            // reflect value immediately to the caller
            DispatchQueue.main.async { self.sendEventBack(value) }
        }
    }
    @Binding var icon: String
    var sendEventBack: (CGFloat) -> Void

    private func speakerSymbol(_ value: CGFloat) -> String {
        switch value {
        case 0:           return "speaker.slash"
        case 0...0.3:     return "speaker.wave.1"
        case 0.3...0.8:   return "speaker.wave.2"
        case 0.8...1.0:   return "speaker.wave.3"
        default:          return "speaker.wave.2"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            switch eventType {
            case .volume:
                if icon.isEmpty {
                    Image(systemName: speakerSymbol(value))
                        .contentTransition(.interpolate)
                        .symbolVariant(value > 0 ? .none : .slash)
                        .frame(width: 20, height: 15, alignment: .leading)
                } else {
                    Image(systemName: icon)
                        .contentTransition(.interpolate)
                        .opacity(value.isZero ? 0.6 : 1)
                        .scaleEffect(value.isZero ? 0.85 : 1)
                        .frame(width: 20, height: 15, alignment: .leading)
                }

            case .brightness:
                Image(systemName: "sun.max.fill")
                    .contentTransition(.symbolEffect)
                    .frame(width: 20, height: 15)
                    .foregroundStyle(.white)

            case .backlight:
                Image(systemName: "keyboard")
                    .contentTransition(.symbolEffect)
                    .frame(width: 20, height: 15)
                    .foregroundStyle(.white)

            case .mic:
                Image(systemName: "mic")
                    .symbolVariant(value > 0 ? .none : .slash)
                    .contentTransition(.interpolate)
                    .frame(width: 20, height: 15)
                    .foregroundStyle(.white)

            default:
                EmptyView()
            }

            if eventType != .mic {
                LoftDraggableProgressBar(value: $value)
            } else {
                Text("Mic \(value > 0 ? "unmuted" : "muted")")
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .allowsTightening(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .symbolVariant(.fill)
        .imageScale(.large)
    }
}

// MARK: - Draggable progress bar (formerly DraggableProgressBar)
struct LoftDraggableProgressBar: View {
    @Binding var value: CGFloat

    @State private var isDragging = false

    var body: some View {
        VStack {
            GeometryReader { geo in
                ZStack(alignment: .leading) {

                    Capsule()
                        .fill(.tertiary)

                    Capsule()
                        .fill(fillStyle)
                        .frame(width: max(0, min(geo.size.width * value, geo.size.width)))
                        .shadow(color: LoftSysEventPrefs.showShadow ? shadowColor : .clear,
                                radius: 8, x: 3)
                        .opacity(value.isZero ? 0 : 1)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            withAnimation(.smooth(duration: 0.3)) {
                                isDragging = true
                                updateValue(gesture: gesture, in: geo)
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.smooth(duration: 0.3)) {
                                isDragging = false
                            }
                        }
                )
            }
            .frame(height: LoftSysEventPrefs.inlineHUD ? (isDragging ? 8 : 5)
                                                       : (isDragging ? 9 : 6))
        }
    }

    private var fillStyle: AnyShapeStyle {
        if LoftSysEventPrefs.enableGradient {
            let base = LoftSysEventPrefs.useAccent ? Color.accentColor : Color.white
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        base,
                        base.ensureMinimumBrightness(factor: LoftSysEventPrefs.useAccent ? 0.2 : 0.0)
                    ],
                    startPoint: .trailing,
                    endPoint: .leading
                )
            )
        } else {
            return AnyShapeStyle(LoftSysEventPrefs.useAccent ? Color.accentColor : Color.white)
        }
    }

    private var shadowColor: Color {
        if LoftSysEventPrefs.useAccent {
            return Color.accentColor.ensureMinimumBrightness(factor: 0.7)
        } else {
            return .white
        }
    }

    private func updateValue(gesture: DragGesture.Value, in geometry: GeometryProxy) {
        let dragPosition = gesture.location.x
        let newValue = dragPosition / max(1, geometry.size.width)
        value = max(0, min(newValue, 1))
    }
}
