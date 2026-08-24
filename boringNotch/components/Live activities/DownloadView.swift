import AppKit
import Defaults
import Foundation
import SwiftUI

nonisolated enum DownloadFileInspector {
    static func browser(for url: URL) -> DownloadBrowser? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".download") { return .safari }
        if name.hasSuffix(".crdownload") { return .chromium }
        if name.hasSuffix(".part") { return .firefox }
        return nil
    }

    static func displayName(for url: URL) -> String {
        let suffixes = [".crdownload", ".download", ".part"]
        let name = url.lastPathComponent
        return suffixes.first(where: { name.lowercased().hasSuffix($0) })
            .map { String(name.dropLast($0.count)) } ?? name
    }

    static func bytesReceived(at url: URL, isDirectory: Bool, fileManager: FileManager = .default) -> Int64 {
        if !isDirectory {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}

@MainActor
final class DownloadWatcher: ObservableObject {
    static let shared = DownloadWatcher()

    @Published private(set) var downloadFiles: [DownloadRecord] = []
    @Published private(set) var lastError: String?

    private var monitoringTask: Task<Void, Never>?
    private var firstSeenAt: [String: Date] = [:]
    private let downloadsDirectory: URL

    private init(fileManager: FileManager = .default) {
        downloadsDirectory = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)

        if Defaults[.enableDownloadListener] {
            startMonitoring()
        }
    }

    deinit {
        monitoringTask?.cancel()
    }

    func startMonitoring() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.scanDownloadsDirectory()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        downloadFiles = []
        firstSeenAt = [:]
    }

    func refreshConfiguration() {
        if Defaults[.enableDownloadListener] {
            startMonitoring()
            scanDownloadsDirectory()
        } else {
            stopMonitoring()
        }
    }

    private func scanDownloadsDirectory() {
        do {
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
            ]
            let urls = try FileManager.default.contentsOfDirectory(
                at: downloadsDirectory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )

            let previousIDs = Set(downloadFiles.map(\.id))
            var records: [DownloadRecord] = []

            for url in urls {
                guard let browser = DownloadFileInspector.browser(for: url), isBrowserEnabled(browser) else { continue }
                let id = url.standardizedFileURL.path
                let values = try? url.resourceValues(forKeys: keys)
                let received = DownloadFileInspector.bytesReceived(at: url, isDirectory: values?.isDirectory == true)
                let total = expectedBytes(for: url, browser: browser)
                let started = firstSeenAt[id] ?? values?.contentModificationDate ?? Date()
                firstSeenAt[id] = started

                records.append(
                    DownloadRecord(
                        id: id,
                        sourceURL: url,
                        displayName: DownloadFileInspector.displayName(for: url),
                        browser: browser,
                        bytesReceived: received,
                        totalBytes: total,
                        startedAt: started
                    )
                )
            }

            records.sort { $0.startedAt > $1.startedAt }
            let currentIDs = Set(records.map(\.id))
            firstSeenAt = firstSeenAt.filter { currentIDs.contains($0.key) }
            downloadFiles = records
            lastError = nil

            if !currentIDs.subtracting(previousIDs).isEmpty {
                BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .download)
            }
        } catch {
            lastError = error.localizedDescription
            downloadFiles = []
        }
    }

    private func isBrowserEnabled(_ browser: DownloadBrowser) -> Bool {
        switch browser {
        case .safari: Defaults[.enableSafariDownloads]
        case .chromium: Defaults[.enableChromiumDownloads]
        case .firefox: Defaults[.enableFirefoxDownloads]
        }
    }

    private func expectedBytes(for url: URL, browser: DownloadBrowser) -> Int64? {
        guard browser == .safari else { return nil }

        let candidates = [
            url.appendingPathComponent("Info.plist"),
            url.appendingPathComponent("Download.plist"),
        ]
        let keys = [
            "NSURLDownloadExpectedContentLength",
            "DownloadEntryProgressTotalToLoad",
            "DownloadEntryExpectedContentLength",
        ]

        for candidate in candidates {
            guard let dictionary = NSDictionary(contentsOf: candidate) as? [String: Any] else { continue }
            for key in keys {
                if let number = dictionary[key] as? NSNumber, number.int64Value > 0 {
                    return number.int64Value
                }
            }
        }
        return nil
    }
}

struct DownloadArea: View {
    @ObservedObject var watcher = DownloadWatcher.shared

    var body: some View {
        Group {
            if let download = watcher.downloadFiles.first {
                HStack(spacing: 10) {
                    AppIcon(for: download.browser.bundleIdentifier)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(download.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let progress = download.progress {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(download.formattedBytes)
                            .font(.caption.monospacedDigit())
                        Text(download.browser.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("No active downloads", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("download-activity")
    }
}

struct CompactDownloadActivity: View {
    @ObservedObject var watcher = DownloadWatcher.shared

    var body: some View {
        if let download = watcher.downloadFiles.first {
            HStack(spacing: 8) {
                AppIcon(for: download.browser.bundleIdentifier)
                    .frame(width: 20, height: 20)
                Rectangle()
                    .fill(.black)
                    .frame(minWidth: 100)
                if let progress = download.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .symbolEffect(.pulse)
                }
            }
        }
    }
}
