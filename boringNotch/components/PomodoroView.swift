//
//  PomodoroView.swift
//  boringNotch
//
//  Created by Christian Teo on 2026-04-29.
//

import SwiftUI

struct PomodoroView: View {
    @ObservedObject var pomodoroManager = PomodoroManager.shared
    @State private var isLongPressing: Bool = false
    
    private let timerSize: CGFloat = 140
    private let progressLineWidth: CGFloat = 6

    var body: some View {
        VStack(spacing: 12) {
            // Phase indicator dots
            phaseIndicators
            
            // Circular progress timer
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: progressLineWidth)
                
                // Progress circle
                Circle()
                    .trim(from: 0, to: pomodoroManager.progress)
                    .stroke(
                        pomodoroManager.phaseColor,
                        style: StrokeStyle(lineWidth: progressLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: pomodoroManager.progress)
                
                // Timer content
                VStack(spacing: 2) {
                    Text(pomodoroManager.currentPhase.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.gray)
                    
                    Text(pomodoroManager.formattedTime)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: timerSize, height: timerSize)
            
            // Sessions counter with long-press
            sessionsCounter
            
            // Control buttons
            controlButtons
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    
    // MARK: - Subviews
    
    private var phaseIndicators: some View {
        HStack(spacing: 16) {
            ForEach(PomodoroManager.PomodoroPhase.allCases, id: \.self) { phase in
                VStack(spacing: 4) {
                    Circle()
                        .fill(pomodoroManager.currentPhase == phase ? pomodoroManager.phaseColor : Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                    
                    Text(phase.displayName)
                        .font(.system(size: 9))
                        .foregroundColor(pomodoroManager.currentPhase == phase ? .white : .gray)
                }
            }
        }
    }
    
    private var sessionsCounter: some View {
        HStack(spacing: 4) {
            Text("Sessions")
                .font(.system(size: 11))
                .foregroundStyle(.gray)
            
            Text("\(pomodoroManager.sessionsCompleted)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(sessionsCompletedColor)
                .scaleEffect(isLongPressing ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isLongPressing)
            
            if pomodoroManager.sessionsCompleted > 0 {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 9))
                    .foregroundStyle(.gray.opacity(0.5))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.05))
        )
        .contentShape(Rectangle())
        .gesture(
            LongPressGesture(minimumDuration: 0.8)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isLongPressing = true
                    }
                }
                .onEnded { _ in
                    pomodoroManager.resetSessions()
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isLongPressing = false
                    }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isLongPressing = false
                    }
                }
        )
    }
    
    private var sessionsCompletedColor: Color {
        if pomodoroManager.sessionsCompleted % pomodoroManager.sessionsBeforeLongBreak == 0 && pomodoroManager.sessionsCompleted > 0 {
            return .blue
        } else if pomodoroManager.currentPhase == .work {
            return .red
        } else {
            return .green
        }
    }
    
    private var controlButtons: some View {
        HStack(spacing: 24) {
            // Reset button
            Button(action: {
                pomodoroManager.reset()
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.gray)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Reset Timer")
            
            // Play/Pause button
            Button(action: {
                if pomodoroManager.isRunning {
                    pomodoroManager.pause()
                } else {
                    pomodoroManager.start()
                }
            }) {
                Image(systemName: pomodoroManager.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(pomodoroManager.phaseColor.opacity(0.8))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .help(pomodoroManager.isRunning ? "Pause" : "Start")
            
            // Skip button
            Button(action: {
                pomodoroManager.pause()
                pomodoroManager.reset()
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.gray)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Skip to Next")
        }
    }
}

#Preview {
    PomodoroView()
        .frame(width: 300, height: 300)
        .background(Color.black)
}