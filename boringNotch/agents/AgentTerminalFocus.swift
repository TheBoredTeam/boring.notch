//
//  AgentTerminalFocus.swift
//  boringCode
//
//  Traz para frente a aba/janela onde a sessão está rodando. Casamento por TTY
//  via AppleScript no Terminal/iTerm2, como no TerminalJumpService do Open Island
//  (github.com/Octane0411/open-vibe-island), GPL-3.0.
//

import AppKit
import os

enum AgentTerminalFocus {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "boringcode", category: "AgentTerminalFocus")

    static func focus(_ session: AgentSession) {
        switch session.host {
        case .terminal:
            if let tty = session.tty, runAppleScript(terminalScript(tty: devPath(tty))) { return }
            activate(bundleID: "com.apple.Terminal")
        case .iTerm:
            if let tty = session.tty, runAppleScript(iTermScript(tty: devPath(tty))) { return }
            activate(bundleID: "com.googlecode.iterm2")
        case .vsCode(let bundleID):
            // Abrir a pasta foca a janela que já está com ela aberta.
            openFolder(session.cwd, bundleID: bundleID)
        case .claudeDesktop, .other, .unknown:
            if let bundleID = session.host.bundleID { activate(bundleID: bundleID) }
        }
    }

    private static func devPath(_ tty: String) -> String {
        tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
    }

    private static func activate(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
            return
        }
        app.activate()
    }

    private static func openFolder(_ path: String, bundleID: String) {
        guard !path.isEmpty,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            activate(bundleID: bundleID)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: appURL, configuration: configuration)
    }

    @discardableResult
    private static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            log.error("AppleScript falhou: \(error, privacy: .public)")
            return false
        }
        return result?.booleanValue ?? false
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func terminalScript(tty: String) -> String {
        """
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(escape(tty))" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
    }

    private static func iTermScript(tty: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(escape(tty))" then
                            select w
                            tell t to select
                            tell s to select
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
    }
}
