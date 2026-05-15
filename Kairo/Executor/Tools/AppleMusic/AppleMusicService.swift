import Foundation

struct AppleMusicService {
    static let scriptQueue = DispatchQueue(label: "com.kairo.applescript.music")
    static func currentTrack() async -> NowPlayingData? {
        let script = """
        tell application "Music"
            if it is running then
                if player state is playing or player state is paused then
                    set trackName to name of current track
                    set artistName to artist of current track
                    set isPlaying to (player state is playing)
                    return trackName & "|||" & artistName & "|||" & (isPlaying as string)
                end if
            end if
            return ""
        end tell
        """

        return await withCheckedContinuation { cont in
            AppleMusicService.scriptQueue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: script)?
                    .executeAndReturnError(&error)
                    .stringValue ?? ""

                guard !result.isEmpty else {
                    cont.resume(returning: nil)
                    return
                }

                let parts = result.components(separatedBy: "|||")
                guard parts.count >= 3 else {
                    cont.resume(returning: nil)
                    return
                }

                let data = NowPlayingData(
                    title: parts[0],
                    artist: parts[1],
                    artworkURL: nil,
                    isPlaying: parts[2] == "true"
                )
                cont.resume(returning: data)
            }
        }
    }
}
