//
//  PearWebSocketRequestTests.swift
//  boringNotchTests
//

import XCTest
@testable import boringNotch

final class PearWebSocketRequestTests: XCTestCase {
    func testAuthenticationUsesOneQueryToken() throws {
        let url = try XCTUnwrap(URL(string: "ws://localhost:26538/api/v1/ws?token=old&locale=en&token=older"))
        let token = "a+b/c=d&other=value?# percent% ü"
        let request = try WebSocketURLBuilder.authenticatedRequest(to: url, token: token)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.queryItems?.filter { $0.name == "token" }, [URLQueryItem(name: "token", value: token)])
        XCTAssertEqual(components.queryItems?.filter { $0.name == "locale" }, [URLQueryItem(name: "locale", value: "en")])
        XCTAssertEqual(components.path, "/api/v1/ws")
        XCTAssertFalse(components.percentEncodedQuery?.contains("+") ?? true)
        XCTAssertTrue(components.percentEncodedQuery?.contains("%2B") ?? false)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
    }

    func testSecureEndpointAndPortArePreserved() throws {
        let url = try XCTUnwrap(WebSocketURLBuilder.buildURL(from: "https://localhost:26539"))
        let request = try WebSocketURLBuilder.authenticatedRequest(to: url, token: "secret")
        XCTAssertEqual(request.url?.scheme, "wss")
        XCTAssertEqual(request.url?.host, "localhost")
        XCTAssertEqual(request.url?.port, 26539)
    }

    func testEmptyTokenIsRejected() throws {
        let url = try XCTUnwrap(URL(string: "ws://localhost:26538/api/v1/ws"))
        XCTAssertThrowsError(try WebSocketURLBuilder.authenticatedRequest(to: url, token: "")) { error in
            guard case YouTubeMusicError.authenticationRequired = error else {
                return XCTFail("Expected authenticationRequired, received \(error)")
            }
        }
    }

    func testNonWebSocketURLIsRejected() throws {
        let url = try XCTUnwrap(URL(string: "https://localhost:26538/api/v1/ws"))
        XCTAssertThrowsError(try WebSocketURLBuilder.authenticatedRequest(to: url, token: "secret"))
    }
}
