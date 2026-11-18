//
//  AgentSocketServer.swift
//  boringNotch
//
//  Écoute un socket Unix ; chaque connexion envoie une ligne JSON (AgentEnvelope).
//  Le hook échoue en silence si l'app est fermée (voir scripts/agent-hook.sh).
//

import Foundation

final class AgentSocketServer {
    // Dans le container sandbox : seul endroit où bind() est autorisé.
    // Le hook (scripts/agent-hook.sh) vise le même chemin.
    static let socketPath = NSHomeDirectory() + "/.bn.sock"

    private var source: DispatchSourceRead?

    func start() {
        unlink(Self.socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Self.socketPath
        guard path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return }
        withUnsafeMutablePointer(to: &addr.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: path.utf8.count + 1) { strcpy($0, path) }
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else { close(fd); return }
        chmod(path, 0o600)

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .utility))
        src.setEventHandler { [weak self] in
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            // Un clic tardif écrit sur un hook déjà parti : sans ça, SIGPIPE tue l'app (send() échoue alors en EPIPE, ignoré).
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            self?.read(client)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func read(_ client: Int32) {
        DispatchQueue.global(qos: .utility).async {
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while case let n = recv(client, &buf, buf.count, 0), n > 0 { data.append(buf, count: n) }
            guard let env = try? JSONDecoder().decode(AgentEnvelope.self, from: data) else { close(client); return }
            // Hook bloquant : on garde la connexion ouverte jusqu'à la décision de l'utilisateur.
            let reply: ((String?) -> Void)? = env.wait == true ? { text in
                if let text { _ = text.withCString { send(client, $0, strlen($0), 0) } }
                close(client)
            } : nil
            if reply == nil { close(client) }
            Task { @MainActor in
                if env.kind == "command" { ActivityEvents.shared.commandFinished(env) }
                else { AgentStore.shared.apply(env, reply: reply) }
            }
        }
    }
}
