//
//  BackgroundAppsManager.swift
//  boringNotch
//
//  Tracks menu bar apps whose icons may be hidden by the notch
//

import AppKit
import Combine
import SwiftUI

struct AppInfo: Identifiable, Equatable {
    let id: String          // bundleIdentifier
    let bundleID: String
    let localizedName: String
    let icon: NSImage
    let pid: pid_t

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.bundleID == rhs.bundleID
    }
}

@MainActor
class BackgroundAppsManager: ObservableObject {
    static let shared = BackgroundAppsManager()

    @Published var runningApps: [AppInfo] = []

    private var cancellables = Set<AnyCancellable>()

    private init() {
        refreshAppsImpl()
        observeNotifications()
    }

    deinit {
        cancellables.forEach { $0.cancel() }
    }

    // MARK: - Public

    func refreshApps() {
        refreshAppsImpl()
    }

    func activateApp(_ app: AppInfo) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        }
    }

    func showApp(_ app: AppInfo) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        guard let runningApp = apps.first else { return }
        runningApp.unhide()
        runningApp.activate(options: .activateIgnoringOtherApps)
    }

    func quitApp(_ app: AppInfo) {
        let pid = app.pid
        Task {
            await XPCHelperClient.shared.quitApp(pid: pid, force: false)
        }
    }

    func forceQuitApp(_ app: AppInfo) {
        let pid = app.pid
        Task {
            await XPCHelperClient.shared.quitApp(pid: pid, force: true)
        }
    }

    // MARK: - Private helpers

    private func findRunningApp(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    // MARK: - Private

    private func refreshAppsImpl() {
        let workspace = NSWorkspace.shared
        let ourBundleID = Bundle.main.bundleIdentifier ?? ""

        let apps = workspace.runningApplications
            .filter { app in
                guard let bundleID = app.bundleIdentifier,
                      let name = app.localizedName, !name.isEmpty
                else { return false }

                // Show all regular and accessory GUI apps
                guard app.activationPolicy == .regular || app.activationPolicy == .accessory else { return false }

                // Exclude ourselves
                guard bundleID != ourBundleID else { return false }

                // Exclude Apple system daemons
                guard !bundleID.hasPrefix("com.apple.") else { return false }

                // Exclude WebKit helper / renderer subprocesses
                guard bundleID.range(of: "\\.WebKit\\.", options: .regularExpression) == nil else { return false }
                guard !bundleID.contains(".helper") else { return false }
                guard !bundleID.contains(".renderer") else { return false }

                // Exclude virtualization guest VMs
                guard bundleID != "com.apple.Virtualization.VirtualMachine" else { return false }

                return true
            }
            .compactMap { app -> AppInfo? in
                guard
                    let bundleID = app.bundleIdentifier,
                    let name = app.localizedName
                else { return nil }

                let icon: NSImage
                if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                    icon = workspace.icon(forFile: appURL.path)
                    icon.size = NSSize(width: 22, height: 22)
                } else {
                    let runningIcon = app.icon ?? workspace.icon(for: .applicationBundle)
                    runningIcon.size = NSSize(width: 22, height: 22)
                    icon = runningIcon
                }

                return AppInfo(
                    id: bundleID,
                    bundleID: bundleID,
                    localizedName: name,
                    icon: icon,
                    pid: app.processIdentifier
                )
            }

        // Deduplicate by "clean name" — merge sub-processes into their parent app
        var seen = [String: AppInfo]()
        for appInfo in apps {
            let key = Self.groupKey(for: appInfo)
            if let existing = seen[key] {
                // Keep the one with the shorter bundle ID (more likely the main app)
                if appInfo.bundleID.count < existing.bundleID.count {
                    seen[key] = appInfo
                }
            } else {
                seen[key] = appInfo
            }
        }
        runningApps = Array(seen.values)
    }

    /// Derive a group key from an app's name so sub-processes map to the same parent
    private static func groupKey(for app: AppInfo) -> String {
        var name = app.localizedName
        let suffixes = [
            " Helper (Renderer)", " Helper (Plugin)", " Helper",
            " Graphics and Media", " Networking", " Web Content",
            " Agent", " Launcher", " Health Monitor", " Menu",
        ]
        for suffix in suffixes {
            if name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
                break
            }
        }
        return name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func observeNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshAppsImpl() }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshAppsImpl() }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshAppsImpl() }
            .store(in: &cancellables)
    }

    /// Convert icon to grayscale for menu-bar-like appearance
    private static func desaturatedIcon(_ icon: NSImage) -> NSImage {
        guard let tiff = icon.tiffRepresentation,
              let ciImage = CIImage(data: tiff)
        else { return icon }

        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(0.0, forKey: kCIInputSaturationKey)
        filter?.setValue(0.05, forKey: kCIInputBrightnessKey)
        filter?.setValue(1.1, forKey: kCIInputContrastKey)

        guard let output = filter?.outputImage else { return icon }

        let rep = NSCIImageRep(ciImage: output)
        let result = NSImage(size: NSSize(width: 22, height: 22))
        result.addRepresentation(rep)
        return result
    }
}
