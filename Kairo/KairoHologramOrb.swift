//
//  KairoHologramOrb.swift
//  Kairo — Holographic AI presence
//
//  A breathing plasma sphere that glows when the agent speaks,
//  expands to show content (CCTV, text, images) with holographic
//  scan-line effects. Two instances: notch orb + display panel.
//

import SwiftUI

// ═══════════════════════════════════════════
// MARK: - Hologram Mode
// ═══════════════════════════════════════════

enum HologramMode: Equatable {
    case dormant, idle, listening, speaking, displaying
}

// ═══════════════════════════════════════════
// MARK: - Hologram Manager
// ═══════════════════════════════════════════

class KairoHologramManager: ObservableObject {
    static let shared = KairoHologramManager()

    @Published var displayText: String?
    @Published var displayImage: NSImage?
    @Published var isShowingDisplay: Bool = false

    func showContent(text: String? = nil, image: NSImage? = nil) {
        displayText = text
        displayImage = image
        withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) {
            isShowingDisplay = true
        }
    }

    func dismiss() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            isShowingDisplay = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.displayText = nil
            self?.displayImage = nil
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Holographic Orb
// ═══════════════════════════════════════════

struct KairoHologramOrb: View {
    var size: CGFloat = 120
    var mode: HologramMode = .idle

    private var intensity: CGFloat {
        switch mode {
        case .dormant: return 0
        case .idle: return 0.85
        case .listening: return 0.92
        case .speaking: return 1.0
        case .displaying: return 0.9
        }
    }

    private var breatheSpeed: Double {
        switch mode {
        case .speaking: return 2.8
        case .listening: return 1.8
        case .displaying: return 1.4
        default: return 1.0
        }
    }

    private var breatheAmount: CGFloat {
        switch mode {
        case .speaking: return 0.06
        case .listening: return 0.04
        default: return 0.025
        }
    }

    private let sparks: [(a: Double, d: CGFloat, sp: Double, sz: CGFloat, h: Double)] = [
        (0,   0.50, 0.45, 2.0, 0.52), (30,  0.53, 0.35, 1.5, 0.58),
        (72,  0.48, 0.65, 2.5, 0.72), (110, 0.55, 0.40, 1.8, 0.62),
        (150, 0.47, 0.55, 2.2, 0.78), (195, 0.52, 0.30, 1.6, 0.55),
        (230, 0.50, 0.50, 2.0, 0.68), (270, 0.54, 0.60, 1.4, 0.75),
        (310, 0.49, 0.42, 2.3, 0.60), (345, 0.51, 0.38, 1.7, 0.65),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            orbCanvas(t: t)
        }
    }

    // MARK: - Main Render

    private func orbCanvas(t: Double) -> some View {
        let bX = 1.0 + sin(t * breatheSpeed) * breatheAmount
        let bY = 1.0 + sin(t * breatheSpeed + 0.4) * breatheAmount * 0.7
        let glow = 0.6 + sin(t * 1.5) * 0.25
        let core = size * 0.88

        return ZStack {
            // ── Outer Glow ──
            Circle()
                .fill(RadialGradient(
                    colors: [
                        .cyan.opacity(0.35 * intensity * glow),
                        .purple.opacity(0.2 * intensity * glow),
                        .blue.opacity(0.1 * intensity),
                        .clear,
                    ],
                    center: .center,
                    startRadius: size * 0.12,
                    endRadius: size * 0.8
                ))
                .frame(width: size * 1.8, height: size * 1.8)
                .blur(radius: 16)

            // ── Plasma Core ──
            ZStack {
                // Layer 1: Cyan/purple base — slow rotation
                Ellipse()
                    .fill(AngularGradient(colors: [
                        Color(red: 0, green: 0.85, blue: 1),
                        Color(red: 0.45, green: 0.15, blue: 0.85),
                        Color(red: 0.1, green: 0.25, blue: 0.75),
                        Color(red: 0, green: 0.85, blue: 1),
                    ], center: .center))
                    .rotationEffect(.degrees(t * 22))
                    .scaleEffect(x: 0.85, y: 1.0)
                    .blur(radius: size * 0.09)
                    .opacity(intensity)

                // Layer 2: Pink/gold counter-rotation
                Ellipse()
                    .fill(AngularGradient(colors: [
                        Color(red: 0.92, green: 0.25, blue: 0.55),
                        Color(red: 0.95, green: 0.6, blue: 0.05),
                        Color(red: 0.78, green: 0.28, blue: 0.65),
                        Color(red: 0.92, green: 0.25, blue: 0.55),
                    ], center: .center))
                    .rotationEffect(.degrees(-t * 35 + 55))
                    .scaleEffect(x: 1.0, y: 0.68)
                    .blur(radius: size * 0.07)
                    .blendMode(.screen)
                    .opacity(intensity * 0.85)

                // Layer 3: Ethereal wisps — fast highlights
                Ellipse()
                    .fill(AngularGradient(colors: [
                        .white.opacity(0.8), .cyan.opacity(0.2),
                        .clear, .purple.opacity(0.25), .white.opacity(0.8),
                    ], center: .center))
                    .rotationEffect(.degrees(t * 50 + 115))
                    .scaleEffect(x: 0.6, y: 0.92)
                    .blur(radius: size * 0.05)
                    .blendMode(.plusLighter)
                    .opacity(intensity * 0.65)

                // Layer 4: Deep undercurrent — slow drift
                Ellipse()
                    .fill(AngularGradient(colors: [
                        Color(red: 0.18, green: 0.08, blue: 0.48),
                        Color(red: 0, green: 0.55, blue: 0.75),
                        Color(red: 0.48, green: 0.1, blue: 0.38),
                        Color(red: 0.18, green: 0.08, blue: 0.48),
                    ], center: .center))
                    .rotationEffect(.degrees(-t * 15 + 190))
                    .scaleEffect(x: 0.88, y: 0.62)
                    .blur(radius: size * 0.08)
                    .blendMode(.screen)
                    .opacity(intensity * 0.55)

                // Layer 5: Wandering nebula — shifting center
                Ellipse()
                    .fill(AngularGradient(
                        colors: [
                            Color(red: 0.3, green: 0.7, blue: 0.9).opacity(0.5),
                            Color(red: 0.7, green: 0.2, blue: 0.5).opacity(0.4),
                            Color(red: 0.1, green: 0.4, blue: 0.7).opacity(0.45),
                            Color(red: 0.6, green: 0.4, blue: 0.8).opacity(0.4),
                            Color(red: 0.3, green: 0.7, blue: 0.9).opacity(0.5),
                        ],
                        center: UnitPoint(
                            x: 0.5 + sin(t * 0.7) * 0.15,
                            y: 0.5 + cos(t * 0.7) * 0.15
                        )
                    ))
                    .rotationEffect(.degrees(t * 28 + 250))
                    .scaleEffect(x: 0.75, y: 0.85)
                    .blur(radius: size * 0.06)
                    .blendMode(.screen)
                    .opacity(intensity * 0.45)

                // Center brightness — hot white core
                Circle()
                    .fill(RadialGradient(
                        colors: [
                            .white.opacity(0.45 * intensity),
                            .white.opacity(0.2 * intensity),
                            .cyan.opacity(0.12 * intensity),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.32
                    ))

                // Edge shadow for spherical depth
                Circle()
                    .fill(RadialGradient(
                        colors: [.clear, .black.opacity(0.3)],
                        center: .center,
                        startRadius: size * 0.22,
                        endRadius: size * 0.44
                    ))
            }
            .frame(width: core, height: core)
            .clipShape(Circle())

            // ── Shell Rim ──
            Circle()
                .strokeBorder(
                    AngularGradient(colors: [
                        .cyan.opacity(0.45), .white.opacity(0.2),
                        .purple.opacity(0.3), .blue.opacity(0.35),
                        .cyan.opacity(0.45),
                    ], center: .center),
                    lineWidth: 1.2
                )
                .frame(width: core, height: core)
                .rotationEffect(.degrees(t * 12))

            // ── Pulse Ring (speaking / listening) ──
            if mode == .speaking || mode == .listening {
                Circle()
                    .strokeBorder(
                        AngularGradient(colors: [
                            .cyan.opacity(0.6), .white.opacity(0.4),
                            .purple.opacity(0.5), .cyan.opacity(0.6),
                        ], center: .center),
                        lineWidth: 1.5
                    )
                    .frame(width: size * 0.94, height: size * 0.94)
                    .scaleEffect(1.0 + sin(t * 3.2) * 0.04)
                    .opacity(0.5 + sin(t * 2.5) * 0.3)
                    .blur(radius: 1.5)
            }

            // ── Specular Highlight ──
            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.3 * intensity), .clear],
                    center: UnitPoint(x: 0.33, y: 0.27),
                    startRadius: 0,
                    endRadius: size * 0.22
                ))
                .frame(width: core, height: core)

            // ── Orbiting Sparks ──
            ForEach(0..<sparks.count, id: \.self) { i in
                sparkDot(i: i, t: t)
            }
        }
        .scaleEffect(x: bX, y: bY)
    }

    // MARK: - Spark Particle

    private func sparkDot(i: Int, t: Double) -> some View {
        let s = sparks[i]
        let angle = (s.a + t * s.sp * 35) * .pi / 180
        let x = cos(angle) * size * s.d
        let y = sin(angle) * size * s.d
        let flicker = 0.5 + sin(t * 4 + Double(i) * 1.3) * 0.5

        return Circle()
            .fill(Color(hue: s.h, saturation: 0.75, brightness: 1.0))
            .frame(width: s.sz, height: s.sz)
            .blur(radius: 1.2)
            .opacity(0.7 * intensity * flicker)
            .offset(x: x, y: y)
    }
}

// ═══════════════════════════════════════════
// MARK: - Holographic Display Panel
// ═══════════════════════════════════════════

struct KairoHologramDisplay: View {
    @ObservedObject var manager: KairoHologramManager
    var maxWidth: CGFloat = 380

    var body: some View {
        if manager.isShowingDisplay {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                panel(t: t)
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.5, anchor: .top).combined(with: .opacity),
                removal: .scale(scale: 0.85, anchor: .top).combined(with: .opacity)
            ))
        }
    }

    private func panel(t: Double) -> some View {
        let hue = (t * 0.08).truncatingRemainder(dividingBy: 1.0)
        let shape = RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)

        return ZStack {
            // Glass base — proper Phase 1 glass treatment with a darker
            // scrim so the holographic colours pop off it.
            shape
                .fill(.regularMaterial)
                .overlay { shape.fill(Color.black.opacity(0.35)) }
                .overlay { shape.fill(Kairo.Palette.glassTint) }

            // Animated holographic border (kept — this is the hologram's
            // signature visual language)
            shape.strokeBorder(
                LinearGradient(colors: [
                    Color(hue: hue, saturation: 0.5, brightness: 0.85).opacity(0.45),
                    .cyan.opacity(0.25),
                    Color(hue: (hue + 0.3).truncatingRemainder(dividingBy: 1.0),
                          saturation: 0.6, brightness: 0.8).opacity(0.35),
                    .purple.opacity(0.25),
                    Color(hue: hue, saturation: 0.5, brightness: 0.85).opacity(0.45),
                ], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1
            )

            // Scan lines
            holoScanLines(t: t)
                .clipShape(shape)

            // Content
            VStack(alignment: .leading, spacing: Kairo.Space.sm) {
                if let text = manager.displayText {
                    Text(text)
                        .font(Kairo.Typography.mono)
                        .foregroundStyle(LinearGradient(
                            colors: [.cyan, .white.opacity(0.9)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .shadow(color: .cyan.opacity(0.4), radius: 5)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let image = manager.displayImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Kairo.Radius.sm, style: .continuous))
                        .overlay {
                            holoScanLines(t: t)
                                .opacity(0.3)
                                .clipShape(RoundedRectangle(cornerRadius: Kairo.Radius.sm, style: .continuous))
                        }
                }
            }
            .padding(Kairo.Space.lg)
        }
        .frame(maxWidth: maxWidth)
        .shadow(color: .cyan.opacity(0.18), radius: 16, x: 0, y: 4)
    }

    // MARK: - Scan Lines

    private func holoScanLines(t: Double) -> some View {
        let sweep = t.truncatingRemainder(dividingBy: 4.0) / 4.0

        return GeometryReader { geo in
            ZStack {
                // Static horizontal lines
                Canvas { ctx, canvasSize in
                    for y in stride(from: 0, to: canvasSize.height, by: 3) {
                        ctx.fill(
                            Path(CGRect(x: 0, y: y, width: canvasSize.width, height: 1)),
                            with: .color(.white.opacity(0.025))
                        )
                    }
                }

                // Sweeping highlight
                Rectangle()
                    .fill(LinearGradient(
                        colors: [
                            .clear, .cyan.opacity(0.06),
                            .cyan.opacity(0.12),
                            .cyan.opacity(0.06), .clear,
                        ],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(height: 40)
                    .offset(y: -geo.size.height / 2 + CGFloat(sweep) * geo.size.height)
            }
        }
        .allowsHitTesting(false)
    }
}

// ═══════════════════════════════════════════
// MARK: - Composite Hologram View (notch)
// ═══════════════════════════════════════════

struct KairoHologramView: View {
    @ObservedObject var hologram = KairoHologramManager.shared
    @ObservedObject var feedback = KairoFeedbackEngine.shared
    var orbSize: CGFloat = 70

    private var activeMode: HologramMode {
        if hologram.isShowingDisplay { return .displaying }
        if feedback.isSpeaking { return .speaking }
        return .idle
    }

    var body: some View {
        VStack(spacing: Kairo.Space.sm) {
            KairoHologramOrb(size: orbSize, mode: activeMode)

            if !feedback.currentText.isEmpty {
                Text(feedback.currentText)
                    .font(Kairo.Typography.bodySmall)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .shadow(color: .cyan.opacity(0.3), radius: 4)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, Kairo.Space.xl)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            if hologram.isShowingDisplay {
                KairoHologramDisplay(manager: hologram)
                    .padding(.horizontal, Kairo.Space.md)
            }
        }
        .animation(Kairo.Motion.spring, value: activeMode)
    }
}
