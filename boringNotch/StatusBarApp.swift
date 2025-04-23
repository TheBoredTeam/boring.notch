import SwiftUI
import AppKit

@main
struct StatusBarApp: App {
    @StateObject private var workspaceMonitor = WorkspaceMonitor()
    
    var body: some Scene {
        MenuBarExtra {
            EmptyView()
        } label: {
            Text(workspaceMonitor.currentStatus)
                .font(.system(size: 12))
        }
    }
}

class WorkspaceMonitor: ObservableObject {
    @Published var currentStatus: String = "Loading..."
    private var workspaceObserver: NSObjectProtocol?
    private var appObserver: NSObjectProtocol?
    
    init() {
        setupWorkspaceObserver()
        setupAppObserver()
        updateCurrentStatus()
    }
    
    private func setupWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateCurrentStatus()
        }
    }
    
    private func setupAppObserver() {
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateCurrentStatus()
        }
    }
    
    private func updateCurrentStatus() {
        if let activeApp = NSWorkspace.shared.frontmostApplication {
            currentStatus = activeApp.localizedName ?? "Unknown App"
        } else {
            if let spaceNumber = SpaceHelper.getCurrentSpaceNumber() {
                currentStatus = "Desktop \(spaceNumber)"
            } else {
                currentStatus = "Unknown Space"
            }
        }
    }
    
    deinit {
        if let workspaceObserver = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        if let appObserver = appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appObserver)
        }
    }
} 