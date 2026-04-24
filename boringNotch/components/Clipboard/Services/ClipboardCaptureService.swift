import Foundation
import AppKit

@MainActor
class ClipboardCaptureService: ObservableObject {
    static let shared = ClipboardCaptureService()
    
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    
    weak var delegate: ClipboardCaptureDelegate?
    
    private init() {
        lastChangeCount = pasteboard.changeCount
    }
    
    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkForChanges() {
        let currentChangeCount = pasteboard.changeCount
        
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        
        captureCurrentClipboard()
    }
    
    private func captureCurrentClipboard() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return }
        
        let bundleIdentifier = frontmostApp.bundleIdentifier ?? "unknown"
        let appName = frontmostApp.localizedName ?? "Unknown App"
        
        // Capture only text, images are ignored
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            let item = ClipboardItem(
                id: UUID(),
                kind: .text(string),
                sourceApp: bundleIdentifier,
                sourceAppName: appName,
                timestamp: Date(),
                isPinned: false
            )
            delegate?.didCaptureClipboardItem(item)
        }
    }
}

protocol ClipboardCaptureDelegate: AnyObject {
    func didCaptureClipboardItem(_ item: ClipboardItem)
}
