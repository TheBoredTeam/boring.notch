//
//  FocusView.swift
//  boringNotch
//
//  The Focus tab: the dial on the left, distraction switches and the day's
//  focus total on the right.
//

import Defaults
import SwiftUI

struct FocusView: View {
    @ObservedObject private var timer = FocusTimerManager.shared
    @ObservedObject private var blocker = DistractionBlocker.shared

    // Read through @Default rather than Defaults[...] directly: a plain
    // subscript read inside `body` is not observed, so editing the blocklist
    // in Settings would leave these switches and counts stale until the view
    // was rebuilt for some other reason.
    @Default(.focusBlockApps) private var blockApps
    @Default(.focusBlockSites) private var blockSites
    @Default(.focusBlockedApps) private var blockedApps
    @Default(.focusBlockedSites) private var blockedSites

    var body: some View {
        HStack(spacing: 14) {
            dialColumn

            Divider()
                .overlay(FocusPalette.border)

            VStack(spacing: 8) {
                distractionsPanel
                focusTotalPanel
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Dial

    private var dialColumn: some View {
        VStack(spacing: 4) {
            FocusDial(
                phase: timer.session.phase,
                progress: timer.progress,
                remaining: timer.remaining,
                totalDuration: timer.session.durations.duration(for: timer.session.phase),
                isIdle: timer.session.isIdle,
                isPaused: timer.session.isPaused,
                onToggle: { timer.toggle() }
            )

            // Skip and Stop only appear once there is something to skip or
            // stop — an idle dial has one obvious action and no clutter.
            HStack(spacing: 10) {
                if !timer.session.isIdle {
                    secondaryButton(
                        title: NSLocalizedString("focus_skip", comment: "Focus control: skip to the next phase"),
                        systemImage: "forward.end.fill"
                    ) { timer.skip() }

                    secondaryButton(
                        title: NSLocalizedString("focus_reset", comment: "Focus control: stop and reset the session"),
                        systemImage: "stop.fill"
                    ) { timer.stop() }
                }
            }
            .frame(height: 16)
        }
        .frame(width: 176)
    }

    private func secondaryButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(FocusPalette.secondary)
                .frame(width: 22, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(title))
    }

    // MARK: - Distractions

    private var distractionsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(NSLocalizedString("focus_distractions", comment: "Focus panel section header").uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .kerning(0.6)
                    .foregroundStyle(FocusPalette.label)

                Spacer()

                Button {
                    SettingsWindowController.shared.showWindow()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(FocusPalette.label)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("focus_edit_blocklist", comment: "Focus panel: open blocklist settings"))
            }

            HStack(spacing: 10) {
                blockToggle(
                    title: NSLocalizedString("focus_block_apps", comment: "Focus toggle: block distracting apps"),
                    systemImage: "square.grid.2x2",
                    isOn: $blockApps,
                    count: blockedApps.count
                )
                blockToggle(
                    title: NSLocalizedString("focus_block_sites", comment: "Focus toggle: block distracting sites"),
                    systemImage: "globe",
                    isOn: $blockSites,
                    count: blockedSites.count
                )
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(FocusPalette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FocusPalette.border, lineWidth: 1)
        )
    }

    private func blockToggle(
        title: String,
        systemImage: String,
        isOn: Binding<Bool>,
        count: Int
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
                .foregroundStyle(FocusPalette.secondary)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                // The count is what makes an empty blocklist obvious before
                // the user starts a session and wonders why nothing happened.
                Text(countLabel(count))
                    .font(.system(size: 8))
                    .foregroundStyle(count == 0 ? .orange.opacity(0.8) : FocusPalette.label)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(count == 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title), \(countLabel(count))"))
    }

    private func countLabel(_ count: Int) -> String {
        count == 0
            ? NSLocalizedString("focus_block_none_selected", comment: "Focus toggle subtitle when the blocklist is empty")
            : String(format: NSLocalizedString("focus_block_count", comment: "Focus toggle subtitle, e.g. '5 selected'"), count)
    }

    // MARK: - Focus total

    private var focusTotalPanel: some View {
        VStack(spacing: 1) {
            Text(FocusTimeFormatter.totalLabel(timer.focusToday))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(NSLocalizedString("focus_time_today", comment: "Label under the day's focus total"))
                .font(.system(size: 9))
                .foregroundStyle(FocusPalette.label)

            if blocker.isActive && blocker.interruptionsBlocked > 0 {
                Text(
                    String(
                        format: NSLocalizedString(
                            "focus_interruptions_blocked",
                            comment: "How many distractions were pushed aside this session"
                        ),
                        blocker.interruptionsBlocked
                    )
                )
                .font(.system(size: 8))
                .foregroundStyle(FocusPalette.work.opacity(0.9))
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(FocusPalette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FocusPalette.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
