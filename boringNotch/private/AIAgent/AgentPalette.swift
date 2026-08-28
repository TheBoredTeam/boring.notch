//
//  AgentPalette.swift
//  boringNotch
//
//  Vibe Island-inspired design tokens and small shared components for the
//  agent surfaces: warm paper text on near-black ink, mono labels, and the
//  signature state dots with a soft pulse for waiting/running.
//

import SwiftUI

enum AgentPalette {
    /// Near-black pill background (matches the physical notch).
    static let ink = Color(red: 0x0A / 255.0, green: 0x0A / 255.0, blue: 0x0E / 255.0)
    /// Warm paper white — primary text.
    static let paper = Color(red: 0xF1 / 255.0, green: 0xEA / 255.0, blue: 0xD9 / 255.0)

    // Status colors (from the v7/v8 vibe-island palette)
    static let waiting = Color(red: 0xE7 / 255.0, green: 0xA7 / 255.0, blue: 0x62 / 255.0)      // amber
    static let waitingApproval = Color(red: 0xF4 / 255.0, green: 0xA4 / 255.0, blue: 0xA4 / 255.0) // soft red
    static let waitingAnswer = Color(red: 0xFF / 255.0, green: 0xD5 / 255.0, blue: 0x8A / 255.0)    // light amber
    static let running = Color(red: 0x6E / 255.0, green: 0xA7 / 255.0, blue: 0xFF / 255.0)       // blue
    static let completed = Color(red: 0x6F / 255.0, green: 0xB9 / 255.0, blue: 0x82 / 255.0)     // green

    static let paperSecondary = paper.opacity(0.62)
    static let paperFaint = paper.opacity(0.4)

    static func tint(for phase: AgentSession.Phase) -> Color {
        switch phase {
        case .waitingApproval: return waitingApproval
        case .waitingAnswer: return waitingAnswer
        case .busy: return running
        case .errored: return waitingApproval
        case .idle: return completed
        }
    }
}

// MARK: - State dot

struct AgentStateDot: View {
    let color: Color
    var pulsing: Bool = false
    var size: CGFloat = 8

    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
            if pulsing {
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .scaleEffect(animate ? 1.9 : 0.9)
                    .opacity(animate ? 0 : 0.8)
                    .animation(
                        .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                        value: animate)
            }
        }
        .onAppear { animate = true }
    }
}

// MARK: - Mono label

struct AgentMonoLabel: View {
    let text: String
    var color: Color = AgentPalette.paperFaint

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

// MARK: - Chip

struct AgentChip: View {
    let text: String
    var tint: Color = AgentPalette.paperSecondary

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                Capsule().fill(Color.white.opacity(0.06))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            )
    }
}

// MARK: - Buttons

struct AgentPrimaryButtonStyle: ButtonStyle {
    var tint: Color = AgentPalette.paper

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(AgentPalette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(minWidth: 72)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct AgentSecondaryButtonStyle: ButtonStyle {
    var tint: Color = AgentPalette.paper

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(minWidth: 72)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Age formatting

enum AgentAge {
    static func string(from date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }
}
