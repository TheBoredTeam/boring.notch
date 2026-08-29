//
//  ClaudeCodeAuthOpener.swift
//  boringNotch
//
//  Opens Terminal running the claude CLI so the user can sign in once.
//  Authentication itself always happens in the user's own terminal.
//

import Foundation
import AppKit

enum ClaudeCodeAuthOpener {
    @discardableResult
    static func openTerminalLogin() -> Bool {
        let binary = ClaudeCodeRunner.resolveBinary()
        let command = binary.isEmpty ? "claude" : "'\(binary.replacingOccurrences(of: "'", with: ""))'"
        let source = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            NSLog("[Agent] opened Terminal for Claude Code login")
            return true
        } catch {
            NSLog("[Agent] failed to open Terminal: \(error)")
            return false
        }
    }
}