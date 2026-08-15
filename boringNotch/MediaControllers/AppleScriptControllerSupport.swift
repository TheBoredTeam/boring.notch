//
//  AppleScriptControllerSupport.swift
//  boringNotch
//
//  Shared scaffolding for AppleScript-driven media controllers.
//

import Foundation

/// The "tell application X to command" shape and distributed player-info
/// observation that AppleMusicController and SpotifyController previously
/// copy-pasted between each other.
enum AppleScriptControllerSupport {
    static func executeCommand(_ command: String, appName: String) async {
        let script = "tell application \"\(appName)\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
    }

    /// Streams player-info notifications from DistributedNotificationCenter
    /// and cancels the underlying observer when the stream terminates.
    static func playerInfoNotifications(named name: String) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let observerTask = Task {
                let notifications = DistributedNotificationCenter.default().notifications(
                    named: NSNotification.Name(name)
                )
                for await _ in notifications {
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in observerTask.cancel() }
        }
    }
}
