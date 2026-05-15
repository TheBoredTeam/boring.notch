//
//  CompanionRootView.swift
//  KairoiOS — main companion screen
//
//  Two halves:
//    1. Top: paired Mac status — name, connection state, "Start Live
//       Activity" button.
//    2. Bottom: recent transcript snippets and a compact toolbox row.
//
//  Real pairing / state-sync is out of scope for the scaffold — the view
//  reads from a `CompanionViewModel` that today returns sample data.
//

import SwiftUI
import ActivityKit

struct CompanionRootView: View {
    @StateObject private var vm = CompanionViewModel()

    var body: some View {
        ZStack {
            Kairo.Palette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Kairo.Space.xl) {
                    header
                    pairedMacCard
                    recentSection
                    quickActions
                }
                .padding(Kairo.Space.lg)
                .padding(.top, Kairo.Space.xl)
            }
        }
        .foregroundStyle(Kairo.Palette.text)
        .onAppear { vm.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.xs) {
            Text("Kairo")
                .font(Kairo.Typography.display)
            Text("Your assistant, on your wrist.")
                .font(Kairo.Typography.body)
                .foregroundStyle(Kairo.Palette.textDim)
        }
    }

    // MARK: - Paired Mac card

    private var pairedMacCard: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.md) {
            HStack {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Kairo.Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.macDeviceName)
                        .font(Kairo.Typography.titleSmall)
                    Text(vm.connectionState)
                        .font(Kairo.Typography.bodySmall)
                        .foregroundStyle(vm.isConnected ? Kairo.Palette.success : Kairo.Palette.textDim)
                }
                Spacer()
                StatusDot(connected: vm.isConnected)
            }

            Button {
                vm.toggleLiveActivity()
            } label: {
                HStack {
                    Image(systemName: vm.liveActivityActive ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(vm.liveActivityActive ? "Stop Live Activity" : "Start Live Activity")
                        .font(Kairo.Typography.bodyEmphasis)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Kairo.Space.md)
                .background(
                    RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                        .fill(Kairo.Palette.accent)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(Kairo.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Kairo.Radius.lg, style: .continuous)
                .fill(Kairo.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Kairo.Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Recent section

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.md) {
            Text("RECENT")
                .font(Kairo.Typography.captionStrong)
                .tracking(1.2)
                .foregroundStyle(Kairo.Palette.textDim)

            VStack(spacing: Kairo.Space.sm) {
                ForEach(vm.recentTurns) { turn in
                    TurnRow(turn: turn)
                }
            }
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.md) {
            Text("QUICK ACTIONS")
                .font(Kairo.Typography.captionStrong)
                .tracking(1.2)
                .foregroundStyle(Kairo.Palette.textDim)
            HStack(spacing: Kairo.Space.sm) {
                ActionTile(icon: "mic.fill",       label: "Talk")
                ActionTile(icon: "house.fill",     label: "Home")
                ActionTile(icon: "music.note",     label: "Music")
                ActionTile(icon: "cloud.sun.fill", label: "Weather")
            }
        }
    }
}

// MARK: - Subviews

private struct StatusDot: View {
    let connected: Bool
    var body: some View {
        Circle()
            .fill(connected ? Kairo.Palette.success : Kairo.Palette.textDim)
            .frame(width: 8, height: 8)
            .shadow(color: (connected ? Kairo.Palette.success : .clear).opacity(0.6),
                    radius: 4, x: 0, y: 0)
    }
}

private struct TurnRow: View {
    let turn: CompanionViewModel.Turn

    var body: some View {
        HStack(alignment: .top, spacing: Kairo.Space.md) {
            Image(systemName: turn.role == .user ? "person.fill" : "k.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(turn.role == .user ? Kairo.Palette.textDim : Kairo.Palette.accent)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(turn.label)
                    .font(Kairo.Typography.captionStrong)
                    .tracking(1.0)
                    .foregroundStyle(Kairo.Palette.textDim)
                Text(turn.text)
                    .font(Kairo.Typography.body)
                    .foregroundStyle(Kairo.Palette.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Kairo.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .fill(Kairo.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5)
        )
    }
}

private struct ActionTile: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: Kairo.Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Kairo.Palette.accent)
            Text(label)
                .font(Kairo.Typography.captionStrong)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Kairo.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .fill(Kairo.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5)
        )
    }
}

// MARK: - View model (scaffold)

@MainActor
final class CompanionViewModel: ObservableObject {
    struct Turn: Identifiable {
        enum Role { case user, kairo }
        let id = UUID()
        let role: Role
        let text: String
        var label: String { role == .user ? "YOU" : "KAIRO" }
    }

    @Published var macDeviceName: String = "John's Mac"
    @Published var isConnected: Bool = true
    @Published var connectionState: String = "Connected · Listening"
    @Published var liveActivityActive: Bool = false
    @Published var recentTurns: [Turn] = []

    private var activity: Activity<KairoActivityAttributes>?

    func refresh() {
        // Sample data — replace with real session-sync in a future phase.
        recentTurns = [
            .init(role: .user,  text: "What's the weather like today?"),
            .init(role: .kairo, text: "Partly cloudy, 24°C in Kampala. Rain later this afternoon."),
            .init(role: .user,  text: "Play something focused."),
            .init(role: .kairo, text: "Putting on Brian Eno — Music for Airports.")
        ]
    }

    func toggleLiveActivity() {
        if liveActivityActive {
            stop()
        } else {
            start()
        }
    }

    private func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = KairoActivityAttributes(macDeviceName: macDeviceName, sessionID: UUID().uuidString)
        let state = KairoActivityAttributes.State(
            mode: .listening,
            primaryText: "Hey Kairo — I'm here.",
            secondaryText: nil
        )
        do {
            let content = ActivityContent(state: state, staleDate: nil)
            activity = try Activity<KairoActivityAttributes>.request(attributes: attrs, content: content)
            liveActivityActive = true
        } catch {
            print("[Kairo iOS] Live activity request failed: \(error)")
        }
    }

    private func stop() {
        Task {
            await activity?.end(nil, dismissalPolicy: .immediate)
            activity = nil
            liveActivityActive = false
        }
    }
}
