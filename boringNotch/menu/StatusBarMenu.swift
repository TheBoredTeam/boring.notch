import Cocoa
import SwiftUI

class BoringStatusMenu: NSMenu {
    var statusItem: NSStatusItem!
    private var pomodoroWindow: NSWindow?
    
    override init() {
        super.init()
        setupStatusItem()
        buildMenu()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "BoringNotch")
            button.action = #selector(showMenu)
        }
    }
    
    private func buildMenu() {
        let menu = NSMenu()
        let pomodoroItem = NSMenuItem(title: "Pomodoro Timer", action: #selector(openPomodoro), keyEquivalent: "p")
        pomodoroItem.target = self
        menu.addItem(pomodoroItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }
    
    @objc private func showMenu() {
        statusItem.button?.performClick(nil)
    }
    
    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
    
    @objc private func openPomodoro() {
        if let window = pomodoroWindow, window.isVisible {
            window.close()
            pomodoroWindow = nil
            return
        }
        let hosting = NSHostingController(rootView: PomodoroView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Pomodoro"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        pomodoroWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
