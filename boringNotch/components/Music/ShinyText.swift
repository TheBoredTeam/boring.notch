
//
//  ShinyText.swift
//  boringNotch
//
//
// create by Yuvraj soni (25/01/2026)

import SwiftUI

public struct ShinyText: View {
    public enum Direction { case left, right }

    let text: String

    var disabled: Bool = false
    var speed: Double = 2.0
    var color: Color = Color(hex: "#b5b5b5")
    var shineColor: Color = .white
    var spread: Double = 120
    var yoyo: Bool = false
    var pauseOnHover: Bool = false
    var direction: Direction = .left
    var delay: Double = 0.0
    var font: Font? = nil
    // ✅ NEW: If you want perfect sync (e.g., lyrics), provide external progress/time
    var externalProgress01: Double? = nil   // 0...1
    var externalTime: Double? = nil         // seconds

    // Wider + smoother shine
    var wideBand: Double = 0.42
    var softEdges: Double = 0.22

    @State private var isPaused: Bool = false
    @State private var pauseStart: Date? = nil
    @State private var pausedTotal: TimeInterval = 0

    private var animationDuration: Double { max(0.01, speed) }
    private var delayDuration: Double { max(0.0, delay) }

    public init(
        _ text: String,
        disabled: Bool = false,
        speed: Double = 2.0,
        color: Color = Color(hex: "#b5b5b5"),
        shineColor: Color = .white,
        spread: Double = 120,
        yoyo: Bool = false,
        pauseOnHover: Bool = false,
        direction: Direction = .left,
        delay: Double = 0.0,
        font: Font? = nil,
        wideBand: Double = 0.42,
        softEdges: Double = 0.22,
        externalProgress01: Double? = nil,
        externalTime: Double? = nil
    ) {
        self.text = text
        self.disabled = disabled
        self.speed = speed
        self.color = color
        self.shineColor = shineColor
        self.spread = spread
        self.yoyo = yoyo
        self.pauseOnHover = pauseOnHover
        self.direction = direction
        self.delay = delay
        self.font = font
        self.wideBand = wideBand
        self.softEdges = softEdges
        self.externalProgress01 = externalProgress01
        self.externalTime = externalTime
    }

    // MARK: - Progress (0...1)
    private func computeProgress01(elapsed: Double) -> Double {
        let anim = animationDuration
        let del = delayDuration

        if yoyo {
            let cycle = anim + del
            let full = cycle * 2
            let t = elapsed.truncatingRemainder(dividingBy: full)

            if t < anim {
                let p = t / anim
                return direction == .left ? p : (1.0 - p)
            } else if t < cycle {
                return direction == .left ? 1.0 : 0.0
            } else if t < cycle + anim {
                let rt = t - cycle
                let p = 1.0 - (rt / anim)
                return direction == .left ? p : (1.0 - p)
            } else {
                return direction == .left ? 0.0 : 1.0
            }
        } else {
            let cycle = anim + del
            let t = elapsed.truncatingRemainder(dividingBy: cycle)

            if t < anim {
                let p = t / anim
                return direction == .left ? p : (1.0 - p)
            } else {
                return direction == .left ? 1.0 : 0.0
            }
        }
    }

    // MARK: - Wide Shine Gradient Stops
    private func gradientStops(progress01: Double) -> [Gradient.Stop] {
        let p = max(0.0, min(1.0, progress01))

        let halfBand = max(0.05, min(0.49, wideBand / 2.0))
        let edge = max(0.01, min(0.49, softEdges))

        let leftOuter = max(0.0, p - halfBand - edge)
        let leftInner = max(0.0, p - halfBand)
        let rightInner = min(1.0, p + halfBand)
        let rightOuter = min(1.0, p + halfBand + edge)

        var stops: [Gradient.Stop] = [
            .init(color: color, location: 0.0),
            .init(color: color, location: leftOuter),
            .init(color: shineColor.opacity(0.55), location: leftInner),
            .init(color: shineColor.opacity(1.0), location: p),
            .init(color: shineColor.opacity(0.55), location: rightInner),
            .init(color: color, location: rightOuter),
            .init(color: color, location: 1.0)
        ]

        stops = stops
            .filter { $0.location >= 0.0 && $0.location <= 1.0 }
            .sorted { $0.location < $1.location }

        return stops
    }

    private func startPointEndPoint(angleDegrees: Double) -> (UnitPoint, UnitPoint) {
        let theta = angleDegrees * .pi / 180.0
        let dx = cos(theta)
        let dy = sin(theta)

        let sx = 0.5 - dx * 0.5
        let sy = 0.5 - dy * 0.5
        let ex = 0.5 + dx * 0.5
        let ey = 0.5 + dy * 0.5

        return (UnitPoint(x: sx, y: sy), UnitPoint(x: ex, y: ey))
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let now = context.date

            // ✅ stable time (no state mutation in render)
            let t = now.timeIntervalSinceReferenceDate

            // pause logic
            let effectiveTime: Double
            if disabled {
                effectiveTime = 0
            } else if isPaused {
                effectiveTime = (pauseStart?.timeIntervalSinceReferenceDate ?? t) - pausedTotal
            } else {
                effectiveTime = t - pausedTotal
            }

            let progress01: Double
            if let p = externalProgress01 {
                progress01 = max(0.0, min(1.0, p))
            } else if let tExternal = externalTime {
                progress01 = computeProgress01(elapsed: max(0.0, tExternal))
            } else {
                progress01 = computeProgress01(elapsed: effectiveTime)
            }

            let stops = gradientStops(progress01: progress01)
            let (sp, ep) = startPointEndPoint(angleDegrees: spread)

            Text(text)
                .font(font)
                .foregroundStyle(.clear)
                .overlay(
                    LinearGradient(
                        gradient: Gradient(stops: stops),
                        startPoint: sp,
                        endPoint: ep
                    )
                )
                .mask(
                    Text(text).font(font)
                )
        }
        .onHover { hovering in
            // If externally driven, don't pause internally
            if externalProgress01 != nil || externalTime != nil { return }

            guard pauseOnHover else { return }

            if hovering {
                if !isPaused {
                    isPaused = true
                    pauseStart = Date()
                }
            } else {
                if isPaused {
                    isPaused = false
                    if let start = pauseStart {
                        pausedTotal += Date().timeIntervalSince(start)
                    }
                    pauseStart = nil
                }
            }
        }
        .onChange(of: direction) { _, _ in
            pausedTotal = 0
            pauseStart = nil
            isPaused = false
        }
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255,
                            (int >> 8) * 17,
                            (int >> 4 & 0xF) * 17,
                            (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255,
                            int >> 16,
                            int >> 8 & 0xFF,
                            int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24,
                            int >> 16 & 0xFF,
                            int >> 8 & 0xFF,
                            int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}