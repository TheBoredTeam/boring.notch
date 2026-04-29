//
//  PomodoroClosedView.swift
//  boringNotch
//
//  Created by Claw on 2026-04-29.
//  Compact timer display for closed notch state.
//

import SwiftUI

struct PomodoroClosedView: View {
    @ObservedObject var pomodoroManager: PomodoroManager
    
    var body: some View {
        HStack(spacing: 6) {
            // Phase indicator dot
            Circle()
                .fill(phaseColor)
                .frame(width: 6, height: 6)
            
            // Timer text
            Text(pomodoroManager.formattedTime)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
            
            // Sessions counter
            if pomodoroManager.sessionsCompleted > 0 {
                Text("•\(pomodoroManager.sessionsCompleted)")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.5))
        )
    }
    
    private var phaseColor: Color {
        switch pomodoroManager.currentPhase {
        case .work:
            return Color(red: 1.0, green: 0.4, blue: 0.4) // Red for work
        case .shortBreak:
            return Color(red: 0.4, green: 1.0, blue: 0.4) // Green for short break
        case .longBreak:
            return Color(red: 0.4, green: 0.8, blue: 1.0) // Blue for long break
        }
    }
}