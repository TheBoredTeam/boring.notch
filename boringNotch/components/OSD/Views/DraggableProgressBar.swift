//
//  DraggableProgressBarView.swift
//  boringNotch
//
//  Created by Alexander on 2026-02-07.
//

import SwiftUI
import Defaults

public struct DraggableProgressBar: View {
    @Binding public var value: CGFloat
    public var onChange: ((CGFloat) -> Void)? = nil
    public var accentColor: Color? = nil
    public var compact: Bool = false

    @State private var isDragging = false

    public init(value: Binding<CGFloat>, onChange: ((CGFloat) -> Void)? = nil, accentColor: Color? = nil, compact: Bool = false) {
        self._value = value
        self.onChange = onChange
        self.accentColor = accentColor
        self.compact = compact
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.tertiary)
                Capsule()
                    .fill(fillStyle())
                    .frame(width: max(0, min(geo.size.width * value, geo.size.width)))
                    .shadow(color: shadowColor(), radius: 8, x: 3)
                    .opacity(value.isZero ? 0 : 1)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(in: geo))
            .accessibilityElement()
            .accessibilityLabel(Text(NSLocalizedString("OSD.ValueLabel", comment: "Label for OSD value slider")))
            .accessibilityValue(Text("\(Int(value * 100))%"))
            .accessibilityAdjustableAction { direction in
                let step: CGFloat = 0.05
                switch direction {
                case .increment:
                    updateValueClamped(value + step)
                case .decrement:
                    updateValueClamped(value - step)
                default: break
                }
            }
        }
        .frame(height: compact ? (Defaults[.inlineOSD] ? 6 : 7) : (Defaults[.inlineOSD] ? (isDragging ? 8 : 5) : (isDragging ? 9 : 6)))
    }

    private func fillStyle() -> AnyShapeStyle {
        if let c = accentColor {
            if Defaults[.enableGradient] {
                return AnyShapeStyle(LinearGradient(
                    colors: [c, c.ensureMinimumBrightness(factor: 0.2)],
                    startPoint: .trailing,
                    endPoint: .leading
                ))
            } else {
                return AnyShapeStyle(c)
            }
        }

        if Defaults[.enableGradient] {
            return AnyShapeStyle(LinearGradient(
                colors: Defaults[.systemEventIndicatorUseAccent] ?
                [Color.effectiveAccent, Color.effectiveAccent.ensureMinimumBrightness(factor: 0.2)] :
                [Color.white, Color.white.opacity(0.2)],
                startPoint: .trailing,
                endPoint: .leading
            ))
        }

        return AnyShapeStyle(Defaults[.systemEventIndicatorUseAccent] ? Color.effectiveAccent : Color.white)
    }

    private func shadowColor() -> Color {
        guard Defaults[.systemEventIndicatorShadow] else { return .clear }
        if let c = accentColor { return c.ensureMinimumBrightness(factor: 0.7) }
        return Defaults[.systemEventIndicatorUseAccent] ? Color.effectiveAccent.ensureMinimumBrightness(factor: 0.7) : Color.white
    }

    private func dragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                withAnimation(.smooth(duration: 0.12)) {
                    isDragging = true
                    updateValue(from: gesture.location.x, in: geo.size.width)
                }
            }
            .onEnded { _ in
                withAnimation(.smooth(duration: 0.12)) {
                    isDragging = false
                }
            }
    }

    private func updateValue(from x: CGFloat, in width: CGFloat) {
        guard width > 0 else { return }
        let newValue = x / width
        updateValueClamped(newValue)
    }

    private func updateValueClamped(_ newValue: CGFloat) {
        let clamped = max(0, min(newValue, 1))
        if clamped != value {
            value = clamped
            onChange?(value)
        }
    }
}
