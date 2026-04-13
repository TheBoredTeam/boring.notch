//
//  SteadyCheckInManager.swift
//  spruceNotch
//

import AppKit
import Combine
import Defaults
import Foundation

@MainActor
final class SteadyCheckInManager: ObservableObject {
    static let shared = SteadyCheckInManager()

    @Published private(set) var phase: SteadyCheckInPhase = .idle
    @Published var next: String = ""
    @Published var previously: String = ""
    @Published var blockers: String = ""
    @Published var feelingEmoji: String = ""
    @Published var currentStep: Int = 0

    private let draftStore = SteadyCheckInDraftStore.shared

    private init() {
        if let draft = draftStore.load() {
            next = draft.next
            previously = draft.previously
            blockers = draft.blockers
            feelingEmoji = draft.feelingEmoji
            if draft.lastFailureMessage != nil {
                phase = .failed(message: draft.lastFailureMessage ?? "")
            }
        }
    }

    private func persistDraft(failureMessage: String?) {
        let draft = SteadyCheckInDraft(
            next: next,
            previously: previously,
            blockers: blockers,
            feelingEmoji: feelingEmoji,
            lastFailureMessage: failureMessage,
            updatedAt: Date()
        )
        draftStore.save(draft)
    }

    private func clearPersistedDraft() {
        draftStore.clear()
    }

    func openSteadyApp() {
        if openDesktopSteadyApp() {
            return
        }
        guard let url = resolvedCheckInURL() else { return }
        _ = NSWorkspace.shared.open(url)
    }

    private func openDesktopSteadyApp() -> Bool {
        let workspace = NSWorkspace.shared
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        let knownBundleIDs = [
            "com.steady.desktop",
            "com.runsteady.desktop",
            "space.steady.desktop"
        ]
        for bundleID in knownBundleIDs {
            if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                workspace.openApplication(at: appURL, configuration: config, completionHandler: nil)
                return true
            }
        }

        let fileManager = FileManager.default
        let commonAppPaths = [
            "/Applications/Steady.app",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications/Steady.app")
        ]
        for path in commonAppPaths where fileManager.fileExists(atPath: path) {
            let appURL = URL(fileURLWithPath: path)
            workspace.openApplication(at: appURL, configuration: config, completionHandler: nil)
            return true
        }

        return false
    }

    private func resolvedCheckInURL() -> URL? {
        let raw = Defaults[.steadyCheckInURL].trimmingCharacters(in: .whitespacesAndNewlines)
        let day = Self.dayString()
        let substituted = raw.replacingOccurrences(of: "{date}", with: day)
        guard let url = URL(string: substituted), url.scheme == "http" || url.scheme == "https" else {
            return nil
        }
        return url
    }

    func startManualFlow() {
        phase = .idle
        currentStep = 0
        NotificationCenter.default.post(name: .steadyCheckInOpenNotch, object: nil)
    }

    func beginScheduledFlow() {
        phase = .idle
        currentStep = 0
        NotificationCenter.default.post(name: .steadyCheckInOpenNotch, object: nil)
    }

    func ignoreFlow() {
        let today = Self.dayString()
        Defaults[.steadyCheckInLastIgnoredDay] = today
        Defaults[.steadyCheckInScheduledPromptDay] = today
        resetAfterDismiss()
    }

    func markCompletedAndDismiss() {
        let today = Self.dayString()
        Defaults[.steadyCheckInLastCompletedDay] = today
        Defaults[.steadyCheckInScheduledPromptDay] = today
        resetAfterDismiss()
    }

    func forgetFailure() {
        let today = Self.dayString()
        Defaults[.steadyCheckInLastIgnoredDay] = today
        Defaults[.steadyCheckInScheduledPromptDay] = today
        resetAfterDismiss()
    }

    func advanceFromStep() {
        switch currentStep {
        case 0, 1:
            currentStep += 1
            phase = .collecting(step: currentStep)
        case 2:
            Task { await submit() }
        default:
            Task { await submit() }
        }
        persistDraft(failureMessage: nil)
    }

    func goBack() {
        guard currentStep > 0 else { return }
        currentStep -= 1
        phase = .collecting(step: currentStep)
    }

    func submit() async {
        phase = .submitting
        persistDraft(failureMessage: nil)

        let result = await SteadyAutomationRunner.run(
            next: next,
            previously: previously,
            blockers: blockers,
            feelingEmoji: feelingEmoji
        )

        switch result {
        case .success:
            phase = .succeeded
            let today = Self.dayString()
            Defaults[.steadyCheckInLastCompletedDay] = today
            Defaults[.steadyCheckInScheduledPromptDay] = today
            clearPersistedDraft()
        case .failure(let message, _):
            phase = .failed(message: message)
            persistDraft(failureMessage: message)
        }
    }

    func retryAfterFixingSteady() {
        Task { await submit() }
    }

    func dismissSuccess() {
        resetAfterDismiss()
    }

    private func resetAfterDismiss() {
        phase = .idle
        next = ""
        previously = ""
        blockers = ""
        feelingEmoji = ""
        currentStep = 0
        clearPersistedDraft()
        SpruceViewCoordinator.shared.currentView = .home
        NSApp.setActivationPolicy(.accessory)
    }

    func questionTitle(for step: Int) -> String {
        switch step {
        case 0:
            return "What did you do previously?"
        case 1:
            return "What do you intend to do next?"
        case 2:
            return "Are you blocked by anything?"
        default:
            return ""
        }
    }

    static func dayString(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }
}
