import Foundation

struct SpotifyAuthConfiguration {
    static let redirectURI = "boringnotch://spotify-auth/callback"
    static let callbackScheme = "boringnotch"
    static let callbackHost = "spotify-auth"
    static let callbackPath = "/callback"
    static let scopes = ["user-read-playback-state", "user-read-currently-playing"]

    let clientID: String

    var isConfigured: Bool { !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static func current(bundle: Bundle = .main) -> SpotifyAuthConfiguration {
        let infoValue = bundle.object(forInfoDictionaryKey: "SPOTIFY_CLIENT_ID") as? String
        let envValue = ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_ID"]
        let buildSettingPlaceholder = "$(SPOTIFY_CLIENT_ID)"
        let raw = (infoValue?.isEmpty == false ? infoValue : envValue) ?? ""
        let sanitized = raw == buildSettingPlaceholder ? "" : raw
        return SpotifyAuthConfiguration(clientID: sanitized.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
