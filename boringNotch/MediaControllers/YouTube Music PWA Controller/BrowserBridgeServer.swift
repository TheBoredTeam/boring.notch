//
//  BrowserBridgeServer.swift
//  boringNotch
//
//  Loopback WebSocket server that the Boring Notch browser extension connects to.
//
//  A browser extension cannot listen on a socket, so the app is the server and the
//  extension is the client. `com.apple.security.network.server` is already in the app's
//  entitlements, so this needs no signing changes.
//
//  Authorisation is by `Origin`, not by a shared secret. The browser sets that header
//  itself and page script cannot override it, so a website probing the loopback port is
//  rejected at the handshake while the extension connects with nothing to configure.
//  See BrowserBridgeWebSocket.swift for why we speak RFC 6455 ourselves rather than
//  using NWProtocolWebSocket.
//

import Foundation
import Network
import os

actor BrowserBridgeServer {
    /// Per-connection state. Held by reference so a stale read loop can tell by identity
    /// whether it has been superseded.
    private final class Client: @unchecked Sendable {
        let connection: NWConnection
        /// Bytes received but not yet consumed — TCP is a stream, so a frame may be split
        /// across reads and several frames may share one read.
        var buffer = Data()
        var didUpgrade = false
        var suppressDisconnectCallback = false
        var extensionIdentifier: String?
        /// Accumulates payloads across a fragmented message.
        var fragmentOpcode: BrowserBridgeOpcode?
        var fragmentPayload = Data()

        init(connection: NWConnection) {
            self.connection = connection
        }
    }

    private let configuration: BrowserBridgeConfiguration
    private var listener: NWListener?
    private var client: Client?
    /// Connections that have not completed the handshake yet. Kept apart so an
    /// unauthorised peer cannot displace a working extension.
    private var pending: [Client] = []
    private static let maxPendingConnections = 8

    private let queue = DispatchQueue(label: "boringnotch.browserbridge", qos: .userInitiated)
    private static let logger = Logger(subsystem: "theboringteam.boringnotch", category: "BrowserBridge")

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// Read synchronously and off-actor by `isActive()`, which the media controller
    /// protocol requires to be non-async.
    private let liveness = BrowserBridgeLiveness()

    private var onState: (@Sendable (BrowserBridgeTrackState) -> Void)?
    private var onConnectionChange: (@Sendable (Bool) -> Void)?

    init(configuration: BrowserBridgeConfiguration = .default) {
        self.configuration = configuration
    }

    nonisolated var livenessProbe: BrowserBridgeLiveness { liveness }

    /// Identifier of the connected extension, for display in Settings.
    var connectedExtensionIdentifier: String? { client?.extensionIdentifier }

    func setHandlers(
        onState: @escaping @Sendable (BrowserBridgeTrackState) -> Void,
        onConnectionChange: @escaping @Sendable (Bool) -> Void
    ) {
        self.onState = onState
        self.onConnectionChange = onConnectionChange
    }

    // MARK: - Lifecycle

    func start() throws {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Binding the local endpoint to loopback keeps the listener off every other
        // interface, so nothing on the network can reach it.
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: configuration.port) ?? .any
        )

        let newListener: NWListener
        do {
            newListener = try NWListener(using: parameters)
        } catch {
            throw BrowserBridgeError.listenerFailed(error.localizedDescription)
        }

        newListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Self.logger.info("Browser bridge listening on 127.0.0.1")
            case .failed(let error):
                Self.logger.error("Browser bridge listener failed: \(error.localizedDescription)")
                Task { await self?.handleListenerFailure() }
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }

        listener = newListener
        newListener.start(queue: queue)
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        if let current = client { close(current) }
        for connection in pending { close(connection) }
        pending.removeAll()
        liveness.clear()
    }

    private func handleListenerFailure() {
        listener?.cancel()
        listener = nil
        liveness.clear()
        onConnectionChange?(false)
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let incoming = Client(connection: connection)

        if pending.count >= Self.maxPendingConnections, let oldest = pending.first {
            close(oldest)
        }
        pending.append(incoming)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { await self?.receive(on: incoming) }
            case .failed, .cancelled:
                Task { await self?.handleDisconnect(of: incoming) }
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func close(_ target: Client) {
        target.suppressDisconnectCallback = true
        target.connection.stateUpdateHandler = nil
        target.connection.cancel()
        pending.removeAll { $0 === target }
        if client === target { client = nil }
    }

    /// Promotes a connection to the active client once its handshake is accepted.
    private func promote(_ target: Client) {
        pending.removeAll { $0 === target }
        if let previous = client, previous !== target {
            close(previous)
        }
        target.didUpgrade = true
        client = target
        liveness.markAlive()
    }

    private func handleDisconnect(of target: Client) {
        pending.removeAll { $0 === target }
        guard client === target else { return }
        client = nil
        liveness.clear()
        if !target.suppressDisconnectCallback {
            onConnectionChange?(false)
        }
    }

    private func isKnown(_ target: Client) -> Bool {
        client === target || pending.contains { $0 === target }
    }

    private func receive(on target: Client) {
        guard isKnown(target) else { return }

        target.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                Self.logger.debug("Browser bridge receive error: \(error.localizedDescription)")
                Task { await self.handleDisconnect(of: target) }
                return
            }

            if let data, !data.isEmpty {
                Task { await self.ingest(data, on: target) }
            }

            if isComplete {
                Task { await self.handleDisconnect(of: target) }
                return
            }

            Task { await self.receive(on: target) }
        }
    }

    // MARK: - Protocol

    private func ingest(_ data: Data, on target: Client) {
        guard isKnown(target) else { return }
        target.buffer.append(data)

        if !target.didUpgrade {
            guard performHandshake(on: target) else { return }
        }

        drainFrames(on: target)
    }

    /// Returns true once the connection has been upgraded and frame parsing may begin.
    private func performHandshake(on target: Client) -> Bool {
        do {
            guard let (request, consumed) = try BrowserBridgeHandshake.parse(target.buffer) else {
                return false // header block not fully received yet
            }

            guard BrowserBridgeHandshake.isAllowedOrigin(request.origin) else {
                Self.logger.error(
                    "Browser bridge rejected a connection from origin: \(request.origin ?? "none", privacy: .public)"
                )
                send(
                    BrowserBridgeHandshake.rejectResponse(
                        status: "403 Forbidden",
                        message: "Only browser extensions may connect to the Boring Notch bridge."
                    ),
                    on: target,
                    thenClose: true
                )
                return false
            }

            target.buffer.removeSubrange(target.buffer.startIndex..<target.buffer.index(target.buffer.startIndex, offsetBy: consumed))
            target.extensionIdentifier = request.originIdentifier

            send(BrowserBridgeHandshake.acceptResponse(for: request.key), on: target)
            promote(target)

            Self.logger.info(
                "Browser bridge accepted extension \(request.originIdentifier ?? "unknown", privacy: .public)"
            )
            sendMessage(.welcome(), on: target)
            onConnectionChange?(true)
            return true
        } catch {
            Self.logger.debug("Browser bridge handshake failed: \(String(describing: error))")
            send(
                BrowserBridgeHandshake.rejectResponse(status: "400 Bad Request", message: "Bad handshake."),
                on: target,
                thenClose: true
            )
            return false
        }
    }

    private func drainFrames(on target: Client) {
        while true {
            guard isKnown(target) else { return }

            let decoded: (frame: BrowserBridgeFrame, consumed: Int)?
            do {
                decoded = try BrowserBridgeFraming.decode(target.buffer)
            } catch {
                Self.logger.debug("Browser bridge framing error: \(String(describing: error))")
                close(target)
                return
            }

            guard let (frame, consumed) = decoded else { return } // wait for more bytes
            target.buffer.removeSubrange(target.buffer.startIndex..<target.buffer.index(target.buffer.startIndex, offsetBy: consumed))

            handle(frame, on: target)
        }
    }

    private func handle(_ frame: BrowserBridgeFrame, on target: Client) {
        switch frame.opcode {
        case .ping:
            sendRaw(BrowserBridgeFraming.encode(opcode: .pong, payload: frame.payload), on: target)
            liveness.markAlive()

        case .pong:
            liveness.markAlive()

        case .close:
            let wasClient = client === target
            sendRaw(BrowserBridgeFraming.closeFrame(), on: target)
            close(target)
            if wasClient {
                liveness.clear()
                onConnectionChange?(false)
            }

        case .text, .binary:
            if frame.isFinal {
                handlePayload(frame.payload, on: target)
            } else {
                target.fragmentOpcode = frame.opcode
                target.fragmentPayload = frame.payload
            }

        case .continuation:
            guard target.fragmentOpcode != nil else { return }
            target.fragmentPayload.append(frame.payload)
            if frame.isFinal {
                let payload = target.fragmentPayload
                target.fragmentOpcode = nil
                target.fragmentPayload = Data()
                handlePayload(payload, on: target)
            }
        }
    }

    private func handlePayload(_ payload: Data, on target: Client) {
        guard client === target else { return }
        guard let message = try? decoder.decode(BrowserBridgeInboundMessage.self, from: payload) else {
            Self.logger.debug("Browser bridge received an undecodable message")
            return
        }

        switch message.type {
        case .hello:
            // The handshake already authorised this connection; hello is now just an
            // announcement, retained so the extension can report its version.
            liveness.markAlive()
            sendMessage(.welcome(), on: target)

        case .ping:
            liveness.markAlive()
            sendMessage(.pong(), on: target)

        case .state:
            guard let state = message.state else { return }
            liveness.markAlive()
            onState?(state)

        case .bye:
            close(target)
            liveness.clear()
            onConnectionChange?(false)
        }
    }

    // MARK: - Sending

    func send(_ command: BrowserBridgeCommand, value: Double? = nil) {
        guard let client, client.didUpgrade else { return }
        sendMessage(.command(command, value: value), on: client)
    }

    private func sendMessage(_ message: BrowserBridgeOutboundMessage, on target: Client) {
        guard let data = try? encoder.encode(message) else {
            Self.logger.error("Browser bridge failed to encode \(message.type)")
            return
        }
        sendRaw(BrowserBridgeFraming.encode(opcode: .text, payload: data), on: target)
    }

    private func sendRaw(_ data: Data, on target: Client) {
        send(data, on: target, thenClose: false)
    }

    private func send(_ data: Data, on target: Client, thenClose: Bool = false) {
        target.connection.send(
            content: data,
            completion: .contentProcessed { [weak self] error in
                if let error {
                    Self.logger.debug("Browser bridge send failed: \(error.localizedDescription)")
                }
                if thenClose {
                    Task { await self?.close(target) }
                }
            }
        )
    }
}

/// Thread-safe last-seen timestamp.
///
/// `MediaControllerProtocol.isActive()` is synchronous and non-isolated, so it cannot
/// await the server actor. This gives it something cheap and safe to read instead.
final class BrowserBridgeLiveness: @unchecked Sendable {
    private let lock = NSLock()
    private var lastSeen: Date?
    private let timeout: TimeInterval

    init(timeout: TimeInterval = BrowserBridgeConfiguration.default.clientTimeout) {
        self.timeout = timeout
    }

    func markAlive() {
        lock.lock()
        lastSeen = Date()
        lock.unlock()
    }

    func clear() {
        lock.lock()
        lastSeen = nil
        lock.unlock()
    }

    var isAlive: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let lastSeen else { return false }
        return Date().timeIntervalSince(lastSeen) < timeout
    }
}
