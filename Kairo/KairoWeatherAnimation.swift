//
//  KairoWeatherAnimation.swift
//  Kairo — Ambient weather particle system
//
//  Renders live weather-driven animations behind the idle screen:
//  rain, snow, thunderstorm, clouds, fog, sunshine, stars.
//

import SwiftUI

// ═══════════════════════════════════════════
// MARK: - Weather Type Detection
// ═══════════════════════════════════════════

enum KairoWeatherType {
    case clear
    case clouds
    case rain
    case heavyRain
    case drizzle
    case snow
    case thunderstorm
    case fog
    case wind

    static func from(condition: String) -> KairoWeatherType {
        let c = condition.lowercased()
        if c.contains("thunder") || c.contains("storm") { return .thunderstorm }
        if c.contains("heavy rain") || c.contains("extreme") { return .heavyRain }
        if c.contains("rain") || c.contains("shower") { return .rain }
        if c.contains("drizzle") { return .drizzle }
        if c.contains("snow") || c.contains("sleet") || c.contains("blizzard") { return .snow }
        if c.contains("fog") || c.contains("mist") || c.contains("haze") || c.contains("smoke") { return .fog }
        if c.contains("cloud") || c.contains("overcast") { return .clouds }
        if c.contains("wind") || c.contains("squall") || c.contains("tornado") { return .wind }
        return .clear
    }

    var accentColor: Color {
        switch self {
        case .clear:        return Color(hex: 0xFFA726)
        case .clouds:       return Color(hex: 0x90A4AE)
        case .rain, .drizzle: return Color(hex: 0x42A5F5)
        case .heavyRain:    return Color(hex: 0x1565C0)
        case .snow:         return Color(hex: 0xB3E5FC)
        case .thunderstorm: return Color(hex: 0x7E57C2)
        case .fog:          return Color(hex: 0x78909C)
        case .wind:         return Color(hex: 0x80CBC4)
        }
    }

    var bgGradient: [Color] {
        switch self {
        case .clear:
            return [Color(hex: 0x0D1B2A).opacity(0.3), Color(hex: 0x1B2838).opacity(0.1)]
        case .clouds:
            return [Color(hex: 0x37474F).opacity(0.2), Color(hex: 0x263238).opacity(0.1)]
        case .rain, .drizzle:
            return [Color(hex: 0x0D47A1).opacity(0.15), Color(hex: 0x1A237E).opacity(0.08)]
        case .heavyRain:
            return [Color(hex: 0x0D47A1).opacity(0.25), Color(hex: 0x1A237E).opacity(0.12)]
        case .snow:
            return [Color(hex: 0xE1F5FE).opacity(0.08), Color(hex: 0xB3E5FC).opacity(0.04)]
        case .thunderstorm:
            return [Color(hex: 0x311B92).opacity(0.2), Color(hex: 0x1A237E).opacity(0.1)]
        case .fog:
            return [Color(hex: 0x546E7A).opacity(0.15), Color(hex: 0x37474F).opacity(0.08)]
        case .wind:
            return [Color(hex: 0x004D40).opacity(0.12), Color(hex: 0x00695C).opacity(0.06)]
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Main Weather Animation View
// ═══════════════════════════════════════════

struct KairoWeatherAnimationView: View {
    let weatherType: KairoWeatherType
    let bounds: CGSize

    var body: some View {
        ZStack {
            LinearGradient(
                colors: weatherType.bgGradient + [.clear],
                startPoint: .top, endPoint: .bottom
            )

            switch weatherType {
            case .clear:
                SunshineEffect(bounds: bounds)
                StarsEffect(bounds: bounds, count: 12)
            case .clouds:
                CloudsEffect(bounds: bounds, count: 4)
            case .rain:
                RainEffect(bounds: bounds, intensity: .normal)
            case .heavyRain:
                RainEffect(bounds: bounds, intensity: .heavy)
                LightningEffect()
            case .drizzle:
                RainEffect(bounds: bounds, intensity: .light)
                CloudsEffect(bounds: bounds, count: 2)
            case .snow:
                SnowEffect(bounds: bounds, count: 35)
            case .thunderstorm:
                RainEffect(bounds: bounds, intensity: .heavy)
                LightningEffect()
                ThunderGlow()
            case .fog:
                FogEffect(bounds: bounds)
            case .wind:
                WindEffect(bounds: bounds)
                CloudsEffect(bounds: bounds, count: 3)
            }
        }
        .allowsHitTesting(false)
    }
}

// ═══════════════════════════════════════════
// MARK: - Rain Effect
// ═══════════════════════════════════════════

enum RainIntensity { case light, normal, heavy }

struct RainEffect: View {
    let bounds: CGSize
    let intensity: RainIntensity

    private var dropCount: Int {
        switch intensity {
        case .light:  return 20
        case .normal: return 40
        case .heavy:  return 65
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.03)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<dropCount {
                    let seed = Double(i) * 137.508
                    let speed = baseSpeed(i: i)
                    let x = ((seed + time * (8 + Double(i % 5) * 2)).truncatingRemainder(dividingBy: Double(size.width) + 40)) - 20
                    let y = ((seed * 3.7 + time * speed).truncatingRemainder(dividingBy: Double(size.height) + 60)) - 30
                    let length = dropLength(i: i)
                    let alpha = dropAlpha(i: i)

                    let path = Path { p in
                        p.move(to: CGPoint(x: x, y: y))
                        p.addLine(to: CGPoint(x: x - 1.5, y: y + length))
                    }
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color(hex: 0x64B5F6).opacity(alpha),
                                Color(hex: 0x42A5F5).opacity(alpha * 0.3)
                            ]),
                            startPoint: CGPoint(x: x, y: y),
                            endPoint: CGPoint(x: x, y: y + length)
                        ),
                        lineWidth: lineWidth(i: i)
                    )
                }
            }
        }
    }

    private func baseSpeed(i: Int) -> Double {
        switch intensity {
        case .light:  return 80 + Double(i % 7) * 8
        case .normal: return 120 + Double(i % 7) * 12
        case .heavy:  return 180 + Double(i % 7) * 18
        }
    }

    private func dropLength(i: Int) -> CGFloat {
        switch intensity {
        case .light:  return CGFloat(8 + i % 6)
        case .normal: return CGFloat(12 + i % 10)
        case .heavy:  return CGFloat(18 + i % 14)
        }
    }

    private func dropAlpha(i: Int) -> Double {
        switch intensity {
        case .light:  return 0.15 + Double(i % 5) * 0.04
        case .normal: return 0.2 + Double(i % 5) * 0.06
        case .heavy:  return 0.25 + Double(i % 5) * 0.08
        }
    }

    private func lineWidth(i: Int) -> CGFloat {
        switch intensity {
        case .light:  return 0.8
        case .normal: return CGFloat(i % 3 == 0 ? 1.2 : 0.8)
        case .heavy:  return CGFloat(i % 4 == 0 ? 1.8 : 1.0)
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Snow Effect
// ═══════════════════════════════════════════

struct SnowEffect: View {
    let bounds: CGSize
    let count: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.04)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    let seed = Double(i) * 97.31
                    let drift = sin(time * (0.6 + Double(i % 4) * 0.15) + seed) * 18
                    let x = ((seed * 2.3 + drift).truncatingRemainder(dividingBy: Double(size.width) + 20)) - 10
                    let speed = 18 + Double(i % 8) * 5
                    let y = ((seed * 1.7 + time * speed).truncatingRemainder(dividingBy: Double(size.height) + 40)) - 20
                    let radius = CGFloat(1.5 + Double(i % 5) * 0.8)
                    let alpha = 0.2 + Double(i % 6) * 0.06

                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(alpha))
                    )
                    if i % 3 == 0 {
                        let glowRect = CGRect(x: x - radius * 2.5, y: y - radius * 2.5, width: radius * 5, height: radius * 5)
                        context.fill(
                            Path(ellipseIn: glowRect),
                            with: .color(.white.opacity(alpha * 0.15))
                        )
                    }
                }
            }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Lightning Effect
// ═══════════════════════════════════════════

struct LightningEffect: View {
    @State private var flash = false
    @State private var boltPath: Path?
    @State private var boltX: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if flash, let path = boltPath {
                    path.stroke(
                        LinearGradient(
                            colors: [.white, Color(hex: 0xB388FF), Color(hex: 0x7C4DFF).opacity(0.3)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 1)
                    .shadow(color: Color(hex: 0x7C4DFF).opacity(0.8), radius: 20)

                    path.stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                }

                Rectangle()
                    .fill(.white)
                    .opacity(flash ? 0.06 : 0)
            }
            .onAppear { scheduleLightning(size: geo.size) }
        }
    }

    private func scheduleLightning(size: CGSize) {
        let delay = Double.random(in: 3...8)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            boltPath = generateBolt(size: size)
            withAnimation(.easeIn(duration: 0.05)) { flash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.08)) { flash = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeIn(duration: 0.03)) { flash = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                        withAnimation(.easeOut(duration: 0.15)) { flash = false }
                        scheduleLightning(size: size)
                    }
                }
            }
        }
    }

    private func generateBolt(size: CGSize) -> Path {
        var path = Path()
        let startX = CGFloat.random(in: size.width * 0.2...size.width * 0.8)
        var x = startX
        var y: CGFloat = 0
        path.move(to: CGPoint(x: x, y: y))

        let segments = Int.random(in: 5...9)
        let segmentH = size.height * 0.7 / CGFloat(segments)

        for _ in 0..<segments {
            x += CGFloat.random(in: -20...20)
            y += segmentH + CGFloat.random(in: -4...4)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

// ═══════════════════════════════════════════
// MARK: - Thunder Glow (ambient purple pulse)
// ═══════════════════════════════════════════

struct ThunderGlow: View {
    @State private var glow = false

    var body: some View {
        RadialGradient(
            colors: [Color(hex: 0x7C4DFF).opacity(glow ? 0.12 : 0), .clear],
            center: .top, startRadius: 0, endRadius: 250
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Clouds Effect
// ════════════════════════════════��══════════

struct CloudsEffect: View {
    let bounds: CGSize
    let count: Int
    @State private var offsets: [CGFloat]

    init(bounds: CGSize, count: Int) {
        self.bounds = bounds
        self.count = count
        _offsets = State(initialValue: (0..<count).map { _ in CGFloat.random(in: -50...50) })
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    let speed = 6 + Double(i) * 2.5
                    let baseX = (time * speed + Double(i) * 120).truncatingRemainder(dividingBy: Double(size.width) + 200) - 100
                    let y = 15 + CGFloat(i) * (size.height * 0.2)
                    let w: CGFloat = CGFloat(60 + i * 20)
                    let h: CGFloat = CGFloat(16 + i * 4)
                    let alpha = 0.06 + Double(i) * 0.02

                    let rect = CGRect(x: baseX, y: y, width: w, height: h)
                    let cloudPath = Path(roundedRect: rect, cornerRadius: h / 2)
                    context.fill(cloudPath, with: .color(.white.opacity(alpha)))

                    let innerRect = CGRect(x: baseX + w * 0.2, y: y - h * 0.3, width: w * 0.5, height: h * 0.8)
                    let innerPath = Path(roundedRect: innerRect, cornerRadius: h * 0.4)
                    context.fill(innerPath, with: .color(.white.opacity(alpha * 0.7)))
                }
            }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Sunshine Effect
// ═══════════════════════════════════════════

struct SunshineEffect: View {
    let bounds: CGSize
    @State private var rotation: Double = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFFA726).opacity(pulse ? 0.12 : 0.06), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 1.5, height: 30 + CGFloat(i % 3) * 8)
                    .offset(y: -50)
                    .rotationEffect(.degrees(Double(i) * 45 + rotation))
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0xFFA726).opacity(0.15), Color(hex: 0xFFCC02).opacity(0.05), .clear],
                        center: .center, startRadius: 0, endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)
                .scaleEffect(pulse ? 1.1 : 0.95)
        }
        .position(x: bounds.width * 0.8, y: 30)
        .onAppear {
            withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) { rotation = 360 }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Stars Effect (clear night)
// ═══════════════════════════════════════════

struct StarsEffect: View {
    let bounds: CGSize
    let count: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    let seed = Double(i) * 73.97
                    let x = (seed * 17.3).truncatingRemainder(dividingBy: Double(size.width))
                    let y = (seed * 11.7).truncatingRemainder(dividingBy: Double(size.height) * 0.5)
                    let twinkle = (sin(time * (1.5 + Double(i % 4) * 0.3) + seed) + 1) / 2
                    let r: CGFloat = CGFloat(1 + Double(i % 3) * 0.5)
                    let alpha = 0.1 + twinkle * 0.2

                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                }
            }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Fog Effect
// ═══════════════════════════════════════════

struct FogEffect: View {
    let bounds: CGSize
    @State private var drift: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                let yPos = CGFloat(i) * bounds.height * 0.18 + 20
                let alpha = 0.04 + Double(i) * 0.015
                let w = bounds.width * CGFloat(0.7 + Double(i % 3) * 0.2)
                Capsule()
                    .fill(.white.opacity(alpha))
                    .frame(width: w, height: CGFloat(18 + i * 6))
                    .blur(radius: CGFloat(12 + i * 4))
                    .offset(x: drift + CGFloat(i * 15), y: yPos)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) { drift = 30 }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Wind Effect (streaks)
// ═══════════════════════════════════════════

struct WindEffect: View {
    let bounds: CGSize

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.04)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<12 {
                    let seed = Double(i) * 53.7
                    let speed = 100 + Double(i % 4) * 30
                    let x = (time * speed + seed * 8).truncatingRemainder(dividingBy: Double(size.width) + 100) - 50
                    let y = (seed * 5.3).truncatingRemainder(dividingBy: Double(size.height))
                    let length = CGFloat(20 + i % 5 * 12)
                    let alpha = 0.04 + Double(i % 4) * 0.02
                    let curve = sin(time * 2 + seed) * 4

                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addQuadCurve(
                        to: CGPoint(x: x + length, y: y + CGFloat(curve)),
                        control: CGPoint(x: x + length * 0.5, y: y - 6)
                    )
                    context.stroke(
                        path,
                        with: .color(.white.opacity(alpha)),
                        lineWidth: CGFloat(i % 3 == 0 ? 1.5 : 0.8)
                    )
                }
            }
        }
    }
}
