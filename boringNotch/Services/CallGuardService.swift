import AppKit
import AVFoundation
import Defaults
import Foundation
import SpotifyAdDampenerCore

@MainActor
final class CallGuardService: ObservableObject {
    static let shared = CallGuardService()

    @Published private(set) var isCallLikelyActive = false
    @Published private(set) var statusText = "No call detected"

    private var timer: Timer?

    private init() {}

    func start() {
        evaluate()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func evaluate() {
        let bundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let micSuspicious = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized && hasLikelyCallApp(bundleIDs)
        let screenCaptureSuspicious = CGPreflightScreenCaptureAccess() && hasLikelyCallApp(bundleIDs)
        let signals = CallGuardSignals(
            runningBundleIDs: bundleIDs,
            microphoneActive: micSuspicious,
            screenCaptureActive: screenCaptureSuspicious,
            manualOverride: Defaults[.spotifyAdDampenerManualCallSuppress]
        )
        let active = CallGuardRules.isCallActive(signals)
        isCallLikelyActive = active
        if Defaults[.spotifyAdDampenerManualCallSuppress] {
            statusText = "Manually suppressed"
        } else if active {
            statusText = "Call or capture app likely active"
        } else {
            statusText = "No call detected"
        }
    }

    private func hasLikelyCallApp(_ bundleIDs: Set<String>) -> Bool {
        !bundleIDs.isDisjoint(with: CallGuardRules.knownCallBundleIDs)
            || !bundleIDs.isDisjoint(with: CallGuardRules.browserBundleIDs)
    }
}
