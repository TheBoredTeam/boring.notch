//
//  TextRecognitionService.swift
//  boringNotch
//
//  Vision-backed OCR and barcode reading for captured images.
//
//  Runs entirely on-device: Vision does not touch the network, so text
//  scraped off the screen — which can be anything the user has open — never
//  leaves the Mac.
//

import CoreGraphics
import Foundation
import Vision

enum TextRecognitionError: LocalizedError {
    case noTextFound
    case noCodeFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noTextFound:
            return NSLocalizedString("capture_error_no_text", comment: "Shown when OCR found no readable text")
        case .noCodeFound:
            return NSLocalizedString("capture_error_no_code", comment: "Shown when no QR or barcode was found")
        case .failed(let reason):
            return reason
        }
    }
}

enum TextRecognitionService {
    /// Recognises text in an image and returns it assembled into paragraphs.
    ///
    /// `.accurate` rather than `.fast`: this runs once on a user-initiated
    /// capture, not per video frame, so the extra tens of milliseconds buy
    /// materially better results on small UI text — which is most of what
    /// gets captured off a screen.
    static func recognizeText(in image: CGImage) async throws -> String {
        let lines = try await recognizeLines(in: image)
        let text = OCRTextAssembler.assemble(lines)
        guard !text.isEmpty else { throw TextRecognitionError.noTextFound }
        return text
    }

    static func recognizeLines(in image: CGImage) async throws -> [RecognizedLine] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: TextRecognitionError.failed(error.localizedDescription))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines: [RecognizedLine] = observations.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return RecognizedLine(
                        text: candidate.string,
                        boundingBox: observation.boundingBox,
                        confidence: candidate.confidence
                    )
                }
                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            // Language correction fixes OCR slips using a dictionary, which
            // helps prose and actively hurts the other common case — codes,
            // identifiers, file paths and URLs, where a "correction" silently
            // changes the characters the user wanted to copy.
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true

            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: TextRecognitionError.failed(error.localizedDescription))
            }
        }
    }

    /// Reads the first QR code or barcode in an image and returns its payload.
    static func detectCode(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error {
                    continuation.resume(throwing: TextRecognitionError.failed(error.localizedDescription))
                    return
                }
                let observations = request.results as? [VNBarcodeObservation] ?? []
                // Largest first: a screenshot often catches several codes
                // (a page footer, an app badge), and the one the user aimed
                // at is almost always the biggest on screen.
                let payload = observations
                    .sorted { $0.boundingBox.area > $1.boundingBox.area }
                    .compactMap(\.payloadStringValue)
                    .first { !$0.isEmpty }

                guard let payload else {
                    continuation.resume(throwing: TextRecognitionError.noCodeFound)
                    return
                }
                continuation.resume(returning: payload)
            }

            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: TextRecognitionError.failed(error.localizedDescription))
            }
        }
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
