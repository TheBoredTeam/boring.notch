//
//  DownloadActivity.swift
//  boringNotch
//

import SwiftUI

/// Download progress in the closed notch.
///
/// Follows the same geometry as the other closed-notch activities: content on either side
/// of a black spacer the width of the physical notch.
struct DownloadActivity: View {
    @EnvironmentObject var vm: BoringViewModel

    /// The finished download being announced, if any. Takes over the whole activity.
    let completed: DownloadItem?
    /// Everything still in flight, already collapsed into one summary.
    let summary: DownloadSummary?
    let notchHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: completed != nil ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(completed != nil ? .green : .white)
                    .imageScale(.medium)

                label
            }
            .frame(width: activitySlotWidth, alignment: .trailing)

            // The spacer only needs to clear a physical notch. On displays without one it
            // is dead space that pushes the two labels to opposite ends of the bar.
            Rectangle()
                .fill(.black)
                .frame(width: vm.hasNotch ? vm.closedNotchSize.width + activityNotchClearance : 16)

            HStack(spacing: 6) {
                trailing
            }
            .frame(width: activitySlotWidth, alignment: .leading)
        }
        .frame(height: notchHeight, alignment: .center)
    }

    @ViewBuilder
    private var label: some View {
        if let name = completed?.displayName ?? summary?.primaryName {
            // Runtime data, so verbatim: it must not be picked up as a localization key.
            // No fixedSize either — the slot has to be free to truncate it.
            Text(verbatim: name)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
        } else if let count = summary?.count, count > 1 {
            // A batch has no single name to speak for it, so say how many.
            Text("\(count) downloads")
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
        } else {
            // The publisher never revealed a filename; inventing one would be worse.
            Text(completed != nil ? "Downloaded" : "Downloading")
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if completed != nil {
            Text("Downloaded")
                .font(.subheadline)
                .foregroundStyle(.gray)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        } else if let summary {
            if summary.isDeterminate {
                Text(summary.fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    // Percent changes glide rather than snapping, and a monospaced digit
                    // keeps the label from reflowing as the number widens.
                    .animation(.smooth, value: summary.fraction)
            } else {
                // Size unknown, so there is no honest percentage to show.
                Text("Downloading")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    VStack(spacing: 4) {
        // A single download with a name the publisher revealed.
        DownloadActivity(
            completed: nil,
            summary: DownloadSummary(
                primaryName: "Ubuntu.iso", count: 1, fraction: 0.72,
                isDeterminate: true, throughput: 8_200_000, eta: 41
            ),
            notchHeight: 32
        )

        // Chromium publishes a placeholder, so the label falls back to the generic word.
        DownloadActivity(
            completed: nil,
            summary: DownloadSummary(
                primaryName: nil, count: 1, fraction: 0.31,
                isDeterminate: true, throughput: nil, eta: nil
            ),
            notchHeight: 32
        )

        // Several at once collapse into a count and an aggregate percentage.
        DownloadActivity(
            completed: nil,
            summary: DownloadSummary(
                primaryName: nil, count: 3, fraction: 0.55,
                isDeterminate: true, throughput: 12_000_000, eta: 90
            ),
            notchHeight: 32
        )

        // Unknown total size: an honest "Downloading" rather than a made-up percentage.
        DownloadActivity(
            completed: nil,
            summary: DownloadSummary(
                primaryName: "stream.bin", count: 1, fraction: 0,
                isDeterminate: false, throughput: nil, eta: nil
            ),
            notchHeight: 32
        )

        // Completion.
        DownloadActivity(
            completed: DownloadItem(
                fileURL: URL(fileURLWithPath: "/tmp/Ubuntu.iso"), displayName: "Ubuntu.iso",
                fraction: 1, completedBytes: 100, totalBytes: 100, throughput: nil, eta: nil,
                state: .completed, startedAt: Date()
            ),
            summary: nil,
            notchHeight: 32
        )
    }
    .background(Color.black)
    .environmentObject(BoringViewModel())
}
