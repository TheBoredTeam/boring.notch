import Foundation

enum CodexPermissionRelayError: LocalizedError, Equatable {
    case invalidCallback
    case unavailable
    case rejected(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidCallback:
            "This permission request has expired. Review it in Codex."
        case .unavailable:
            "This permission request is no longer active. Review it in Codex."
        case .rejected(let statusCode):
            "Codex rejected the permission response (HTTP \(statusCode))."
        }
    }
}

enum CodexPermissionRelay {
    static func acknowledge(callback: CodexPermissionCallback) async throws {
        try await submit("ready", callback: callback)
    }

    static func submit(
        _ decision: CodexPermissionDecision,
        callback: CodexPermissionCallback
    ) async throws {
        try await submit(decision.rawValue, callback: callback)
    }

    private static func submit(
        _ decision: String,
        callback: CodexPermissionCallback
    ) async throws {
        guard callback.isActive(),
              let endpoint = endpoint(port: callback.port) else {
            throw CodexPermissionRelayError.invalidCallback
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "token": callback.token,
            "decision": decision,
        ])

        let response: URLResponse
        do {
            response = try await session.data(for: request).1
        } catch {
            throw CodexPermissionRelayError.unavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexPermissionRelayError.unavailable
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CodexPermissionRelayError.rejected(
                statusCode: httpResponse.statusCode
            )
        }
    }

    private static func endpoint(port: Int) -> URL? {
        guard (1024...65535).contains(port) else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = port
        components.path = "/decision"
        return components.url
    }
}
