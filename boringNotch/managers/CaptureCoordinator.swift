//
//  CaptureCoordinator.swift
//  boringNotch
//
//  Ties the capture pieces together: pick a target, take the shot, deliver it
//  where the user asked, and report what happened in the notch.
//
//  The views call into this and read `status`; they never talk to
//  ScreenCaptureKit, Vision or the shelf directly.
//

import AppKit
import Combine
import CoreGraphics
import Defaults
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class CaptureCoordinator: ObservableObject {
    static let shared = CaptureCoordinator()

    /// The last thing that happened, shown under the tiles.
    enum Status: Equatable {
        case idle
        case working
        case success(String)
        case failure(String)
    }

    @Published private(set) var status: Status = .idle
    /// Non-nil while a colour has just been sampled, so the swatch can be
    /// shown next to the tiles.
    @Published private(set) var lastColor: SampledColor?

    private let capture = ScreenCaptureService.shared
    private let recorder = GIFRecorder.shared
    private var statusResetTask: Task<Void, Never>?

    private init() {}

    var isRecordingGIF: Bool { recorder.isRecording }
    var hasScreenRecordingPermission: Bool { capture.hasPermission }

    // MARK: - Stills

    func takeScreenshot(_ kind: CaptureKind) {
        run { [self] in
            let image = try await image(for: kind)
            try await deliver(image, kind: kind)
        }
    }

    /// Captures, OCRs, and puts the text on the clipboard.
    ///
    /// Always the clipboard regardless of the chosen destination: the point of
    /// "Get Text" is to paste it somewhere a moment later, and writing it to a
    /// file instead would be an odd surprise.
    func captureText() {
        run { [self] in
            let image = try await image(for: .area)
            let text = try await TextRecognitionService.recognizeText(in: image)
            Self.writeToClipboard(text)
            succeed(
                String(
                    format: NSLocalizedString(
                        "capture_status_text_copied",
                        comment: "Status after OCR, e.g. '124 characters copied'"
                    ),
                    text.count
                )
            )
        }
    }

    /// Captures an area, reads the first QR/barcode in it, and opens it if it
    /// is a URL — otherwise copies the payload.
    func scanCode() {
        run { [self] in
            let image = try await image(for: .area)
            let payload = try await TextRecognitionService.detectCode(in: image)

            if let url = URL(string: payload), let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                NSWorkspace.shared.open(url)
                succeed(String(format: NSLocalizedString("capture_status_code_opened", comment: "Status after opening a scanned link"), url.host ?? payload))
            } else {
                // Anything that is not plainly a web link is copied rather
                // than opened: a QR code can encode a mailto:, an app URL
                // scheme or a shell-ish string, and opening those unasked is
                // how a scanner becomes an attack surface.
                Self.writeToClipboard(payload)
                succeed(NSLocalizedString("capture_status_code_copied", comment: "Status after copying a scanned code"))
            }
        }
    }

    // MARK: - Colour

    /// The system colour sampler — the same loupe the system colour panel
    /// uses. No screen-recording permission needed, and it matches what users
    /// already know.
    func pickColor() {
        NSColorSampler().show { [weak self] color in
            guard let self else { return }
            guard let color, let srgb = color.usingColorSpace(.sRGB) else {
                self.status = .idle
                return
            }

            let sampled = SampledColor(
                red: Double(srgb.redComponent),
                green: Double(srgb.greenComponent),
                blue: Double(srgb.blueComponent),
                alpha: Double(srgb.alphaComponent)
            )
            self.lastColor = sampled

            let text = sampled.string(for: Defaults[.captureColorFormat])
            Self.writeToClipboard(text)
            self.succeed(String(format: NSLocalizedString("capture_status_color_copied", comment: "Status after copying a colour"), text))
        }
    }

    // MARK: - Measure

    /// An on-screen ruler: drag a rectangle, get its size copied.
    func measure() {
        CaptureOverlayController.shared.present(mode: .measure) { [weak self] result in
            guard let self else { return }
            guard case .measured(let rect) = result else {
                self.status = .idle
                return
            }
            let label = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
            Self.writeToClipboard(label)
            self.succeed(String(format: NSLocalizedString("capture_status_measured", comment: "Status after measuring a region"), label))
        }
    }

    // MARK: - GIF

    func toggleGIFRecording() {
        if recorder.isRecording {
            recorder.stop()
            return
        }

        CaptureOverlayController.shared.present(mode: .area) { [weak self] result in
            guard let self else { return }
            guard case .area(let rect, let screen) = result else {
                self.status = .idle
                return
            }
            self.run {
                let url = try await self.recorder.record(rect: rect, on: screen)
                try await self.deliverFile(
                    url,
                    message: NSLocalizedString("capture_status_gif_saved", comment: "Status after adding a recorded GIF to the shelf")
                )
            }
        }
    }

    // MARK: - Pin

    /// Drags out a region and floats it above everything as a reference card.
    ///
    /// Always takes a fresh capture rather than pinning "the last one": the
    /// last capture may have been a full screen, or minutes ago, and pinning
    /// something the user can no longer see the provenance of is confusing.
    func pinLastOrCapture() {
        run { [self] in
            let image = try await image(for: .area)
            PinnedCaptureWindow.present(image: image)
            succeed(NSLocalizedString("capture_status_pinned", comment: "Status after pinning a capture on top"))
        }
    }

    // MARK: - Acquiring an image

    private func image(for kind: CaptureKind) async throws -> CGImage {
        switch kind {
        case .fullscreen:
            // Give the notch a beat to close before photographing the screen
            // it is sitting on.
            try? await Task.sleep(for: .milliseconds(250))
            return try await capture.captureDisplay(containing: NSEvent.mouseLocation)

        case .area:
            let result = await presentOverlay(mode: .area)
            guard case .area(let rect, let screen) = result else { throw CancellationError() }
            return try await capture.captureArea(rect, on: screen)

        case .window:
            let windows = try await capture.capturableWindows()
            guard !windows.isEmpty else { throw ScreenCaptureError.noWindowFound }
            let result = await presentOverlay(mode: .window(windows))
            guard case .window(let window) = result else { throw CancellationError() }
            return try await capture.captureWindow(id: window.id)
        }
    }

    private func presentOverlay(mode: CaptureOverlayMode) async -> CaptureOverlayResult {
        await withCheckedContinuation { continuation in
            CaptureOverlayController.shared.present(mode: mode) { result in
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Delivery

    private func deliver(_ image: CGImage, kind: CaptureKind) async throws {
        switch Defaults[.captureDestination] {
        case .clipboard:
            Self.writeToClipboard(image)
            succeed(NSLocalizedString("capture_status_copied", comment: "Status after copying a capture to the clipboard"))

        case .shelf:
            let url = try Self.writePNG(image, kind: kind)
            try await deliverFile(
                url,
                message: NSLocalizedString("capture_status_in_shelf", comment: "Status after adding a capture to the shelf")
            )

        case .file:
            guard let url = Self.runSavePanel(kind: kind) else {
                status = .idle
                return
            }
            try Self.writePNG(image, to: url)
            succeed(NSLocalizedString("capture_status_saved", comment: "Status after saving a capture to a file"))
        }

        if Defaults[.capturePlaySound] {
            NSSound(named: "Grab")?.play()
        }
    }

    /// Hands a finished file to the shelf.
    ///
    /// Goes through `load(_ providers:)` rather than constructing a ShelfItem
    /// here, so the capture reuses the same bookmark and thumbnail path as a
    /// dragged-in file instead of a second, subtly different one.
    ///
    /// Takes the already-localized message rather than a key: NSLocalizedString
    /// with a runtime key is invisible to string extraction, so the catalog
    /// entry would silently rot the first time someone renamed it.
    private func deliverFile(_ url: URL, message: String) async throws {
        ShelfStateViewModel.shared.load([NSItemProvider(contentsOf: url)].compactMap { $0 })
        BoringViewCoordinator.shared.currentView = .shelf
        succeed(message)
    }

    // MARK: - Files and clipboard

    private static func writePNG(_ image: CGImage, kind: CaptureKind) throws -> URL {
        let directory = temporaryDirectory.appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(CaptureNaming.filename(for: .now, kind: kind, fileExtension: "png"))
        try writePNG(image, to: url)
        return url
    }

    @discardableResult
    private static func writePNG(_ image: CGImage, to url: URL) throws -> URL {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw ScreenCaptureError.captureFailed(
                NSLocalizedString("capture_error_encoder", comment: "Shown when the image encoder could not be created")
            )
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenCaptureError.captureFailed(
                NSLocalizedString("capture_error_write", comment: "Shown when a capture could not be written to disk")
            )
        }
        return url
    }

    private static func runSavePanel(kind: CaptureKind) -> URL? {
        // The panel is what grants a sandboxed app write access to wherever
        // the user picks; there is no other way to save outside the container.
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = CaptureNaming.filename(for: .now, kind: kind, fileExtension: "png")
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func writeToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func writeToClipboard(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let rep = NSBitmapImageRep(cgImage: image)
        // TIFF as well as PNG: some older apps only accept TIFF from the
        // pasteboard, and writing both costs nothing.
        if let png = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        pasteboard.setData(rep.tiffRepresentation, forType: .tiff)
    }

    // MARK: - Status

    private func run(_ work: @escaping () async throws -> Void) {
        guard capture.hasPermission else {
            requestPermission()
            return
        }

        statusResetTask?.cancel()
        status = .working

        Task { @MainActor in
            do {
                try await work()
            } catch is CancellationError {
                // The user pressed Escape or clicked the desktop. Not a
                // failure, and not worth a message.
                status = .idle
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    private func requestPermission() {
        guard !capture.requestPermission() else { return }
        // macOS only ever shows its prompt once; after that the only route is
        // System Settings, so say so rather than appearing to do nothing.
        fail(ScreenCaptureError.permissionDenied.localizedDescription)
        capture.openScreenRecordingSettings()
    }

    private func succeed(_ message: String) {
        status = .success(message)
        scheduleStatusReset()
    }

    private func fail(_ message: String) {
        status = .failure(message)
        Log.general.error("Capture failed: \(message)")
        scheduleStatusReset()
    }

    private func scheduleStatusReset() {
        statusResetTask?.cancel()
        statusResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.status = .idle
        }
    }
}
