import SwiftUI
import Combine
import AppKit

class MusicManager: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    
    @Published var songTitle: String = "Blinding Lights"
    @Published var artistName: String = "The Weeknd"
    @Published var albumArt: String = "music.note"
    @Published var isPlaying = false
    
    init() {
        setupNowPlayingObserver()
        fetchNowPlayingInfo()
    }
    
    private func setupNowPlayingObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fetchNowPlayingInfo),
            name: NSNotification.Name("com.apple.iTunes.playerInfo"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fetchNowPlayingInfo),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
    }
    
    @objc private func fetchNowPlayingInfo() {
        let scriptPath = Bundle.main.path(forResource: "NowPlaying", ofType: "scpt")
        
        guard let scriptPath = scriptPath else {
            print("Script path not found.")
            return
        }
        
        let scriptURL = URL(fileURLWithPath: scriptPath)
        
        do {
            let script = try NSAppleScript(contentsOf: scriptURL, error: nil)
            var error: NSDictionary?
            if let output = script?.executeAndReturnError(&error).stringValue {
                parseNowPlayingInfo(output)
            } else if let error = error {
                print("AppleScript Error: \(error)")
            }
        } catch {
            print("Error loading AppleScript: \(error)")
        }
    }
    
    
    private func parseNowPlayingInfo(_ info: String) {
        let components = info.components(separatedBy: "||")
        print(components)
        if components.count == 4 {
            songTitle = components[0]
            artistName = components[1]
            albumArt = components[2]
            isPlaying = (components[3] == "playing")
        } else {
            songTitle = "Unknown Title"
            artistName = "Unknown Artist"
            albumArt = "music.note"
            isPlaying = false
        }
    }
    
    func togglePlayPause() {
        if isPlaying {
            executeAppleScript(script: "tell application \"System Events\" to tell process \"\(currentPlayerProcess())\" to keystroke space")
        } else {
            executeAppleScript(script: "tell application \"System Events\" to tell process \"\(currentPlayerProcess())\" to keystroke space")
        }
    }
    
    func nextTrack() {
        let script = """
        tell application "System Events"
            if (exists (processes where name is "Music")) then
                tell application "Music" to next track
            else if (exists (processes where name is "Spotify")) then
                tell application "Spotify" to next track
            end if
        end tell
        """
        executeAppleScript(script: script)
    }
    
    func previousTrack() {
        let script = """
        tell application "System Events"
            if (exists (processes where name is "Music")) then
                tell application "Music" to previous track
            else if (exists (processes where name is "Spotify")) then
                tell application "Spotify" to previous track
            end if
        end tell
        """
        executeAppleScript(script: script)
    }
    
    private func executeAppleScript(script: String) {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript Error: \(error)")
            }
        }
    }
    
    private func currentPlayerProcess() -> String {
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").count > 0 {
            return "Music"
        } else if NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").count > 0 {
            return "Spotify"
        } else {
            return ""
        }
    }
}
