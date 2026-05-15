import SwiftUI

struct OrbPresence: View {
    let voiceState: VoiceState

    @State private var breathePhase: CGFloat = 0
    @State private var thinkRotation: CGFloat = 0
    @State private var waveOffset: CGFloat = 0

    var body: some View {
        ZStack {
            coreOrb

            switch voiceState {
            case .idle:
                idleBreath
            case .listening(let amp):
                listeningRipples(amplitude: amp)
            case .thinking:
                thinkingSwirl
            case .speaking(let amp):
                speakingUndulation(amplitude: amp)
            }
        }
        .onAppear { startPhaseLoops() }
    }

    private var coreOrb: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Kairo.Palette.orbCore,
                        Kairo.Palette.orbDeep,
                        .black,
                    ],
                    center: UnitPoint(x: 0.3, y: 0.3),
                    startRadius: 2,
                    endRadius: 60
                )
            )
    }

    private var idleBreath: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Kairo.Palette.orbCore.opacity(0.35), .clear],
                    center: .center, startRadius: 0, endRadius: 60
                )
            )
            .scaleEffect(1.0 + sin(breathePhase) * 0.08)
            .opacity(0.5 + sin(breathePhase) * 0.3)
    }

    private func listeningRipples(amplitude: Float) -> some View {
        let amp = CGFloat(amplitude)
        return ZStack {
            rippleCircle(index: 0, amp: amp, amplitude: amplitude)
            rippleCircle(index: 1, amp: amp, amplitude: amplitude)
            rippleCircle(index: 2, amp: amp, amplitude: amplitude)
        }
    }

    private func rippleCircle(index: Int, amp: CGFloat, amplitude: Float) -> some View {
        let i = CGFloat(index)
        let scale = 1.0 + amp * 0.8 + i * 0.25 + sin(waveOffset + i) * 0.1
        let lineW = 2.0 - i * 0.5
        let op = 1.0 - Double(index) * 0.3
        let strokeOp = 0.5 - Double(index) * 0.15
        return Circle()
            .stroke(Kairo.Palette.orbCore.opacity(strokeOp), lineWidth: lineW)
            .scaleEffect(scale)
            .opacity(op)
            .animation(.easeOut(duration: 0.15), value: amplitude)
    }

    private var thinkingSwirl: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Kairo.Palette.orbCore.opacity(0.5), .clear],
                        center: .center, startRadius: 0, endRadius: 60
                    )
                )
                .scaleEffect(1.0 + sin(breathePhase * 1.5) * 0.12)
                .opacity(0.6)

            Arc(startAngle: .degrees(0), endAngle: .degrees(120))
                .stroke(
                    AngularGradient(
                        colors: [.clear, Kairo.Palette.orbCore, .clear],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(thinkRotation))
                .frame(width: 56, height: 56)
        }
    }

    private func speakingUndulation(amplitude: Float) -> some View {
        let amp = CGFloat(amplitude)
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Kairo.Palette.orbCore.opacity(0.6 + Double(amp) * 0.4),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 60 + amp * 40
                    )
                )
                .scaleEffect(1.0 + amp * 0.25)
                .animation(.easeOut(duration: 0.08), value: amplitude)

            Circle()
                .fill(Kairo.Palette.orbCore.opacity(Double(amp) * 0.3))
                .scaleEffect(0.8 + amp * 0.2)
                .blur(radius: 4)
                .animation(.easeOut(duration: 0.05), value: amplitude)
        }
    }

    private func startPhaseLoops() {
        withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
            breathePhase = .pi * 2
        }
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            thinkRotation = 360
        }
        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            waveOffset = .pi * 2
        }
    }
}

struct Arc: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        p.addArc(center: center, radius: radius,
                 startAngle: startAngle, endAngle: endAngle,
                 clockwise: false)
        return p
    }
}
