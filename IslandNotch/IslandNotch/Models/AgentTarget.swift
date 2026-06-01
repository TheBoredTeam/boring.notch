//  AgentTarget.swift
//  IslandNotch
//
//  Purpose: The local CLI coding agent a copied screenshot is destined for.
//           Each agent has its own default PayloadMode.
//  Layer: Model

import Foundation

/// A local CLI coding agent the user pastes screenshots into.
enum AgentTarget: String, Codable, CaseIterable, Identifiable {
    case claudeCode
    case codex
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .custom: return "Custom"
        }
    }

    /// Sensible default clipboard mode per agent. Verified intent: both read a
    /// pasted file path natively, so default to a path payload.
    var defaultPayloadMode: PayloadMode {
        switch self {
        case .claudeCode: return .pathLookAtPrefixed
        case .codex: return .pathPlain
        case .custom: return .pathPlain
        }
    }
}
