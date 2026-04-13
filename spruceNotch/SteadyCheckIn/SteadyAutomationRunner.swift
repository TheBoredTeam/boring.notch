//
//  SteadyAutomationRunner.swift
//  spruceNotch
//

import AppKit
import Defaults

enum SteadyAutomationResult: Equatable {
    case success
    case failure(message: String, recoveryHint: String?)
}

enum SteadyAutomationRunner {
    @MainActor
    static func run(
        next: String,
        previously: String,
        blockers: String,
        feelingEmoji: String
    ) async -> SteadyAutomationResult {
        switch Defaults[.steadyAutomationMode] {
        case .pasteboardAssist:
            return await runPasteboardAssist(
                next: next,
                previously: previously,
                blockers: blockers,
                feelingEmoji: feelingEmoji
            )
        case .accessibilityExperimental:
            return .failure(
                message: "Accessibility automation is not implemented yet.",
                recoveryHint: "Sign in to Steady, then tap Try again after we add selectors—or use “Open Steady & copy answers” in Settings."
            )
        }
    }

    @MainActor
    private static func runPasteboardAssist(
        next: String,
        previously: String,
        blockers: String,
        feelingEmoji: String
    ) async -> SteadyAutomationResult {
        guard let url = resolvedCheckInURL() else {
            return .failure(
                message: "Invalid Steady check-in URL.",
                recoveryHint: "Set a valid https URL in Settings → Steady Check-in. Use {date} for today’s date (yyyy-MM-dd)."
            )
        }

        let pasteboardText = formatPasteboard(
            next: next,
            previously: previously,
            blockers: blockers,
            feelingEmoji: feelingEmoji
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(pasteboardText, forType: .string)

        let opened = NSWorkspace.shared.open(url)
        if opened {
            return .success
        }
        return .failure(
            message: "Could not open the Steady URL.",
            recoveryHint: "Check the URL in Settings, or open Steady manually and use Try again."
        )
    }

    /// Replaces `{date}` with today’s date in the current calendar/time zone (`yyyy-MM-dd`).
    @MainActor
    private static func resolvedCheckInURL() -> URL? {
        let raw = Defaults[.steadyCheckInURL].trimmingCharacters(in: .whitespacesAndNewlines)
        let day = SteadyCheckInManager.dayString()
        let substituted = raw.replacingOccurrences(of: "{date}", with: day)
        guard let url = URL(string: substituted), url.scheme == "http" || url.scheme == "https" else {
            return nil
        }
        return url
    }

    private static func formatPasteboard(
        next: String,
        previously: String,
        blockers: String,
        feelingEmoji: String
    ) -> String {
        _ = feelingEmoji
        return [previously, next, blockers].joined(separator: "\n\n")
    }
}
