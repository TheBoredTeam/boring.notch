//
//  SessionDotsIndicator.swift
//  boringNotch
//
//  Row of dots showing all active Claude Code sessions
//  Green blinking = active (thinking or running tools), Orange blinking = needs permission, Gray = idle
//

import SwiftUI

struct SessionDotsIndicator: View {
    @ObservedObject var manager = ClaudeCodeManager.shared

    var body: some View {
        HStack(spacing: 6) {
            ForEach(manager.availableSessions) { session in
                SessionDot(
                    session: session,
                    state: manager.sessionStates[session.id]
                )
                .onTapGesture {
                    manager.focusIDE(for: session)
                }
            }
        }
    }
}

struct SessionDot: View {
    let session: ClaudeSession
    let state: ClaudeCodeState?

    @State private var isBlinking = false

    private var dotColor: Color {
        if state?.needsPermission == true {
            return .orange
        } else if state?.isActive == true {
            return .green
        }
        return .gray
    }

    private var shouldBlink: Bool {
        state?.needsPermission == true || state?.isActive == true
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(dotColor)
            .frame(width: 14, height: 3)
            .opacity(shouldBlink ? (isBlinking ? 1.0 : 0.3) : 0.5)
            .animation(.easeInOut(duration: 0.6), value: isBlinking)
            .onAppear {
                startBlinkingIfNeeded()
            }
            .onChange(of: shouldBlink) { _, newValue in
                if newValue {
                    startBlinkingIfNeeded()
                } else {
                    isBlinking = false
                }
            }
            .onChange(of: state?.needsPermission) { _, _ in
                // Reset animation when permission state changes
                if shouldBlink {
                    isBlinking = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        startBlinkingIfNeeded()
                    }
                }
            }
            .help(tooltipText)
    }

    private var tooltipText: String {
        var text = session.displayName
        if state?.needsPermission == true {
            text += " - Needs permission"
        } else if state?.isActive == true {
            text += " - Working"
        } else {
            text += " - Idle"
        }
        return text
    }

    private func startBlinkingIfNeeded() {
        guard shouldBlink else { return }
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            isBlinking = true
        }
    }
}

/// Compact version showing just the dots without additional styling
struct SessionDotsIndicatorCompact: View {
    @ObservedObject var manager = ClaudeCodeManager.shared

    var body: some View {
        HStack(spacing: 4) {
            ForEach(manager.availableSessions) { session in
                SessionDotCompact(
                    session: session,
                    state: manager.sessionStates[session.id]
                )
                .onTapGesture {
                    manager.focusIDE(for: session)
                }
            }
        }
    }
}

struct SessionDotCompact: View {
    let session: ClaudeSession
    let state: ClaudeCodeState?

    @State private var isBlinking = false

    private var dotColor: Color {
        if state?.needsPermission == true {
            return .orange
        } else if state?.isActive == true {
            return .green
        }
        return .gray
    }

    private var shouldBlink: Bool {
        state?.needsPermission == true || state?.isActive == true
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(dotColor)
            .frame(width: 14, height: 3)
            .opacity(shouldBlink ? (isBlinking ? 1.0 : 0.3) : 0.5)
            .animation(.easeInOut(duration: 0.6), value: isBlinking)
            .onAppear {
                if shouldBlink {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        isBlinking = true
                    }
                }
            }
            .onChange(of: shouldBlink) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        isBlinking = true
                    }
                } else {
                    isBlinking = false
                }
            }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Normal size
        SessionDotsIndicator()
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)

        // Compact size
        SessionDotsIndicatorCompact()
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
    }
    .padding()
}
