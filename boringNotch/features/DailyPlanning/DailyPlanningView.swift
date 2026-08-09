import AppKit
import SwiftUI

struct DailyPlanningView: View {
    @ObservedObject private var manager = DailyPlanningManager.shared

    var body: some View {
        ZStack {
            if !manager.isFinishingSession {
                VStack(spacing: 8) {
                    header
                    content
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.12), value: manager.isFinishingSession)
        .task(id: manager.isFinishingSession) {
            guard manager.isFinishingSession else { return }

            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            manager.finalizeActiveSession()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: sessionKind == .eveningReview ? "moon.stars.fill" : "sunrise.fill")
                .foregroundStyle(sessionKind == .eveningReview ? .indigo : .orange)
            VStack(alignment: .leading, spacing: 0) {
                Text(sessionKind == .eveningReview ? "Evening Review" : "Today’s Plan")
                    .font(.headline)
                if let date = manager.activeSession?.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            DailyWorkflowFinishButton(kind: sessionKind) {
                manager.beginFinishingActiveSession()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch manager.contentState {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading today’s reminders…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)

        case .permissionDenied:
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.lock.fill")
                    .foregroundStyle(.orange)
                Text("Allow Reminders access to use daily planning and review.")
                    .font(.callout)
                Spacer()
                Button("Open Settings") {
                    guard
                        let url = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                        )
                    else {
                        return
                    }
                    NSWorkspace.shared.open(url)
                }
                .controlSize(.small)
            }
            .frame(maxHeight: .infinity)

        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .frame(maxHeight: .infinity)

        case .loaded(let sections):
            if sections.all.isEmpty {
                Label("No reminders are due today.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else if sessionKind == .eveningReview {
                eveningSections(sections)
            } else {
                reminderList(sections.all, emptyMessage: "Nothing planned")
            }
        }
    }

    private var sessionKind: DailyWorkflowKind {
        manager.activeSession?.kind ?? .morningPlanning
    }

    private func eveningSections(_ sections: DailyReminderSections) -> some View {
        HStack(alignment: .top, spacing: 12) {
            reminderSection(
                title: "Still open",
                count: sections.incomplete.count,
                symbol: "circle",
                color: .orange,
                items: sections.incomplete
            )
            Divider()
            reminderSection(
                title: "Completed",
                count: sections.completed.count,
                symbol: "checkmark.circle.fill",
                color: .green,
                items: sections.completed
            )
        }
    }

    private func reminderSection(
        title: String,
        count: Int,
        symbol: String,
        color: Color,
        items: [DailyReminderItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol).foregroundStyle(color)
                Text("\(title) · \(count)")
                    .font(.caption.bold())
            }
            reminderList(items, emptyMessage: "None")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reminderList(_ items: [DailyReminderItem], emptyMessage: String) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                if items.isEmpty {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(items) { item in
                        DailyReminderRow(item: item, manager: manager)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }

}

struct DailyWorkflowNotificationView: View {
    let session: DailyWorkflowSession
    let notchWidth: CGFloat
    let height: CGFloat

    private let bellCycleDuration = 2.4
    private let bellRingDuration = 0.9
    private let pulseDuration = 1.2

    var body: some View {
        HStack(spacing: 0) {
            Color.black
                .frame(width: notchWidth)

            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let ringTime = elapsed.truncatingRemainder(dividingBy: bellCycleDuration)
                let pulse = elapsed.truncatingRemainder(dividingBy: pulseDuration) / pulseDuration

                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .rotationEffect(
                            .degrees(bellAngle(at: ringTime)),
                            anchor: .top
                        )
                        .frame(width: 20, height: 28)

                    Text(session.kind.notificationTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)

                    ZStack {
                        Circle()
                            .stroke(Color.green.opacity(1 - pulse), lineWidth: 1.25)
                            .frame(width: 6, height: 6)
                            .scaleEffect(1 + pulse * 2.2)

                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .shadow(color: Color.green.opacity(0.65), radius: 4)
                    }
                    .frame(width: 22, height: 28)
                }
                .padding(.horizontal, 12)
                .frame(width: 236, height: height, alignment: .leading)
            }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(session.kind.notificationAccessibilityLabel)
    }

    private func bellAngle(at elapsed: TimeInterval) -> Double {
        guard elapsed < bellRingDuration else { return 0 }
        let progress = elapsed / bellRingDuration
        return sin(progress * .pi * 7) * 11 * (1 - progress)
    }
}

private struct DailyWorkflowFinishButton: View {
    let kind: DailyWorkflowKind
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(kind.actionTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.effectiveAccent)
                    .offset(x: isHovering ? 2 : 0)
                    .animation(StandardAnimations.interactive, value: isHovering)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DailyWorkflowFinishButtonStyle(isHovering: isHovering))
        .onHover { hovering in
            withAnimation(StandardAnimations.interactive) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(kind.actionTitle)
    }
}

private struct DailyWorkflowFinishButtonStyle: ButtonStyle {
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovering ? Color.primary : Color.secondary)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(Color.effectiveAccent)
                    .frame(height: 1)
                    .scaleEffect(x: isHovering ? 1 : 0, anchor: .leading)
            }
            .opacity(configuration.isPressed ? 0.68 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(StandardAnimations.interactive, value: configuration.isPressed)
            .animation(StandardAnimations.interactive, value: isHovering)
    }
}

private struct DailyReminderRow: View {
    let item: DailyReminderItem
    @ObservedObject var manager: DailyPlanningManager

    var body: some View {
        HStack(spacing: 7) {
            Button(action: toggleCompletion) {
                DailyReminderCompletionMark(isCompleted: displayedCompletion)
            }
            .buttonStyle(.plain)
            .disabled(
                manager.isFinishingSession
                    || manager.updatingReminderIDs.contains(item.id)
            )
            .accessibilityLabel(
                displayedCompletion ? "Mark as not completed" : "Mark as completed"
            )

            AnimatedReminderTitle(
                title: item.title.isEmpty ? "Untitled reminder" : item.title,
                isCompleted: displayedCompletion
            )

            Spacer(minLength: 4)

            Text(item.listTitle)
                .font(.caption2)
                .foregroundStyle(displayedCompletion ? .quaternary : .tertiary)
                .lineLimit(1)
                .animation(.easeInOut(duration: 0.28), value: displayedCompletion)
        }
        .padding(.vertical, 3)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .animation(.easeInOut(duration: 0.18), value: isVisible)
    }

    private func toggleCompletion() {
        let completed = !displayedCompletion

        Task {
            await manager.setReminderCompleted(
                reminderID: item.id,
                completed: completed,
                animateSectionTransfer: manager.activeSession?.kind == .eveningReview
            )
        }
    }

    private var transition: DailyReminderTransition? {
        manager.reminderTransitions[item.id]
    }

    private var displayedCompletion: Bool {
        transition?.targetCompletion ?? item.isCompleted
    }

    private var isVisible: Bool {
        transition?.phase != .hidden
    }
}

private struct DailyReminderCompletionMark: View {
    let isCompleted: Bool

    @State private var isHovering = false

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: isCompleted ? 0 : 1)
                .stroke(
                    strokeColor,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    isCompleted
                        ? .linear(duration: 0.3)
                        : .linear(duration: 0.3).delay(0.12),
                    value: isCompleted
                )

            DailyReminderCheckmarkShape()
                .trim(from: 0, to: isCompleted ? 1 : 0)
                .stroke(
                    strokeColor,
                    style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
                )
                .padding(3)
                .animation(
                    isCompleted
                        ? .linear(duration: 0.2).delay(0.15)
                        : .linear(duration: 0.15),
                    value: isCompleted
                )
        }
        .frame(width: 18, height: 18)
        .padding(2)
        .contentShape(Circle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }

    private var strokeColor: Color {
        isCompleted || isHovering ? .effectiveAccent : .secondary
    }
}

private struct DailyReminderCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.84))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.16))
        return path
    }
}

private struct AnimatedReminderTitle: View {
    let title: String
    let isCompleted: Bool

    var body: some View {
        Text(title)
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(isCompleted ? .secondary : .primary)
            .overlay {
                AnimatedStrikeThroughShape(progress: isCompleted ? 1 : 0)
                    .stroke(
                        Color.secondary.opacity(0.8),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                    .animation(
                        isCompleted
                            ? .easeInOut(duration: 0.28).delay(0.07)
                            : .easeInOut(duration: 0.24),
                        value: isCompleted
                    )
            }
            .offset(x: isCompleted ? 4 : 0)
            .animation(.easeInOut(duration: 0.32), value: isCompleted)
    }
}

private struct AnimatedStrikeThroughShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * progress, y: rect.midY))
        return path
    }
}

private extension DailyWorkflowKind {
    var notificationTitle: String {
        switch self {
        case .morningPlanning: String(localized: "Ready to plan your day?")
        case .eveningReview: String(localized: "Ready to review your day?")
        }
    }

    var actionTitle: String {
        switch self {
        case .morningPlanning: String(localized: "Start My Day")
        case .eveningReview: String(localized: "Wrap Up My Day")
        }
    }

    var notificationAccessibilityLabel: String {
        switch self {
        case .morningPlanning:
            String(localized: "Morning planning is ready. Hover to open.")
        case .eveningReview:
            String(localized: "Evening review is ready. Hover to open.")
        }
    }
}

#Preview {
    DailyPlanningView()
        .frame(width: 616, height: 142)
        .preferredColorScheme(.dark)
}
