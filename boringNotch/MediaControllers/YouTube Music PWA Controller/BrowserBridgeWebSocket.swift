//
//  BrowserBridgeWebSocket.swift
//  boringNotch
//
//  A minimal RFC 6455 server: handshake parsing plus frame coding.
//
//  Why not `NWProtocolWebSocket`, which would give this for free? Because its
//  server-side metadata exposes only the opcode, response and close code — it provides
//  no way to read the client's handshake headers. We need the `Origin` header: it is set
//  by the browser and cannot be forged by page JavaScript, so it is what lets us accept
//  the extension and reject any web page that probes the loopback port. That check is
//  what removes the need for a user-entered pairing secret.
//
//  Scope is deliberately small: text frames, close, ping/pong, and continuation. No
//  extensions, no compression.
//

import CryptoKit
import Foundation

// MARK: - Handshake

enum BrowserBridgeHandshake {
    /// Appended to the client key before hashing. Fixed by RFC 6455 §1.3.
    private static let magicGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    struct Request {
        let key: String
        let origin: String?
        /// The extension's own identifier, parsed out of `chrome-extension://<id>`.
        var originIdentifier: String? {
            guard let origin, let range = origin.range(of: "://") else { return nil }
            return String(origin[range.upperBound...])
        }
    }

    enum Failure: Error {
        case incomplete
        case malformed
        case forbiddenOrigin(String?)
    }

    /// Parses an HTTP upgrade request.
    ///
    /// Returns `nil` when the header block hasn't fully arrived yet, so the caller can
    /// keep buffering. Throws when the request is present but unusable.
    static func parse(_ buffer: Data) throws -> (request: Request, consumed: Int)? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            // Don't buffer unbounded garbage from a client that never sends a valid request.
            if buffer.count > 16 * 1024 { throw Failure.malformed }
            return nil
        }

        let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
        guard let text = String(data: headerData, encoding: .utf8) else {
            throw Failure.malformed
        }

        var lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, requestLine.uppercased().hasPrefix("GET ") else {
            throw Failure.malformed
        }
        lines.removeFirst()

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        guard headers["upgrade"]?.lowercased().contains("websocket") == true,
              headers["connection"]?.lowercased().contains("upgrade") == true,
              let key = headers["sec-websocket-key"], !key.isEmpty,
              headers["sec-websocket-version"] == "13"
        else {
            throw Failure.malformed
        }

        let request = Request(key: key, origin: headers["origin"])
        return (request, buffer.distance(from: buffer.startIndex, to: headerEnd.upperBound))
    }

    /// Only browser extensions may drive playback.
    ///
    /// A page at `https://example.com` gets `Origin: https://example.com`; the browser
    /// sets this header itself and script cannot override it, so no website can pass this
    /// check. A native process on this machine could forge it — but a native process can
    /// already synthesise media keys, so this grants it nothing new.
    static func isAllowedOrigin(_ origin: String?) -> Bool {
        guard let origin else { return false }
        return origin.hasPrefix("chrome-extension://") || origin.hasPrefix("moz-extension://")
    }

    static func acceptResponse(for key: String) -> Data {
        let digest = Insecure.SHA1.hash(data: Data((key + magicGUID).utf8))
        let accept = Data(digest).base64EncodedString()
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(accept)\r
        \r

        """
        return Data(response.utf8)
    }

    static func rejectResponse(status: String, message: String) -> Data {
        let body = Data(message.utf8)
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        return Data(response.utf8) + body
    }
}

// MARK: - Framing

enum BrowserBridgeOpcode: UInt8 {
    case continuation = 0x0
    case text = 0x1
    case binary = 0x2
    case close = 0x8
    case ping = 0x9
    case pong = 0xA
}

struct BrowserBridgeFrame {
    let isFinal: Bool
    let opcode: BrowserBridgeOpcode
    let payload: Data
}

enum BrowserBridgeFraming {
    enum Failure: Error {
        case unmaskedClientFrame
        case unsupportedOpcode(UInt8)
        case oversizedPayload
    }

    /// Frames larger than this are refused outright. Playback state is a few hundred
    /// bytes; anything approaching this is a bug or an attack.
    static let maxPayloadBytes = 1 << 20 // 1 MiB

    /// Decodes one frame from the front of `buffer`.
    ///
    /// Returns `nil` when the frame hasn't fully arrived — TCP is a stream, so a frame
    /// can be split across reads and several frames can share one read.
    static func decode(_ buffer: Data) throws -> (frame: BrowserBridgeFrame, consumed: Int)? {
        let bytes = [UInt8](buffer)
        guard bytes.count >= 2 else { return nil }

        let isFinal = (bytes[0] & 0x80) != 0
        let rawOpcode = bytes[0] & 0x0F
        guard let opcode = BrowserBridgeOpcode(rawValue: rawOpcode) else {
            throw Failure.unsupportedOpcode(rawOpcode)
        }

        let isMasked = (bytes[1] & 0x80) != 0
        // RFC 6455 §5.1: every frame from client to server must be masked.
        guard isMasked else { throw Failure.unmaskedClientFrame }

        var index = 2
        var payloadLength = Int(bytes[1] & 0x7F)

        if payloadLength == 126 {
            guard bytes.count >= index + 2 else { return nil }
            payloadLength = Int(bytes[index]) << 8 | Int(bytes[index + 1])
            index += 2
        } else if payloadLength == 127 {
            guard bytes.count >= index + 8 else { return nil }
            var value = 0
            for offset in 0..<8 {
                value = (value << 8) | Int(bytes[index + offset])
            }
            // A 64-bit length that overflows Int, or simply an absurd one.
            guard value >= 0, value <= maxPayloadBytes else { throw Failure.oversizedPayload }
            payloadLength = value
            index += 8
        }

        guard payloadLength <= maxPayloadBytes else { throw Failure.oversizedPayload }

        guard bytes.count >= index + 4 else { return nil }
        let mask = Array(bytes[index..<(index + 4)])
        index += 4

        guard bytes.count >= index + payloadLength else { return nil }

        var payload = [UInt8](repeating: 0, count: payloadLength)
        for offset in 0..<payloadLength {
            payload[offset] = bytes[index + offset] ^ mask[offset % 4]
        }
        index += payloadLength

        return (BrowserBridgeFrame(isFinal: isFinal, opcode: opcode, payload: Data(payload)), index)
    }

    /// Encodes a server frame. Server-to-client frames are never masked.
    static func encode(opcode: BrowserBridgeOpcode, payload: Data) -> Data {
        var out = Data()
        out.append(0x80 | opcode.rawValue) // FIN set; we never fragment outbound frames.

        let count = payload.count
        if count < 126 {
            out.append(UInt8(count))
        } else if count <= 0xFFFF {
            out.append(126)
            out.append(UInt8((count >> 8) & 0xFF))
            out.append(UInt8(count & 0xFF))
        } else {
            out.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                out.append(UInt8((count >> shift) & 0xFF))
            }
        }

        out.append(payload)
        return out
    }

    static func closeFrame(code: UInt16 = 1000) -> Data {
        var payload = Data()
        payload.append(UInt8((code >> 8) & 0xFF))
        payload.append(UInt8(code & 0xFF))
        return encode(opcode: .close, payload: payload)
    }
}
