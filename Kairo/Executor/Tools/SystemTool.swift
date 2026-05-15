import Foundation

struct SystemTool: Tool {
    let name = "system"
    let description = "Opens apps, runs shell, controls mac"
    let permissionTier: PermissionTier = .destructive
    let supportedTiers: [ExecutionTier] = [.native]

    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult {
        let action = args["action"] as? String ?? ""
        switch action {
        case "open_app":
            let app = args["app"] as? String ?? ""
            try kairoRunAppleScript("tell application \"\(app)\" to activate")
            return ToolResult(success: true, output: "Opened \(app)", tierUsed: .native)
        case "shell":
            let cmd = args["command"] as? String ?? ""
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", cmd]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return ToolResult(success: true, output: out, tierUsed: .native)
        default:
            return ToolResult(success: false, output: "Unknown action", tierUsed: .native)
        }
    }
}
