import Foundation

struct SpotifyAuthToken: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let scope: String?
    let expiresAt: Date

    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }

    init(accessToken: String, refreshToken: String?, tokenType: String = "Bearer", scope: String?, expiresIn: TimeInterval, receivedAt: Date = Date()) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.scope = scope
        self.expiresAt = receivedAt.addingTimeInterval(expiresIn)
    }

    init(accessToken: String, refreshToken: String?, tokenType: String, scope: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.scope = scope
        self.expiresAt = expiresAt
    }
}

struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String?
    let expiresIn: TimeInterval
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }

    func authToken(previousRefreshToken: String? = nil, receivedAt: Date = Date()) -> SpotifyAuthToken {
        SpotifyAuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken ?? previousRefreshToken,
            tokenType: tokenType,
            scope: scope,
            expiresIn: expiresIn,
            receivedAt: receivedAt
        )
    }
}
