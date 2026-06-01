//  ScreenshotStore+Capture.swift
//  IslandNotch
//
//  Purpose: Orchestrates a capture: run the engine → record the entry →
//           conditionally auto-copy the pasteable payload for the active agent.
//  Layer: Service

import AppKit
import Foundation

extension ScreenshotStore {
    /// Captures interactively and files the result. Auto-copies to the clipboard
    /// only when the user has opted that `source` into auto-copy (e.g. double-⌘).
    func capture(source: CaptureSource) async {
        guard ensureFolder() else { return }

        let destination = folderURL.appendingPathComponent(makeTimestampFilename())
        let result = await captureService.captureInteractive(to: destination)

        switch result {
        case .cancelled:
            Log.capture.debug("capture cancelled (source: \(source.rawValue))")
        case .failed(let error):
            Log.capture.error("capture failed: \(error.localizedDescription)")
        case .captured(let url):
            let entry = ScreenshotEntry(file: url.lastPathComponent, ts: Date(), source: source)
            await append(entry)
            Log.capture.debug("captured \(entry.file) (source: \(source.rawValue))")

            if preferences.shouldAutoCopy(source) {
                copyToClipboard(entry)
            }
        }
    }

    /// Copies an entry's payload for the active agent and flags it for the UI
    /// "Copied" flash, which auto-clears after a short delay.
    func copyToClipboard(_ entry: ScreenshotEntry) {
        let agent = preferences.activeAgent
        let mode = preferences.payloadMode(for: agent)
        let url = entry.url(in: folderURL)
        guard PasteboardService.copy(url: url, mode: mode) else { return }

        lastCopiedFileID = entry.file
        let copiedID = entry.file
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self else { return }
            if self.lastCopiedFileID == copiedID { self.lastCopiedFileID = nil }
        }
    }
}
