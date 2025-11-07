import SwiftUI

extension Bundle {
    var loftReleaseVersionNumber: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    var loftBuildVersionNumber: String? {
        infoDictionary?["CFBundleVersion"] as? String
    }
    
    var loftReleaseVersionPretty: String {
        "v\(loftReleaseVersionNumber ?? "1.0.0")"
    }
    
    var loftIconFileName: String? {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let iconFileName = iconFiles.last
        else { return nil }
        return iconFileName
    }
}

struct LoftBundleAppIcon: View {
    var body: some View {
        Bundle.main.loftIconFileName
            .flatMap { NSImage(named: $0) }
            .map { Image(nsImage: $0) }
    }
}

func loftIsNewVersion() -> Bool {
    let defaults = UserDefaults.standard
    let currentVersion = Bundle.main.loftReleaseVersionNumber ?? "1.0"
    let savedVersion = defaults.string(forKey: "LastVersionRun") ?? ""
    
    if currentVersion != savedVersion {
        defaults.set(currentVersion, forKey: "LastVersionRun")
        return true
    }
    return false
}

func loftIsExtensionRunning(_ bundleID: String) -> Bool {
    NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
}
