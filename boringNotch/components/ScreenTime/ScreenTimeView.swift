//
//  ScreenTimeView.swift
//  boringNotch
//
//  The Screen Time tab shown in the open notch: a category donut, today's total +
//  app-switch count, and a ranked per-app list. Data comes from ScreenTimeManager.
//

import Charts
import Defaults
import SwiftUI

struct ScreenTimeView: View {
    @ObservedObject private var manager = ScreenTimeManager.shared
    @Default(.screenTimeCategoryOverrides) private var categoryOverrides
    @Default(.screenTimeCategoryColors) private var categoryColors

    private let maxRows = 6

    private var resolver: CategoryResolver {
        CategoryResolver(overrides: categoryOverrides)
    }

    private var today: DailyUsage { manager.today }

    var body: some View {
        Group {
            if today.totalSeconds <= 0 {
                emptyState
            } else {
                HStack(alignment: .center, spacing: 18) {
                    donut
                        .frame(width: 132, height: 132)
                    VStack(alignment: .leading, spacing: 8) {
                        header
                        appList
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Screen Time")
                    .font(.headline)
                Text(formatDuration(today.totalSeconds))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            Spacer()
            Label("\(today.switchCount)", systemImage: "arrow.left.arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("App switches today")
        }
    }

    // MARK: Donut

    private var slices: [CategorySlice] {
        manager.categorySlices(using: resolver).map {
            CategorySlice(id: $0.category.id, category: $0.category, seconds: $0.seconds)
        }
    }

    private var donut: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Time", slice.seconds),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(2)
            .foregroundStyle(color(for: slice.category))
        }
        .chartLegend(.hidden)
        .overlay {
            VStack(spacing: 1) {
                Text(formatDuration(today.totalSeconds))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                Text("Today")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: App list

    private var rows: [AppRow] {
        let ranked = today.rankedApps
        guard ranked.count > maxRows else {
            return ranked.map { AppRow(bundleID: $0.bundleID, name: $0.displayName, seconds: $0.seconds, isOther: false) }
        }
        let head = ranked.prefix(maxRows)
        let tail = ranked.dropFirst(maxRows)
        let otherSeconds = tail.reduce(0) { $0 + $1.seconds }
        var result = head.map { AppRow(bundleID: $0.bundleID, name: $0.displayName, seconds: $0.seconds, isOther: false) }
        if otherSeconds > 0 {
            result.append(AppRow(bundleID: "", name: "Other", seconds: otherSeconds, isOther: true))
        }
        return result
    }

    private var maxRowSeconds: TimeInterval {
        max(rows.first?.seconds ?? 1, 1)
    }

    private var appList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                ForEach(rows) { row in
                    appRow(row)
                }
            }
        }
    }

    private func appRow(_ row: AppRow) -> some View {
        let category = row.isOther ? CategoryResolver.other : resolver.category(for: row.bundleID)
        return HStack(spacing: 8) {
            Group {
                if row.isOther {
                    Image(systemName: "ellipsis.circle.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                } else {
                    AppIcon(for: row.bundleID)
                        .resizable()
                }
            }
            .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                // "Other" is localizable; real app names are verbatim (already localized by the system).
                (row.isOther ? Text("Other") : Text(verbatim: row.name))
                    .font(.system(size: 12))
                    .lineLimit(1)
                GeometryReader { geo in
                    Capsule()
                        .fill(color(for: category).opacity(0.85))
                        .frame(
                            width: max(2, geo.size.width * CGFloat(row.seconds / maxRowSeconds)),
                            height: 3
                        )
                }
                .frame(height: 3)
            }

            Text(formatDuration(row.seconds))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "hourglass")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No activity tracked yet today")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    /// Category color, honoring a user override if present.
    private func color(for category: AppCategory) -> Color {
        let hex = categoryColors[category.id] ?? category.colorHex
        return Color(stHex: hex)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}

// MARK: - Row / slice models

private struct CategorySlice: Identifiable {
    let id: String
    let category: AppCategory
    let seconds: TimeInterval
}

private struct AppRow: Identifiable {
    let bundleID: String
    let name: String
    let seconds: TimeInterval
    let isOther: Bool
    var id: String { isOther ? "__other__" : bundleID }
}
