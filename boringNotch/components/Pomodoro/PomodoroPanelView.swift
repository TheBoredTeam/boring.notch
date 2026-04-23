//
//  PomodoroPanelView.swift
//  boringNotch

import SwiftUI

// Layout budget (measured from the notch open content area):
//   Total notch open height: 190px
//   Bottom padding on NotchLayout: 12px  → 178px
//   BoringHeader (frame height ~32px): 32px → ~146px for NotchHomeView content
//   Panel width: 215px (170px with camera)
//
// Budget breakdown (146px):
//   Controls (large HoverButton): 40px
//   Phase + Session labels:       ~32px
//   Ring:                          70px   ← designed to fit exactly
//   Adaptive spacers:               ~4px
//   Total:                        ~146px ✓

struct PomodoroPanelView: View {
    @ObservedObject private var timer = PomodoroTimerViewModel.shared

    // Arc spans 270° (0.75 of full circle), open at the bottom.
    // Rotating 135° clockwise puts the arc start at 7-o'clock so the
    // 90° gap sits centered at 6-o'clock (bottom).
    private let maxRingSize: CGFloat = 88
    private let ringLineWidth: CGFloat = 5
    private let arcFraction: Double = 0.75
    private let arcRotation: Double = 135
    private let controlsRowHeight: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let topInset: CGFloat = 8
            let ringToControlsGap: CGFloat = 2
            let computedRingSize = min(
                maxRingSize,
                max(
                    62,
                    geo.size.height - controlsRowHeight - topInset - ringToControlsGap
                )
            )

            VStack(alignment: .center, spacing: 0) {
                Color.clear
                    .frame(height: topInset)

                ringWithContent(size: computedRingSize)

                Spacer(minLength: ringToControlsGap)

                controlsToolbar
                    .frame(height: controlsRowHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                format: NSLocalizedString("pomodoro_a11y_compact", comment: "A11y: Pomodoro state"),
                timer.formattedTime,
                timer.currentPhase.localizedString
            )
        )
    }

    // MARK: - Ring

    private func ringWithContent(size: CGFloat) -> some View {
        ZStack {
            // Background track arc
            Circle()
                .trim(from: 0, to: arcFraction)
                .stroke(
                    Color.white.opacity(0.14),
                    style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(arcRotation))

            // Progress fill arc
            Circle()
                .trim(from: 0, to: timer.progress * arcFraction)
                .stroke(
                    timer.currentPhase.tintColor,
                    style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(arcRotation))
                .animation(.linear(duration: 0.35), value: timer.progress)

            // Stack inside ring area: icon at top, then Focus + Session.
            VStack(spacing: 0) {
                Image(systemName: timer.currentPhase.systemImage)
                    .font(.system(size: max(10, size * 0.16), weight: .regular))
                    .foregroundStyle(timer.currentPhase.tintColor)
                    .padding(.bottom, max(1, size * 0.02))

                VStack(spacing: 0) {
                    Text(timer.currentPhase.localizedString)
                        .font(.system(size: max(11, size * 0.145), weight: .semibold, design: .default))
                        .foregroundStyle(timer.currentPhase.tintColor)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-2)
                        .minimumScaleFactor(0.85)
                        .lineLimit(2)

                    Text(String(
                        format: NSLocalizedString("pomodoro_session_label_format", comment: "Pomodoro session label"),
                        timer.completedFocusSessions + 1
                    ))
                    .font(.system(size: max(8, size * 0.1), weight: .semibold, design: .default))
                    .foregroundStyle(.gray)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.top, max(2, size * 0.03))
                }
            }
            .offset(y: -(size * 0.03))

            // Overlay timer in the lower gap area.
            Text(timer.formattedTime)
                .font(.system(size: max(16, size * 0.08), weight: .light, design: .default))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .offset(y: size * 0.43)
                .zIndex(1)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Controls — same HoverButton scales as music slotToolbar

    private var controlsToolbar: some View {
        HStack(spacing: 6) {
            HoverButton(icon: "arrow.counterclockwise", scale: .medium) {
                timer.reset()
            }
            .accessibilityLabel(NSLocalizedString("pomodoro_a11y_reset", comment: "Reset Pomodoro"))

            HoverButton(
                icon: timer.isRunning ? "pause.fill" : "play.fill",
                scale: .large
            ) {
                timer.toggleStartPause()
            }
            .accessibilityLabel(
                timer.isRunning
                    ? NSLocalizedString("pomodoro_a11y_pause", comment: "Pause Pomodoro")
                    : NSLocalizedString("pomodoro_a11y_resume", comment: "Resume Pomodoro")
            )

            HoverButton(icon: "forward.fill", scale: .medium) {
                timer.skip()
            }
            .accessibilityLabel(NSLocalizedString("pomodoro_a11y_skip", comment: "Skip to next Pomodoro phase"))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
