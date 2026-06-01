//
//  CaptureService.swift
//  boringNotch
//
//  Purpose: Performs the actual screenshot. The engine shells out to the native
//           `screencapture -i` for free interactive region selection.
//  Layer: Service
//

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
