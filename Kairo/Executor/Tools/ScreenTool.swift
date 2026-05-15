import AppKit
import ScreenCaptureKit
import Vision

struct ScreenTool: Tool {
    let name = "see_screen"
    let description = "Captures and OCRs the active screen"
    let permissionTier: PermissionTier = .safe
    let supportedTiers: [ExecutionTier] = [.native]

    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            return ToolResult(success: false, output: "No display found", tierUsed: .native)
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        try handler.perform([req])
        let text = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        return ToolResult(success: true, output: text, tierUsed: .native)
    }
}
