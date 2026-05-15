import Foundation

struct YouTubeTool: Tool {
    let name = "youtube"
    let description = "Plays YouTube videos via browser extension"
    let permissionTier: PermissionTier = .safe
    let supportedTiers: [ExecutionTier] = [.browserExtension, .uiAutomation]

    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult {
        let query = args["query"] as? String ?? ""

        switch tier {
        case .browserExtension:
            await KairoWebSocketServer.shared.send([
                "app": "youtube",
                "action": "play",
                "query": query,
                "autoplay": true
            ] as [String: Any])
            return ToolResult(success: true, output: "Playing: \(query)", tierUsed: .browserExtension)

        case .uiAutomation:
            let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let url = "https://www.youtube.com/results?search_query=\(escaped)"
            try kairoRunAppleScript("open location \"\(url)\"")
            return ToolResult(success: true, output: "Opened YouTube search", tierUsed: .uiAutomation)

        default:
            return ToolResult(success: false, output: "Unsupported tier", tierUsed: tier)
        }
    }
}
