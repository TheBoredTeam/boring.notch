//
//  DownloadActivityStateTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

final class DownloadActivityStateTests: XCTestCase {
    private func item(
        _ name: String?,
        fraction: Double = 0,
        completed: Int64 = 0,
        total: Int64? = nil,
        throughput: Int? = nil,
        eta: TimeInterval? = nil,
        state: DownloadItem.State = .downloading
    ) -> DownloadItem {
        DownloadItem(
            fileURL: URL(fileURLWithPath: "/tmp/\(name ?? "unnamed")"),
            displayName: name,
            fraction: fraction,
            completedBytes: completed,
            totalBytes: total,
            throughput: throughput,
            eta: eta,
            state: state,
            startedAt: Date()
        )
    }

    // MARK: - Naming

    func testStripsInProgressExtensions() {
        XCTAssertEqual(DownloadNaming.displayName(forPublished: "archive.zip.crdownload"), "archive.zip")
        XCTAssertEqual(DownloadNaming.displayName(forPublished: "movie.mkv.part"), "movie.mkv")
        XCTAssertEqual(DownloadNaming.displayName(forPublished: "Ubuntu.iso.download"), "Ubuntu.iso")
        XCTAssertEqual(DownloadNaming.displayName(forPublished: "notes.pdf.OPDOWNLOAD"), "notes.pdf")
    }

    func testKeepsOrdinaryNames() {
        XCTAssertEqual(DownloadNaming.displayName(forPublished: "Ubuntu.iso"), "Ubuntu.iso")
        // ".download" only counts as a suffix, never as the whole name.
        XCTAssertEqual(DownloadNaming.displayName(forPublished: "report.docx"), "report.docx")
    }

    /// Chromium publishes this placeholder, and showing it to the user would be worse than
    /// showing nothing.
    func testRejectsChromiumPlaceholder() {
        XCTAssertNil(DownloadNaming.displayName(forPublished: "Unconfirmed 512210.crdownload"))
        XCTAssertNil(DownloadNaming.displayName(forPublished: "Unconfirmed 1.crdownload"))
        // A real file that merely starts with the word is not a placeholder.
        XCTAssertEqual(
            DownloadNaming.displayName(forPublished: "Unconfirmed report.pdf"), "Unconfirmed report.pdf")
        XCTAssertEqual(DownloadNaming.displayName(forPublished: "Unconfirmed.crdownload"), "Unconfirmed")
    }

    func testIdentifiesInProgressArtefacts() {
        XCTAssertTrue(DownloadNaming.isInProgressArtefact("Unconfirmed 512210.crdownload"))
        XCTAssertFalse(DownloadNaming.isInProgressArtefact("Ubuntu.iso"))
    }

    // MARK: - Terminal state

    func testTerminalStateClassification() {
        XCTAssertEqual(
            DownloadActivityState.terminalState(isCancelled: true, fraction: 0.4, isDeterminate: true),
            .cancelled)
        XCTAssertEqual(
            DownloadActivityState.terminalState(isCancelled: false, fraction: 1.0, isDeterminate: true),
            .completed)
        XCTAssertEqual(
            DownloadActivityState.terminalState(isCancelled: false, fraction: 0.42, isDeterminate: true),
            .failed)
    }

    /// Progress rarely lands exactly on 1.0, so a download that is a rounding error short
    /// must still count as finished.
    func testNearlyCompleteCountsAsCompleted() {
        XCTAssertEqual(
            DownloadActivityState.terminalState(isCancelled: false, fraction: 0.9995, isDeterminate: true),
            .completed)
    }

    /// With no known total there is no fraction to judge by, and publishers stop publishing
    /// such a transfer only once it is done.
    func testIndeterminateFinishesAsCompleted() {
        XCTAssertEqual(
            DownloadActivityState.terminalState(isCancelled: false, fraction: 0, isDeterminate: false),
            .completed)
        XCTAssertEqual(
            DownloadActivityState.terminalState(isCancelled: true, fraction: 0, isDeterminate: false),
            .cancelled)
    }

    // MARK: - Aggregation

    func testNothingActiveSummarizesToNil() {
        XCTAssertNil(DownloadActivityState.summarize([]))
        XCTAssertNil(DownloadActivityState.summarize([item("a.zip", state: .completed)]))
    }

    func testSingleDownloadKeepsItsName() {
        let summary = DownloadActivityState.summarize([
            item("Ubuntu.iso", fraction: 0.72, completed: 720, total: 1000, throughput: 8_200_000, eta: 41)
        ])
        XCTAssertEqual(summary?.primaryName, "Ubuntu.iso")
        XCTAssertEqual(summary?.count, 1)
        XCTAssertEqual(summary?.fraction ?? 0, 0.72, accuracy: 0.0001)
        XCTAssertEqual(summary?.isDeterminate, true)
        XCTAssertEqual(summary?.throughput, 8_200_000)
        XCTAssertEqual(summary?.eta, 41)
    }

    /// A batch has no single name, and the progress bar should reflect bytes rather than
    /// treating a 40 KB icon as equal to a 2 GB image.
    func testMultipleDownloadsWeightByBytes() {
        let summary = DownloadActivityState.summarize([
            item("big.iso", fraction: 0.5, completed: 500, total: 1000),
            item("small.txt", fraction: 1.0, completed: 100, total: 100),
        ])
        XCTAssertNil(summary?.primaryName)
        XCTAssertEqual(summary?.count, 2)
        // 600 of 1100 bytes, not the 0.75 an unweighted mean would give.
        XCTAssertEqual(summary?.fraction ?? 0, 600.0 / 1100.0, accuracy: 0.0001)
    }

    func testThroughputSumsAndEtaTakesTheLongest() {
        let summary = DownloadActivityState.summarize([
            item("a", completed: 1, total: 10, throughput: 1_000, eta: 5),
            item("b", completed: 1, total: 10, throughput: 2_500, eta: 30),
        ])
        XCTAssertEqual(summary?.throughput, 3_500)
        XCTAssertEqual(summary?.eta, 30)
    }

    /// Nobody knows a total, so there is no honest percentage to show.
    func testAllUnknownTotalsAreIndeterminate() {
        let summary = DownloadActivityState.summarize([
            item("stream.bin", completed: 400),
            item("other.bin", completed: 900),
        ])
        XCTAssertEqual(summary?.isDeterminate, false)
        XCTAssertEqual(summary?.fraction, 0)
        XCTAssertEqual(summary?.count, 2)
    }

    /// A mix falls back to the mean of the downloads that do know their size, rather than
    /// counting the unknown one as zero and understating progress.
    func testMixedTotalsUseKnownDownloadsOnly() {
        let summary = DownloadActivityState.summarize([
            item("known.iso", fraction: 0.8, completed: 800, total: 1000),
            item("stream.bin", completed: 400),
        ])
        XCTAssertEqual(summary?.isDeterminate, true)
        XCTAssertEqual(summary?.fraction ?? 0, 0.8, accuracy: 0.0001)
        XCTAssertEqual(summary?.count, 2)
    }

    func testTerminalDownloadsAreExcludedFromTheSummary() {
        let summary = DownloadActivityState.summarize([
            item("done.zip", fraction: 1, completed: 100, total: 100, state: .completed),
            item("live.iso", fraction: 0.25, completed: 250, total: 1000),
        ])
        XCTAssertEqual(summary?.count, 1)
        XCTAssertEqual(summary?.primaryName, "live.iso")
    }

    /// A paused download is still an active one; it should keep the slot rather than vanish.
    func testPausedDownloadStaysInTheSummary() {
        let summary = DownloadActivityState.summarize([
            item("paused.iso", fraction: 0.3, completed: 300, total: 1000, state: .paused)
        ])
        XCTAssertEqual(summary?.count, 1)
    }

    func testFractionIsClampedWhenPublishersOvershoot() {
        let summary = DownloadActivityState.summarize([
            item("odd.bin", fraction: 1.5, completed: 1500, total: 1000)
        ])
        XCTAssertEqual(summary?.fraction, 1.0)
    }
}
