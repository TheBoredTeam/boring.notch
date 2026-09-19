//
//  FocusLiveActivity.swift
//  boringNotch
//
//  The closed-notch presentation of a running focus session: a phase glyph on
//  one wing, the countdown on the other.
//
//  Laid out the same way as the music activity — content on the wings either
//  side of a black rectangle that masks the physical notch cutout — so the
//  two look like the same system rather than two different widgets.
//

import SwiftUI

struct FocusLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var timer = FocusTimerManager.shared

    private var phase: FocusPhase { timer.session.phase }
    private var tint: Color { FocusPalette.tint(for: phase) }
    private var itemSize: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(FocusPalette.track, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: min(1, max(0, timer.progress)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: timer.progress)
                Image(systemName: phase.systemImage)
                    .font(.system(size: max(6, itemSize * 0.42), weight: .medium))
                    .foregroundStyle(tint)
            }
            .frame(width: itemSize, height: itemSize)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Text(FocusTimeFormatter.countdown(timer.remaining))
                .font(.system(size: max(9, itemSize * 0.5), weight: .semibold, design: .rounded))
                .monospacedDigit()
                // A fixed width stops the pill twitching as the countdown
                // crosses 10:00 -> 9:59.
                .frame(width: max(34, itemSize * 2), alignment: .center)
                .foregroundStyle(timer.session.isPaused ? FocusPalette.secondary : .white)
                .opacity(timer.session.isPaused ? 0.6 : 1)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(phase.localizedTitle), \(FocusTimeFormatter.countdown(timer.remaining))")
        )
    }
}
