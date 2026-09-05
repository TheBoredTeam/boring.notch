import Foundation
import Cocoa
import AsyncXPCConnection

/// Why a helper call failed. Methods still degrade to false/nil for
/// backward compatibility, but never silently: every transport failure —
/// a thrown XPC error or a dropped connection — is recorded in `lastError`
/// (interruption/invalidation record `.unavailable`), and connection loss
/// also flips `helperAvailable` for Settings to surface. A helper that
/// answers, even with false/nil, is a result, not an error, and leaves
/// `lastError` untouched.
enum XPCHelperError: Error {
    /// The XPC service could not be reached (crashed or restarting).
    case unavailable
    /// The helper refused the request (e.g. accessibility not granted).
    case declined
    /// Connection dropped mid-call.
    case transport(underlying: Error)
}

@MainActor
final class XPCHelperClient: NSObject, ObservableObject {
    nonisolated static let shared = XPCHelperClient()

    nonisolated private override init() {
        super.init()
    }

    private let serviceName = "theboringteam.boringnotch.BoringNotchXPCHelper"

    /// Coarse, UI-friendly view of helper connectivity. Flips to false from
    /// the connection's interruption/invalidation handlers so a crashed
    /// helper is visible in Settings instead of features silently degrading;
    /// flips back to true when a live connection is (re)established.
    @MainActor @Published private(set) var helperAvailable = true
    @MainActor private(set) var lastError: XPCHelperError?
    
    private var remoteService: RemoteXPCService<BoringNotchXPCHelperProtocol>?
    private var connection: NSXPCConnection?
    /// Set by the interruption/invalidation hops, cleared when a fresh
    private var lastKnownAuthorization: Bool?
    private let notificationDelegate = NotificationXPCDelegate()
    @MainActor private var activationObserver: (any NSObjectProtocol)?
    private var lunarListener: BoringNotchXPCHelperLunarListener?

    /// Open-notch refcount: one ContentView per screen can hold the notch
    /// open, but the helper only wants the effective state, so
    /// `setNotchOpen` is sent on the 0→1 and 1→0 transitions only.
    @MainActor private var notchOpenCount = 0
    
    // MARK: - Connection Management (Main Actor Isolated)
    
    private func ensureRemoteService() -> RemoteXPCService<BoringNotchXPCHelperProtocol> {
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
            helperAvailable = true
            return existing
        }

        let conn = NSXPCConnection(serviceName: serviceName)

        // One exported object serves both callback protocols.
        notificationDelegate.lunarListener = lunarListener
        conn.exportedInterface = makeAppDelegateInterface()
        conn.exportedObject = notificationDelegate

        conn.interruptionHandler = { [weak self, weak conn] in
            Task { @MainActor in
                // Ignore stale handlers: an interruption from a deallocated
                // connection must not nil a freshly-built one.
                guard let self, let conn, self.connection === conn else { return }
                self.connection = nil
                self.remoteService = nil
                self.helperAvailable = false
                self.lastError = .unavailable
            }
        }

        conn.invalidationHandler = { [weak self, weak conn] in
            Task { @MainActor in
                guard let self, let conn, self.connection === conn else { return }
                self.connection = nil
                self.remoteService = nil
                self.helperAvailable = false
                self.lastError = .unavailable
            }
        }
        
        conn.resume()

        let service = RemoteXPCService<BoringNotchXPCHelperProtocol>(
            connection: conn,
            remoteInterface: BoringNotchXPCHelperProtocol.self
        )
        
        connection = conn
        remoteService = service
        helperAvailable = true
        lastError = nil
        // A helper restart forgets our state — always re-announce the
        // effective notch-open state so its banner keep-alive gate converges
        // to ours, whether we currently count open notches or not.
        Task {
            do {
                try await service.withService { $0.setNotchOpen(notchOpenCount > 0) }
            } catch {
                lastError = .transport(underlying: error)
            }
        }
        return service
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
    func startMonitoringAccessibilityAuthorization() {
        stopMonitoringAccessibilityAuthorization()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { _ = await self?.isAccessibilityAuthorized() }
        }
        // Initial probe so observers get the current state without waiting
        // for the first activation.
        Task { _ = await isAccessibilityAuthorized() }
    }

    func stopMonitoringAccessibilityAuthorization() {
        guard let activationObserver else { return }
        NotificationCenter.default.removeObserver(activationObserver)
        self.activationObserver = nil
    }
    
    // MARK: - Accessibility
    
    // Fire-and-forget: callers invoke this from non-isolated contexts, and the work
    // itself hops onto the main actor.
    nonisolated func requestAccessibilityAuthorization() {
        Task { @MainActor in
            let service = ensureRemoteService()
            do {
                try await service.withService { service in
                    service.requestAccessibilityAuthorization()
                }
            } catch {
                lastError = .transport(underlying: error)
            }
        }
    }
    
    func isAccessibilityAuthorized() async -> Bool {
        do {
            let service = ensureRemoteService()
            let result: Bool = try await service.withContinuation { service, continuation in
                service.isAccessibilityAuthorized { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            notifyAuthorizationChange(result)
            return result
        } catch {
            lastError = .transport(underlying: error)
            return false
        }
    }
    
    func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        do {
            let service = ensureRemoteService()
            let result: Bool = try await service.withContinuation { service, continuation in
                service.ensureAccessibilityAuthorization(promptIfNeeded) { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            notifyAuthorizationChange(result)
            return result
        } catch {
            lastError = .transport(underlying: error)
            return false
        }
    }
    
    // MARK: - Keyboard Brightness
    
    func currentKeyboardBrightness() async -> Float? {
        do {
            let service = ensureRemoteService()
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentKeyboardBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            lastError = .transport(underlying: error)
            return nil
        }
    }
    
    func setKeyboardBrightness(_ value: Float) async -> Bool {
        do {
            let service = ensureRemoteService()
            return try await service.withContinuation { service, continuation in
                service.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            lastError = .transport(underlying: error)
            return false
        }
    }
    
    // MARK: - Screen Brightness
    
    func currentScreenBrightness() async -> Float? {
        do {
            let service = ensureRemoteService()
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentScreenBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            lastError = .transport(underlying: error)
            return nil
        }
    }

    func displayIDForBrightness() async -> CGDirectDisplayID? {
        do {
            let service = ensureRemoteService()
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.displayIDForBrightness(with: { value in
                    continuation.resume(returning: value)
                })
            }
            guard let num = result else { return nil }
            return CGDirectDisplayID(num.uint32Value)
        } catch {
            lastError = .transport(underlying: error)
            return nil
        }
    }
    
    func setScreenBrightness(_ value: Float) async -> Bool {
        do {
            let service = ensureRemoteService()
            return try await service.withContinuation { service, continuation in
                service.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            lastError = .transport(underlying: error)
            return false
        }
    }
    /// Returns the resulting brightness, or nil on failure.
    func adjustScreenBrightness(by value: Float) async -> Float? {
        do {
            let service = ensureRemoteService()
            return try await service.withContinuation { service, continuation in
                service.adjustScreenBrightness(by: value) { result in
                    continuation.resume(returning: result?.floatValue)
                }
            }
        } catch {
            lastError = .transport(underlying: error)
            return nil
        }
    }

    // MARK: - Lunar Events

    func isLunarAvailable() async -> Bool {
        do {
            let service = ensureRemoteService()
            return try await service.withContinuation { service, continuation in
                service.isLunarAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            lastError = .transport(underlying: error)
            return false
        }
    }

    func startLunarEventStream(listener: BoringNotchXPCHelperLunarListener) async -> Bool {
        lunarListener = listener
        // Register on the shared exported object too: the connection may
        // already exist (it isn't rebuilt for listeners any more), in
        // which case this is the only path that hooks Lunar events up.
        notificationDelegate.lunarListener = listener
        do {
            let service = ensureRemoteService()
            return try await service.withContinuation { service, continuation in
                service.startLunarEventStream { started in
                    continuation.resume(returning: started)
                }
            }
        } catch {
            lastError = .transport(underlying: error)
            return false
        }
    }

    func stopLunarEventStream() async {
        do {
            let service = ensureRemoteService()
            try await service.withService { service in
                service.stopLunarEventStream()
            }
        } catch {
            lastError = .transport(underlying: error)
            return
        }
    }

    func setLunarOSDHidden(_ hide: Bool) async -> Bool {
        do {
            let service = ensureRemoteService()
            return try await service.withContinuation { service, continuation in
                service.setLunarOSDHidden(hide) { ok in
                    continuation.resume(returning: ok)
                }
            }
        } catch {
            lastError = .transport(underlying: error)
            return false
        }
    }
}

// MARK: - Notification Center banners

/// The app's single exported XPC object. Banner pushes are republished as local
/// notifications; Lunar events are forwarded to whichever listener the OSD code
/// registered, since both callbacks share one connection.
final class NotificationXPCDelegate: NSObject, BoringNotchXPCAppDelegate {
    /// Written on the MainActor (connection setup, `startLunarEventStream`),
    /// read on the XPC connection's private delivery queue. The lock
    /// synchronizes cross-thread publication; the listener itself is still
    /// invoked on the delivery queue — no per-event actor hop on this hot
    /// path.
    private let lunarListenerLock = NSLock()
    private var _lunarListener: BoringNotchXPCHelperLunarListener?

    var lunarListener: BoringNotchXPCHelperLunarListener? {
        get {
            lunarListenerLock.lock()
            defer { lunarListenerLock.unlock() }
            return _lunarListener
        }
        set {
            lunarListenerLock.lock()
            _lunarListener = newValue
            lunarListenerLock.unlock()
        }
    }

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
            await MainActor.run { self.lastError = .transport(underlying: error) }
            return false
        }
    }

    nonisolated func stopNotificationWatching() {
        Task {
            let service = await MainActor.run { ensureRemoteService() }
            do {
                try await service.withService { $0.stopNotificationWatching() }
            } catch {
                await MainActor.run { self.lastError = .transport(underlying: error) }
            }
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
            await MainActor.run { self.lastError = .transport(underlying: error) }
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
            await MainActor.run { self.lastError = .transport(underlying: error) }
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
            await MainActor.run { self.lastError = .transport(underlying: error) }
            return false
        }
    }

    /// Keeps a banner alive so its reply field stays usable, optionally
    /// moving it off-screen so the user never sees it.
    nonisolated func holdNotification(token: String) {
        Task {
            let service = await MainActor.run { ensureRemoteService() }
            do {
                try await service.withService { $0.holdNotification(token) }
            } catch {
                await MainActor.run { self.lastError = .transport(underlying: error) }
            }
        }
    }

    nonisolated func releaseNotification(token: String) {
        Task {
            let service = await MainActor.run { ensureRemoteService() }
            do {
                try await service.withService { $0.releaseNotification(token) }
            } catch {
                await MainActor.run { self.lastError = .transport(underlying: error) }
            }
        }
    }

    /// Feeds the helper the notch's effective open state so it can gate its
    /// focus-stealing banner keep-alive expand to open-notch-only.
    /// Refcounted across screens: only 0→1 sends true, only 1→0 sends false.
    nonisolated func notchOpened() {
        Task { @MainActor in
            notchOpenCount += 1
            if notchOpenCount == 1 { sendNotchOpen(true) }
        }
    }

    nonisolated func notchClosed() {
        Task { @MainActor in
            guard notchOpenCount > 0 else {
                NSLog("[boringNotch] XPCHelperClient: unmatched notchClosed ignored")
                return
            }
            notchOpenCount -= 1
            if notchOpenCount == 0 { sendNotchOpen(false) }
        }
    }

    @MainActor private func sendNotchOpen(_ open: Bool) {
        let service = ensureRemoteService()
        Task {
            do {
                try await service.withService { $0.setNotchOpen(open) }
            } catch {
                lastError = .transport(underlying: error)
            }
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
            await MainActor.run { self.lastError = .transport(underlying: error) }
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
            await MainActor.run { self.lastError = .transport(underlying: error) }
            return "xpc error: \(error)"
        }
    }
}

extension Notification.Name {
    static let systemNotificationDidAppear = Notification.Name("systemNotificationDidAppear")
    static let systemNotificationDidDisappear = Notification.Name("systemNotificationDidDisappear")
}


