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

struct BrightnessHardwareResult: Equatable {
    let displayID: CGDirectDisplayID
    let brightness: Float
}

@MainActor
protocol BrightnessHardwareControlling: AnyObject {
    func displayIDForBrightness() async -> CGDirectDisplayID?
    func currentScreenBrightness(displayID: CGDirectDisplayID) async -> BrightnessHardwareResult?
    func setScreenBrightness(
        _ value: Float, displayID: CGDirectDisplayID) async -> BrightnessHardwareResult?
    func adjustScreenBrightness(
        by value: Float, displayID: CGDirectDisplayID) async -> BrightnessHardwareResult?
}

@MainActor
final class XPCHelperClient: NSObject, ObservableObject, BrightnessHardwareControlling {
    nonisolated static let shared = XPCHelperClient()

    override nonisolated private init() {
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

    /// AX trust has no public change notification. Check once at startup and
    /// whenever the app becomes active after a permission change in System
    /// Settings. Every AX-needing call also publishes changes.
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
    func currentScreenBrightness(displayID: CGDirectDisplayID) async -> BrightnessHardwareResult? {
        do {
            let service = ensureRemoteService()
            let result: (NSNumber?, NSNumber?) = try await service.withContinuation { service, continuation in
                service.currentScreenBrightness(forDisplayID: NSNumber(value: displayID)) { id, value in
                    continuation.resume(returning: (id, value))
                }
            }
            guard let id = result.0, let value = result.1 else { return nil }
            return BrightnessHardwareResult(
                displayID: CGDirectDisplayID(id.uint32Value), brightness: value.floatValue)
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
    func setScreenBrightness(
        _ value: Float, displayID: CGDirectDisplayID
    ) async -> BrightnessHardwareResult? {
        do {
            let service = ensureRemoteService()
            let result: (NSNumber?, NSNumber?) = try await service.withContinuation { service, continuation in
                service.setScreenBrightness(value, forDisplayID: NSNumber(value: displayID)) { id, value in
                    continuation.resume(returning: (id, value))
                }
            }
            guard let id = result.0, let value = result.1 else { return nil }
            return BrightnessHardwareResult(
                displayID: CGDirectDisplayID(id.uint32Value), brightness: value.floatValue)
        } catch {
            lastError = .transport(underlying: error)
            return nil
        }
    }

    func adjustScreenBrightness(
        by value: Float, displayID: CGDirectDisplayID
    ) async -> BrightnessHardwareResult? {
        do {
            let service = ensureRemoteService()
            let result: (NSNumber?, NSNumber?) = try await service.withContinuation { service, continuation in
                service.adjustScreenBrightness(by: value, forDisplayID: NSNumber(value: displayID)) { id, value in
                    continuation.resume(returning: (id, value))
                }
            }
            guard let id = result.0, let value = result.1 else { return nil }
            return BrightnessHardwareResult(
                displayID: CGDirectDisplayID(id.uint32Value), brightness: value.floatValue)
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
        NotificationCenter.default.post(
            name: .systemNotificationDidAppear, object: nil, userInfo: payload
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

    nonisolated func setNotificationFilter(bundleIDs: Set<String>, allApps: Bool) {
        Task {
            let service = await MainActor.run { ensureRemoteService() }
            do {
                try await service.withService {
                    $0.setNotificationFilter(Array(bundleIDs), allApps: allApps)
                }
            } catch {
                await MainActor.run { self.lastError = .transport(underlying: error) }
            }
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
}

extension Notification.Name {
    static let systemNotificationDidAppear = Notification.Name("systemNotificationDidAppear")
}

