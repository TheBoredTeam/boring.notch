import Foundation

public struct CallGuardSignals: Equatable {
    public let runningBundleIDs: Set<String>
    public let microphoneActive: Bool
    public let screenCaptureActive: Bool
    public let manualOverride: Bool

    public init(runningBundleIDs: Set<String>, microphoneActive: Bool, screenCaptureActive: Bool, manualOverride: Bool) {
        self.runningBundleIDs = runningBundleIDs
        self.microphoneActive = microphoneActive
        self.screenCaptureActive = screenCaptureActive
        self.manualOverride = manualOverride
    }
}

public enum CallGuardRules {
    public static let knownCallBundleIDs: Set<String> = [
        "com.apple.FaceTime",
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.hnc.Discord",
        "com.tinyspeck.slackmacgap",
        "net.whatsapp.WhatsApp",
        "ru.keepcoder.Telegram"
    ]

    public static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "com.microsoft.edgemac"
    ]

    public static func isCallActive(_ signals: CallGuardSignals) -> Bool {
        if signals.manualOverride { return true }
        if signals.microphoneActive { return true }
        if signals.screenCaptureActive && !signals.runningBundleIDs.isDisjoint(with: knownCallBundleIDs) { return true }
        return false
    }
}
