//
//  PearAuthenticationLifetimeTests.swift
//  boringNotchTests
//

import XCTest
@testable import boringNotch

private actor AuthenticationProbe {
    private var requests: [CheckedContinuation<String, Error>] = []
    var count: Int { requests.count }
    func request() async throws -> String {
        try await withCheckedThrowingContinuation { requests.append($0) }
    }
    func succeed(_ index: Int, token: String) { requests[index].resume(returning: token) }
}

final class PearAuthenticationLifetimeTests: XCTestCase {
    private func waitForRequest(_ count: Int, on probe: AuthenticationProbe) async throws {
        for _ in 0..<1000 {
            if await probe.count == count { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Authentication request did not start")
        throw CancellationError()
    }

    func testConcurrentCallersShareOneRequestAndCacheTheToken() async throws {
        let probe = AuthenticationProbe()
        let auth = YouTubeMusicAuthManager(requestAuthentication: { try await probe.request() })
        let first = Task { try await auth.authenticate() }
        try await waitForRequest(1, on: probe)
        let second = Task { try await auth.authenticate() }
        await probe.succeed(0, token: "shared")
        let a = try await first.value
        let b = try await second.value
        let cached = try await auth.authenticate()
        XCTAssertEqual([a, b, cached], ["shared", "shared", "shared"])
        let count = await probe.count
        XCTAssertEqual(count, 1)
    }

    func testInvalidationRejectsLateSuccessWithoutReplacingNewCredentials() async throws {
        let probe = AuthenticationProbe()
        let auth = YouTubeMusicAuthManager(requestAuthentication: { try await probe.request() })
        let old = Task { try await auth.authenticate() }
        try await waitForRequest(1, on: probe)
        await auth.invalidateToken()
        let current = Task { try await auth.authenticate() }
        try await waitForRequest(2, on: probe)
        await probe.succeed(1, token: "current")
        let newToken = try await current.value
        XCTAssertEqual(newToken, "current")
        await probe.succeed(0, token: "obsolete")
        do { _ = try await old.value; XCTFail("Invalidated authentication must fail") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
        let retained = await auth.currentToken
        XCTAssertEqual(retained, "current")
    }

    func testEmptyTokenIsNotCached() async throws {
        let auth = YouTubeMusicAuthManager(requestAuthentication: { "" })
        do { _ = try await auth.authenticate(); XCTFail("Empty authentication must fail") }
        catch YouTubeMusicError.authenticationRequired { }
        let retained = await auth.currentToken
        XCTAssertNil(retained)
    }
}
