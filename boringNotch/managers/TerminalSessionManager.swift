//
//  TerminalSessionManager.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import Defaults
import SwiftTerm

enum TerminalCursorStyleOption: String, CaseIterable {
    case blinkBlock
    case steadyBlock
    case blinkUnderline
    case steadyUnderline
    case blinkBar
    case steadyBar

    var displayName: String {
        switch self {
        case .blinkBlock: "Block (blinking)"
        case .steadyBlock: "Block (steady)"
        case .blinkUnderline: "Underline (blinking)"
        case .steadyUnderline: "Underline (steady)"
        case .blinkBar: "Bar (blinking)"
        case .steadyBar: "Bar (steady)"
        }
    }

    var swiftTermStyle: CursorStyle {
        switch self {
        case .blinkBlock: .blinkBlock
        case .steadyBlock: .steadyBlock
        case .blinkUnderline: .blinkUnderline
        case .steadyUnderline: .steadyUnderline
        case .blinkBar: .blinkBar
        case .steadyBar: .steadyBar
        }
    }
}

final class StableTerminalHostView: NSView {
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        guard bounds.width >= 10, bounds.height >= 10 else { return }
        for subview in subviews where subview is LocalProcessTerminalView {
            subview.frame = bounds.insetBy(dx: 6, dy: 6)
        }
        for subview in subviews where subview is NSVisualEffectView {
            subview.frame = bounds
        }
    }
}

@MainActor
final class TerminalSessionManager: ObservableObject {
    private static var sessions: [String: TerminalSessionManager] = [:]

    static func session(for screenUUID: String?) -> TerminalSessionManager {
        let key = screenUUID ?? "primary"
        if let session = sessions[key] { return session }
        let session = TerminalSessionManager()
        sessions[key] = session
        return session
    }

    static func applyCurrentSettings() {
        for session in sessions.values {
            session.applySettings()
        }
    }

    @Published private(set) var title = "Terminal"
    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?

    let hostView: StableTerminalHostView = {
        let view = StableTerminalHostView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        let backdrop = NSVisualEffectView(frame: view.bounds)
        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.autoresizingMask = [.width, .height]
        view.addSubview(backdrop)
        return view
    }()

    private var terminalView: LocalProcessTerminalView?
    private weak var focusedWindow: BoringNotchSkyLightWindow?

    private init() {}

    func mount(delegate: LocalProcessTerminalViewDelegate) {
        if let terminalView {
            terminalView.processDelegate = delegate
            return
        }

        let frame = hostView.bounds.width >= 10 && hostView.bounds.height >= 10
            ? hostView.bounds.insetBy(dx: 6, dy: 6)
            : NSRect(x: 0, y: 0, width: 588, height: 288)
        let view = LocalProcessTerminalView(frame: frame)
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = .white
        view.processDelegate = delegate
        hostView.addSubview(view)
        terminalView = view
        applySettings()
        startShell()
    }

    private func applySettings() {
        guard let terminalView else { return }
        let fontSize = CGFloat(Defaults[.terminalFontSize])
        let family = Defaults[.terminalFontFamily]
        terminalView.font = NSFont(name: family, size: fontSize)
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let background = NSColor(Defaults[.terminalBackgroundColor])
            .withAlphaComponent(CGFloat(Defaults[.terminalOpacity]))
        terminalView.nativeBackgroundColor = background
        terminalView.layer?.backgroundColor = NSColor.clear.cgColor
        terminalView.layer?.isOpaque = false
        terminalView.nativeForegroundColor = NSColor(Defaults[.terminalForegroundColor])
        terminalView.caretColor = NSColor(Defaults[.terminalCursorColor])
        terminalView.caretViewTracksFocus = false
        let cursorStyle = TerminalCursorStyleOption(rawValue: Defaults[.terminalCursorStyle])
            ?? .blinkBlock
        terminalView.getTerminal().setCursorStyle(cursorStyle.swiftTermStyle)
        let scrollback = Defaults[.terminalScrollbackLines]
        terminalView.getTerminal().buffer.changeHistorySize(scrollback)
        terminalView.getTerminal().options.scrollback = scrollback
        terminalView.optionAsMetaKey = Defaults[.terminalOptionAsMeta]
        terminalView.allowMouseReporting = Defaults[.terminalMouseReporting]
        terminalView.useBrightColors = Defaults[.terminalBoldAsBright]
        terminalView.setNeedsDisplay(terminalView.bounds)
    }

    func restart() {
        terminalView?.terminate()
        terminalView?.removeFromSuperview()
        terminalView = nil
        isRunning = false
        title = "Terminal"
        errorMessage = nil
    }

    func shellDidExit(source: TerminalView) {
        guard let terminalView, source === terminalView else { return }
        isRunning = false
    }

    func setTitle(_ newTitle: String) {
        title = newTitle
    }

    func focus(attempts: Int = 4) {
        guard BoringViewCoordinator.shared.currentView == .terminal else { return }
        guard let terminalView else { return }
        guard let window = hostView.window as? BoringNotchSkyLightWindow else {
            retryFocus(attempts: attempts)
            return
        }
        focusedWindow = window
        window.wantsKeyForTextInput = true
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        window.makeKeyAndOrderFront(nil)
        if !window.makeFirstResponder(terminalView) {
            retryFocus(attempts: attempts)
        }
    }

    func resignFocus() {
        if let window = focusedWindow {
            if window.firstResponder === terminalView {
                window.makeFirstResponder(nil)
            }
            window.wantsKeyForTextInput = false
        }
        focusedWindow = nil
    }

    private func retryFocus(attempts: Int) {
        guard attempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.focus(attempts: attempts - 1)
        }
    }

    private func startShell() {
        guard let terminalView else { return }
        let shell = Defaults[.terminalShellPath]
        guard shell.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: shell) else {
            errorMessage = "The selected shell is not executable. Choose another shell in Settings."
            return
        }
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
        environment.removeValue(forKey: "TERM_PROGRAM")
        terminalView.startProcess(
            executable: shell,
            args: [],
            environment: environment.map { "\($0.key)=\($0.value)" },
            execName: "-" + (shell as NSString).lastPathComponent
        )
        isRunning = true
    }
}
