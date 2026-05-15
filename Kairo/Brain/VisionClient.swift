import Foundation
import AppKit
import ScreenCaptureKit
import CoreGraphics
import UniformTypeIdentifiers

/// Multimodal vision via Anthropic's Claude API.
///
/// Captures the current display, base64-encodes the image, and asks
/// Claude 3.5 Sonnet a question about it via the Messages API.
///
/// Requires `ANTHROPIC_API_KEY` in env. Without it, all calls return
/// the error string so the ReAct loop can route around.
///
/// Privacy: only ever called from `VisionTool`, which is invoked
/// explicitly by the LLM (which is in turn invoked by the user).
/// Screen capture goes through macOS's `ScreenCaptureKit` consent
/// gate the first time.
@MainActor
final class KairoVisionClient {
    static let shared = KairoVisionClient()
    private init() {}

    /// Whether an API key is configured. The Brain checks this to decide
    /// whether to advertise the `vision` tool in early conversation.
    var isConfigured: Bool {
        let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        return !key.isEmpty
    }

    /// Capture the screen + ask Claude. Returns the model's text reply.
    func ask(question: String) async throws -> String {
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !key.isEmpty else {
            throw VisionError.notConfigured
        }

        // 1. Capture screen
        let imageData = try await captureScreenAsJPEG()
        let base64 = imageData.base64EncodedString()

        // 2. Build the Messages API payload
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20

        let body: [String: Any] = [
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 600,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64
                            ]
                        ],
                        [
                            "type": "text",
                            "text": question.isEmpty ? "Describe what's on screen in one paragraph." : question
                        ]
                    ]
                ]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        // 3. Call
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw VisionError.transport("Bad response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw VisionError.httpStatus(http.statusCode, body.prefix(200).description)
        }

        // 4. Extract content[0].text
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw VisionError.malformedResponse
        }
        return text
    }

    // MARK: - Capture

    private func captureScreenAsJPEG() async throws -> Data {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw VisionError.captureFailed("No display found")
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        // Downscale to keep payload reasonable — Claude can do 1568×1568 max,
        // and we don't need pixel-perfect for context.
        let scale: CGFloat = 0.6
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try jpegData(from: cgImage, quality: 0.7)
    }

    private func jpegData(from cgImage: CGImage, quality: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw VisionError.captureFailed("Couldn't create image destination")
        }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw VisionError.captureFailed("JPEG encode failed")
        }
        return data as Data
    }
}

// MARK: - Errors

enum VisionError: LocalizedError {
    case notConfigured
    case captureFailed(String)
    case transport(String)
    case httpStatus(Int, String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:           return "Vision needs ANTHROPIC_API_KEY in ~/.kairo.env"
        case .captureFailed(let s):    return "Screen capture failed: \(s)"
        case .transport(let s):        return "Network error: \(s)"
        case .httpStatus(let c, let s): return "Claude API HTTP \(c): \(s)"
        case .malformedResponse:       return "Claude returned unexpected payload"
        }
    }
}
