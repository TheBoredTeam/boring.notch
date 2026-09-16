//
//  MeetingLiveActivity.swift
//  boringNotch
//
//  Closed and expanded presentations for "a meeting is about to start".
//
//  Follows the same shape as the notification activity: content on the wings
//  either side of a black rectangle masking the physical cutout when closed,
//  and a single obvious action when opened.
//

import Defaults
import SwiftUI

/// Closed notch: a calendar glyph on one wing, the countdown on the other.
struct MeetingLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    let alert: MeetingAlert

    private var itemSize: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }

    /// Amber once it has actually started — the same "you are late" colour
    /// language the Calendar app uses, without needing to read anything.
    private var tint: Color {
        if case .inProgress = alert.timing { return Color(red: 0.984, green: 0.737, blue: 0.180) }
        return .effectiveAccent
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: alert.canJoin ? "video.fill" : "calendar")
                .font(.system(size: max(7, itemSize * 0.5), weight: .medium))
                .foregroundStyle(tint)
                .frame(width: itemSize, height: itemSize)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Text(alert.localizedTiming)
                .font(.system(size: max(9, itemSize * 0.46), weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: max(44, itemSize * 2.4), alignment: .center)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(alert.title), \(alert.localizedTiming)"))
    }
}

/// Open notch: what, when, and one button that does the obvious thing.
struct MeetingExpandedView: View {
    @ObservedObject private var manager = MeetingAlertManager.shared
    let alert: MeetingAlert

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: alert.start)) – \(formatter.string(from: alert.end))"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: alert.canJoin ? "video.fill" : "calendar")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.effectiveAccent.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(alert.localizedTiming) · \(timeRange)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)

                if let provider = alert.meetingLink?.provider {
                    Text(provider.displayName)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer(minLength: 8)

            VStack(spacing: 6) {
                // One primary action. Join when there is something to join,
                // otherwise open the event — offering a dead "Join" button on
                // a meeting with no link would be worse than not offering one.
                Button {
                    if alert.canJoin { manager.join() } else { manager.openInCalendar() }
                } label: {
                    Label(
                        alert.canJoin
                            ? NSLocalizedString("meeting_join", comment: "Button that opens the meeting's video link")
                            : NSLocalizedString("meeting_open", comment: "Button that opens the event in Calendar"),
                        systemImage: alert.canJoin ? "video.fill" : "calendar"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .frame(minWidth: 96)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.effectiveAccent)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    manager.dismissCurrent()
                } label: {
                    Text(NSLocalizedString("meeting_dismiss", comment: "Button that hides the meeting alert"))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Closed notch: a pulsing dot while the microphone is in use.
///
/// Deliberately says "microphone", not "dictation": CoreAudio reports that the
/// input device is running, not which process is using it or why.
struct MicrophoneLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var monitor = MicrophoneActivityMonitor.shared

    @State private var pulse = false

    private var itemSize: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }
    private let tint = Color(red: 0.984, green: 0.549, blue: 0.180)

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "mic.fill")
                .font(.system(size: max(7, itemSize * 0.5), weight: .medium))
                .foregroundStyle(tint)
                .frame(width: itemSize, height: itemSize)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .scaleEffect(pulse ? 1.0 : 0.6)
                .opacity(pulse ? 1 : 0.45)
                .frame(width: itemSize, height: itemSize)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NSLocalizedString("microphone_in_use", comment: "Accessibility label while the microphone is in use")))
    }
}
