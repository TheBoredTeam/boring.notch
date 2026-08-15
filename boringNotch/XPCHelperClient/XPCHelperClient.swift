import Foundation
import Cocoa
import AsyncXPCConnection

final class XPCHelperClient: NSObject {
    nonisolated static let shared = XPCHelperClient()
    
    private let serviceName = "theboringteam.boringnotch.BoringNotchXPCHelper"
    
    private var remoteService: RemoteXPCService<BoringNotchXPCHelperProtocol>?
    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?
    private let notificationDelegate = NotificationXPCDelegate()
    @MainActor private var activationObserver: (any NSObjectProtocol)?
    private var lunarListener: BoringNotchXPCHelperLunarListener?
    private var hasLunarListener: Bool = false
    
    deinit {
        connection?.invalidate()
        stopMonitoringAccessibilityAuthorization()
    }
    
    // MARK: - Connection Management (Main Actor Isolated)
    
    @MainActor
    private func ensureRemoteService(needsListener: Bool = false) -> RemoteXPCService<BoringNotchXPCHelperProtocol> {
        // Always reuse a live connection — never tear one down to attach a
        // listener. The exported object below serves *both* callback
        // protocols from the moment the connection is created, so there's
        // nothing to re-negotiate.
        //
        // This previously invalidated and rebuilt the connection whenever
        // Lunar/OSD asked for a listener. The helper captures its callback
        // proxy once, when notification watching starts; invalidating that
        // connection left it holding a dead proxy, so banners kept being
        // captured in the helper and silently never arrived in the app.
        if let existing = remoteService {
            notificationDelegate.lunarListener = lunarListener
            hasLunarListener = hasLunarListener || (needsListener && lunarListener != nil)
            return existing
        }

        let conn = NSXPCConnection(serviceName: serviceName)

        // One exported object serves both callback protocols.
        notificationDelegate.lunarListener = lunarListener
        conn.exportedInterface = makeAppDelegateInterface()
        conn.exportedObject = notificationDelegate
        hasLunarListener = needsListener && lunarListener != nil

        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
                self?.hasLunarListener = false
            }
        }
        
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
                self?.hasLunarListener = false
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

    private func makeAppDelegateInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: (any BoringNotchXPCAppDelegate).self)
        interface.setClasses(
            NSSet(array: [BNLunarBrightnessEvent.self]) as! Set<AnyHashable>,
            for: #selector(BoringNotchXPCHelperLunarListener.lunarEventDidUpdate(_:)),
            argumentIndex: 0,
            ofReply: false
        )
        return interface
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

    /// AX trust has no public change notification. Polling the helper every
    /// few seconds costs ~29k XPC round-trips per day for a boolean that
    /// changes maybe twice a year, so instead we check once at start and
    /// then on every app activation — the natural moment a user comes back
    /// from System Settings after toggling the switch. Every AX-needing
    /// call (isAccessibilityAuthorized/ensureAccessibilityAuthorization)
    /// also re-posts changes itself via notifyAuthorizationChange.
    nonisolated func startMonitoringAccessibilityAuthorization() {
        stopMonitoringAccessibilityAuthorization()
        Task { @MainActor [weak self] in
            guard let self else { return }
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { _ = await self?.isAccessibilityAuthorized() }
            }
        }
        // Initial probe so observers get the current state without waiting
        // for the first activation.
        Task { _ = await isAccessibilityAuthorized() }
    }

    nonisolated func stopMonitoringAccessibilityAuthorization() {
        Task { @MainActor [weak self] in
            guard let self, let activationObserver else { return }
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
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

    nonisolated func displayIDForBrightness() async -> CGDirectDisplayID? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.displayIDForBrightness(with: { value in
                    continuation.resume(returning: value)
                })
            }
            guard let num = result else { return nil }
            return CGDirectDisplayID(num.uint32Value)
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
    /// Returns the resulting brightness, or nil on failure.
    nonisolated func adjustScreenBrightness(by value: Float) async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.adjustScreenBrightness(by: value) { result in
                    continuation.resume(returning: result?.floatValue)
                }
            }
        } catch {
            return nil
        }
    }

    // MARK: - Lunar Events

    nonisolated func isLunarAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isLunarAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func startLunarEventStream(listener: BoringNotchXPCHelperLunarListener) async -> Bool {
        await MainActor.run {
            lunarListener = listener
            // Register on the shared exported object too: the connection may
            // already exist (it isn't rebuilt for listeners any more), in
            // which case this is the only path that hooks Lunar events up.
            notificationDelegate.lunarListener = listener
        }
        do {
            let service = await MainActor.run {
                ensureRemoteService(needsListener: true)
            }
            return try await service.withContinuation { service, continuation in
                service.startLunarEventStream { started in
                    continuation.resume(returning: started)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func stopLunarEventStream() async {
        do {
            let service = await MainActor.run {
                ensureRemoteService(needsListener: true)
            }
            try await service.withService { service in
                service.stopLunarEventStream()
            }
        } catch {
            return
        }
    }

    nonisolated func setLunarOSDHidden(_ hide: Bool) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setLunarOSDHidden(hide) { ok in
                    continuation.resume(returning: ok)
                }
            }
        } catch {
            return false
        }
    }
}

// MARK: - Notification Center banners

/// The app's single exported XPC object. Banner pushes are republished as local
/// notifications; Lunar events are forwarded to whichever listener the OSD code
/// registered, since both callbacks share one connection.
final class NotificationXPCDelegate: NSObject, BoringNotchXPCAppDelegate {
    var lunarListener: BoringNotchXPCHelperLunarListener?

    func lunarEventDidUpdate(_ event: BNLunarBrightnessEvent) {
        lunarListener?.lunarEventDidUpdate(event)
    }

    func lunarStreamDidStop(_ reason: String?) {
        lunarListener?.lunarStreamDidStop(reason)
    }

    func notificationDidAppear(_ payload: [String: String]) {
        NSLog("[boringNotch] app received banner: \(payload["appName"] ?? "-") / \(payload["title"] ?? "-")")
        NotificationCenter.default.post(
            name: .systemNotificationDidAppear, object: nil, userInfo: payload
        )
    }

    func notificationDidDisappear(_ token: String) {
        NotificationCenter.default.post(
            name: .systemNotificationDidDisappear, object: nil, userInfo: ["token": token]
        )
    }
}

extension XPCHelperClient {
    nonisolated func startNotificationWatching() async -> Bool {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            return try await service.withContinuation { service, continuation in
                service.startNotificationWatching { started in
                    continuation.resume(returning: started)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func stopNotificationWatching() {
        Task {
            let service = await MainActor.run { ensureRemoteService() }
            try? await service.withService { $0.stopNotificationWatching() }
        }
    }

    nonisolated func replyToNotification(token: String, text: String) async -> Bool {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            return try await service.withContinuation { service, continuation in
                service.replyToNotification(token, text: text) { sent in
                    continuation.resume(returning: sent)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func performNotificationAction(token: String, name: String) async -> Bool {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            return try await service.withContinuation { service, continuation in
                service.performNotificationAction(token, name: name) { done in
                    continuation.resume(returning: done)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func openNotification(token: String) async -> Bool {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            return try await service.withContinuation { service, continuation in
                service.openNotification(token) { opened in
                    continuation.resume(returning: opened)
                }
            }
        } catch {
            return false
        }
    }

    /// Keeps a banner alive so its reply field stays usable, optionally
    /// moving it off-screen so the user never sees it.
    nonisolated func holdNotification(token: String) {
        Task {
            let service = await MainActor.run { ensureRemoteService() }
            try? await service.withService { $0.holdNotification(token) }
        }
    }

    nonisolated func releaseNotification(token: String) {
        Task {
            let service = await MainActor.run { ensureRemoteService() }
            try? await service.withService { $0.releaseNotification(token) }
        }
    }

    nonisolated func sendIMessage(_ text: String, toChatNamed name: String) async -> Bool {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            return try await service.withContinuation { service, continuation in
                service.sendIMessage(text, toChatNamed: name) { sent in
                    continuation.resume(returning: sent)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func dismissNotification(token: String) async -> Bool {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            return try await service.withContinuation { service, continuation in
                service.dismissNotification(token) { dismissed in
                    continuation.resume(returning: dismissed)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func notificationDebugDump() async -> String {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            return try await service.withContinuation { service, continuation in
                service.notificationDebugDump { dump in
                    continuation.resume(returning: dump)
                }
            }
        } catch {
            return "xpc error: \(error)"
        }
    }
}

extension Notification.Name {
    static let systemNotificationDidAppear = Notification.Name("systemNotificationDidAppear")
    static let systemNotificationDidDisappear = Notification.Name("systemNotificationDidDisappear")
}


