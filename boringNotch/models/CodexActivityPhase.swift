//
//  CodexActivityPhase.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

enum CodexActivityTier: Equatable {
    case smile, syncing, spin, iris
}

struct CodexActivityLevel: Equatable {
    let activeCount: Int

    init(activeCount: Int) {
        self.activeCount = max(0, activeCount)
    }

    var tier: CodexActivityTier {
        switch activeCount {
        case 0: return .smile
        case 1...2: return .syncing
        case 3: return .spin
        default: return .iris
        }
    }

    var speedMultiplier: Double {
        guard activeCount >= 4 else { return 1 }
        let extra = Double(activeCount - 4)
        return 1.15 + 1.35 * extra / (extra + 6)
    }
}

enum CodexActivityPhase: String, Decodable {
    case offline, idle, active, waiting, error

    var isInProgress: Bool { self == .active || self == .waiting }

    var statusText: String {
        switch self {
        case .offline: return "Codex is disconnected"
        case .idle: return "Codex is ready"
        case .active: return "Codex is working"
        case .waiting: return "Codex needs your attention"
        case .error: return "Codex reported an error"
        }
    }
}

struct CodexActivitySnapshot: Decodable {
    let service: String
    let version: Int
    let phase: CodexActivityPhase
    let updatedAt: TimeInterval
    let activeCount: Int

    func validatedPhase(at now: Date) -> CodexActivityPhase {
        let age = now.timeIntervalSince1970 - updatedAt
        guard service == "boringnotch-codex-activity", version == 1,
              age >= -2, age <= 8, activeCount >= 0,
              phase.isInProgress == (activeCount > 0) else { return .offline }
        return phase
    }

    func validatedActiveCount(at now: Date) -> Int {
        validatedPhase(at: now).isInProgress ? activeCount : 0
    }
}
