import XCTest
@testable import SpotifyAdDampenerCore

final class PKCETests: XCTestCase {
    func testGeneratedVerifierLengthAndCharactersAreURLSafe() throws {
        let verifier = try PKCE.generateVerifier()
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertLessThanOrEqual(verifier.count, 128)
        XCTAssertTrue(verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." || $0 == "_" || $0 == "~" })
    }

    func testChallengeUsesSHA256Base64URLWithoutPadding() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(PKCE.challenge(for: verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testBuildAuthorizationURLContainsRequiredSpotifyQueryItems() throws {
        let url = try PKCE.authorizationURL(
            clientID: "client id",
            redirectURI: "boringnotch://spotify-auth/callback",
            scopes: ["user-read-playback-state", "user-read-currently-playing"],
            state: "state-123",
            codeChallenge: "challenge_abc"
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "accounts.spotify.com")
        XCTAssertEqual(components.path, "/authorize")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["client_id"], "client id")
        XCTAssertEqual(items["redirect_uri"], "boringnotch://spotify-auth/callback")
        XCTAssertEqual(items["scope"], "user-read-playback-state user-read-currently-playing")
        XCTAssertEqual(items["state"], "state-123")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["code_challenge"], "challenge_abc")
    }
}
