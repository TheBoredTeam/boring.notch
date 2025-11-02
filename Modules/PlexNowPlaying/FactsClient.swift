//
//  FactsClient.swift
//  boringNotch (Plex Module)
//

import Foundation
import Defaults

public final class FactsClient: @unchecked Sendable {
    public static let shared = FactsClient()
    public var debugLogging: Bool = true
    private init() {}

    /// Obtiene información del álbum usando Discogs si está habilitado.
    /// Devuelve `AlbumFacts?` o `nil` si no se puede obtener información.
    public func fetchFacts(artist: String, album: String) async -> AlbumFacts? {
        let useDiscogs = Defaults[.enableDiscogs]
        let token = Defaults[.discogsToken].trimmingCharacters(in: .whitespacesAndNewlines)

        if debugLogging {
            print("ℹ️ [Facts] useDiscogs=\(useDiscogs) token.isEmpty=\(token.isEmpty)")
            print("ℹ️ [Facts] solicitando facts para: \(artist) — \(album)")
        }

        // 🔹 Si está habilitado Discogs y hay token válido
        if useDiscogs && !token.isEmpty {
            if debugLogging { print("➡️ [Facts] usando Discogs") }

            do {
                // El cliente ya usa Defaults, no se pasa el token manualmente
                let maybeFacts = try await DiscogsClient.shared.fetchFacts(artist: artist, album: album)

                if let facts = maybeFacts {
                    if debugLogging {
                        print("✅ [Facts] Discogs OK label=\(facts.label ?? "-") releaseDate=\(facts.releaseDate ?? "-")")
                    }
                    return facts
                } else {
                    if debugLogging { print("⚠️ [Facts] Discogs sin resultados") }
                    return nil
                }
            } catch {
                if debugLogging { print("❌ [Facts] Discogs error: \(error)") }
                return nil
            }
        }

        // 🔹 Si Discogs está deshabilitado o no hay token
        if debugLogging {
            print("⚠️ [Facts] Discogs deshabilitado o sin token — no se devuelve facts")
        }
        return nil
    }
}
