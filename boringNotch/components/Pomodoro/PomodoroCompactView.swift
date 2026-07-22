//
//  PomodoroCompactView.swift
//  boringNotch
//

import SwiftUI

struct PomodoroCompactView: View {
    @ObservedObject var timer = PomodoroTimerViewModel.shared
    let closedNotchWidth: CGFloat
    let height: CGFloat

    var body: some View {
        // Mirror closed music layout sizing so spacing from the camera is consistent.
        let sideSlotWidth = max(0, height - 12)

        HStack(spacing: 0) {
            HStack {
                Image(systemName: timer.currentPhase.systemImage)
                    .font(.caption2)
                    .foregroundStyle(timer.currentPhase.tintColor)
            }
            .frame(width: sideSlotWidth, height: sideSlotWidth, alignment: .center)

            Rectangle()
                .fill(.black)
                .frame(width: max(0, closedNotchWidth))

            HStack {
                Text(timer.compactFormattedTime)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: sideSlotWidth, height: sideSlotWidth, alignment: .center)
        }
        .frame(height: height, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                format: NSLocalizedString("pomodoro_a11y_compact", comment: "A11y: Pomodoro state"),
                timer.formattedTime,
                timer.currentPhase.localizedString
            )
        )
    }
}
