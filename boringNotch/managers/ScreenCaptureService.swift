//
//  ScreenCaptureService.swift
//  boringNotch
//
//  ScreenCaptureKit wrapper for still captures.
//
//  ScreenCaptureKit rather than shelling out to /usr/sbin/screencapture: the
//  app is sandboxed and cannot spawn it. SCScreenshotManager needs only the
//  Screen Recording permission, which the user grants once in System Settings.
//

import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case noDisplayFound
    case noWindowFound
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return NSLocalizedString(
                "capture_error_permission",
                comment: "Shown when Screen Recording permission has not been granted"
            )
        case .noDisplayFound:
            return NSLocalizedString("capture_error_no_display", comment: "Shown when no display could be found to capture")
        case .noWindowFound:
            return NSLocalizedString("capture_error_no_window", comment: "Shown when no window could be found to capture")
        case .captureFailed(let reason):
            return reason
        }
    }
}

/// A window the user can pick, reduced to what the picker overlay needs.
struct CapturableWindow: Identifiable, Sendable {
    let id: CGWindowID
    /// Global AppKit coordinates (bottom-left origin), ready for an overlay
    /// window to hit-test against.
    let frame: CGRect
    let appName: String?
    let title: String?
}

@MainActor
final class ScreenCaptureService {
    static let shared = ScreenCaptureService()

    private init() {}

    // MARK: - Permission

    /// Whether Screen Recording has already been granted.
    ///
    /// Preflight never prompts, which matters: the tiles need to know whether
    /// to show a permission hint *before* the user clicks one.
    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks for Screen Recording.
    ///
    /// macOS only shows this prompt once per app; afterwards the request is a
    /// no-op and the user has to go to System Settings, so the caller is
    /// expected to offer that as a fallback.
    @discardableResult
    func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Shareable content

    /// Windows that can be captured, front-most first.
    ///
    /// Our own windows are excluded: the notch and the picker overlay are on
    /// screen at the moment of capture and are never what the user is aiming
    /// at. Tiny windows are dropped too — they are almost always shadows,
    /// status items or offscreen helpers rather than something to capture.
    func capturableWindows() async throws -> [CapturableWindow] {
        let content = try await shareableContent()
        let ownPID = ProcessInfo.processInfo.processIdentifier

        return content.windows
            .filter { $0.owningApplication?.processID != ownPID }
            .filter { $0.frame.width >= 40 && $0.frame.height >= 40 }
            .filter { $0.isOnScreen }
            .map {
                CapturableWindow(
                    id: $0.windowID,
                    frame: Self.appKitFrame(for: $0.frame),
                    appName: $0.owningApplication?.applicationName,
                    title: $0.title
                )
            }
    }

    // MARK: - Capture

    /// Captures a whole display — the one containing `point`, or the main one.
    func captureDisplay(containing point: CGPoint? = nil) async throws -> CGImage {
        let content = try await shareableContent()
        guard let display = Self.display(in: content, containing: point) else {
            throw ScreenCaptureError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        return try await capture(filter: filter, size: CGSize(width: display.width, height: display.height))
    }

    /// Captures a rectangle of a display.
    ///
    /// `selection` is in global AppKit coordinates; it is rebased onto the
    /// display and clamped to it, because a drag that runs past the edge would
    /// otherwise ask for pixels that do not exist.
    func captureArea(_ selection: CGRect, on screen: NSScreen) async throws -> CGImage {
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == screen.cgDisplayID })
            ?? Self.display(in: content, containing: CGPoint(x: selection.midX, y: selection.midY))
        else {
            throw ScreenCaptureError.noDisplayFound
        }

        let clamped = CaptureGeometry.clamped(selection, to: screen.frame)
        guard clamped.width >= 1, clamped.height >= 1 else {
            throw ScreenCaptureError.captureFailed(
                NSLocalizedString("capture_error_empty_selection", comment: "Shown when the dragged selection is empty")
            )
        }

        let sourceRect = CaptureGeometry.sourceRect(forSelection: clamped, in: screen.frame)
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        // The deployment target is macOS 14.0; this arrived in 14.2. Without
        // it the menu bar is still captured for a display filter, so 14.0 and
        // 14.1 just get the default behaviour rather than losing anything.
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        // Ask for pixels, not points: without scaling by the backing factor a
        // Retina capture comes back at half resolution and looks soft.
        let scale = screen.backingScaleFactor
        configuration.width = Int((clamped.width * scale).rounded())
        configuration.height = Int((clamped.height * scale).rounded())
        configuration.showsCursor = false
        configuration.captureResolution = .best

        return try await capture(filter: filter, configuration: configuration)
    }

    /// Captures one window, including its shadow-free bounds.
    func captureWindow(id windowID: CGWindowID) async throws -> CGImage {
        let content = try await shareableContent()
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenCaptureError.noWindowFound
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try await capture(filter: filter, size: window.frame.size)
    }

    // MARK: - Plumbing

    private func shareableContent() async throws -> SCShareableContent {
        guard hasPermission else { throw ScreenCaptureError.permissionDenied }
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            // The most common failure here is the permission having been
            // revoked between the preflight and the call.
            throw ScreenCaptureError.permissionDenied
        }
    }

    private func capture(filter: SCContentFilter, size: CGSize) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        configuration.width = max(1, Int((size.width * scale).rounded()))
        configuration.height = max(1, Int((size.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try await capture(filter: filter, configuration: configuration)
    }

    private func capture(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw ScreenCaptureError.captureFailed(error.localizedDescription)
        }
    }

    /// The display containing a point, falling back to the main display.
    private static func display(in content: SCShareableContent, containing point: CGPoint?) -> SCDisplay? {
        if let point,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
           let match = content.displays.first(where: { $0.displayID == screen.cgDisplayID }) {
            return match
        }
        if let mainID = NSScreen.main?.cgDisplayID,
           let match = content.displays.first(where: { $0.displayID == mainID }) {
            return match
        }
        return content.displays.first
    }

    /// Converts a CoreGraphics window frame (top-left origin, y growing down
    /// from the primary display's top) into AppKit's global coordinates
    /// (bottom-left origin), which is what an overlay window hit-tests in.
    private static func appKitFrame(for cgFrame: CGRect) -> CGRect {
        // CG's origin is the top-left of the *primary* display, so the flip
        // is about that display's height, not the union of all of them.
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else { return cgFrame }
        return CGRect(
            x: cgFrame.minX,
            y: primaryHeight - cgFrame.maxY,
            width: cgFrame.width,
            height: cgFrame.height
        )
    }
}
