//
//  BetterDisplayManager.swift
//  boringNotch
//
//  Created by Alexander on 2026-02-05.
//

import AppKit
import CoreGraphics

@Observable
final class BetterDisplayManager {
    static let shared = BetterDisplayManager()
    
    let betterDisplayBundleIdentifier = "pro.betterdisplay.BetterDisplay"

    private enum ControlTarget {
        case brightness
        case volume
        case mute
        case other(String)

        init(from notification: BetterDisplayOSDNotification) {
            let target = notification.controlTarget ?? ""
            let iconID = notification.systemIconID ?? -1

            if target.contains("Brightness") || target.contains("brightness") || iconID == 1 {
                self = .brightness
            } else if target == "volume" || iconID == 3 {
                self = .volume
            } else if target == "mute" || iconID == 4 {
                self = .mute
            } else {
                self = .other(target)
            }
        }
    }

    private(set) var isBetterDisplayAvailable = false
    private(set) var brightnessValue: Float = 0.0
    private(set) var lastChangeAt: Date = .distantPast
    
    private let visibleDuration: TimeInterval = 1.2
    private var observers: [NSObjectProtocol] = []
    
    private init() {
        checkBetterDisplayAvailability()

        let terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.configureBetterDisplayIntegration(enabled: false)
        }
        observers.append(terminationObserver)
    }
    
    deinit { stopObserving() }
    
    var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }
    
    // MARK: - BetterDisplay Detection
    
    private func checkBetterDisplayAvailability() {
        let workspace = NSWorkspace.shared
        let betterDisplayURL = workspace.urlForApplication(withBundleIdentifier: betterDisplayBundleIdentifier)
        isBetterDisplayAvailable = betterDisplayURL != nil && workspace.runningApplications.contains(where: {
            $0.bundleIdentifier == betterDisplayBundleIdentifier
        })
    }
    
    // MARK: - Notification Observing
    
    func startObserving() {
        stopObserving()
        checkBetterDisplayAvailability()
        configureBetterDisplayIntegration(enabled: true)

        let osdObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.betterdisplay.BetterDisplay.osd"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { await self?.handleOsdNotification(notification) }
        }
        observers.append(osdObserver)

        let launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == self?.betterDisplayBundleIdentifier {
                self?.checkBetterDisplayAvailability()
                self?.configureBetterDisplayIntegration(enabled: true)
            }
        }
        observers.append(launchObserver)

        let quitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == self?.betterDisplayBundleIdentifier {
                self?.isBetterDisplayAvailable = false
            }
        }
        observers.append(quitObserver)
    }
    
    func stopObserving() {
        configureBetterDisplayIntegration(enabled: false)
        guard !observers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        observers.forEach {
            distributed.removeObserver($0)
            workspace.removeObserver($0)
        }
        observers.removeAll()
    }
    
    // MARK: - OSD Notification Handler
    
    private func handleOsdNotification(_ notification: Notification) async {
        guard let jsonString = notification.object as? String,
              let data = jsonString.data(using: .utf8) else { return }
        
        let osd: BetterDisplayOSDNotification
        do {
            osd = try JSONDecoder().decode(BetterDisplayOSDNotification.self, from: data)
        } catch { return }
        
        let targetType = ControlTarget(from: osd)
        guard let rawValue = osd.value else { return }
        let maxVal = osd.maxValue ?? 1.0
        
        switch targetType {
        case .brightness:
            let targetScreenUUID = NSScreen.screens.first { screen in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                      let displayID = osd.displayID else { return false }
                return CGDirectDisplayID(number.uint32Value) == CGDirectDisplayID(displayID)
            }?.displayUUID
            
            await MainActor.run {
                brightnessValue = Float(rawValue)
                lastChangeAt = Date()
                BoringViewCoordinator.shared.toggleSneakPeek(
                    status: true,
                    type: .brightness,
                    value: CGFloat(rawValue / maxVal),
                    targetScreenUUID: targetScreenUUID
                )
            }

        case .volume:
            let normalized = maxVal > 0 ? Float(rawValue / maxVal) : Float(rawValue)
            await MainActor.run {
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(normalized))
            }

        case .mute:
            await MainActor.run {
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(rawValue))
            }

        case .other:
            return
        }
    }
    
    // MARK: - Control Methods
    
    func adjustBrightness(by delta: Float) {
        guard isBetterDisplayAvailable else { return }
        setBrightness(max(0, min(64, brightnessValue + delta)))
    }
    
    func setBrightness(_ value: Float) {
        guard isBetterDisplayAvailable else { return }
        let normalizedValue = max(0, min(64, value))
        sendIntegrationRequest(commands: ["set"], parameters: ["brightness": "\(normalizedValue)"])
        DispatchQueue.main.async { [weak self] in
            self?.brightnessValue = normalizedValue
            self?.lastChangeAt = Date()
        }
    }
    
    // MARK: - Integration Configuration
    
    func configureBetterDisplayIntegration(enabled: Bool) {
        guard isBetterDisplayAvailable else { return }
        sendIntegrationRequest(commands: ["set"], parameters: enabled
            ? ["osdShowBasic": "off", "osdIntegrationNotification": "on"]
            : ["osdShowBasic": "on",  "osdIntegrationNotification": "off"]
        )
    }
    
    private func sendIntegrationRequest(commands: [String], parameters: [String: String]) {
        let request = BetterDisplayNotificationRequestData(
            uuid: UUID().uuidString,
            commands: commands,
            parameters: parameters
        )
        do {
            let encodedData = try JSONEncoder().encode(request)
            if let jsonString = String(data: encodedData, encoding: .utf8) {
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name("com.betterdisplay.BetterDisplay.request"),
                    object: jsonString,
                    userInfo: nil,
                    deliverImmediately: true
                )
            }
        } catch {
            print("Failed to encode integration request: \(error)")
        }
    }

}
