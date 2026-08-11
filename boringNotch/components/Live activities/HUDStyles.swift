//
//  HUDStyles.swift
//  boringNotch
//
//  Alternative renderers for the system HUD (volume / brightness / backlight /
//  mic) shown below the closed notch. Each takes the same inputs as
//  SystemEventIndicatorModifier — an event type, a 0...1 value, and an icon —
//  and draws a distinct visual. The active one is chosen by Defaults[.hudStyle].
//

import SwiftUI
import Defaults

// MARK: - Shared helpers

private func hudSpeakerSymbol(_ value: CGFloat) -> String {
    switch value {
    case 0: return "speaker.slash"
    case 0...0.3: return "speaker.wave.1"
    case 0.3...0.8: return "speaker.wave.2"
    default: return "speaker.wave.3"
    }
}

private func hudIconName(type: SneakContentType, value: CGFloat, icon: String) -> String {
    if !icon.isEmpty { return icon }
    switch type {
    case .volume: return hudSpeakerSymbol(value)
    case .brightness: return value > 0.6 ? "sun.max" : "sun.min"
    case .backlight: return value > 0.5 ? "light.max" : "light.min"
    case .mic: return value > 0 ? "mic" : "mic.slash"
    default: return "circle"
    }
}

/// The HUD's working tint — accent when the user opts in, otherwise white.
private var hudTint: Color {
    Defaults[.systemEventIndicatorUseAccent] ? .effectiveAccent : .white
}

// MARK: - Notch-hugging arc

/// A progress arc that bows downward, hugging the underside of the notch. The
/// filled portion sweeps left→right with the value; a soft glow rides the tip.
struct ArcHUD: View {
    let type: SneakContentType
    let value: CGFloat
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hudIconName(type: type, value: value, icon: icon))
                .symbolVariant(.fill)
                .foregroundStyle(.white)
                .imageScale(.large)
                .frame(width: 22)
                .contentTransition(.interpolate)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    ArcShape()
                        .stroke(Color.white.opacity(0.15),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    ArcShape()
                        .trim(from: 0, to: max(0.001, value))
                        .stroke(
                            LinearGradient(colors: [hudTint.opacity(0.6), hudTint],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .shadow(color: hudTint.opacity(0.6), radius: 4)
                        .animation(.smooth(duration: 0.35), value: value)
                }
                .frame(width: w, height: h)
            }
            .frame(height: 18)

            if Defaults[.showClosedNotchHUDPercentage] {
                Text("\(Int(value * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A shallow downward arc spanning the full width.
    private struct ArcShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: 2))
            p.addQuadCurve(
                to: CGPoint(x: rect.width, y: 2),
                control: CGPoint(x: rect.width / 2, y: rect.height)
            )
            return p
        }
    }
}

// MARK: - Segmented pips

/// Discrete tick segments that light up to represent the level — legible at a
/// glance, with a Teenage-Engineering / old-iOS feel.
struct PipsHUD: View {
    let type: SneakContentType
    let value: CGFloat
    let icon: String

    private let count = 16

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hudIconName(type: type, value: value, icon: icon))
                .symbolVariant(.fill)
                .foregroundStyle(.white)
                .imageScale(.large)
                .frame(width: 22)
                .contentTransition(.interpolate)

            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { i in
                    let lit = CGFloat(i) < value * CGFloat(count)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(lit ? hudTint : Color.white.opacity(0.14))
                        .frame(maxWidth: .infinity)
                        .frame(height: lit ? 13 : 9)
                        .shadow(color: lit && Defaults[.systemEventIndicatorShadow]
                                ? hudTint.opacity(0.7) : .clear, radius: 3)
                        .animation(.snappy(duration: 0.18), value: lit)
                }
            }
            .frame(height: 14)

            if Defaults[.showClosedNotchHUDPercentage] {
                Text("\(Int(value * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Liquid fill

/// A rounded capsule that fills with liquid; the surface is a gentle sine wave
/// that ripples while the value changes, sloshing toward the new level.
struct LiquidHUD: View {
    let type: SneakContentType
    let value: CGFloat
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hudIconName(type: type, value: value, icon: icon))
                .symbolVariant(.fill)
                .foregroundStyle(.white)
                .imageScale(.large)
                .frame(width: 22)
                .contentTransition(.interpolate)

            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Empty tube.
                        Capsule().fill(Color.white.opacity(0.08))

                        // Body of liquid with a vertical sheen.
                        LiquidWave(progress: value, phase: t * 2.0, amplitude: 1.8)
                            .fill(
                                LinearGradient(
                                    colors: [hudTint.opacity(0.85), hudTint, hudTint.opacity(0.7)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .shadow(color: Defaults[.systemEventIndicatorShadow]
                                    ? hudTint.opacity(0.55) : .clear, radius: 5)

                        // Bright meniscus riding the wavy surface for a wet edge.
                        LiquidWave(progress: value, phase: t * 2.0, amplitude: 1.8)
                            .stroke(Color.white.opacity(0.85), lineWidth: 1.2)
                            .blur(radius: 0.4)
                            .mask(
                                // Only show the highlight near the leading surface.
                                LinearGradient(colors: [.clear, .white, .clear],
                                               startPoint: .leading, endPoint: .trailing)
                            )

                        // Glossy top highlight across the whole tube.
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.22), .clear],
                                    startPoint: .top, endPoint: .center
                                )
                            )
                            .allowsHitTesting(false)

                        Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(Capsule())
                    .animation(.smooth(duration: 0.45), value: value)
                }
            }
            .frame(height: 18)

            if Defaults[.showClosedNotchHUDPercentage] {
                Text("\(Int(value * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A horizontally-filling shape whose leading edge is an organic, sloshing
    /// surface — two superimposed sine waves of different frequency rather than
    /// one, so it reads as liquid rather than a vibrating line.
    private struct LiquidWave: Shape {
        var progress: CGFloat
        var phase: Double
        var amplitude: CGFloat

        var animatableData: Double { phase }

        func path(in rect: CGRect) -> Path {
            var p = Path()
            let fillW = max(0, min(rect.width, rect.width * progress))
            guard fillW > 0 else { return p }
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: rect.height))
            let steps = 24
            for i in 0...steps {
                let frac = Double(i) / Double(steps)
                let y = rect.height * CGFloat(frac)
                // Two waves: a slow primary swell + a faster, smaller ripple.
                let primary = sin(phase + frac * 3.4) * Double(amplitude)
                let ripple  = sin(phase * 1.9 + frac * 7.0) * Double(amplitude) * 0.45
                let x = fillW + CGFloat(primary + ripple)
                p.addLine(to: CGPoint(x: x, y: y))
            }
            p.addLine(to: CGPoint(x: 0, y: rect.height))
            p.closeSubpath()
            return p
        }
    }
}

// MARK: - Reactive waveform

/// A row of bars whose heights ripple outward from the level — taller near the
/// "current" position, animating continuously so it feels alive.
struct WaveformHUD: View {
    let type: SneakContentType
    let value: CGFloat
    let icon: String

    private let count = 22

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hudIconName(type: type, value: value, icon: icon))
                .symbolVariant(.fill)
                .foregroundStyle(.white)
                .imageScale(.large)
                .frame(width: 22)
                .contentTransition(.interpolate)

            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 2) {
                    ForEach(0..<count, id: \.self) { i in
                        let frac = CGFloat(i) / CGFloat(count - 1)
                        let active = frac <= value
                        // Bars within the level ripple; the rest sit as a low floor.
                        let wave = (sin(t * 6 + Double(i) * 0.6) + 1) / 2  // 0...1
                        let base: CGFloat = active ? 0.35 : 0.12
                        let h = base + (active ? CGFloat(wave) * 0.65 : 0)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(active ? hudTint : Color.white.opacity(0.14))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(3, h * 16))
                            .shadow(color: active && Defaults[.systemEventIndicatorShadow]
                                    ? hudTint.opacity(0.6) : .clear, radius: 2)
                    }
                }
                .frame(height: 16)
                .animation(.smooth(duration: 0.3), value: value)
            }

            if Defaults[.showClosedNotchHUDPercentage] {
                Text("\(Int(value * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Router

/// Picks the right renderer for the below-notch HUD slot based on the user's
/// chosen style. `.standard` keeps the original SystemEventIndicatorModifier.
struct BelowNotchHUD: View {
    let type: SneakContentType
    @Binding var value: CGFloat
    let icon: String
    let style: HUDStyle
    @Binding var accent: Color?
    var sendEventBack: (CGFloat) -> Void

    var body: some View {
        switch style {
        case .arc:
            ArcHUD(type: type, value: value, icon: icon)
        case .pips:
            PipsHUD(type: type, value: value, icon: icon)
        case .liquid:
            LiquidHUD(type: type, value: value, icon: icon)
        case .waveform:
            WaveformHUD(type: type, value: value, icon: icon)
        case .standard, .inline:
            SystemEventIndicatorModifier(
                eventType: .constant(type),
                value: $value,
                icon: .constant(icon),
                accent: $accent,
                sendEventBack: sendEventBack
            )
        }
    }
}
