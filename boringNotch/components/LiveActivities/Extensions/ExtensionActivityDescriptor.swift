// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Foundation

/// Wire values are deliberately independent of SwiftUI, host types, and scheduler policy.
struct ExtensionActivitySnapshot: Decodable {
    let activities: [ExtensionActivityDescriptor]

    func validate() throws {
        guard activities.count <= 16, Set(activities.map(\.id)).count == activities.count else {
            throw ExtensionError.invalidPackage
        }
        try activities.forEach { try $0.validate() }
    }
}

struct ExtensionActivityDescriptor: Decodable, Equatable {
    enum Relevance: String, Decodable {
        case passive, active, timeSensitive

        var priority: Int {
            switch self {
            case .passive: return -10
            case .active: return 25
            case .timeSensitive: return 50
            }
        }
    }

    let id: String
    let label: String
    var relevance: Relevance? = nil
    var expiresAt: Double? = nil
    var displays: [String]? = nil
    var surface: LiveActivitySurface? = nil

    func validate() throws {
        guard id.utf8.count <= 100,
              id.range(of: #"\A[A-Za-z0-9][A-Za-z0-9._-]*\z"#, options: .regularExpression) != nil,
              !label.isEmpty, label.utf8.count <= 256,
              expiresAt?.isFinite != false,
              displays.map({ $0.count <= 32 && $0.allSatisfy { !$0.isEmpty && $0.utf8.count <= 128 } }) ?? true
        else { throw ExtensionError.invalidPackage }
    }

    func hostDescriptor(namespace: String) -> LiveActivityDescriptor {
        LiveActivityDescriptor(
            id: LiveActivityID(namespace: namespace, name: id),
            priority: (relevance ?? .active).priority,
            lifetime: expiresAt.map { .until(Date(timeIntervalSince1970: $0)) } ?? .persistent,
            displayScope: displays.map { .displays(Set($0)) } ?? .all,
            surface: surface ?? .desktop
        )
    }
}
