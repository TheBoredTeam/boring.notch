//
//  CodexAvatarStyle.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

enum CodexAvatarStyle: String, CaseIterable, Identifiable {
    case smile
    case orbit
    case lines
    case colorfulOrbit

    var id: String { rawValue }

    static func selected(manual: Self, level: CodexActivityLevel, followsActivity: Bool, previewing: Bool = false) -> Self {
        guard followsActivity, !previewing else { return manual }
        switch level.tier {
        case .smile: return .smile
        case .syncing: return .lines
        case .spin: return .orbit
        case .iris: return .colorfulOrbit
        }
    }

    var displayName: String {
        switch self {
        case .smile: return "Smile"
        case .orbit: return "Orbit"
        case .lines: return "Lines"
        case .colorfulOrbit: return "Colorful orbit"
        }
    }
}
