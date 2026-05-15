import Foundation
import AppKit

@MainActor
final class AudioDucker {
    static let shared = AudioDucker()

    private var wasPlayingMusic = false
    private var wasPlayingSpotify = false

    func duck() async {
        let musicState = await runScript("""
            tell application "System Events"
                if exists (processes where name is "Music") then
                    tell application "Music"
                        if player state is playing then
                            pause
                            return "paused"
                        end if
                    end tell
                end if
                return "not_playing"
            end tell
        """)
        wasPlayingMusic = (musicState == "paused")

        let spotifyState = await runScript("""
            tell application "System Events"
                if exists (processes where name is "Spotify") then
                    tell application "Spotify"
                        if player state is playing then
                            pause
                            return "paused"
                        end if
                    end tell
                end if
                return "not_playing"
            end tell
        """)
        wasPlayingSpotify = (spotifyState == "paused")

        await KairoWebSocketServer.shared.send([
            "app": "browser",
            "action": "pause_all_media",
        ])
    }

    func restore() async {
        if wasPlayingMusic {
            _ = await runScript("tell application \"Music\" to play")
            wasPlayingMusic = false
        }
        if wasPlayingSpotify {
            _ = await runScript("tell application \"Spotify\" to play")
            wasPlayingSpotify = false
        }
        await KairoWebSocketServer.shared.send([
            "app": "browser",
            "action": "resume_all_media",
        ])
    }

    private static let scriptQueue = DispatchQueue(label: "com.kairo.applescript")

    private func runScript(_ source: String) async -> String {
        await withCheckedContinuation { cont in
            Self.scriptQueue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?
                    .executeAndReturnError(&error)
                    .stringValue ?? ""
                cont.resume(returning: result)
            }
        }
    }
}
