import Foundation

struct SpotifyAuthConfiguration {
    static let defaultRedirectURI = MinitapBrand.spotifyRedirectURI
    static let scopes = ["user-read-playback-state", "user-read-currently-playing"]

    let clientID: String
    let redirectURI: String

    var isConfigured: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && callbackComponents != nil
    }

    var callbackScheme: String? { callbackComponents?.scheme }
    var callbackHost: String? { callbackComponents?.host }
    var callbackPath: String { callbackComponents?.path ?? "" }

    private var callbackComponents: URLComponents? {
        URLComponents(string: redirectURI)
    }

    static func current(bundle: Bundle = .main) -> SpotifyAuthConfiguration {
        let clientID = sanitizedInfoOrEnvironmentValue(
            key: "SPOTIFY_CLIENT_ID",
            placeholder: "$(SPOTIFY_CLIENT_ID)",
            bundle: bundle
        )
        let configuredRedirectURI = sanitizedInfoOrEnvironmentValue(
            key: "SPOTIFY_REDIRECT_URI",
            placeholder: "$(SPOTIFY_REDIRECT_URI)",
            bundle: bundle
        )
        let redirectURI = configuredRedirectURI.isEmpty ? defaultRedirectURI : configuredRedirectURI
        return SpotifyAuthConfiguration(
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            redirectURI: redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func sanitizedInfoOrEnvironmentValue(key: String, placeholder: String, bundle: Bundle) -> String {
        let infoValue = bundle.object(forInfoDictionaryKey: key) as? String
        let envValue = ProcessInfo.processInfo.environment[key]
        let raw = (infoValue?.isEmpty == false ? infoValue : envValue) ?? ""
        return raw == placeholder ? "" : raw
    }
}
