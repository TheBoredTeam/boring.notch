//
//  BetterDisplayManager.swift
//  boringNotch
//
//  Created by Alexander on 2026-02-05.
//

import Foundation
import Cocoa
import CoreGraphics
import Defaults
import Combine

final class BetterDisplayManager: ObservableObject {
    static let shared = BetterDisplayManager()
    
    @Published private(set) var isBetterDisplayAvailable = false
    @Published private(set) var brightnessValue: Float = 0.0
    @Published private(set) var lastChangeAt: Date = .distantPast
    
    private let visibleDuration: TimeInterval = 1.2
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var shouldEnableIntegration: Bool {
        Defaults[.osdReplacement]
            && (Defaults[.osdBrightnessSource] == .betterDisplay || Defaults[.osdVolumeSource] == .betterDisplay)
    }
    
    private init() {
        checkBetterDisplayAvailability()
        refreshIntegrationState()
        // Observe OSD source changes (brightness, volume) and OSD replacement
        Defaults.publisher(.osdBrightnessSource)
            .sink { [weak self] _ in self?.refreshIntegrationState() }
            .store(in: &cancellables)

        Defaults.publisher(.osdVolumeSource)
            .sink { [weak self] _ in self?.refreshIntegrationState() }
            .store(in: &cancellables)

        Defaults.publisher(.osdReplacement)
            .sink { [weak self] _ in self?.refreshIntegrationState() }
            .store(in: &cancellables)
        // Observe app termination to restore OSD
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.configureBetterDisplayIntegration(enabled: false)
            }
            .store(in: &cancellables)
    }
    
    deinit {
        stopObserving()
    }
    
    var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }
    
    // MARK: - BetterDisplay Detection
    
    private func checkBetterDisplayAvailability() {
        let workspace = NSWorkspace.shared
        let betterDisplayURL = workspace.urlForApplication(withBundleIdentifier: "pro.betterdisplay.BetterDisplay")
        
        isBetterDisplayAvailable = betterDisplayURL != nil && workspace.runningApplications.contains(where: {
            $0.bundleIdentifier == "pro.betterdisplay.BetterDisplay"
        })
    }
    
    // MARK: - Notification Observing
    
    func startObserving() {
        stopObserving()
        checkBetterDisplayAvailability()
        
        // 1) Observe BetterDisplay OSD notifications (the documented integration API)
        let osdObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.betterdisplay.BetterDisplay.osd"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { await self?.handleOsdNotification(notification) }
        }
        observers.append(osdObserver)
        
        // 2) Observe BetterDisplay launch/quit via the regular notification center
        let launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == "pro.betterdisplay.BetterDisplay" {
                self?.checkBetterDisplayAvailability()
                if self?.shouldEnableIntegration == true {
                    self?.configureBetterDisplayIntegration(enabled: true)
                }
            }
        }
        observers.append(launchObserver)
        
        let quitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == "pro.betterdisplay.BetterDisplay" {
                self?.isBetterDisplayAvailable = false
            }
        }
        observers.append(quitObserver)
    }
    
    func stopObserving() {
        guard !observers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        observers.forEach { observer in
            distributed.removeObserver(observer)
            workspace.removeObserver(observer)
        }
        observers.removeAll()
    }
    
    // MARK: - OSD Notification Handler
    
    private func handleOsdNotification(_ notification: Notification) async {
        // BetterDisplay sends the JSON as notification.object (a String), not userInfo
        guard let jsonString = notification.object as? String,
              let data = jsonString.data(using: .utf8) else {
            return
        }
        
        let osd: BetterDisplayOSDNotification
        do {
            osd = try JSONDecoder().decode(BetterDisplayOSDNotification.self, from: data)
        } catch {
            return
        }
        
        // Determine type from controlTarget or systemIconID
        let target = osd.controlTarget ?? ""
        let iconID = osd.systemIconID ?? -1
        
        let isBrightness = target.contains("Brightness") || target.contains("brightness") || iconID == 1
        let isVolume = target == "volume" || iconID == 3
        let isMute = target == "mute" || iconID == 4
        
        guard let rawValue = osd.value else { return }
        let maxVal = osd.maxValue ?? 1.0
        
        if isBrightness {
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
        } else if isVolume {
            let normalized = maxVal > 0 ? Float(rawValue / maxVal) : Float(rawValue)
            await MainActor.run {
                BoringViewCoordinator.shared.toggleSneakPeek(
                    status: true,
                    type: .volume,
                    value: CGFloat(normalized)
                )
            }
        } else if isMute {
            await MainActor.run {
                BoringViewCoordinator.shared.toggleSneakPeek(
                    status: true,
                    type: .volume,
                    value: CGFloat(rawValue)
                )
            }
        }
    }
    
    // MARK: - Control Methods
    
    func adjustBrightness(by delta: Float) {
        guard isBetterDisplayAvailable else { return }
        let newBrightness = max(0, min(64, brightnessValue + delta))
        setBrightness(newBrightness)
    }
    
    func setBrightness(_ value: Float) {
        guard isBetterDisplayAvailable else { return }
        
        // Send command to BetterDisplay using DistributedNotificationCenter
        let normalizedValue = max(0, min(64, value))
        sendIntegrationRequest(commands: ["set"], parameters: ["brightness": "\(normalizedValue)"])
        
        // Update local state
        DispatchQueue.main.async { [weak self] in
            self?.brightnessValue = normalizedValue
            self?.lastChangeAt = Date()
        }
    }
    
    // MARK: - BetterDisplay Integration Configuration
    
    private func configureBetterDisplayIntegration(enabled: Bool) {
        guard isBetterDisplayAvailable else { return }
        
        if enabled {
            // Disable BetterDisplay's OSD and enable notifications
            sendIntegrationRequest(commands: ["set"], parameters: [
                "osdShowBasic": "off",
                "osdIntegrationNotification": "on"
            ])
        } else {
            // Restore BetterDisplay's OSD and disable notifications
            sendIntegrationRequest(commands: ["set"], parameters: [
                "osdShowBasic": "on",
                "osdIntegrationNotification": "off"
            ])
        }
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

    private func refreshIntegrationState() {
        if shouldEnableIntegration {
            startObserving()
            configureBetterDisplayIntegration(enabled: true)
        } else {
            configureBetterDisplayIntegration(enabled: false)
            stopObserving()
        }
    }
}
