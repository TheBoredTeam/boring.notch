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
            Button(sessionKind == .eveningReview ? "Finish Review" : "Finish Planning") {
                manager.beginFinishingActiveSession()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
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
                        reminderRow(item)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reminderRow(_ item: DailyReminderItem) -> some View {
        HStack(spacing: 6) {
            Button {
                Task {
                    await manager.setReminderCompleted(
                        reminderID: item.id,
                        completed: !item.isCompleted
                    )
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(
                manager.isFinishingSession || manager.updatingReminderIDs.contains(item.id)
            )
            Text(item.title.isEmpty ? "Untitled reminder" : item.title)
                .font(.caption)
                .lineLimit(1)
                .strikethrough(item.isCompleted)
            Spacer(minLength: 4)
            Text(item.listTitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
        .animation(.easeInOut(duration: 0.15), value: item.isCompleted)
    }
}

#Preview {
    DailyPlanningView()
        .frame(width: 616, height: 142)
        .preferredColorScheme(.dark)
}
