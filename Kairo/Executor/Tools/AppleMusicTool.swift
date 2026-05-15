import Foundation

struct AppleMusicTool: Tool {
    let name = "apple_music"
    let description = "Controls Apple Music playback"
    let permissionTier: PermissionTier = .safe
    let supportedTiers: [ExecutionTier] = [.native]

    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult {
        let action = args["action"] as? String ?? "play"
        let query = args["query"] as? String ?? ""
        let script: String
        switch action {
        case "play":
            script = query.isEmpty
                ? "tell application \"Music\" to play"
                : "tell application \"Music\" to play (first track whose name contains \"\(query)\")"
        case "pause": script = "tell application \"Music\" to pause"
        case "next":  script = "tell application \"Music\" to next track"
        case "prev":  script = "tell application \"Music\" to previous track"
        default: return ToolResult(success: false, output: "Unknown action", tierUsed: .native)
        }
        try kairoRunAppleScript(script)

        if action == "play" || action == "next" || action == "prev" {
            try? await Task.sleep(for: .milliseconds(800))
            if let track = await AppleMusicService.currentTrack() {
                await MainActor.run {
                    KairoRuntime.shared.present(.nowPlaying, payload: track)
                }
            }
        }

        return ToolResult(success: true, output: "\(action) ok", tierUsed: .native)
    }
}

func kairoRunAppleScript(_ source: String) throws {
    var error: NSDictionary?
    if let script = NSAppleScript(source: source) {
        script.executeAndReturnError(&error)
        if let err = error {
            throw NSError(domain: "AppleScript", code: -1, userInfo: err as? [String: Any])
        }
    }
}
