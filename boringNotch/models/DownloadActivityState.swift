//
//  DownloadActivityState.swift
//  boringNotch
//

import Foundation

/// One download the notch knows about.
///
/// Deliberately free of `Progress` and of any UI type so the aggregation and
/// classification rules below can be unit tested directly.
struct DownloadItem: Identifiable, Equatable {
    enum State: Equatable {
        case downloading
        case paused
        case completed
        case cancelled
        case failed

        /// Whether the download has stopped for good, whatever the outcome.
        var isTerminal: Bool {
            switch self {
            case .downloading, .paused: return false
            case .completed, .cancelled, .failed: return true
            }
        }
    }

    /// The destination URL, which is what the publisher keys its progress on and is stable
    /// for the life of the download.
    var id: URL { fileURL }

    var fileURL: URL
    /// `nil` when the publisher only ever exposed a placeholder, so there is no real name
    /// to show. The UI says "Downloading" rather than inventing one.
    var displayName: String?
    /// 0...1. Only meaningful when `totalBytes` is known; see `DownloadSummary`.
    var fraction: Double
    var completedBytes: Int64
    /// `nil` when the publisher never told us how big the file is, which is normal for
    /// chunked responses with no Content-Length.
    var totalBytes: Int64?
    /// Bytes per second, when the publisher reports it.
    var throughput: Int?
    var eta: TimeInterval?
    var state: State
    var startedAt: Date

    /// A download whose size is unknown can still report bytes so far, but a percentage
    /// would be invented rather than measured.
    var isDeterminate: Bool { totalBytes.map { $0 > 0 } ?? false }
}

/// What the compact notch shows when one activity has to stand for every active download.
struct DownloadSummary: Equatable {
    /// The filename, but only when a single download makes one meaningful.
    var primaryName: String?
    var count: Int
    var fraction: Double
    /// False when no active download knows its total size, so the UI shows an
    /// indeterminate bar instead of a fabricated percentage.
    var isDeterminate: Bool
    /// Combined bytes per second across every download reporting a rate.
    var throughput: Int?
    /// The longest remaining time, i.e. when the whole batch is expected to be done.
    var eta: TimeInterval?
}

/// Turns the filename a downloader publishes into one worth showing.
///
/// Downloaders publish progress against the *partial* file they are writing, not the
/// finished one, so the raw name is usually an implementation detail: Chromium publishes
/// `Unconfirmed 512210.crdownload`, which tells the user nothing at all.
enum DownloadNaming {
    /// Extensions browsers append to a file that is still being written.
    static let inProgressExtensions: Set<String> = [
        "crdownload",  // Chromium
        "part",        // Firefox
        "download",    // Safari
        "opdownload",  // Opera
        "partial",
    ]

    /// Chromium's stand-in for a name it has not settled on yet, e.g. "Unconfirmed 512210".
    private static func isPlaceholder(_ stem: String) -> Bool {
        let prefix = "Unconfirmed "
        guard stem.hasPrefix(prefix) else { return false }
        let digits = stem.dropFirst(prefix.count)
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }

    /// The name to show while downloading, or `nil` when the publisher has not revealed one.
    static func displayName(forPublished name: String) -> String? {
        var stem = name
        // Only one layer: "archive.zip.crdownload" is meant to read as "archive.zip".
        if let dot = stem.lastIndex(of: "."),
           inProgressExtensions.contains(String(stem[stem.index(after: dot)...]).lowercased())
        {
            stem = String(stem[..<dot])
        }
        guard !stem.isEmpty, !isPlaceholder(stem) else { return nil }
        return stem
    }

    /// Whether a filename is a partial-download artefact rather than a finished file.
    static func isInProgressArtefact(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: ".") else { return false }
        return inProgressExtensions.contains(String(name[name.index(after: dot)...]).lowercased())
    }
}

enum DownloadActivityState {
    /// Classify a download that has just stopped being published.
    ///
    /// The publish/subscribe API gives no explicit outcome — the progress object simply
    /// goes away — so the outcome has to be read off the last known state.
    static func terminalState(isCancelled: Bool, fraction: Double, isDeterminate: Bool) -> DownloadItem.State {
        if isCancelled { return .cancelled }
        // A download whose size was never known cannot be judged by its fraction, and
        // publishers only stop publishing such a transfer once it has finished.
        if !isDeterminate { return .completed }
        // Floating-point progress rarely lands exactly on 1.0.
        return fraction >= 0.999 ? .completed : .failed
    }

    /// Collapse every in-flight download into the single activity slot.
    ///
    /// Returns `nil` when nothing is in flight, which is the caller's signal to take the
    /// activity down rather than show an empty one.
    static func summarize(_ items: [DownloadItem]) -> DownloadSummary? {
        let active = items.filter { !$0.state.isTerminal }
        guard !active.isEmpty else { return nil }

        let determinate = active.filter(\.isDeterminate)

        // Weighting by byte count is what makes a 2 GB image dominate a 40 KB icon, which
        // is what someone watching the bar actually cares about. It only works when every
        // total is known; otherwise fall back to the unweighted mean.
        let fraction: Double
        let isDeterminate: Bool
        if determinate.count == active.count {
            let total = determinate.reduce(Int64(0)) { $0 + ($1.totalBytes ?? 0) }
            let completed = determinate.reduce(Int64(0)) { $0 + $1.completedBytes }
            fraction = total > 0 ? min(1, Double(completed) / Double(total)) : 0
            isDeterminate = true
        } else if !determinate.isEmpty {
            fraction = determinate.reduce(0) { $0 + $1.fraction } / Double(determinate.count)
            isDeterminate = true
        } else {
            fraction = 0
            isDeterminate = false
        }

        let throughputs = active.compactMap(\.throughput)
        let etas = active.compactMap(\.eta)

        return DownloadSummary(
            // A batch has no one filename to speak for it, so the view says how many instead.
            primaryName: active.count == 1 ? active[0].displayName : nil,
            count: active.count,
            fraction: fraction,
            isDeterminate: isDeterminate,
            throughput: throughputs.isEmpty ? nil : throughputs.reduce(0, +),
            eta: etas.max()
        )
    }
}
