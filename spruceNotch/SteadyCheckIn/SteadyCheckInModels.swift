//
//  SteadyCheckInModels.swift
//  spruceNotch
//

import Defaults
import Foundation

enum SteadyCheckInPhase: Equatable {
    case idle
    case collecting(step: Int)
    case submitting
    case failed(message: String)
    case succeeded
}

struct SteadyCheckInDraft: Codable, Equatable {
    var next: String
    var previously: String
    var blockers: String
    /// Single emoji for “How are you feeling?” (pasteboard assist).
    var feelingEmoji: String
    var lastFailureMessage: String?
    var updatedAt: Date

    static let empty = SteadyCheckInDraft(
        next: "",
        previously: "",
        blockers: "",
        feelingEmoji: "",
        lastFailureMessage: nil,
        updatedAt: Date()
    )

    enum CodingKeys: String, CodingKey {
        case next, previously, blockers, feelingEmoji, lastFailureMessage, updatedAt
    }

    init(
        next: String,
        previously: String,
        blockers: String,
        feelingEmoji: String,
        lastFailureMessage: String?,
        updatedAt: Date
    ) {
        self.next = next
        self.previously = previously
        self.blockers = blockers
        self.feelingEmoji = feelingEmoji
        self.lastFailureMessage = lastFailureMessage
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        next = try c.decode(String.self, forKey: .next)
        previously = try c.decode(String.self, forKey: .previously)
        blockers = try c.decode(String.self, forKey: .blockers)
        feelingEmoji = try c.decodeIfPresent(String.self, forKey: .feelingEmoji) ?? ""
        lastFailureMessage = try c.decodeIfPresent(String.self, forKey: .lastFailureMessage)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

/// Mood emojis aligned with Steady’s check-in grid (subset; enough to pick a match).
enum SteadyCheckInFeelingEmojis {
    static let all: [String] = [
        "😀", "😃", "😄", "😁", "🙂", "😊", "😌", "😐", "😑", "🤔",
        "😕", "😟", "😢", "😭", "😤", "😠", "🤯", "😵", "🥱", "😴", "💪"
    ]
}

enum SteadyAutomationMode: String, Codable, CaseIterable, Identifiable, Defaults.Serializable {
    case pasteboardAssist
    case accessibilityExperimental

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pasteboardAssist:
            return "Open Steady & copy answers"
        case .accessibilityExperimental:
            return "Accessibility automation (stub)"
        }
    }

    var detail: String {
        switch self {
        case .pasteboardAssist:
            return "Opens your check-in URL in the browser and copies formatted text to the clipboard. Paste into each field in Steady, then submit there."
        case .accessibilityExperimental:
            return "Reserved for full UI automation when selectors are implemented. Currently returns a failure so you can use Try again after signing in."
        }
    }
}

extension Notification.Name {
    static let steadyCheckInOpenNotch = Notification.Name("steadyCheckInOpenNotch")
}
