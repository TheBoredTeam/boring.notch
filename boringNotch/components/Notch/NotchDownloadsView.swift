//
//  NotchDownloadsView.swift
//  boringNotch
//

import SwiftUI

/// The Downloads section of the opened notch: every download in flight, with the detail
/// there is no room for in the closed notch.
struct NotchDownloadsView: View {
    @ObservedObject private var manager = DownloadActivityManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Downloads")
                .font(.headline)
                .foregroundStyle(.white)

            if manager.activeDownloads.isEmpty {
                if let completed = manager.completionBanner {
                    DownloadRow(item: completed)
                } else {
                    Text("No active downloads")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(manager.activeDownloads) { item in
                            DownloadRow(item: item)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
    }
}

/// One download: name, bar, and whatever numbers the publisher actually gave us.
private struct DownloadRow: View {
    let item: DownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.fileURL.path))
                    .resizable()
                    .frame(width: 16, height: 16)

                if let name = item.displayName {
                    // Runtime data, so verbatim: not a localization key.
                    Text(verbatim: name)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Downloading")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if item.state == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.small)
                } else if item.isDeterminate {
                    Text(item.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            // An indeterminate bar is the honest rendering when the total size is unknown;
            // a fraction would be invented.
            Group {
                if item.isDeterminate {
                    ProgressView(value: min(max(item.fraction, 0), 1))
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(.effectiveAccent)
            .animation(.smooth, value: item.fraction)

            if let detail = detailText {
                Text(verbatim: detail)
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }

    /// "1.8 GB of 2.7 GB · 8.2 MB/s · 41s left", omitting whatever is unknown rather than
    /// filling the gaps with placeholders.
    private var detailText: String? {
        var parts: [String] = []

        if let total = item.totalBytes, total > 0 {
            parts.append(
                "\(Self.bytes.string(fromByteCount: item.completedBytes)) / "
                    + Self.bytes.string(fromByteCount: total)
            )
        } else if item.completedBytes > 0 {
            parts.append(Self.bytes.string(fromByteCount: item.completedBytes))
        }

        if let throughput = item.throughput, throughput > 0 {
            parts.append("\(Self.bytes.string(fromByteCount: Int64(throughput)))/s")
        }

        if item.state == .downloading, let eta = item.eta, eta > 0,
           let formatted = Self.duration.string(from: eta)
        {
            parts.append(formatted)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    private static let duration: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()
}

#Preview {
    NotchDownloadsView()
        .frame(width: 300, height: 160)
        .background(Color.black)
}
