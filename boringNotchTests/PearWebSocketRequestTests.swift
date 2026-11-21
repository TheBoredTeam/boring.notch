//
//  PearWebSocketRequestTests.swift
//  boringNotchTests
//

import XCTest
@testable import boringNotch

final class PearWebSocketRequestTests: XCTestCase {
    func testRequestIsAcceptedByPearQueryAndBearerAuthVersions() throws {
        let url = try XCTUnwrap(
            WebSocketURLBuilder.buildURL(
                from: "https://localhost:26539?token=old&locale=en%2By&token=older"
            )
        )
        let token = "a+b/c=d&other=value?# percent% ü"
        let request = try WebSocketURLBuilder.authenticatedRequest(to: url, token: token)
        let requestURL = try XCTUnwrap(request.url)

        XCTAssertEqual(requestURL.scheme, "wss")
        XCTAssertEqual(requestURL.host, "localhost")
        XCTAssertEqual(requestURL.port, 26539)
        XCTAssertEqual(requestURL.path, "/api/v1/ws")

        let queryAuthVersion = PearWebSocketServerMock(
            expectedToken: token,
            authentication: .queryParameter
        )
        let bearerAuthVersion = PearWebSocketServerMock(
            expectedToken: token,
            authentication: .bearerHeader
        )

        XCTAssertTrue(queryAuthVersion.accepts(request))
        XCTAssertTrue(bearerAuthVersion.accepts(request))
    }

    func testRequestRejectsEmptyToken() throws {
        let url = try XCTUnwrap(URL(string: "ws://localhost:26538/api/v1/ws"))
        XCTAssertThrowsError(try WebSocketURLBuilder.authenticatedRequest(to: url, token: "")) { error in
            guard case YouTubeMusicError.authenticationRequired = error else {
                return XCTFail("Expected authenticationRequired, received \(error)")
            }
        }
    }

    func testRequestRejectsNonWebSocketURL() throws {
        let url = try XCTUnwrap(URL(string: "https://localhost:26538/api/v1/ws"))
        XCTAssertThrowsError(try WebSocketURLBuilder.authenticatedRequest(to: url, token: "secret"))
    }
}

private struct PearWebSocketServerMock {
    enum Authentication {
        case queryParameter
        case bearerHeader
    }

    let expectedToken: String
    let authentication: Authentication

    func accepts(_ request: URLRequest) -> Bool {
        guard let url = request.url, url.path == "/api/v1/ws" else { return false }

        switch authentication {
        case .queryParameter:
            return queryValue(named: "token", in: url) == expectedToken
        case .bearerHeader:
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer \(expectedToken)"
        }
    }

    // Mirrors Pear Desktop's ctx.req.query('token') lookup. URLSearchParams
    // returns the first value and applies form-style '+' decoding.
    private func queryValue(named name: String, in url: URL) -> String? {
        guard let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery else {
            return nil
        }

        for pair in query.split(separator: "&", omittingEmptySubsequences: false) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let queryName = formDecode(parts[0]), queryName == name else { continue }
            return parts.count == 2 ? formDecode(parts[1]) : ""
        }

        return nil
    }

    private func formDecode(_ value: Substring) -> String? {
        String(value)
            .replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding
    }
}
