import Foundation
import Cocoa
import ApplicationServices
import AsyncXPCConnection

struct HUDPermissionStatus: Equatable, Sendable {
    let accessibilityAuthorized: Bool
    let inputMonitoringAuthorized: Bool

    var isAuthorized: Bool {
        accessibilityAuthorized
    }
}

final class XPCHelperClient: NSObject {
    nonisolated static let shared = XPCHelperClient()
    
    private let serviceName = "theboringteam.boringnotch.BoringNotchXPCHelper"
    
    private var remoteService: RemoteXPCService<BoringNotchXPCHelperProtocol>?
    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?
    private var lastKnownHUDPermissionStatus: HUDPermissionStatus?
    private var monitoringTask: Task<Void, Never>?
    
    deinit {
        connection?.invalidate()
        stopMonitoringAccessibilityAuthorization()
    }
    
    // MARK: - Connection Management (Main Actor Isolated)
    
    @MainActor
    private func ensureRemoteService() -> RemoteXPCService<BoringNotchXPCHelperProtocol> {
        if let existing = remoteService {
            return existing
        }
        
        let conn = NSXPCConnection(serviceName: serviceName)
        
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }
        
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }
        
        conn.resume()
        
        let service = RemoteXPCService<BoringNotchXPCHelperProtocol>(
            connection: conn,
            remoteInterface: BoringNotchXPCHelperProtocol.self
        )
        
        connection = conn
        remoteService = service
        return service
    }
    
    @MainActor
    private func getRemoteService() -> RemoteXPCService<BoringNotchXPCHelperProtocol>? {
        remoteService
    }
    
    @MainActor
    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": granted]
        )
    }

    @MainActor
    private func notifyHUDPermissionChange(_ status: HUDPermissionStatus) {
        notifyAuthorizationChange(status.accessibilityAuthorized)
        guard lastKnownHUDPermissionStatus != status else { return }
        lastKnownHUDPermissionStatus = status
        NSLog(
            "[HUD] permissions accessibility=%@ inputMonitoring=%@",
            status.accessibilityAuthorized.description,
            status.inputMonitoringAuthorized.description
        )
        NotificationCenter.default.post(
            name: .hudPermissionStatusChanged,
            object: nil,
            userInfo: [
                "accessibilityAuthorized": status.accessibilityAuthorized,
                "inputMonitoringAuthorized": status.inputMonitoringAuthorized,
                "authorized": status.isAuthorized
            ]
        )
    }

    // MARK: - Monitoring
    nonisolated func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        // Ensure only one monitor exists
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                _ = await self.hudPermissionStatus()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { break }
            }
        }
    }

    nonisolated func stopMonitoringAccessibilityAuthorization() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // Expose whether the client is actively monitoring (useful for tests/debug)
    var isMonitoring: Bool {
        return monitoringTask != nil
    }
    
    // MARK: - Accessibility

    // The media-key event tap lives in the main app. Accessibility trust is
    // process-specific, so checking the XPC helper here reports the wrong app.
    private nonisolated func mainAppAccessibilityAuthorized(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() || CGPreflightPostEventAccess() {
            return true
        }
        guard prompt else { return false }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestPostEventAccess()
        return AXIsProcessTrusted() || CGPreflightPostEventAccess()
    }

    private nonisolated func mainAppInputMonitoringAuthorized() -> Bool {
        CGPreflightListenEventAccess()
    }
    
    nonisolated func requestAccessibilityAuthorization() {
        let authorized = mainAppAccessibilityAuthorized(prompt: true)
        Task {
            _ = await hudPermissionStatus()
            await MainActor.run {
                notifyAuthorizationChange(authorized)
            }
        }
    }
    
    nonisolated func isAccessibilityAuthorized() async -> Bool {
        let authorized = mainAppAccessibilityAuthorized(prompt: false)
        await MainActor.run {
            notifyAuthorizationChange(authorized)
        }
        return authorized
    }
    
    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        let authorized = mainAppAccessibilityAuthorized(prompt: promptIfNeeded)
        await MainActor.run {
            notifyAuthorizationChange(authorized)
        }
        return authorized
    }

    nonisolated func isInputMonitoringAuthorized() async -> Bool {
        let authorized = mainAppInputMonitoringAuthorized()
        _ = await hudPermissionStatus()
        return authorized
    }

    nonisolated func requestInputMonitoringAuthorization() async -> Bool {
        let authorized = CGRequestListenEventAccess()
        _ = await hudPermissionStatus()
        return authorized
    }

    nonisolated func hudPermissionStatus() async -> HUDPermissionStatus {
        let status = HUDPermissionStatus(
            accessibilityAuthorized: mainAppAccessibilityAuthorized(prompt: false),
            inputMonitoringAuthorized: mainAppInputMonitoringAuthorized()
        )
        await MainActor.run {
            notifyHUDPermissionChange(status)
        }
        return status
    }

    nonisolated func requestHUDPermissions() async -> HUDPermissionStatus {
        if !mainAppAccessibilityAuthorized(prompt: false) {
            _ = mainAppAccessibilityAuthorized(prompt: true)
        }
        return await hudPermissionStatus()
    }
    
    // MARK: - Keyboard Brightness
    
    nonisolated func isKeyboardBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isKeyboardBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentKeyboardBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentKeyboardBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
    
    // MARK: - Screen Brightness
    
    nonisolated func isScreenBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isScreenBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentScreenBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentScreenBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func bluetoothAccessoryBatteryData() async -> Data? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSData? = try await service.withContinuation { service, continuation in
                service.bluetoothAccessoryBatteryData { data in
                    continuation.resume(returning: data)
                }
            }
            return result as Data?
        } catch {
            return nil
        }
    }
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
    static let hudPermissionStatusChanged = Notification.Name("hudPermissionStatusChanged")
    static let mediaKeyInterceptorStateChanged = Notification.Name("mediaKeyInterceptorStateChanged")
}
