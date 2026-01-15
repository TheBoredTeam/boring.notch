//
//  ToolActivityIndicator.swift
//  boringNotch
//
//  Animated indicator showing when Claude Code tools are running
//

import SwiftUI

struct ToolActivityIndicator: View {
    let isActive: Bool
    let toolName: String?

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Pulse ring when active
            if isActive {
                Circle()
                    .stroke(Color.green.opacity(0.5), lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .scaleEffect(isAnimating ? 1.5 : 1.0)
                    .opacity(isAnimating ? 0 : 0.8)
            }

            // Icon
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundColor(isActive ? .green : .gray)
                .rotationEffect(.degrees(isActive && shouldRotate ? (isAnimating ? 360 : 0) : 0))
        }
        .frame(width: 24, height: 24)
        .onAppear {
            if isActive {
                startAnimation()
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                startAnimation()
            } else {
                isAnimating = false
            }
        }
    }

    private var iconName: String {
        guard let name = toolName?.lowercased() else {
            return "terminal.fill"
        }

        switch name {
        case "bash":
            return "terminal.fill"
        case "read":
            return "doc.text.fill"
        case "write":
            return "pencil"
        case "edit":
            return "pencil.line"
        case "glob":
            return "magnifyingglass"
        case "grep":
            return "text.magnifyingglass"
        case "task":
            return "person.fill"
        case "webfetch":
            return "globe"
        case "websearch":
            return "magnifyingglass.circle"
        default:
            return "gearshape.fill"
        }
    }

    private var shouldRotate: Bool {
        guard let name = toolName?.lowercased() else { return false }
        return ["bash", "task", "webfetch", "websearch"].contains(name)
    }

    private func startAnimation() {
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            isAnimating = true
        }
    }
}

struct ToolActivityIndicatorCompact: View {
    let isActive: Bool

    @State private var dotIndex = 0
    private let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(isActive ? (index == dotIndex ? Color.green : Color.green.opacity(0.3)) : Color.gray.opacity(0.3))
                    .frame(width: 4, height: 4)
            }
        }
        .onReceive(timer) { _ in
            if isActive {
                dotIndex = (dotIndex + 1) % 3
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            ToolActivityIndicator(isActive: true, toolName: "Bash")
            ToolActivityIndicator(isActive: true, toolName: "Read")
            ToolActivityIndicator(isActive: true, toolName: "Glob")
            ToolActivityIndicator(isActive: false, toolName: nil)
        }

        HStack(spacing: 20) {
            ToolActivityIndicatorCompact(isActive: true)
            ToolActivityIndicatorCompact(isActive: false)
        }
    }
    .padding()
    .background(Color.black.opacity(0.8))
}
