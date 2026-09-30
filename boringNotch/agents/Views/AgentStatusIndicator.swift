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
        case .running: .claudeOrange
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
}

struct AgentStatusIndicator: View {
    let status: AgentSessionStatus
    var size: CGFloat = 16

    @State private var pulse = false

    var body: some View {
        Group {
            switch status {
            case .running:
                ClaudeSpinner(size: size)
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

/// O "✻" pulsante do Claude Code no terminal.
private struct ClaudeSpinner: View {
    let size: CGFloat
    private static let frames = ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { context in
            let index = Int(context.date.timeIntervalSinceReferenceDate / 0.12) % Self.frames.count
            Text(Self.frames[index])
                .font(.system(size: size * 0.95, weight: .semibold))
                .foregroundStyle(Color.claudeOrange)
                .frame(width: size, height: size)
        }
    }
}
