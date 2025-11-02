//
//  Defaults+Discogs.swift
//  boringNotch
//

import Defaults

public extension Defaults.Keys {
    // Discogs
    static let enableDiscogs = Key<Bool>("enableDiscogs", default: false)
    static let discogsToken  = Key<String>("discogsToken", default: "")

    // Enricher local (opcional, legacy)
    static let enricherURL   = Key<String>("enricherURL", default: "")

    // PMS y Plex token (para auto-polling)
    static let pmsURL        = Key<String>("PMS_URL",   default: "")
    static let plexToken     = Key<String>("PLEX_TOKEN", default: "")
}
