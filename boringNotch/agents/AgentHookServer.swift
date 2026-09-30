//
//  AgentHookServer.swift
//  boringCode
//
//  Servidor HTTP mínimo num Unix socket local. O script de hook do Claude Code
//  (ver AgentHookScript) faz `curl --unix-socket` para cá. Pedidos de permissão
//  ficam com a conexão aberta até o usuário aprovar/recusar no notch — mesma
//  ideia da ponte por socket do Open Island
//  (github.com/Octane0411/open-vibe-island), GPL-3.0.
//

import Foundation
import os

final class AgentHookConnection: @unchecked Sendable {  // estado só é tocado na fila serial do servidor
    struct Request {
        let event: String
        let headers: [String: String]
        let body: Data
    }

    fileprivate let fd: Int32
    private let queue: DispatchQueue
    private var readSource: DispatchSourceRead?
    private var buffer = Data()
    private var parsedRequest = false
    private var finished = false

    fileprivate var onRequest: ((Request) -> Void)?
    /// Uso interno do servidor: conexão encerrada (respondida ou abandonada).
    fileprivate var onFinished: (() -> Void)?
    /// Chamado se o cliente desconectar antes da resposta (ex.: usuário respondeu no terminal).
    /// Roda na fila do servidor.
    var onClientGone: (() -> Void)?

    fileprivate init(fd: Int32, queue: DispatchQueue) {
        self.fd = fd
        self.queue = queue
    }

    fileprivate func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { [fd] in close(fd) }
        readSource = source
        source.resume()
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        let count = read(fd, &chunk, chunk.count)
        guard count > 0 else {
            // EOF/erro: se ainda devíamos uma resposta, o cliente desistiu.
            let gone = !finished
            finish()
            if gone, parsedRequest { onClientGone?() }
            return
        }
        guard !parsedRequest else { return }
        buffer.append(contentsOf: chunk[0..<count])
        if buffer.count > 4 * 1024 * 1024 { finish(); return }
        parseIfComplete()
    }

    private func parseIfComplete() {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return }
        guard let head = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) else {
            finish(); return
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { finish(); return }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        if buffer.count - bodyStart < length {
            if headers["expect"]?.lowercased() == "100-continue" {
                headers["expect"] = nil
                writeAll(Data("HTTP/1.1 100 Continue\r\n\r\n".utf8))
            }
            return
        }

        parsedRequest = true
        let path = String(requestLine[1])
        let event = path.split(separator: "/").last.map(String.init) ?? ""
        let body = buffer[bodyStart..<(bodyStart + length)]
        buffer = Data()
        onRequest?(Request(event: event, headers: headers, body: Data(body)))
    }

    /// Responde e fecha. `body == nil` → 204 (hook não imprime nada, Claude segue normal).
    func respond(_ body: Data?) {
        queue.async { [self] in
            guard !finished else { return }
            var response: String
            if let body, !body.isEmpty {
                response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                response += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                writeAll(Data(response.utf8) + body)
            } else {
                response = "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"
                writeAll(Data(response.utf8))
            }
            finish()
        }
    }

    private func writeAll(_ data: Data) {
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = write(fd, pointer, remaining)
                if written <= 0 { return }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        readSource?.cancel()
        readSource = nil
        onFinished?()
        onFinished = nil
    }
}

final class AgentHookServer: @unchecked Sendable {
    static let socketURL: URL = AgentPaths.supportDirectory.appendingPathComponent("agents.sock")

    private let socketURL: URL
    private let queue = DispatchQueue(label: "boringcode.agents.hook-server")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [ObjectIdentifier: AgentHookConnection] = [:]
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "boringcode", category: "AgentHookServer")

    /// Chamado na fila do servidor. Quem trata deve chamar `connection.respond` exatamente uma vez.
    var onRequest: ((AgentHookConnection.Request, AgentHookConnection) -> Void)?

    var isRunning: Bool { listenFD >= 0 }

    init(socketURL: URL = AgentHookServer.socketURL) {
        self.socketURL = socketURL
    }

    func start() {
        queue.sync { startLocked() }
    }

    func stop() {
        queue.sync {
            acceptSource?.cancel()
            acceptSource = nil
            listenFD = -1
            connections.values.forEach { $0.respond(nil) }
            connections.removeAll()
            unlink(socketURL.path)
        }
    }

    private func startLocked() {
        guard listenFD < 0 else { return }
        let path = socketURL.path
        try? FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { log.error("socket() falhou: \(errno)"); return }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else {
            log.error("caminho do socket longo demais: \(path)")
            close(fd); return
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
            raw[pathBytes.count] = 0
        }

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            log.error("bind/listen falhou: \(errno)")
            close(fd); return
        }
        // Só o próprio usuário conversa com o socket.
        chmod(path, 0o600)

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClient() }
        source.setCancelHandler { close(fd) }
        acceptSource = source
        source.resume()
        log.info("escutando em \(path)")
    }

    private func acceptClient() {
        let clientFD = accept(listenFD, nil, nil)
        guard clientFD >= 0 else { return }
        var noSigPipe: Int32 = 1
        setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        let connection = AgentHookConnection(fd: clientFD, queue: queue)
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.onFinished = { [weak self] in self?.connections[key] = nil }
        connection.onRequest = { [weak self, weak connection] request in
            guard let self, let connection else { return }
            if let onRequest = self.onRequest {
                onRequest(request, connection)
            } else {
                connection.respond(nil)
            }
        }
        connection.start()
    }
}

enum AgentPaths {
    /// `~/Library/Application Support/boringCode` (app não-sandboxed).
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("boringCode", isDirectory: true)
    }()

    static let hookScriptURL = supportDirectory.appendingPathComponent("bin/boringcode-hook")
}
