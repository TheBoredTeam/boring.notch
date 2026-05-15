import Foundation
import Network

@MainActor
final class KairoWebSocketServer {
    static let shared = KairoWebSocketServer()

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let port: UInt16 = 8765

    func start() {
        do {
            let params = NWParameters(tls: nil)
            let ws = NWProtocolWebSocket.Options()
            ws.autoReplyPing = true
            params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            listener?.start(queue: .main)
            print("[Kairo] WebSocket server listening on port \(port)")
        } catch {
            print("[Kairo] WebSocket server failed: \(error)")
        }
    }

    private func accept(_ conn: NWConnection) {
        connections.append(conn)
        conn.stateUpdateHandler = { state in
            if case .ready = state { print("[Kairo] Extension connected") }
        }
        conn.start(queue: .main)
        receive(on: conn)
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            if let data, !data.isEmpty {
                if let msg = String(data: data, encoding: .utf8) {
                    print("[Kairo] Received from extension: \(msg)")
                }
            }
            if error == nil {
                Task { @MainActor in self?.receive(on: conn) }
            }
        }
    }

    func send(_ payload: [String: Any]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])

        for conn in connections where conn.state == .ready {
            conn.send(content: data, contentContext: context, isComplete: true,
                     completion: .contentProcessed { _ in })
        }
    }

    func stop() {
        connections.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
    }
}
