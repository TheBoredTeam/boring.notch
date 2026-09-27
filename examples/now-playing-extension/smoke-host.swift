// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation

@MainActor
private enum ObservedCommands {
    static var artworkOptOut = false
}

@main
struct FreeExtensionSmoke {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let runtime = try ExtensionRuntime(url: URL(fileURLWithPath: CommandLine.arguments[1])) { _, command, value in
            guard let command else { return }
            MainActor.assumeIsolated {
                if String(cString: command) == "presentation.artwork", value == 0 { ObservedCommands.artworkOptOut = true }
            }
        }
        guard runtime.settingsController() != nil else { throw ExtensionError.incompatibleBinary }
        // No license field or license configuration exists in this test host.
        let snapshot: [String: Any] = ["title": "Free example", "artist": "Independent developer", "playing": false]
        runtime.send(snapshot: try JSONSerialization.data(withJSONObject: snapshot))
        guard ObservedCommands.artworkOptOut else { throw ExtensionError.incompatibleBinary }
        for event in ["unlock", "sleep", "wake", "session-inactive", "session-active"] { runtime.send(event: event) }
        runtime.stop()
        guard runtime.settingsController() == nil else { throw ExtensionError.incompatibleBinary }
        print("PASS: free extension loads, receives media, invokes the host, and stops without licensing")
    }
}
