import Foundation
import Cocoa
@preconcurrency import AsyncXPCConnection

final class XPCHelperClient: NSObject {
    nonisolated static let shared = XPCHelperClient()
    
    private let serviceName = "theboringteam.boringnotch.BoringNotchXPCHelper"
    
    private var remoteService: RemoteXPCService<BoringNotchXPCHelperProtocol>?
    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?
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

    // MARK: - Monitoring
    nonisolated func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        // Ensure only one monitor exists
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Call the helper method periodically which will notify on change
                _ = await self.isAccessibilityAuthorized()
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
    
    nonisolated func requestAccessibilityAuthorization() {
        Task {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            try? await service.withService { service in
                service.requestAccessibilityAuthorization()
            }
        }
    }
    
    nonisolated func isAccessibilityAuthorized() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.isAccessibilityAuthorized { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.ensureAccessibilityAuthorization(promptIfNeeded) { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
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

    // MARK: - Menu Bar Access

    nonisolated func menuBarItems() async -> MenuBarItemsResponse {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let data: Data = try await service.withContinuation { service, continuation in
                service.listMenuBarItems { data in
                    continuation.resume(returning: data)
                }
            }
            return try JSONDecoder().decode(MenuBarItemsResponse.self, from: data)
        } catch {
            return MenuBarItemsResponse(
                items: [],
                accessibilityAuthorized: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    nonisolated func activateMenuBarItem(_ descriptor: MenuBarItemDescriptor) async -> MenuBarActionResponse {
        do {
            let request = try JSONEncoder().encode(descriptor)
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let data: Data = try await service.withContinuation { service, continuation in
                service.activateMenuBarItem(request) { data in
                    continuation.resume(returning: data)
                }
            }
            return try JSONDecoder().decode(MenuBarActionResponse.self, from: data)
        } catch {
            return MenuBarActionResponse(success: false, errorMessage: error.localizedDescription)
        }
    }

    nonisolated func menu(for descriptor: MenuBarItemDescriptor) async -> MenuBarMenuResponse {
        do {
            let request = try JSONEncoder().encode(descriptor)
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let data: Data = try await service.withContinuation { service, continuation in
                service.inspectMenuBarItem(request) { data in
                    continuation.resume(returning: data)
                }
            }
            return try JSONDecoder().decode(MenuBarMenuResponse.self, from: data)
        } catch {
            return MenuBarMenuResponse(
                isSupported: false,
                originalMenuPresented: false,
                entries: [],
                errorMessage: error.localizedDescription
            )
        }
    }

    nonisolated func activateMenuEntry(
        _ entry: MenuBarMenuEntry,
        for descriptor: MenuBarItemDescriptor
    ) async -> MenuBarActionResponse {
        do {
            let request = try JSONEncoder().encode(
                MenuBarMenuActionRequest(item: descriptor, entry: entry)
            )
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let data: Data = try await service.withContinuation { service, continuation in
                service.activateMenuBarMenuEntry(request) { data in
                    continuation.resume(returning: data)
                }
            }
            return try JSONDecoder().decode(MenuBarActionResponse.self, from: data)
        } catch {
            return MenuBarActionResponse(success: false, errorMessage: error.localizedDescription)
        }
    }

    nonisolated func moveMenuBarItem(
        _ request: MenuBarItemMoveRequest
    ) async -> MenuBarActionResponse {
        do {
            let requestData = try JSONEncoder().encode(request)
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let data: Data = try await service.withContinuation { service, continuation in
                service.moveMenuBarItem(requestData) { data in
                    continuation.resume(returning: data)
                }
            }
            return try JSONDecoder().decode(MenuBarActionResponse.self, from: data)
        } catch {
            return MenuBarActionResponse(success: false, errorMessage: error.localizedDescription)
        }
    }

}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}
