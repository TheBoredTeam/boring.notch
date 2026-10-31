//
//  TimerLiveActivity.swift
//  boringNotch
//
//  Created by Claude on 2026-07-05.
//

import Defaults
import SwiftUI

struct TimerLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var timerManager = TimerManager.shared

    var body: some View {
        HStack {
            CircularProgressView(
                progress: timerManager.progress,
                color: timerColor
            )
            .frame(
                width: max(0, vm.effectiveClosedNotchHeight - 16),
                height: max(0, vm.effectiveClosedNotchHeight - 16)
            )
            .overlay {
                if timerManager.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(timerColor)
                }
            }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Text(timerManager.formattedRemainingTime)
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundStyle(timerColor)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private var timerColor: Color {
        switch timerManager.mode {
        case .shortBreak, .longBreak:
            return .green
        default:
            return .effectiveAccent
        }
    }
}

struct TimerCompletionActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var timerManager = TimerManager.shared

    var body: some View {
        HStack(spacing: 0) {
            Text(completionText)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            Image(systemName: "timer")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: 76, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private var completionText: String {
        switch timerManager.mode {
        case .work:
            return String(localized: "Focus complete")
        case .shortBreak, .longBreak:
            return String(localized: "Break is over")
        case .custom:
            return String(localized: "Time's up!")
        }
    }
}
