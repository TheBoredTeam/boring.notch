//  ConstellagentPresenceService.swift
//  IslandNotch
//
//  Purpose: Tracks whether the Constellagent desktop app is running (badge only —
//           the notch stays visible regardless).
//  Layer: Service

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ConstellagentPresenceService {
    static let productionBundleID = "com.constellagent.app"
    static let localizedAppName = "Constellagent"

    private(set) var isRunning = false

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.refresh() },
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.refresh() },
        ]
    }

    func refresh() {
        let next = Self.constellagentIsRunning()
        guard next != isRunning else { return }
        isRunning = next
        Log.app.debug("Constellagent running: \(next)")
    }

    static func constellagentIsRunning() -> Bool {
        if ProcessInfo.processInfo.environment["CONSTELLAGENT_ISLAND_NOTCH_ALWAYS"] == "1" {
            return true
        }
        return NSWorkspace.shared.runningApplications.contains(where: isConstellagent)
    }

    static func isConstellagent(_ app: NSRunningApplication) -> Bool {
        if app.bundleIdentifier == productionBundleID {
            return app.activationPolicy == .regular
        }

        guard app.activationPolicy == .regular else { return false }

        if let path = app.executableURL?.path {
            if path.contains("/constellagent/desktop")
                || path.contains("/constellagent/desktop/node_modules/electron")
                || path.hasSuffix("/Constellagent.app/Contents/MacOS/Constellagent")
                || path.hasSuffix("/Electron.app/Contents/MacOS/Electron") {
                return app.localizedName == localizedAppName
            }
            if ProcessInfo.processInfo.environment["CONSTELLAGENT_ISOLATED_DEV"] == "1",
               path.contains("/constellagent/") {
                return app.localizedName == localizedAppName
            }
        }

        guard app.localizedName == localizedAppName else { return false }
        guard let bundleID = app.bundleIdentifier else { return false }
        return bundleID == "com.github.Electron"
            || bundleID.hasPrefix("com.electron.")
            || bundleID.contains("constellagent")
    }
}
