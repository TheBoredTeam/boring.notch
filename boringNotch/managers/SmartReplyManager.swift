//
//  SmartReplyManager.swift
//  boringNotch
//
//  Draft reply suggestions using Apple's on-device Foundation Models —
//  entirely local, no network calls, same model that powers Apple
//  Intelligence system-wide.
//
//  Every touchpoint here is macOS 26+ and Apple-Intelligence-enabled only.
//  This project's deployment target is macOS 14, so nothing outside an
//  `@available`/`#available` guard may reference FoundationModels — Swift's
//  autolinking weak-links the framework based on those annotations, which is
//  what lets the app still launch on older macOS versions at all. Skipping a
//  guard wouldn't just lose this feature, it would risk the whole app
//  failing to launch below macOS 26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum SmartReplyAvailability: Equatable {
    case available
    case unavailable(reason: String)
}

enum SmartReplyManager {
    static var availability: SmartReplyAvailability {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            return .unavailable(reason: "Requires macOS 26 or later.")
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: describeUnavailable(reason))
        }
        #else
        return .unavailable(reason: "Requires macOS 26 or later.")
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func describeUnavailable(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This Mac doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in System Settings → Apple Intelligence & Siri."
        case .modelNotReady:
            return "The on-device model is still downloading."
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }
    #endif

    /// Up to three short reply drafts for the given message, or an empty
    /// array on any unavailability/failure — callers show nothing rather
    /// than an error state for what's an optional nicety, not a feature the
    /// UI depends on.
    static func suggestReplies(sender: String?, body: String) async -> [String] {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *),
              case .available = SystemLanguageModel.default.availability,
              !body.isEmpty
        else { return [] }

        do {
            let session = LanguageModelSession(instructions: """
                You draft extremely short, casual reply suggestions to an \
                incoming message, in the voice of the person replying, not \
                the sender. Match the tone and language of the message. \
                Never invent facts, plans, times, or commitments the message \
                doesn't mention. Each reply must be under 8 words.
                """)
            let prompt = "From: \(sender ?? "someone")\nMessage: \(body)\n\nSuggest 3 short possible replies."
            let result = try await session.respond(to: prompt, generating: ReplySuggestionSet.self)
            return Array(result.content.replies.prefix(3))
        } catch {
            return []
        }
        #else
        return []
        #endif
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct ReplySuggestionSet: Equatable {
    @Guide(description: "2 to 3 short, casual reply suggestions, each under 8 words")
    let replies: [String]
}
#endif
