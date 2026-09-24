import AppKit
import SwiftUI
import Defaults

private let windowDefaults = UserDefaults(suiteName: "DiarySmoke.Window")!
extension Defaults.Keys {
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false, suite: windowDefaults)
    static let hideNonNotchedFromMissionControl = Key<Bool>("hideNonNotchedFromMissionControl", default: false, suite: windowDefaults)
}

// A synthetic reminder source keeps validation away from the user's calendar and reminders.
@MainActor
final class SmokeReminders: DailyReminderProviding {
    var authorization: DailyReminderAuthorization { .authorized }
    var changeNotification: Notification.Name { .init("DiarySmokeReminderChange") }
    func requestAccess() async throws -> Bool { true }
    func reminders(from start: Date, to end: Date) async -> [DailyReminderItem] {
        [.init(id: "sample", title: "Sample reminder", dueDate: start, isCompleted: false, listTitle: "Sample")]
    }
    func setCompleted(_ completed: Bool, reminderID: String) async throws {}
}

// Match the existing button spring without loading unrelated Defaults-backed animations.
enum StandardAnimations { static let interactive = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0) }

extension Color { static var effectiveAccent: Color { .accentColor } }

@main
struct DiarySmoke {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await run(); print("Daily conclusion smoke: passed"); exit(0) }
            catch { fputs("Daily conclusion smoke failed: \(error)\n", stderr); exit(1) }
        }
        app.run()
    }

    @MainActor static func run() async throws {
        defer { windowDefaults.removePersistentDomain(forName: "DiarySmoke.Window") }
        let suite = "DiarySmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DailyWorkflowPreferencesStore(defaults: defaults)
        var preferences = DailyWorkflowPreferences.default
        preferences.eveningReviewEnabled = true
        preferences.eveningReviewMinutes = 0
        try store.savePreferences(preferences)
        let manager = DailyPlanningManager(store: store, reminderService: SmokeReminders())
        manager.setConclusionEnabled(true)
        manager.start()
        try await Task.sleep(for: .milliseconds(100))
        var requestedPresentation = false
        manager.onNeedsPresentation = { requestedPresentation = true }
        precondition(manager.activatePendingSession(requestPresentation: false))
        precondition(!requestedPresentation, "Opening a pending workflow must not recursively reopen the window")
        let window = BoringNotchSkyLightWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 160), styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow], backing: .buffered, defer: false)
        let view = NSHostingView(rootView: DailyPlanningView(manager: manager).frame(width: 640, height: 160).background(.black).preferredColorScheme(.dark))
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        capture(view, name: "review")
        precondition(!manager.isConclusionActive && window.keyboardInputOwner == nil)
        manager.advanceToConclusion()
        try await Task.sleep(for: .milliseconds(250))
        precondition(window.keyboardInputOwner != nil)
        precondition(window.firstResponder is NSTextView)
        precondition(window.isKeyWindow, "The production window must receive keyboard events")
        let editor = window.firstResponder as! NSTextView
        editor.insertText("# A small win\n\n- [x] Finished the draft\n\n**Tomorrow:** make time for a walk.", replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(manager.conclusionText.hasPrefix("# A small win"), "Native input must reach the draft binding")
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "!", charactersIgnoringModifiers: "!", isARepeat: false, keyCode: 18)!
        window.sendEvent(key)
        precondition(manager.conclusionText.hasSuffix("!"), "Key events must update the draft")
        manager.returnActiveSessionToPrompt()
        precondition(manager.activeSession == nil && manager.pendingSession != nil, "Pointer exit must fold back to the prompt")
        window.contentView = nil
        try await Task.sleep(for: .milliseconds(100))
        precondition(window.keyboardInputOwner == nil)
        precondition(manager.activatePendingSession())
        window.contentView = view
        try await Task.sleep(for: .milliseconds(200))
        precondition(manager.conclusionPhase == .writing && manager.conclusionText.hasPrefix("# A small win"))
        manager.returnToReview()
        precondition(manager.conclusionText.hasPrefix("# A small win"))
        manager.advanceToConclusion()
        manager.saveConclusion(reduceMotion: false)
        precondition(manager.conclusionPhase == .writing && manager.conclusionError != nil)
        precondition(manager.conclusionText.hasPrefix("# A small win"), "Failed save must retain text")
        manager.setConclusionDirectory(directory)
        precondition(manager.conclusionPreferences.directoryBookmark != nil)
        try await Task.sleep(for: .milliseconds(350))
        capture(view, name: "writing")
        manager.saveConclusion(reduceMotion: false)
        manager.saveConclusion(reduceMotion: false) // Double clicks must not duplicate files.
        try await Task.sleep(for: .milliseconds(900))
        precondition(manager.conclusionPhase == .filing && !manager.isFinishingSession)
        precondition(window.keyboardInputOwner == nil)
        capture(view, name: "card")
        try await Task.sleep(for: .milliseconds(1000))
        capture(view, name: "folder")
        try await Task.sleep(for: .milliseconds(1350))
        precondition(manager.isFinishingSession)
        capture(view, name: "farewell")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        precondition(files.count == 1)
        let saved = try String(contentsOf: files[0], encoding: .utf8)
        precondition(saved == manager.conclusionText)
        manager.finalizeActiveSession()
        manager.completeFinishingSession()
        precondition(manager.conclusionText.isEmpty && manager.conclusionPhase == .review)

        // Empty conclusions finish without permission or files; morning never offers a diary.
        for (kind, diaryEnabled) in [(DailyWorkflowKind.morningPlanning, true), (.eveningReview, true), (.eveningReview, false)] {
            let freshSuite = "DiarySmoke.\(UUID().uuidString)"
            let freshDefaults = UserDefaults(suiteName: freshSuite)!
            defer { freshDefaults.removePersistentDomain(forName: freshSuite) }
            let freshStore = DailyWorkflowPreferencesStore(defaults: freshDefaults)
            var prefs = DailyWorkflowPreferences.default
            prefs.morningPlanningEnabled = kind == .morningPlanning
            prefs.eveningReviewEnabled = kind == .eveningReview
            prefs.morningPlanningMinutes = 0
            prefs.eveningReviewMinutes = 0
            try freshStore.savePreferences(prefs)
            let fresh = DailyPlanningManager(store: freshStore, reminderService: SmokeReminders())
            fresh.setConclusionEnabled(diaryEnabled)
            fresh.start()
            try await Task.sleep(for: .milliseconds(100))
            precondition(fresh.activatePendingSession())
            if kind == .eveningReview && diaryEnabled {
                fresh.advanceToConclusion()
                fresh.conclusionText = " \n\t "
                fresh.saveConclusion(reduceMotion: true)
                precondition(fresh.savedConclusionURL == nil)
            } else {
                precondition(!fresh.offersConclusion)
                fresh.beginFinishingActiveSession()
            }
            precondition(fresh.isFinishingSession)
        }
    }

    @MainActor static func capture(_ view: NSView, name: String) {
        guard let output = ProcessInfo.processInfo.environment["DIARY_SMOKE_CAPTURES"] else { return }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name).png"))
    }
}
