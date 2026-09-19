//
//  GIFRecorder.swift
//  boringNotch
//
//  Records a region of the screen to an animated GIF.
//
//  SCStream frames are written straight into a CGImageDestination as they
//  arrive, rather than collected in memory and encoded at the end. A 30-second
//  1080p recording at 10fps is ~300 frames; held as CGImages that is several
//  gigabytes, which is how a "record a GIF" feature turns into a memory alarm.
//

import AppKit
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
final class GIFRecorder: NSObject, ObservableObject {
    static let shared = GIFRecorder()

    @Published private(set) var isRecording = false
    @Published private(set) var frameCount = 0
    @Published private(set) var startedAt: Date?

    /// 10fps. GIF stores per-frame delays in hundredths of a second, so 10fps
    /// (a delay of exactly 0.1s) is representable without rounding drift, and
    /// it keeps file size sane — GIF has no interframe compression worth the
    /// name, so every extra frame is close to a whole extra image.
    private static let framesPerSecond = 10
    private static let frameDelay = 1.0 / Double(framesPerSecond)

    /// Hard ceiling on a recording, in frames (~60s at 10fps).
    ///
    /// GIF is a terrible video format and a minute of it is already tens of
    /// megabytes; without a cap, a recording the user forgets about fills the
    /// disk.
    private static let maximumFrames = 600

    private var stream: SCStream?
    private var destination: CGImageDestination?
    private var outputURL: URL?
    private var continuation: CheckedContinuation<URL, Error>?
    private let frameQueue = DispatchQueue(label: "theboringteam.boringnotch.gif-recorder")

    override private init() { super.init() }

    // MARK: - Recording

    /// Records `rect` (global AppKit coordinates) until `stop()` is called or
    /// the frame ceiling is reached, then returns the finished GIF.
    func record(rect: CGRect, on screen: NSScreen) async throws -> URL {
        guard !isRecording else {
            throw ScreenCaptureError.captureFailed(
                NSLocalizedString("capture_error_already_recording", comment: "Shown when a GIF recording is already running")
            )
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.cgDisplayID })
            ?? content.displays.first
        else {
            throw ScreenCaptureError.noDisplayFound
        }

        let clamped = CaptureGeometry.clamped(rect, to: screen.frame)
        guard clamped.width >= 1, clamped.height >= 1 else {
            throw ScreenCaptureError.captureFailed(
                NSLocalizedString("capture_error_empty_selection", comment: "Shown when the dragged selection is empty")
            )
        }

        let url = try Self.makeOutputURL()
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, 0, nil
        ) else {
            throw ScreenCaptureError.captureFailed(
                NSLocalizedString("capture_error_encoder", comment: "Shown when the GIF encoder could not be created")
            )
        }
        // 0 = loop forever, which is what everyone expects from a GIF.
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CaptureGeometry.sourceRect(forSelection: clamped, in: screen.frame)
        // Recorded at 1x rather than the backing scale: a Retina-resolution
        // GIF is four times the bytes for a format nobody views zoomed in.
        configuration.width = Int(clamped.width.rounded())
        configuration.height = Int(clamped.height.rounded())
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(Self.framesPerSecond))
        configuration.showsCursor = true
        configuration.queueDepth = 5

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)

        self.stream = stream
        self.destination = destination
        self.outputURL = url
        frameCount = 0
        startedAt = .now
        isRecording = true

        try await stream.startCapture()

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func stop() {
        guard isRecording else { return }
        Task { await finish() }
    }

    private func finish() async {
        guard isRecording else { return }
        isRecording = false

        if let stream {
            try? await stream.stopCapture()
            try? stream.removeStreamOutput(self, type: .screen)
        }
        stream = nil

        // Everything below has to happen on the same queue the frames were
        // appended on, or the finalize can race a frame still being written.
        let destination = self.destination
        let url = self.outputURL
        let frames = frameCount
        self.destination = nil
        self.outputURL = nil
        startedAt = nil

        let continuation = self.continuation
        self.continuation = nil

        frameQueue.async {
            var finalized = false
            if let destination, frames > 0 {
                finalized = CGImageDestinationFinalize(destination)
            }

            Task { @MainActor in
                guard let url, finalized else {
                    if let url { try? FileManager.default.removeItem(at: url) }
                    continuation?.resume(
                        throwing: ScreenCaptureError.captureFailed(
                            NSLocalizedString(
                                "capture_error_no_frames",
                                comment: "Shown when a GIF recording captured no frames"
                            )
                        )
                    )
                    return
                }
                continuation?.resume(returning: url)
            }
        }
    }

    private static func makeOutputURL() throws -> URL {
        let directory = temporaryDirectory.appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = CaptureNaming.filename(for: .now, kind: .area, fileExtension: "gif")
        return directory.appendingPathComponent(name)
    }
}

// MARK: - Frame output

extension GIFRecorder: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

        // ScreenCaptureKit emits a frame for every vsync it is asked about,
        // including ones where nothing changed and ones where the surface is
        // idle. Only complete frames carry pixels worth keeping.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int,
           SCFrameStatus(rawValue: raw) != .complete {
            return
        }

        let context = CIContext()
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        Task { @MainActor [weak self] in
            self?.append(cgImage)
        }
    }

    private func append(_ image: CGImage) {
        guard isRecording, let destination else { return }
        guard frameCount < Self.maximumFrames else {
            // Ceiling reached: stop cleanly and hand back what was recorded
            // rather than silently dropping frames forever.
            stop()
            return
        }

        frameCount += 1
        let properties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: Self.frameDelay]
        ] as CFDictionary
        frameQueue.async {
            CGImageDestinationAddImage(destination, image, properties)
        }
    }
}
