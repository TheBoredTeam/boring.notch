//
//  GitHubHUDView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct GitHubHUDView: View {
    @ObservedObject private var manager = GitHubHUDManager.shared
    @Default(.githubShowNotifications) private var showNotifications
    @Default(.githubShowPullRequests) private var showPRs
    @Default(.githubShowReviewRequests) private var showReviews
    @Default(.githubShowIssues) private var showIssues
    @Default(.githubShowActivity) private var showActivity
    @Default(.githubShowActions) private var showActions
    @Default(.githubShowContributions) private var showContributions

    @State private var expanded = false

    var body: some View {
        Group {
            switch manager.state {
            case .signedOut:
                HUDStateView(kind: .action, title: "Connect GitHub",
                             message: "Add a personal access token in Settings › GitHub HUD.",
                             buttonTitle: "Open Settings") { SettingsWindowController.shared.showWindow() }
            case .authFailed:
                HUDStateView(kind: .error, title: "GitHub rejected your token",
                             message: "It may have expired or been revoked.",
                             buttonTitle: "Open Settings") { SettingsWindowController.shared.showWindow() }
            case .loading where manager.snapshot == nil:
                HUDStateView(kind: .loading, title: "Loading GitHub…")
            case .offline where manager.snapshot == nil:
                HUDStateView(kind: .offline, title: "You're offline", message: "GitHub data will load when you reconnect.")
            case .rateLimited(let reset) where manager.snapshot == nil:
                HUDStateView(kind: .error, title: "GitHub rate limit reached",
                             message: reset.map { "Resets \($0.hudRelative)." } ?? "Try again shortly.")
            case .failed(let message) where manager.snapshot == nil:
                HUDStateView(kind: .error, title: "Couldn't load GitHub", message: message,
                             buttonTitle: "Retry") { manager.refresh(force: true) }
            default:
                if let snapshot = manager.snapshot { loaded(snapshot) }
                else { HUDStateView(kind: .loading, title: "Loading GitHub…") }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.3), value: manager.state)
        .onAppear { manager.start() }
        .onDisappear { manager.stop() }
    }

    // MARK: Loaded

    private func loaded(_ s: GitHubSnapshot) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                header(s)
                tiles(s)
                if expanded { details(s).transition(.blurReplace) }
            }
            .padding(.horizontal, 4)
        }
    }

    private func header(_ s: GitHubSnapshot) -> some View {
        HStack(spacing: 8) {
            AsyncImage(url: s.user.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Color.white.opacity(0.12))
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 0) {
                Text(s.user.name ?? s.user.login).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text("@\(s.user.login)").font(.system(size: 10)).foregroundStyle(.gray).lineLimit(1)
            }
            statusBadge
            Spacer(minLength: 0)
            Text(s.fetchedAt.hudRelative).font(.system(size: 9)).foregroundStyle(.gray)
            Button { manager.refresh(force: true) } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold)).foregroundStyle(.gray)
            }
            .buttonStyle(.plain)
            .help("Refresh")
            Button {
                withAnimation(.smooth(duration: 0.3)) { expanded.toggle() }
            } label: {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.gray)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch manager.state {
        case .offline: HUDChip(text: "Offline", systemImage: "wifi.slash", tint: .orange)
        case .rateLimited: HUDChip(text: "Rate limited", systemImage: "gauge.with.dots.needle.100percent", tint: .orange)
        case .failed: HUDChip(text: "Stale", systemImage: "exclamationmark.triangle", tint: .orange)
        default: EmptyView()
        }
    }

    private func tiles(_ s: GitHubSnapshot) -> some View {
        HStack(spacing: 8) {
            if showNotifications {
                let unread = s.notifications.filter(\.unread).count
                tile("Unread", value: unread >= 50 ? "50+" : "\(unread)", icon: "bell.fill",
                     tint: unread > 0 ? .blue : .gray, url: URL(string: "https://github.com/notifications"))
            }
            if showPRs, let prs = s.assignedPRs {
                tile("My PRs", value: "\(prs.totalCount)", icon: "arrow.triangle.pull", tint: .green,
                     url: URL(string: "https://github.com/pulls/assigned"))
            }
            if showReviews, let r = s.reviewRequests {
                tile("Reviews", value: "\(r.totalCount)", icon: "eye.fill", tint: r.totalCount > 0 ? .orange : .gray,
                     url: URL(string: "https://github.com/pulls/review-requested"))
            }
            if showIssues, let i = s.assignedIssues {
                tile("Issues", value: "\(i.totalCount)", icon: "exclamationmark.circle.fill", tint: .purple,
                     url: URL(string: "https://github.com/issues/assigned"))
            }
            if showContributions, let c = s.contributions {
                contributionTile(c)
            }
        }
    }

    private func tile(_ title: String, value: String, icon: String, tint: Color, url: URL?) -> some View {
        Button {
            if let url { NSWorkspace.shared.open(url) }
        } label: {
            HUDCard {
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: icon).font(.system(size: 11)).foregroundStyle(tint)
                    Text(value).font(.system(size: 18, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                    Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(.gray)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func contributionTile(_ c: GitHubContributions) -> some View {
        HUDCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(c.total) this year").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                let maxCount = max(1, c.recentDays.map(\.count).max() ?? 1)
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(c.recentDays.enumerated()), id: \.offset) { _, day in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(day.count == 0 ? Color.white.opacity(0.12) : Color.green)
                            .frame(width: 5, height: max(3, 22 * CGFloat(day.count) / CGFloat(maxCount)))
                    }
                }
                .frame(height: 22, alignment: .bottom)
                Text("\(c.commits) commits · \(c.reviews) reviews").font(.system(size: 9)).foregroundStyle(.gray).lineLimit(1)
            }
        }
        .frame(minWidth: 120)
    }

    // MARK: Details

    private func details(_ s: GitHubSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showNotifications, !s.notifications.isEmpty {
                section("Notifications") {
                    ForEach(s.notifications.prefix(3)) { n in
                        row(icon: n.unread ? "circle.fill" : "circle", title: n.subject.title, subtitle: n.repository.fullName,
                            tint: n.unread ? .blue : .gray)
                    }
                }
            }
            if showReviews, let r = s.reviewRequests, !r.items.isEmpty {
                section("Awaiting your review") { ForEach(r.items.prefix(3)) { issueRow($0, icon: "eye.fill", tint: .orange) } }
            }
            if showPRs, let p = s.assignedPRs, !p.items.isEmpty {
                section("Assigned pull requests") { ForEach(p.items.prefix(3)) { issueRow($0, icon: "arrow.triangle.pull", tint: .green) } }
            }
            if showIssues, let i = s.assignedIssues, !i.items.isEmpty {
                section("Assigned issues") { ForEach(i.items.prefix(3)) { issueRow($0, icon: "exclamationmark.circle.fill", tint: .purple) } }
            }
            if showActions, !s.workflowRuns.isEmpty {
                section("GitHub Actions") {
                    ForEach(s.workflowRuns) { run in
                        let (icon, tint) = Self.style(run.outcome)
                        Button { NSWorkspace.shared.open(run.htmlURL) } label: {
                            row(icon: icon, title: run.name ?? "Workflow", subtitle: "\(run.repoName) · \(run.headBranch ?? "")", tint: tint)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if showActivity, !s.events.isEmpty {
                section("Recent activity") {
                    ForEach(s.events.prefix(4)) { e in
                        row(icon: e.icon, title: e.summary,
                            subtitle: "\(e.repo.name)\(e.createdAt.map { " · " + $0.hudRelative } ?? "")", tint: .gray)
                    }
                }
            }
            if !hasAnyDetail(s) {
                Text("Nothing to show — you're all caught up.")
                    .font(.system(size: 11)).foregroundStyle(.gray)
            }
        }
    }

    private func hasAnyDetail(_ s: GitHubSnapshot) -> Bool {
        (showNotifications && !s.notifications.isEmpty) || (showReviews && !(s.reviewRequests?.items.isEmpty ?? true))
            || (showPRs && !(s.assignedPRs?.items.isEmpty ?? true)) || (showIssues && !(s.assignedIssues?.items.isEmpty ?? true))
            || (showActions && !s.workflowRuns.isEmpty) || (showActivity && !s.events.isEmpty)
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.gray)
            content()
        }
    }

    private func issueRow(_ item: GitHubIssueItem, icon: String, tint: Color) -> some View {
        Button { NSWorkspace.shared.open(item.htmlURL) } label: {
            row(icon: icon, title: item.title, subtitle: "\(item.repoName) #\(item.number)", tint: tint)
        }.buttonStyle(.plain)
    }

    private func row(icon: String, title: String, subtitle: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(tint).frame(width: 14)
            Text(title).font(.system(size: 11)).foregroundStyle(.white).lineLimit(1)
            Spacer(minLength: 4)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(.gray).lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private static func style(_ o: GitHubWorkflowRun.Outcome) -> (String, Color) {
        switch o {
        case .running: return ("clock.fill", .yellow)
        case .success: return ("checkmark.circle.fill", .green)
        case .failure: return ("xmark.circle.fill", .red)
        case .other: return ("minus.circle.fill", .gray)
        }
    }
}
