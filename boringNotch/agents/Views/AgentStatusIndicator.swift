//
//  AgentStatusIndicator.swift
//  boringCode
//
//  Ícone de status de uma sessão de agente. Ocupa o mesmo quadrado do
//  mini espectro de áudio no notch fechado.
//

import SwiftUI

extension AgentSessionStatus {
    var tint: Color {
        switch self {
        case .running: .claudeOrange  // por agente: AgentKind.tint
        case .waitingApproval: .yellow
        case .waitingInput: .effectiveAccent
        case .done: .green
        case .error: .red
        case .idle: .gray
        }
    }
}

extension Color {
    /// Laranja da marca Claude — usado só para "rodando".
    static let claudeOrange = Color(red: 0.851, green: 0.467, blue: 0.341)
    /// Azul do Codex (mesmo tom do Open Island).
    static let codexBlue = Color(red: 0.290, green: 0.639, blue: 0.875)
}

extension AgentKind {
    var tint: Color {
        switch self {
        case .claude: .claudeOrange
        case .codex: .codexBlue
        }
    }
}

struct AgentStatusIndicator: View {
    let status: AgentSessionStatus
    var agent: AgentKind = .claude
    var size: CGFloat = 16

    @State private var pulse = false

    var body: some View {
        Group {
            switch status {
            case .running:
                ClaudeSpinner(size: size, tint: agent.tint)
            case .waitingApproval:
                symbol("exclamationmark.circle.fill")
                    .scaleEffect(pulse ? 1.0 : 0.82)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
            case .waitingInput:
                symbol("questionmark.circle.fill")
            case .done:
                symbol("checkmark.circle.fill")
            case .error:
                symbol("xmark.circle.fill")
            case .idle:
                Circle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: size * 0.4, height: size * 0.4)
            }
        }
        .frame(width: size, height: size)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
        .accessibilityElement()
        .accessibilityLabel(Text(status.label))
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(status.tint)
            .frame(width: size * 0.9, height: size * 0.9)
    }
}

/// O ✻ do Claude Code, em versão calma: um glifo só, girando devagar
/// (uma volta a cada 8 s) e "respirando" de leve no brilho. Parado com
/// Reduzir movimento ligado.
private struct ClaudeSpinner: View {
    let size: CGFloat
    var tint: Color = .claudeOrange

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let secondsPerTurn: Double = 8
    private static let breathPeriod: Double = 2.4

    var body: some View {
        if reduceMotion {
            glyph(angle: 0, opacity: 1)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let angle = (t / Self.secondsPerTurn).truncatingRemainder(dividingBy: 1) * 360
                // 0.7 ↔ 1.0, senoide suave
                let opacity = 0.85 + 0.15 * sin(t / Self.breathPeriod * 2 * .pi)
                glyph(angle: angle, opacity: opacity)
            }
        }
    }

    private func glyph(angle: Double, opacity: Double) -> some View {
        SparkShape()
            .stroke(tint, style: StrokeStyle(lineWidth: max(1.2, size * 0.13), lineCap: .round))
            .frame(width: size * 0.78, height: size * 0.78)
            .opacity(opacity)
            .rotationEffect(.degrees(angle))
            .frame(width: size, height: size)
    }
}

/// Asterisco de 8 braços desenhado em vetor — centro exato, gira sem "balançar".
private struct SparkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<4 {
            let angle = Double(index) * .pi / 4
            let dx = cos(angle) * radius, dy = sin(angle) * radius
            path.move(to: CGPoint(x: center.x - dx, y: center.y - dy))
            path.addLine(to: CGPoint(x: center.x + dx, y: center.y + dy))
        }
        return path
    }
}
