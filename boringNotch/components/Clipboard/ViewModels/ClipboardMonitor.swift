import Foundation
import AppKit

@MainActor
class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()
    
    private let captureService = ClipboardCaptureService.shared
    private let stateViewModel = ClipboardStateViewModel.shared
    
    private init() {
        captureService.delegate = stateViewModel
    }
    
    func startMonitoring() {
        captureService.startMonitoring()
    }
    
    func stopMonitoring() {
        captureService.stopMonitoring()
    }
}
