import AppKit
import SwiftUI

struct DailyPlanningView: View {
    @ObservedObject private var manager = DailyPlanningManager.shared

    var body: some View {
        ZStack {
            if manager.isFinishingSession {
                DailyWorkflowCompletionView(kind: sessionKind)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
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

            try? await Task.sleep(for: .seconds(2))
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
        manager.activeSession?.kind ?? manager.finishingSession?.kind ?? .morningPlanning
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

private struct DailyWorkflowCompletionView: View {
    let kind: DailyWorkflowKind

    @State private var isVisible = false

    @State private var copy: DailyWorkflowCompletionCopy

    init(kind: DailyWorkflowKind) {
        self.kind = kind
        _copy = State(initialValue: DailyWorkflowCompletionCopy.random(for: kind))
    }

    private var glowColors: [Color] {
        kind == .morningPlanning
            ? [.orange.opacity(0.72), .yellow.opacity(0.28), .clear]
            : [.indigo.opacity(0.72), .purple.opacity(0.28), .clear]
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: glowColors,
                            center: .center,
                            startRadius: 3,
                            endRadius: 42
                        )
                    )
                    .frame(width: 84, height: 84)
                    .scaleEffect(isVisible ? 1 : 0.35)
                    .opacity(isVisible ? 1 : 0)

                DailyWorkflowSunMoonTransition(kind: kind)
                    .frame(width: 42, height: 42)
                    .scaleEffect(isVisible ? 1 : 0.45)
                    .rotationEffect(.degrees(isVisible ? 0 : -18))
            }

            VStack(spacing: 2) {
                Text(copy.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(copy.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }
}

private struct DailyWorkflowCompletionCopy {
    let title: String
    let subtitle: String

    static func random(for kind: DailyWorkflowKind) -> Self {
        let choices = kind == .morningPlanning ? morningChoices : eveningChoices
        return choices.randomElement() ?? choices[0]
    }

    private static let morningChoices: [Self] = [
        .init(title: String(localized: "A clear start."), subtitle: String(localized: "One good thing at a time.")),
        .init(title: String(localized: "You’re underway."), subtitle: String(localized: "Ready when you are.")),
        .init(title: String(localized: "A fresh page."), subtitle: String(localized: "Make space for what matters.")),
        .init(title: String(localized: "Day, unlocked."), subtitle: String(localized: "Start with what feels important.")),
        .init(title: String(localized: "A thoughtful start."), subtitle: String(localized: "Small steps count.")),
        .init(title: String(localized: "You’ve got this."), subtitle: String(localized: "Your time has a direction.")),
        .init(title: String(localized: "Plans in place."), subtitle: String(localized: "Leave room for the unexpected.")),
        .init(title: String(localized: "Start gently."), subtitle: String(localized: "There’s no need to rush.")),
        .init(title: String(localized: "Good morning."), subtitle: String(localized: "Make today yours.")),
        .init(title: String(localized: "Onward."), subtitle: String(localized: "Begin with intention."))
    ]

    private static let eveningChoices: [Self] = [
        .init(title: String(localized: "Day reviewed."), subtitle: String(localized: "That’s enough for today.")),
        .init(title: String(localized: "A gentle close."), subtitle: String(localized: "Leave the rest for tomorrow.")),
        .init(title: String(localized: "You made it through."), subtitle: String(localized: "Let the day settle.")),
        .init(title: String(localized: "Day, complete."), subtitle: String(localized: "Rest is part of the work.")),
        .init(title: String(localized: "Time to unwind."), subtitle: String(localized: "You showed up for today.")),
        .init(title: String(localized: "That’s a wrap."), subtitle: String(localized: "Tomorrow can wait.")),
        .init(title: String(localized: "A day well held."), subtitle: String(localized: "Take a breath—you’re done.")),
        .init(title: String(localized: "Close the loop."), subtitle: String(localized: "Let tonight be yours.")),
        .init(title: String(localized: "Well done today."), subtitle: String(localized: "The rest can be quiet.")),
        .init(title: String(localized: "Until tomorrow."), subtitle: String(localized: "You’ve done enough."))
    ]
}

private struct DailyWorkflowSunMoonTransition: View {
    let kind: DailyWorkflowKind

    @State private var hasTransitioned = false

    private var isSun: Bool {
        kind == .morningPlanning ? hasTransitioned : !hasTransitioned
    }

    private var sunColor: Color { .yellow.opacity(0.96) }

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(sunColor)
                    .frame(width: 2, height: 7)
                    .offset(y: -18)
                    .rotationEffect(.degrees(Double(index) * 45))
                    .scaleEffect(isSun ? 1 : 0, anchor: .bottom)
                    .opacity(isSun ? 1 : 0)
                    .animation(
                        .easeOut(duration: 0.4).delay(Double(index) * 0.035),
                        value: isSun
                    )
            }

            ZStack {
                Circle()
                    .fill(isSun ? sunColor : .white.opacity(0.9))

                Circle()
                    .fill(.black)
                    .offset(x: isSun ? 34 : 10, y: -4)
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            .scaleEffect(isSun ? 0.7 : 1)
            .rotationEffect(.degrees(isSun ? 90 : 40))
            .animation(.spring(response: 0.64, dampingFraction: 0.65), value: isSun)
        }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                hasTransitioned = true
            }
        }
    }
}

struct DailyWorkflowNotificationView: View {
    let session: DailyWorkflowSession
    let notchWidth: CGFloat
    let height: CGFloat

    private let promptWidth: CGFloat = 236
    private let promptContentOffset: CGFloat = 5
    private let bellCycleDuration = 2.4
    private let bellRingDuration = 0.9
    private let pulseDuration = 1.2

    @ViewBuilder
    var body: some View {
        if notchWidth > 0 {
            VStack(spacing: 0) {
                Color.clear
                    .frame(width: notchWidth, height: height)

                prompt(
                    leadingInset: 12 + promptContentOffset,
                    trailingInset: 12 - promptContentOffset
                )
                    .frame(width: promptWidth, height: height, alignment: .leading)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(session.kind.notificationAccessibilityLabel)
        } else {
            prompt(
                leadingInset: 12 + promptContentOffset,
                trailingInset: 12 - promptContentOffset
            )
                .frame(width: promptWidth, height: height, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(session.kind.notificationAccessibilityLabel)
        }
    }

    private func prompt(leadingInset: CGFloat = 12, trailingInset: CGFloat = 12) -> some View {
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
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
        }
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

struct DailyPlanningSettingsSection: View {
    @ObservedObject private var manager = DailyPlanningManager.shared

    var body: some View {
        Section(header: Text("Daily Planning & Review")) {
            Toggle(
                "Morning planning",
                isOn: enabledBinding(for: .morningPlanning)
            )
            DatePicker(
                "Planning time",
                selection: timeBinding(for: .morningPlanning),
                displayedComponents: .hourAndMinute
            )
            .disabled(!manager.preferences.morningPlanningEnabled)

            Toggle(
                "Evening review",
                isOn: enabledBinding(for: .eveningReview)
            )
            DatePicker(
                "Review time",
                selection: timeBinding(for: .eveningReview),
                displayedComponents: .hourAndMinute
            )
            .disabled(!manager.preferences.eveningReviewEnabled)

            Text(
                "Sessions notify you in the notch, open when you hover, and stay until you finish. Times are stored on this Mac."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func enabledBinding(for kind: DailyWorkflowKind) -> Binding<Bool> {
        Binding(
            get: { manager.preferences.isEnabled(kind) },
            set: { manager.setEnabled($0, for: kind) }
        )
    }

    private func timeBinding(for kind: DailyWorkflowKind) -> Binding<Date> {
        Binding(
            get: { manager.configuredTime(for: kind) },
            set: { manager.setTime($0, for: kind) }
        )
    }
}

#Preview {
    DailyPlanningView()
        .frame(width: 616, height: 142)
        .preferredColorScheme(.dark)
}
