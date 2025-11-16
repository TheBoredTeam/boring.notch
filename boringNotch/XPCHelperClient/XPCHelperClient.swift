import Foundation
import Cocoa

final class XPCHelperClient {
    static let shared = XPCHelperClient()

    private var connection: NSXPCConnection?
    private let helperServiceName = "theboringteam.boringnotch.BoringNotchXPCHelper"
    private var lastKnownAuthorization: Bool?
    private var isConnecting = false
    private let connectionQueue = DispatchQueue(label: "com.boringnotch.xpc.connection")
    
    private var helperBundleURL: URL? {
        let bundleURL = Bundle.main.bundleURL
        return bundleURL.appendingPathComponent("Contents/XPCServices/BoringNotchXPCHelper.xpc")
    }
    
    private var helperIsPresent: Bool {
        guard let url = helperBundleURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    var serviceName: String { helperServiceName }
    
    private init() {}
    
    // MARK: - Helper Availability
    
    /// Validate that the helper binary is bundled with the app
    func register() throws {
        guard helperIsPresent else {
            throw NSError(
                domain: "BoringNotchXPCHelper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Helper not found in bundle"]
            )
        }
    }
    
    /// Included for API compatibility; removing the helper requires a rebuild
    func unregister() throws {
        // No-op
    }
    
    /// Check if the helper XPC service exists inside the bundle
    var isRegistered: Bool { helperIsPresent }

    // MARK: - XPC Connection Management

    func connect() {
        connectionQueue.sync {
            guard connection == nil, !isConnecting else {
                return
            }
            isConnecting = true
            
            // Connect to the bundled XPC service
            let conn = NSXPCConnection(serviceName: helperServiceName)
            conn.remoteObjectInterface = NSXPCInterface(with: (any BoringNotchXPCHelperProtocol).self)

            conn.interruptionHandler = { [weak self] in
                guard let self = self else { return }
                self.connectionQueue.async {
                    self.connection?.invalidate()
                    self.connection = nil
                    self.isConnecting = false
                }
            }

            conn.invalidationHandler = { [weak self] in
                guard let self = self else { return }
                self.connectionQueue.async {
                    self.connection = nil
                    self.isConnecting = false
                }
            }

            conn.resume()
            connection = conn
            isConnecting = false
        }
    }

    func disconnect() {
        connectionQueue.sync {
            connection?.invalidate()
            connection = nil
            isConnecting = false
        }
    }

    private func proxy() -> BoringNotchXPCHelperProtocol? {
        if connection == nil {
            connect()
        }
        
        let proxy = connection?.remoteObjectProxy as? BoringNotchXPCHelperProtocol
        
        return proxy
    }

    private func notifyAuthorizationChangeIfNeeded(_ granted: Bool) {
        connectionQueue.async { [weak self] in
            guard let self else { return }
            guard self.lastKnownAuthorization != granted else { return }
            self.lastKnownAuthorization = granted
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .accessibilityAuthorizationChanged,
                    object: nil,
                    userInfo: ["granted": granted]
                )
            }
        }
    }

    // MARK: - Accessibility Methods

    func requestAccessibilityAuthorization() {
        proxy()?.requestAccessibilityAuthorization()
    }

    func isAccessibilityAuthorized() async -> Bool {
        await withCheckedContinuation { continuation in
            guard let conn = connection ?? { connect(); return connection }() else {
                continuation.resume(returning: false)
                return
            }

            let remote = conn.remoteObjectProxyWithErrorHandler { _ in
                continuation.resume(returning: false)
            } as? BoringNotchXPCHelperProtocol
            
            remote?.isAccessibilityAuthorized { [weak self] granted in
                self?.notifyAuthorizationChangeIfNeeded(granted)
                continuation.resume(returning: granted)
            }
        }
    }

    func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let conn = connection ?? { connect(); return connection }() else {
                continuation.resume(returning: false)
                return
            }

            let remote = conn.remoteObjectProxyWithErrorHandler { _ in
                continuation.resume(returning: false)
            } as? BoringNotchXPCHelperProtocol
            
            remote?.ensureAccessibilityAuthorization(promptIfNeeded) { [weak self] granted in
                self?.notifyAuthorizationChangeIfNeeded(granted)
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Keyboard backlight access via helper

    func isKeyboardBrightnessAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            guard let conn = connection ?? { connect(); return connection }() else {
                continuation.resume(returning: false)
                return
            }

            let remote = conn.remoteObjectProxyWithErrorHandler { _ in
                continuation.resume(returning: false)
            } as? BoringNotchXPCHelperProtocol

            remote?.isKeyboardBrightnessAvailable { available in
                continuation.resume(returning: available)
            }
        }
    }

    func currentKeyboardBrightness() async -> Float? {
        await withCheckedContinuation { continuation in
            guard let conn = connection ?? { connect(); return connection }() else {
                continuation.resume(returning: nil)
                return
            }

            let remote = conn.remoteObjectProxyWithErrorHandler { _ in
                continuation.resume(returning: nil)
            } as? BoringNotchXPCHelperProtocol

            remote?.currentKeyboardBrightness { number in
                if let n = number { continuation.resume(returning: Float(truncating: n)) }
                else { continuation.resume(returning: nil) }
            }
        }
    }

    func setKeyboardBrightness(_ value: Float) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let conn = connection ?? { connect(); return connection }() else {
                continuation.resume(returning: false)
                return
            }

            let remote = conn.remoteObjectProxyWithErrorHandler { _ in
                continuation.resume(returning: false)
            } as? BoringNotchXPCHelperProtocol

            remote?.setKeyboardBrightness(value) { ok in
                continuation.resume(returning: ok)
            }
        }
    }

    // MARK: - Screen brightness access via helper

    func isScreenBrightnessAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            guard let conn = connection ?? { connect(); return connection }() else {
                continuation.resume(returning: false)
                return
            }

            let remote = conn.remoteObjectProxyWithErrorHandler { _ in
                continuation.resume(returning: false)
            } as? BoringNotchXPCHelperProtocol

            remote?.isScreenBrightnessAvailable { available in
                continuation.resume(returning: available)
            }
        }
    }

    func currentScreenBrightness() async -> Float? {
        await withCheckedContinuation { continuation in
            guard let conn = connection ?? { connect(); return connection }() else {
                continuation.resume(returning: nil)
                return
            }

            let remote = conn.remoteObjectProxyWithErrorHandler { _ in
                continuation.resume(returning: nil)
            } as? BoringNotchXPCHelperProtocol

            remote?.currentScreenBrightness { number in
                if let n = number { continuation.resume(returning: Float(truncating: n)) }
                else { continuation.resume(returning: nil) }
            }
        }
    }

    func setScreenBrightness(_ value: Float) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let conn = connection ?? { connect(); return connection }() else {
                continuation.resume(returning: false)
                return
            }

            let remote = conn.remoteObjectProxyWithErrorHandler { _ in
                continuation.resume(returning: false)
            } as? BoringNotchXPCHelperProtocol

            remote?.setScreenBrightness(value) { ok in
                continuation.resume(returning: ok)
            }
        }
    }
}
