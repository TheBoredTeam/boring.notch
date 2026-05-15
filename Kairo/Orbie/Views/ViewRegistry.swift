import SwiftUI

enum OrbieViewID: String, CaseIterable {
    case weather, nowPlaying, searchResults, cameraFeed, notification, quickAnswer, textResponse
}

struct OrbieViewConfig {
    let id: OrbieViewID
    let size: OrbieSize
    let dismissAfter: TimeInterval?
    let dismissible: Bool
}

enum ViewRegistry {
    static let configs: [OrbieViewID: OrbieViewConfig] = [
        .weather:       .init(id: .weather,       size: .card,  dismissAfter: 10,  dismissible: true),
        .nowPlaying:    .init(id: .nowPlaying,     size: .pill,  dismissAfter: nil, dismissible: true),
        .searchResults: .init(id: .searchResults,  size: .panel, dismissAfter: nil, dismissible: true),
        .cameraFeed:    .init(id: .cameraFeed,     size: .card,  dismissAfter: nil, dismissible: true),
        .notification:  .init(id: .notification,   size: .card,  dismissAfter: 6,   dismissible: true),
        .quickAnswer:   .init(id: .quickAnswer,    size: .pill,  dismissAfter: 8,   dismissible: true),
        .textResponse:  .init(id: .textResponse,   size: .panel, dismissAfter: nil, dismissible: true),
    ]

    static func config(for id: OrbieViewID) -> OrbieViewConfig? { configs[id] }
}
