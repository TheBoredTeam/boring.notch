//  CaptureService.swift
//  IslandNotch
//
//  Purpose: Performs the actual screenshot. Default engine shells out to the
//           native `screencapture -i` for free interactive region selection;
//           a ScreenCaptureKit engine is provided behind the same protocol.
//  Layer: Service

import AppKit
import Foundation

/// Result of an interactive capture attempt.
enum CaptureResult {
    case captured(URL)
    /// User pressed Esc / cancelled the region selection.
    case cancelled
    case failed(Error)
}

/// Capture engine abstraction so the interactive `screencapture` path and a
/// future ScreenCaptureKit path are interchangeable.
protocol CaptureService {
    /// Captures interactively and writes a PNG to `destination`.
    func captureInteractive(to destination: URL) async -> CaptureResult
}

/// Default engine: `/usr/sbin/screencapture -i -x <path>`.
/// `-i` = interactive crosshair region, `-x` = no capture sound. We deliberately
/// omit `-c` so the PNG lands on disk (the file path is our integration contract).
struct ScreencaptureCLIService: CaptureService {
    let toolURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

    func captureInteractive(to destination: URL) async -> CaptureResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = toolURL
                process.arguments = ["-i", "-x", destination.path]
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(returning: .failed(error))
                    return
                }
                // screencapture exits 0 even when the user cancels; it just
                // doesn't write the file. So existence is the real signal.
                if FileManager.default.fileExists(atPath: destination.path) {
                    continuation.resume(returning: .captured(destination))
                } else {
                    continuation.resume(returning: .cancelled)
                }
            }
        }
    }
}

/// Optional engine for programmatic (non-interactive) full-display capture on
/// macOS 14+. Kept behind availability so the app still builds/targets 13.0.
/// Interactive region selection is not built into SCK, so this is intended for a
/// future "capture whole screen, no prompt" mode rather than the default flow.
@available(macOS 14.0, *)
struct ScreenCaptureKitService: CaptureService {
    func captureInteractive(to destination: URL) async -> CaptureResult {
        // SCK has no native region selector; fall back to the CLI engine to keep
        // the interactive UX. Full-display SCK capture can be wired here later.
        await ScreencaptureCLIService().captureInteractive(to: destination)
    }
}
